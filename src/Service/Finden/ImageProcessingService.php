<?php

declare(strict_types=1);

namespace App\Service\Finden;

use App\Exception\Finden\ImageProcessingException;
use App\Exception\Finden\ValidationException;
use App\Service\Finden\Contracts\ImageProcessorInterface;
use Psr\Log\LoggerInterface;

/**
 * Service for client-side image processing using TensorFlow.js.
 * 
 * Handles image validation, object detection for books/media items,
 * cropping, and optimization while ensuring GDPR compliance.
 */
class ImageProcessingService implements ImageProcessorInterface
{
    // Maximum image size to process (8MB)
    private const MAX_IMAGE_SIZE = 8 * 1024 * 1024;
    
    // Supported image MIME types
    private const SUPPORTED_MIME_TYPES = [
        'image/jpeg',
        'image/png',
        'image/webp',
    ];
    
    // Minimum dimensions for processing
    private const MIN_IMAGE_WIDTH = 100;
    private const MIN_IMAGE_HEIGHT = 100;
    
    // Maximum dimensions for processing
    private const MAX_IMAGE_WIDTH = 4096;
    private const MAX_IMAGE_HEIGHT = 4096;
    
    // Object detection confidence threshold (0-1)
    private const DETECTION_CONFIDENCE_THRESHOLD = 0.65;
    
    // TensorFlow model configuration
    private const MODEL_URL = 'https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd';
    
    // Classes of objects we're interested in detecting (mapped to COCO-SSD classes)
    private const TARGET_CLASSES = [
        'book' => 'book',
        'cd' => 'sports ball', // Similar shape detection
        'dvd' => 'frisbee',    // Similar shape detection
        'game' => 'suitcase',  // Similar shape for game boxes
        'card' => 'cell phone' // Similar rectangular shape
    ];
    
    private LoggerInterface $logger;
    
    public function __construct(LoggerInterface $logger)
    {
        $this->logger = $logger;
    }
    
