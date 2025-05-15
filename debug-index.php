<?php
error_log("Debug: Starting script");

// Error handling
error_reporting(E_ALL);
ini_set('display_errors', 0);

error_log("Debug: Error handling set");

// Constants
define('LOG_FILE', __DIR__ . '/public/redirect_log.txt');
define('BASE_URL', 'https://willhaben.vip');
define('WILLHABEN_AT_BASE_URL', 'https://willhaben.at');
define('SELLER_MAP', [
    '34434899' => 'rene.kapusta'
]);
define('DEFAULT_SELLER_SLUG', 'rene.kapusta');

error_log("Debug: Constants defined");

function logMessage($message) {
    error_log("Debug: logMessage called with: " . $message);
    $timestamp = date('Y-m-d H:i:s');
    $logEntry = "[{$timestamp}] {$message}" . PHP_EOL;
    
    // Write to log file
    if (file_put_contents(LOG_FILE, $logEntry, FILE_APPEND) === false) {
        error_log("Debug: Failed to write to log file");
    } else {
        error_log("Debug: Successfully wrote to log file");
    }
}

function redirectTo($url) {
    error_log("Debug: redirectTo called with URL: " . $url);
    
    // Log the redirect
    logMessage("Redirecting to: {$url}");
    
    // Send redirect headers
    header("HTTP/1.1 301 Moved Permanently");
    header("Location: {$url}");
    error_log("Debug: Headers sent for redirect");
    exit;
}

function verifySellerAndGetSlug($sellerId) {
    error_log("Debug: verifySellerAndGetSlug called with sellerId: " . $sellerId);
    
    // Sanitize seller ID (numeric only)
    $sellerId = preg_replace('/[^0-9]/', '', $sellerId);
    error_log("Debug: Sanitized sellerId: " . $sellerId);
    
    // Check if seller ID is in our map
    if (isset(SELLER_MAP[$sellerId])) {
        error_log("Debug: Found seller in map: " . SELLER_MAP[$sellerId]);
        return SELLER_MAP[$sellerId];
    }
    
    error_log("Debug: Checking for seller JSON file");
    // Look for seller JSON file in various directories
    foreach (scandir(__DIR__) as $item) {
        error_log("Debug: Checking directory item: " . $item);
        if (is_dir(__DIR__ . '/' . $item) && $item != '.' && $item != '..') {
            $jsonFile = __DIR__ . '/' . $item . '/' . $sellerId . '.json';
            error_log("Debug: Checking for JSON file: " . $jsonFile);
            if (file_exists($jsonFile)) {
                error_log("Debug: Found JSON file, returning slug: " . $item);
                return $item;
            }
        }
    }
    
    error_log("Debug: No seller found");
    return false;
}

// Function to track redirect counts
function trackRedirect($articleId) {
    error_log("Debug: trackRedirect called for articleId: " . $articleId);
    
    $dataPath = __DIR__ . '/data/redirect_tracking.json';
    $data = [];
    
    // Load existing data if available
    if (file_exists($dataPath)) {
        $jsonContent = file_get_contents($dataPath);
        $data = json_decode($jsonContent, true) ?: [];
    }
    
    $now = date('Y-m-d H:i:s');
    
    // Update or create the tracking entry
    if (isset($data[$articleId])) {
        $data[$articleId]['redirect_count']++;
        $data[$articleId]['last_redirect_timestamp'] = $now;
    } else {
        $data[$articleId] = [
            'redirect_count' => 1,
            'first_redirect_timestamp' => $now,
            'last_redirect_timestamp' => $now
        ];
    }
    
    // Save the updated data
    if (!is_dir(dirname($dataPath))) {
        mkdir(dirname($dataPath), 0777, true);
    }
    file_put_contents($dataPath, json_encode($data, JSON_PRETTY_PRINT));
    error_log("Debug: Tracking data saved for articleId: " . $articleId);
}

// Get the request URI
$requestUri = isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '';
error_log("Debug: Request URI: " . $requestUri);

// Log the incoming request
logMessage("Received request: {$requestUri}");

// Pattern matching for seller profile URLs
if (preg_match('#^/iad/kaufen-und-verkaufen/verkaeuferprofil/([0-9]+)/?$#i', $requestUri, $matches)) {
    error_log("Debug: Matched seller profile pattern");
    $sellerId = $matches[1];
    error_log("Debug: Extracted sellerId: " . $sellerId);
    
    // Log seller ID found
    logMessage("Seller ID found: {$sellerId}");
    
    // Verify seller and get slug
    $sellerSlug = verifySellerAndGetSlug($sellerId);
    error_log("Debug: Got sellerSlug: " . ($sellerSlug ?: 'false'));
    
    if ($sellerSlug) {
        error_log("Debug: Redirecting to seller profile");
        // Redirect to seller profile page
        redirectTo(BASE_URL . '/' . $sellerSlug . '/');
    } else {
        error_log("Debug: Invalid seller ID, redirecting to homepage");
        logMessage("Invalid seller ID: {$sellerId}");
        // Redirect to homepage if seller not found
        redirectTo(BASE_URL);
    }
}

// Pattern matching for marketplace URLs: /<username slug>/marketplace/<article id>
if (preg_match('#^/([a-zA-Z0-9._-]+)/marketplace/([0-9]+)/?$#i', $requestUri, $matches)) {
    error_log("Debug: Matched marketplace pattern");
    $usernameSlug = $matches[1];
    $articleId = $matches[2];
    error_log("Debug: Extracted username: " . $usernameSlug . ", articleId: " . $articleId);
    
    // Log marketplace redirect
    logMessage("Marketplace redirect: username={$usernameSlug}, articleId={$articleId}");
    
    // Track this redirect
    trackRedirect($articleId);
    
    // Redirect to article page on willhaben.at
    redirectTo(WILLHABEN_AT_BASE_URL . '/iad/object?adId=' . $articleId);
}

// Function to transform a direct buy link to our marketplace pattern
function transformDirectBuyLink($directBuyUrl, $usernameSlug = null) {
    error_log("Debug: transformDirectBuyLink called with URL: " . $directBuyUrl);
    
    // Extract article ID from URL
    if (preg_match('/-(\d+)\/?(\?|$)/', $directBuyUrl, $matches)) {
        $articleId = $matches[1];
        
        // Use provided username slug or default
        $slug = $usernameSlug ?: DEFAULT_SELLER_SLUG;
        
        $transformedUrl = BASE_URL . '/' . $slug . '/marketplace/' . $articleId;
        error_log("Debug: Transformed URL: " . $transformedUrl);
        return $transformedUrl;
    }
    
    // If unable to parse, return original URL
    error_log("Debug: Unable to transform direct buy link");
    return $directBuyUrl;
}

error_log("Debug: Script reached end without matching any patterns");

