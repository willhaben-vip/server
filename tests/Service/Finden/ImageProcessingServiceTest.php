<?php

declare(strict_types=1);

namespace Tests\Service\Finden;

use App\Exception\Finden\ImageProcessingException;
use App\Exception\Finden\ValidationException;
use App\Service\Finden\ImageProcessingService;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;

/**
 * Test suite for the ImageProcessingService class
 */
class ImageProcessingServiceTest extends TestCase
{
    private LoggerInterface $logger;
    private ImageProcessingService $service;
    private string $fixturesDir;

    protected function setUp(): void
    {
        $this->fixturesDir = __DIR__ . '/Fixtures/images';
        
        // Create a mock logger
        $this->logger = $this->createMock(LoggerInterface::class);
        
        // Create the service with mock dependencies
        $this->service = new ImageProcessingService($this->logger);
    }

    /**
     * Test that valid images pass validation
     */
    public function testValidImagePassesValidation(): void
    {
        // Arrange
        $validImagePath = $this->fixturesDir . '/book.jpg';
        $this->createTestImage($validImagePath, 800, 600);
        $imageData = file_get_contents($validImagePath);
        
        // Act
        $result = $this->service->validateImage($imageData, 'image/jpeg');
        
        // Assert
        $this->assertTrue($result, 'Valid image should pass validation');
        
        // Clean up
        unlink($validImagePath);
    }
    
    /**
     * Test that image validation rejects unsupported formats
     */
    public function testValidationRejectsUnsupportedFormat(): void
    {
        // Arrange
        $imageData = 'invalid image data';
        
        // Assert
        $this->expectException(ValidationException::class);
        $this->expectExceptionMessage('Unsupported image type');
        
        // Act
        $this->service->validateImage($imageData, 'image/bmp');
    }
    
    /**
     * Test that image validation rejects oversized images
     */
    public function testValidationRejectsOversizedImage(): void
    {
        // Arrange
        $this->logger->expects($this->once())
            ->method('warning')
            ->with('Image too large');

        // Create a mock that simulates a very large image
        $largeImageData = str_repeat('x', 10 * 1024 * 1024); // 10MB

        // Assert
        $this->expectException(ValidationException::class);
        $this->expectExceptionMessage('Image size exceeds maximum allowed size');
        
        // Act
        $this->service->validateImage($largeImageData, 'image/jpeg');
    }
    
    /**
     * Test that object detection works as expected
     */
    public function testObjectDetection(): void
    {
        // Arrange
        $validImagePath = $this->fixturesDir . '/book.jpg';
        $this->createTestImage($validImagePath, 800, 600);
        $imageData = file_get_contents($validImagePath);
        
        // Act
        $objects = $this->service->detectObjects($imageData, 'image/jpeg');
        
        // Assert
        $this->assertIsArray($objects);
        $this->assertNotEmpty($objects, 'Should detect at least one object');
        
        // Check that each detected object has the required properties
        foreach ($objects as $object) {
            $this->assertArrayHasKey('class', $object);
            $this->assertArrayHasKey('confidence', $object);
            $this->assertArrayHasKey('bbox', $object);
            $this->assertIsArray($object['bbox']);
            $this->assertArrayHasKey('x', $object['bbox']);
            $this->assertArrayHasKey('y', $object['bbox']);
            $this->assertArrayHasKey('width', $object['bbox']);
            $this->assertArrayHasKey('height', $object['bbox']);
        }
        
        // Clean up
        unlink($validImagePath);
    }
    
    /**
     * Test that image processing works end-to-end
     */
    public function testImageProcessing(): void
    {
        // Arrange
        $validImagePath = $this->fixturesDir . '/book.jpg';
        $this->createTestImage($validImagePath, 800, 600);
        $imageData = file_get_contents($validImagePath);
        
        // Act
        $processedData = $this->service->processImage($imageData, 'image/jpeg');
        
        // Assert
        $this->assertIsString($processedData);
        $this->assertNotEmpty($processedData, 'Processed image should not be empty');
        
        // Verify the processed image is valid (can be loaded as an image)
        $processedImagePath = $this->fixturesDir . '/processed.jpg';
        file_put_contents($processedImagePath, $processedData);
        $processedImage = @imagecreatefromjpeg($processedImagePath);
        $this->assertNotFalse($processedImage, 'Processed data should be a valid image');
        
        // Clean up
        unlink($validImagePath);
        unlink($processedImagePath);
        if ($processedImage) {
            imagedestroy($processedImage);
        }
    }
    