    /**
     * {@inheritdoc}
     */
    public function processImage(string $imageData, string $mimeType): string
    {
        $this->logger->info('Processing image', [
            'mime_type' => $mimeType,
            'size' => strlen($imageData)
        ]);
        
        // Validate the image
        $this->validateImage($imageData, $mimeType);
        
        try {
            // Create image resource from the binary data
            $image = $this->createImageResource($imageData, $mimeType);
            
            // Get original dimensions
            $originalWidth = imagesx($image);
            $originalHeight = imagesy($image);
            
            $this->logger->debug('Image dimensions', [
                'width' => $originalWidth,
                'height' => $originalHeight
            ]);
            
            // Detect objects in the image
            $detectedObjects = $this->detectObjects($imageData, $mimeType);
            
            // If any objects were detected with enough confidence, crop to focus on them
            if (!empty($detectedObjects)) {
                $this->logger->info('Objects detected in image', [
                    'count' => count($detectedObjects)
                ]);
                
                // Get the bounding box covering all detected objects
                $boundingBox = $this->calculateBoundingBox($detectedObjects, $originalWidth, $originalHeight);
                
                // Crop the image to the bounding box
                $image = $this->cropImage(
                    $image, 
                    $boundingBox['x'], 
                    $boundingBox['y'], 
                    $boundingBox['width'], 
                    $boundingBox['height']
                );
                
                $this->logger->debug('Image cropped', [
                    'x' => $boundingBox['x'],
                    'y' => $boundingBox['y'],
                    'width' => $boundingBox['width'],
                    'height' => $boundingBox['height']
                ]);
            } else {
                $this->logger->info('No objects detected in image, using full image');
            }
            
            // Optimize the image
            $processedImageData = $this->optimizeImage($image, $mimeType);
            
            $this->logger->info('Image processed successfully', [
                'original_size' => strlen($imageData),
                'processed_size' => strlen($processedImageData),
                'reduction_percent' => round((1 - (strlen($processedImageData) / strlen($imageData))) * 100, 2)
            ]);
            
            return $processedImageData;
            
        } catch (\Throwable $e) {
            $this->logger->error('Error processing image', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            throw new ImageProcessingException(
                'Failed to process image: ' . $e->getMessage(),
                0,
                $e
            );
        }
    }
    
    /**
     * {@inheritdoc}
     */
    public function detectObjects(string $imageData, string $mimeType): array
    {
        $this->logger->info('Detecting objects in image');
        
        try {
            // Note: In a real implementation, this would be done client-side with TensorFlow.js
            // For server-side demonstration, we're simulating the detection
            
            // Create image resource for analysis
            $image = $this->createImageResource($imageData, $mimeType);
            $width = imagesx($image);
            $height = imagesy($image);
            
            // For demonstration, detect areas with high contrast or color variation
            // which might indicate presence of objects
            $detectedObjects = $this->simulateObjectDetection($image, $width, $height);
            
            $this->logger->info('Object detection completed', [
                'objects_found' => count($detectedObjects)
            ]);
            
            return $detectedObjects;
            
        } catch (\Throwable $e) {
            $this->logger->error('Error detecting objects', [
                'error' => $e->getMessage()
            ]);
            
            throw new ImageProcessingException(
                'Failed to detect objects in image: ' . $e->getMessage(),
                0,
                $e
            );
        }
    }
    
    /**
     * {@inheritdoc}
     */
    public function validateImage(string $imageData, string $mimeType): bool
    {
        $imageSize = strlen($imageData);
        
        // Check file size
        if ($imageSize > self::MAX_IMAGE_SIZE) {
            $this->logger->warning('Image too large', [
                'size' => $imageSize,
                'max_size' => self::MAX_IMAGE_SIZE
            ]);
            
            throw new ValidationException(
                sprintf(
                    'Image size exceeds maximum allowed size of %s MB',
                    self::MAX_IMAGE_SIZE / (1024 * 1024)
                )
            );
        }
        
        // Check MIME type
        if (!in_array($mimeType, self::SUPPORTED_MIME_TYPES)) {
            $this->logger->warning('Unsupported image type', [
                'mime_type' => $mimeType,
                'supported_types' => implode(', ', self::SUPPORTED_MIME_TYPES)
            ]);
            
            throw new ValidationException(
                sprintf(
                    'Unsupported image type: %s. Supported types: %s',
                    $mimeType,
                    implode(', ', self::SUPPORTED_MIME_TYPES)
                )
            );
        }
        
        try {
            // Create image resource to validate it's a proper image
            $image = $this->createImageResource($imageData, $mimeType);
            
            // Check dimensions
            $width = imagesx($image);
            $height = imagesy($image);
            
            if ($width < self::MIN_IMAGE_WIDTH || $height < self::MIN_IMAGE_HEIGHT) {
                $this->logger->warning('Image dimensions too small', [
                    'width' => $width,
                    'height' => $height,
                    'min_width' => self::MIN_IMAGE_WIDTH,
                    'min_height' => self::MIN_IMAGE_HEIGHT
                ]);
                
                throw new ValidationException(
                    sprintf(
                        'Image dimensions too small. Minimum dimensions: %dx%d pixels',
                        self::MIN_IMAGE_WIDTH,
                        self::MIN_IMAGE_HEIGHT
                    )
                );
            }
            
            if ($width > self::MAX_IMAGE_WIDTH || $height > self::MAX_IMAGE_HEIGHT) {
                $this->logger->warning('Image dimensions too large', [
                    'width' => $width,
                    'height' => $height,
                    'max_width' => self::MAX_IMAGE_WIDTH,
                    'max_height' => self::MAX_IMAGE_HEIGHT
                ]);
                
                throw new ValidationException(
                    sprintf(
                        'Image dimensions too large. Maximum dimensions: %dx%d pixels',
                        self::MAX_IMAGE_WIDTH,
                        self::MAX_IMAGE_HEIGHT
                    )
                );
            }
            
            // Image is valid
            return true;
            
        } catch (ValidationException $e) {
            // Re-throw validation exceptions
            throw $e;
        } catch (\Throwable $e) {
            $this->logger->error('Error validating image', [
                'error' => $e->getMessage()
            ]);
            
            throw new ValidationException(
                'Failed to validate image: ' . $e->getMessage(),
                0,
                $e
            );
        }
    }
    
    /**
     * Create an image resource from binary data.
     *
     * @param string $imageData The raw image binary data
     * @param string $mimeType The MIME type of the image
     * @return resource|\GdImage The created image resource
     * 
     * @throws ImageProcessingException When the image cannot be created
     */
    private function createImageResource(string $imageData, string $mimeType)
    {
        $image = @imagecreatefromstring($imageData);
        
        if ($image === false) {
            throw new ImageProcessingException('Failed to create image from data');
        }
        
        return $image;
    }
    
    /**
     * Crop an image to the specified dimensions.
     *
     * @param resource|\GdImage $image The image resource
     * @param int $x The starting X coordinate
     * @param int $y The starting Y coordinate
     * @param int $width The width of the cropped area
     * @param int $height The height of the cropped area
     * @return resource|\GdImage The cropped image
     */
    private function cropImage($image, int $x, int $y, int $width, int $height)
    {
        $croppedImage = imagecreatetruecolor($width, $height);
        
        // Preserve transparency for PNG images
        imagealphablending($croppedImage, false);
        imagesavealpha($croppedImage, true);
        
        // Copy and crop
        imagecopy(
            $croppedImage,
            $image,
            0, 0,
            $x, $y,
            $width, $height
        );
        
        return $croppedImage;
    }
    
    /**
     * Optimize the image for API transmission.
     *
     * @param resource|\GdImage $image The image resource
     * @param string $mime

