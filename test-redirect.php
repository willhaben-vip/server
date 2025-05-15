<?php
/**
 * Test script for the new redirect patterns and tracking functionality
 * 
 * This script tests:
 * 1. Marketplace redirect pattern
 * 2. Direct buy link transformation
 * 3. Redirect tracking functionality
 */

// Include configuration and required classes
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/src/Logger.php';
require_once __DIR__ . '/src/RedirectException.php';
require_once __DIR__ . '/src/RedirectTracker.php';
require_once __DIR__ . '/src/RedirectService.php';

use Willhaben\RedirectService\Logger;
use Willhaben\RedirectService\RedirectTracker;
use Willhaben\RedirectService\RedirectService;
use Willhaben\RedirectService\RedirectException;

// Set up test environment
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Helper functions
function printHeader($title) {
    echo "\n\033[1;36m" . str_repeat("=", 80) . "\n";
    echo "=== " . $title . " ===\n";
    echo str_repeat("=", 80) . "\033[0m\n\n";
}

function printSuccess($message) {
    echo "\033[1;32m✓ SUCCESS: " . $message . "\033[0m\n";
}

function printError($message) {
    echo "\033[1;31m✗ ERROR: " . $message . "\033[0m\n";
}

function printInfo($message) {
    echo "\033[1;34mi INFO: " . $message . "\033[0m\n";
}

function printJson($data) {
    echo json_encode($data, JSON_PRETTY_PRINT) . "\n";
}

// Create instances of the required classes
$logger = new Logger(REDIRECT_LOG_FILE, 'TEST-SCRIPT');
$tracker = new RedirectTracker($logger);
$redirectService = new RedirectService($logger);

// Initialize test data
$testArticleId = "1141031082";
$testUsername = "rene.kapusta";
$testDirectBuyUrl = "https://www.willhaben.at/iad/kaufen-und-verkaufen/d/10-x-dvd-kinder-ab-0-1-6-1141031082/?checkoutMode=direct";

// Start testing
printHeader("WILLHABEN REDIRECT SYSTEM TEST");
echo "Testing the new redirect patterns and tracking functionality\n";
echo "Current time: " . date('Y-m-d H:i:s') . "\n\n";

// Test 1: Test RedirectTracker initialization
printHeader("Test 1: RedirectTracker Initialization");
try {
    // Try to retrieve data for a non-existent article to test initialization
    $data = $tracker->getArticleTracking("nonexistent-article-id");
    printSuccess("RedirectTracker initialized successfully");
    printInfo("Result for non-existent article: " . ($data ? json_encode($data) : "null (expected)"));
} catch (Exception $e) {
    printError("RedirectTracker initialization failed: " . $e->getMessage());
}

// Test 2: Test redirect tracking
printHeader("Test 2: Redirect Tracking");
try {
    // Track redirects for the test article
    echo "Tracking 3 redirects for article ID: $testArticleId\n";
    $tracker->trackRedirect($testArticleId);
    $tracker->trackRedirect($testArticleId);
    $tracker->trackRedirect($testArticleId);
    
    // Get the tracking data
    $data = $tracker->getArticleTracking($testArticleId);
    if ($data) {
        printSuccess("Successfully tracked redirects and retrieved data");
        printInfo("Tracking data for article ID $testArticleId:");
        printJson($data);
        
        // Verify count is at least 3 (or more if previous tests ran)
        if ($data['redirect_count'] >= 3) {
            printSuccess("Redirect count is correct (>= 3)");
        } else {
            printError("Redirect count is incorrect: " . $data['redirect_count']);
        }
    } else {
        printError("Failed to retrieve tracking data");
    }
} catch (Exception $e) {
    printError("Redirect tracking test failed: " . $e->getMessage());
}

// Test 3: Test transformDirectBuyLink
printHeader("Test 3: Direct Buy Link Transformation");
try {
    // Test with a valid URL
    $transformed = $redirectService->transformDirectBuyLink($testDirectBuyUrl);
    $expectedUrl = BASE_URL . '/' . DEFAULT_SELLER_SLUG . '/marketplace/' . $testArticleId;
    
    echo "Original URL: $testDirectBuyUrl\n";
    echo "Transformed URL: $transformed\n";
    echo "Expected URL: $expectedUrl\n\n";
    
    if ($transformed === $expectedUrl) {
        printSuccess("URL transformation successful");
    } else {
        printError("URL transformation failed - URLs don't match");
    }
    
    // Test with a custom username
    $transformed = $redirectService->transformDirectBuyLink($testDirectBuyUrl, "custom-user");
    $expectedUrl = BASE_URL . '/custom-user/marketplace/' . $testArticleId;
    
    if ($transformed === $expectedUrl) {
        printSuccess("URL transformation with custom username successful");
    } else {
        printError("URL transformation with custom username failed");
    }
    
    // Test with an invalid URL
    $invalidUrl = "https://example.com/invalid-url";
    $transformed = $redirectService->transformDirectBuyLink($invalidUrl);
    
    if ($transformed === $invalidUrl) {
        printSuccess("Correctly handled invalid URL by returning the original");
    } else {
        printError("Failed to handle invalid URL properly");
    }
} catch (Exception $e) {
    printError("Direct buy link transformation test failed: " . $e->getMessage());
}

