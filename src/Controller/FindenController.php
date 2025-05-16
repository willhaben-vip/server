<?php

declare(strict_types=1);

namespace App\Controller;

use App\Service\Finden\Contracts\ApiClientInterface;
use App\Service\Finden\Contracts\BarcodeScannerInterface;
use App\Service\Finden\Contracts\ImageProcessorInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Log\LoggerInterface;

/**
 * Controller handling product search functionality through the 'finden' page.
 * 
 * Provides endpoints for:
 * - Image-based search
 * - Text-based search
 * - Barcode scanning
 */
class FindenController
{
    private LoggerInterface $logger;
    private ImageProcessorInterface $imageProcessor;
    private ApiClientInterface $apiClient;
    private BarcodeScannerInterface $barcodeScanner;

    public function __construct(
        LoggerInterface $logger,
        ImageProcessorInterface $imageProcessor,
        ApiClientInterface $apiClient,
        BarcodeScannerInterface $barcodeScanner
    ) {
        $this->logger = $logger;
        $this->imageProcessor = $imageProcessor;
        $this->apiClient = $apiClient;
        $this->barcodeScanner = $barcodeScanner;
    }

    /**
     * Process an image for search and transmit to willhaben API.
     *
     * This endpoint handles image-based search:
     * 1. Receives the uploaded image
     * 2. Processes and crops it (detecting books, games, media)
     * 3. Sends to the willhaben API
     * 4. Returns the search results
     */
    public function processImageSearch(ServerRequestInterface $request, ResponseInterface $response): ResponseInterface
    {
        $this->logger->info('Image search requested');

        try {
            // Extract the uploaded file
            $uploadedFiles = $request->getUploadedFiles();
            
            if (empty($uploadedFiles['image'])) {
                $this->logger->warning('No image uploaded');
                return $this->jsonResponse($response, [
                    'success' => false,
                    'error' => 'No image uploaded',
                ], 400);
            }
            
            $file = $uploadedFiles['image'];
            
            // Validate the image file
            if ($file->getError() !== UPLOAD_ERR_OK) {
                $this->logger->error('File upload error', ['error' => $file->getError()]);
                return $this->jsonResponse($response, [
                    'success' => false,
                    'error' => 'File upload error: ' . $file->getError(),
                ], 400);
            }

            // Process the image (crop objects)
            $processedImage = $this->imageProcessor->processImage(
                $file->getStream()->getContents(),
                $file->getClientMediaType()
            );
            
            // Send to willhaben API
            $searchResults = $this->apiClient->sendImageSearch($processedImage);
            
            // Return results
            return $this->jsonResponse($response, [
                'success' => true, 
                'results' => $searchResults
            ]);
            
        } catch (\Throwable $e) {
            $this->logger->error('Error processing image search', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            return $this->jsonResponse($response, [
                'success' => false,
                'error' => 'Error processing image: ' . $e->getMessage()
            ], 500);
        }
    }

    /**
     * Handle text-based product search.
     *
     * Sends a text query to the willhaben API and returns results.
     */
    public function processTextSearch(ServerRequestInterface $request, ResponseInterface $response): ResponseInterface
    {
        $this->logger->info('Text search requested');

        try {
            // Get search query from request
            $params = $request->getQueryParams();
            $query = $params['query'] ?? null;
            
            if (empty($query)) {
                $this->logger->warning('No search query provided');
                return $this->jsonResponse($response, [
                    'success' => false,
                    'error' => 'No search query provided',
                ], 400);
            }
            
            // Send search query to willhaben API
            $searchResults = $this->apiClient->sendTextSearch($query);
            
            // Return results
            return $this->jsonResponse($response, [
                'success' => true,
                'results' => $searchResults
            ]);
            
        } catch (\Throwable $e) {
            $this->logger->error('Error processing text search', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            return $this->jsonResponse($response, [
                'success' => false,
                'error' => 'Error processing search: ' . $e->getMessage()
            ], 500);
        }
    }

    /**
     * Process barcode data for product search.
     *
     * Handles EAN barcode scanning for books, games, CDs, etc.
     */
    public function processBarcodeSearch(ServerRequestInterface $request, ResponseInterface $response): ResponseInterface
    {
        $this->logger->info('Barcode search requested');

        try {
            // Get barcode data
            $data = $this->getJsonData($request);
            $barcodeData = $data['barcode'] ?? null;
            
            if (empty($barcodeData)) {
                $this->logger->warning('No barcode data provided');
                return $this->jsonResponse($response, [
                    'success' => false,
                    'error' => 'No barcode data provided',
                ], 400);
            }
            
            // Validate EAN format
            if (!$this->barcodeScanner->validateBarcode($barcodeData)) {
                $this->logger->warning('Invalid barcode format', ['barcode' => $barcodeData]);
                return $this->jsonResponse($response, [
                    'success' => false,
                    'error' => 'Invalid barcode format. Must be a valid EAN.',
                ], 400);
            }
            
            // Process the barcode and get product information
            $productInfo = $this->barcodeScanner->getProductInfo($barcodeData);
            
            // Send to willhaben API using the extracted information
            $searchResults = $this->apiClient->sendTextSearch($productInfo['title'] ?? $barcodeData);
            
            // Return results
            return $this->jsonResponse($response, [
                'success' => true,
                'product' => $productInfo,
                'results' => $searchResults
            ]);
            
        } catch (\Throwable $e) {
            $this->logger->error('Error processing barcode search', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            return $this->jsonResponse($response, [
                'success' => false,
                'error' => 'Error processing barcode: ' . $e->getMessage()
            ], 500);
        }
    }

    /**
     * Helper method to create consistent JSON responses.
     */
    private function jsonResponse(ResponseInterface $response, array $data, int $status = 200): ResponseInterface
    {
        $response = $response->withHeader('Content-Type', 'application/json');
        $response = $response->withStatus($status);
        
        $response->getBody()->write(json_encode($data, JSON_PRETTY_PRINT));
        
        return $response;
    }

    /**
     * Helper method to extract JSON data from request body.
     */
    private function getJsonData(ServerRequestInterface $request): array
    {
        $contents = $request->getBody()->getContents();
        
        if (empty($contents)) {
            return [];
        }
        
        return json_decode($contents, true) ?? [];
    }
}

