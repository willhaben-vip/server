<?php

declare(strict_types=1);

namespace App\Service\Finden\WillhabenApiService;

use App\Service\Finden\Contracts\ApiClientInterface;
use GuzzleHttp\Client;
use GuzzleHttp\Exception\GuzzleException;
use Psr\Log\LoggerInterface;

/**
 * Implementation of the willhaben.at API client.
 * 
 * Handles communication with the willhaben.at API for both image and text search.
 */
class WillhabenApiService implements ApiClientInterface
{
    private const IMAGE_SEARCH_ENDPOINT = 'https://www.willhaben.at/webapi/iad/imagesearch/atz';
    private const TEXT_SEARCH_ENDPOINT = 'https://www.willhaben.at/webapi/search/classified';
    
    private Client $httpClient;
    private LoggerInterface $logger;
    
    public function __construct(
        Client $httpClient,
        LoggerInterface $logger
    ) {
        $this->httpClient = $httpClient;
        $this->logger = $logger;
    }
    
    /**
     * {@inheritdoc}
     */
    public function sendImageSearch(string $imageData): array
    {
        $this->logger->info('Sending image search request to willhaben.at');
        
        try {
            // Create request with all required headers based on the provided curl example
            $response = $this->httpClient->request('PUT', self::IMAGE_SEARCH_ENDPOINT, [
                'headers' => [
                    'Content-Type' => 'image/jpeg',
                    'Accept' => 'application/json',
                    'Pragma' => 'no-cache',
                    'Cache-Control' => 'no-cache',
                    'Sec-Fetch-Mode' => 'cors',
                    'Origin' => 'https://www.willhaben.at',
                    'Referer' => 'https://www.willhaben.at/iad/kaufen-und-verkaufen',
                    'User-Agent' => 'Mozilla/5.0 (compatible; FindenSearchBot/1.0; +https://yourdomain.com/bot)',
                    'X-WH-Client' => 'api@willhaben.at;responsive_web;server;1.0.0;desktop',
                ],
                'body' => $imageData,
            ]);
            
            $statusCode = $response->getStatusCode();
            
            if ($statusCode !== 200) {
                $this->logger->error('Non-200 response from willhaben.at image search API', [
                    'status_code' => $statusCode
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    "Image search API returned non-200 status code: $statusCode"
                );
            }
            
            $responseBody = (string) $response->getBody();
            $responseData = json_decode($responseBody, true);
            
            if (json_last_error() !== JSON_ERROR_NONE) {
                $this->logger->error('Failed to parse JSON response from willhaben.at', [
                    'error' => json_last_error_msg()
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    'Failed to parse JSON response from image search API: ' . json_last_error_msg()
                );
            }
            
            $this->logger->info('Successfully received and parsed image search response', [
                'results_count' => isset($responseData['advertSummaryList']['advertSummary']) 
                    ? count($responseData['advertSummaryList']['advertSummary']) 
                    : 0
            ]);
            
            return $this->formatSearchResults($responseData);
            
        } catch (GuzzleException $e) {
            $this->logger->error('HTTP request error during image search', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            throw new \App\Exception\Finden\ApiCommunicationException(
                'Error communicating with image search API: ' . $e->getMessage(),
                0,
                $e
            );
        } catch (\Throwable $e) {
            if (!$e instanceof \App\Exception\Finden\ApiCommunicationException) {
                $this->logger->error('Unexpected error during image search', [
                    'error' => $e->getMessage(),
                    'trace' => $e->getTraceAsString()
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    'Unexpected error during image search: ' . $e->getMessage(),
                    0,
                    $e
                );
            }
            
            throw $e;
        }
    }
    
    /**
     * {@inheritdoc}
     */
    public function sendTextSearch(string $query, array $options = []): array
    {
        $this->logger->info('Sending text search request to willhaben.at', [
            'query' => $query
        ]);
        
        try {
            // Prepare search parameters
            $searchParams = [
                'query' => $query,
                'rows' => $options['rows'] ?? 30,
                'page' => $options['page'] ?? 1,
                // Add any additional filtering parameters
                'categoryId' => $options['categoryId'] ?? null,
                'PRICE_FROM' => $options['priceFrom'] ?? null,
                'PRICE_TO' => $options['priceTo'] ?? null,
            ];
            
            // Filter out null values
            $searchParams = array_filter($searchParams, function ($value) {
                return $value !== null;
            });
            
            // Create request
            $response = $this->httpClient->request('GET', self::TEXT_SEARCH_ENDPOINT, [
                'headers' => [
                    'Accept' => 'application/json',
                    'User-Agent' => 'Mozilla/5.0 (compatible; FindenSearchBot/1.0; +https://yourdomain.com/bot)',
                ],
                'query' => $searchParams,
            ]);
            
            $statusCode = $response->getStatusCode();
            
            if ($statusCode !== 200) {
                $this->logger->error('Non-200 response from willhaben.at text search API', [
                    'status_code' => $statusCode
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    "Text search API returned non-200 status code: $statusCode"
                );
            }
            
            $responseBody = (string) $response->getBody();
            $responseData = json_decode($responseBody, true);
            
            if (json_last_error() !== JSON_ERROR_NONE) {
                $this->logger->error('Failed to parse JSON response from willhaben.at', [
                    'error' => json_last_error_msg()
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    'Failed to parse JSON response from text search API: ' . json_last_error_msg()
                );
            }
            
            $this->logger->info('Successfully received and parsed text search response', [
                'results_count' => isset($responseData['advertSummaryList']['advertSummary']) 
                    ? count($responseData['advertSummaryList']['advertSummary']) 
                    : 0
            ]);
            
            return $this->formatSearchResults($responseData);
            
        } catch (GuzzleException $e) {
            $this->logger->error('HTTP request error during text search', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            throw new \App\Exception\Finden\ApiCommunicationException(
                'Error communicating with text search API: ' . $e->getMessage(),
                0,
                $e
            );
        } catch (\Throwable $e) {
            if (!$e instanceof \App\Exception\Finden\ApiCommunicationException) {
                $this->logger->error('Unexpected error during text search', [
                    'error' => $e->getMessage(),
                    'trace' => $e->getTraceAsString()
                ]);
                
                throw new \App\Exception\Finden\ApiCommunicationException(
                    'Unexpected error during text search: ' . $e->getMessage(),
                    0,
                    $e
                );
            }
            
            throw $e;
        }
    }
    
    /**
     * Format the raw willhaben.at API response into a more usable structure.
     *
     * @param array $responseData The raw API response data
     * @return array The formatted search results
     */
    private function formatSearchResults(array $responseData): array
    {
        $formattedResults = [
            'total' => $responseData['rowsFound'] ?? 0,
            'page' => $responseData['pageRequested'] ?? 1,
            'items' => [],
        ];
        
        if (isset($responseData['advertSummaryList']['advertSummary']) && 
            is_array($responseData['advertSummaryList']['advertSummary'])) {
            
            foreach ($responseData['advertSummaryList']['advertSummary'] as $ad) {
                $item = $this->formatAdItem($ad);
                
                if ($item) {
                    $formattedResults['items'][] = $item;
                }
            }
        }
        
        return $formattedResults;
    }
    
    /**
     * Format a single advertisement item from the willhaben.at API.
     *
     * @param array $ad The raw advertisement data
     * @return array|null The formatted item, or null if invalid
     */
    private function formatAdItem(array $ad): ?array
    {
        if (empty($ad['id'])) {
            return null;
        }
        
        // Extract attributes from the ad
        $attributes = [];
        if (isset($ad['attributes']['attribute']) && is_array($ad['attributes']['attribute'])) {
            foreach ($ad['attributes']['attribute'] as $attr) {
                if (isset($attr['name'], $attr['values']) && !empty($attr['values'])) {
                    $attributes[$attr['name']] = is_array($attr['values']) ? $attr['values'][0] : $attr['values'];
                }
            }
        }
        
        // Extract images
        $images = [];
        if (isset($ad['advertImageList']['advertImage']) && is_array($ad['advertImageList']['advertImage'])) {
            foreach ($ad['advertImageList']['advertImage'] as $image) {
                if (isset($image['mainImageUrl'])) {
                    $images[] = $image['mainImageUrl'];
                }
            }
        }
        
        // Create formatted item
        return [
            'id' => $ad['id'],
            'title' => $ad['description'] ?? '',
            'price' => $attributes['PRICE'] ?? null,
            'priceFormatted' => $attributes['PRICE_FOR_DISPLAY'] ?? null,
            'location' => $attributes['LOCATION'] ?? null,
            'images' => $images,
            'url' => isset($ad['selfLink']) ? 'https://www.willhaben.at' . $ad['selfLink'] : null,
            'description' => $attributes['BODY_DYN'] ?? null,
            'timestamp' => $attributes['PUBLISHED_String'] ?? null,
        ];
    }
}