// Test 4: Test marketplace redirect (can't fully test due to headers being sent)
printHeader("Test 4: Marketplace Redirect");
try {
    // We can't actually test the redirect itself without sending headers
    // But we can test the tracking logic
    echo "Testing redirect for: /$testUsername/marketplace/$testArticleId\n";
    
    // Get initial tracking count
    $initialData = $tracker->getArticleTracking($testArticleId);
    $initialCount = $initialData ? $initialData['redirect_count'] : 0;
    echo "Initial redirect count: $initialCount\n";
    
    // Call the redirect service but catch the exception
    try {
        $redirectService->handleMarketplaceRedirect($testUsername, $testArticleId);
    } catch (RedirectException $e) {
        $targetUrl = $e->getUrl();
        $expectedUrl = WILLHABEN_AT_BASE_URL . '/iad/object?adId=' . $testArticleId;
        
        if ($targetUrl === $expectedUrl) {
            printSuccess("Redirect URL correctly generated: $targetUrl");
        } else {
            printError("Incorrect redirect URL generated: $targetUrl\nExpected: $expectedUrl");
        }
    }
    
    // Check if tracking was updated
    $updatedData = $tracker->getArticleTracking($testArticleId);
    if ($updatedData && $updatedData['redirect_count'] > $initialCount) {
        printSuccess("Redirect count was updated: " . $updatedData['redirect_count']);
    } else {
        printError("Redirect count was not updated properly");
    }
} catch (Exception $e) {
    printError("Marketplace redirect test failed: " . $e->getMessage());
}

// Test 5: Edge cases and error handling
printHeader("Test 5: Edge Cases and Error Handling");

// Test with empty article ID
try {
    echo "Testing with empty article ID...\n";
    $tracker->trackRedirect("");
    $data = $tracker->getArticleTracking("");
    
    if ($data) {
        printSuccess("Empty article ID handled correctly, tracking data:");
        printJson($data);
    } else {
        printInfo("Empty article ID not tracked (this is also acceptable behavior)");
    }
} catch (Exception $e) {
    printInfo("Empty article ID threw exception: " . $e->getMessage() . " (this is acceptable behavior)");
}

// Test URL pattern matching simulation
echo "\nTesting URL pattern matching...\n";
$testUrls = [
    // Valid patterns
    "/rene.kapusta/marketplace/1141031082" => true,
    "/user-name_123/marketplace/9876543210" => true,
    "/username.with.dots/marketplace/1234" => true,
    
    // Invalid patterns
    "/rene.kapusta/wrong-path/1141031082" => false,
    "/marketplace/1141031082" => false,
    "/rene.kapusta/marketplace/" => false,
    "/rene.kapusta/marketplace/invalid-id" => false
];

foreach ($testUrls as $url => $shouldMatch) {
    $matches = [];
    $matched = preg_match('#^/([a-zA-Z0-9._-]+)/marketplace/([0-9]+)/?$#i', $url, $matches);
    
    if ($matched && $shouldMatch) {
        printSuccess("Correctly matched valid URL: $url");
        echo "  Username: " . $matches[1] . ", Article ID: " . $matches[2] . "\n";
    } elseif (!$matched && !$shouldMatch) {
        printSuccess("Correctly rejected invalid URL: $url");
    } elseif ($matched && !$shouldMatch) {
        printError("Incorrectly matched URL that should be rejected: $url");
    } else {
        printError("Failed to match URL that should be valid: $url");
    }
}

// Summary
printHeader("TEST SUMMARY");
echo "All tests completed. Check the data directory for the tracking file.\n";
echo "Tracking file path: " . TRACKING_STORAGE_PATH . "\n\n";

if (file_exists(TRACKING_STORAGE_PATH)) {
    printSuccess("Tracking storage file exists");
    
    if (TRACKING_STORAGE_TYPE === 'json') {
        $content = file_get_contents(TRACKING_STORAGE_PATH);
        $data = json_decode($content, true);
        
        echo "Current tracking data:\n";
        printJson($data);
    } else {
        printInfo("SQLite database exists at: " . TRACKING_STORAGE_PATH);
    }
} else {
    printError("Tracking storage file does not exist");
}

echo "\nTest completed at: " . date('Y-m-d H:i:s') . "\n";