    /**
     * Test error handling for image processing failures
     */
    public function testErrorHandlingForProcessingFailures(): void
    {
        // Arrange
        $invalidImagePath = $this->fixturesDir . '/invalid.jpg';
        file_put_contents($invalidImagePath, 'This is not a valid image data');
        $invalidData = file_get_contents($invalidImagePath);
        
        // Assert
        $this->expectException(ImageProcessingException::class);
        
        // Act
        $this->service->processImage($invalidData, 'image/jpeg');
        
        // Clean up
        unlink($invalidImagePath);
    }
    
    /**
     * Test that memory usage stays within acceptable limits during processing
     */
    public function testMemoryUsageStaysWithinLimits(): void
    {
        // Arrange
        $initialMemory = memory_get_usage(true);
        $validImagePath = $this->fixturesDir . '/book.jpg';
        $this->createTestImage($validImagePath, 1200, 900); // Larger image to test memory usage
        $imageData = file_get_contents($validImagePath);
        
        // Act
        $this->service->processImage($imageData, 'image/jpeg');
        $peakMemory = memory_get_peak_usage(true);
        
        // Clean up
        unlink($validImagePath);
        
        // Calculate memory used for the operation
        $memoryUsed = $peakMemory - $initialMemory;
        
        // Assert - ensure memory usage is within acceptable limits
        // Typically, processing a 1200x900 image shouldn't use more than 50MB of memory
        $maxAcceptableMemory = 50 * 1024 * 1024; // 50MB
        $this->assertLessThan(
            $maxAcceptableMemory,
            $memoryUsed,
            sprintf(
                'Memory usage (%s MB) exceeds acceptable limit (%s MB)',
                round($memoryUsed / (1024 * 1024), 2),
                round($maxAcceptableMemory / (1024 * 1024), 2)
            )
        );
        
        // Also verify that memory is properly released after processing
        $finalMemory = memory_get_usage(true);
        $this->assertLessThan(
            $initialMemory * 1.5, // Allow for some overhead that might not be immediately collected
            $finalMemory,
            'Memory should be properly released after processing'
        );
    }
    
    /**
     * Test that processing performance meets requirements
     */
    public function testPerformanceMeetsRequirements(): void
    {
        // Arrange
        $validImagePath = $this->fixturesDir . '/book.jpg';
        $this->createTestImage($validImagePath, 800, 600);
        $imageData = file_get_contents($validImagePath);
        
        // Define acceptable processing time (in seconds)
        $maxProcessingTime = 2.0; // 2 seconds
        
        // Act - measure processing time
        $startTime = microtime(true);
        $this->service->processImage($imageData, 'image/jpeg');
        $endTime = microtime(true);
        $processingTime = $endTime - $startTime;
        
        // Clean up
        unlink($validImagePath);
        
        // Assert - processing time should be within acceptable limits
        $this->assertLessThan(
            $maxProcessingTime,
            $processingTime,
            sprintf(
                'Processing time (%.3f seconds) exceeds acceptable limit (%.1f seconds)',
                $processingTime,
                $maxProcessingTime
            )
        );
        
        // Log the processing time for reference
        echo sprintf("Image processing completed in %.3f seconds\n", $processingTime);
    }
    
    /**
     * Test that the service handles concurrent processing correctly
     */
    public function testHandlesConcurrentProcessing(): void
    {
        // Arrange - create multiple test images
        $testImages = [];
        $imagePaths = [];
        $imageCount = 3; // Number of concurrent images to process
        
        for ($i = 0; $i < $imageCount; $i++) {
            $imagePath = $this->fixturesDir . "/concurrent_$i.jpg";
            $this->createTestImage($imagePath, 800, 600);
            $imagePaths[] = $imagePath;
            $testImages[] = file_get_contents($imagePath);
        }
        
        // Act - process images "concurrently" (simulated in PHP)
        $results = [];
        $exceptions = [];
        
        // In a real concurrent environment, these would be separate threads/processes
        foreach ($testImages as $index => $imageData) {
            try {
                // Process each image
                $results[$index] = $this->service->processImage($imageData, 'image/jpeg');
            } catch (\Throwable $e) {
                $exceptions[$index] = $e;
            }
        }
        
        // Clean up
        foreach ($imagePaths as $path) {
            unlink($path);
        }
        
        // Assert - all images should be processed successfully
        $this->assertCount(
            $imageCount,
            $results,
            'All images should be processed successfully in concurrent scenario'
        );

