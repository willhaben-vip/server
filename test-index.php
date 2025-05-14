<?php
// Enable error logging to stderr
ini_set('display_errors', 'stderr');
error_reporting(E_ALL);

error_log("Starting test script");

// Set up similar environment to RoadRunner worker
$_SERVER = [
    'REQUEST_URI' => '/iad/kaufen-und-verkaufen/verkaeuferprofil/34434899',  // Test a known seller ID route
    'REQUEST_METHOD' => 'GET',
    'HTTP_HOST' => 'willhaben.vip',
    'REMOTE_ADDR' => '127.0.0.1',
    'SERVER_PROTOCOL' => 'HTTP/1.1',
    'SERVER_NAME' => 'willhaben.vip',
    'SERVER_PORT' => 8080,
    'SCRIPT_NAME' => '/index.php',
    'SCRIPT_FILENAME' => __DIR__ . '/debug-index.php',
    'PHP_SELF' => '/index.php',
    'DOCUMENT_ROOT' => __DIR__,
    'REQUEST_TIME' => time(),
    'REQUEST_TIME_FLOAT' => microtime(true),
    'HTTPS' => 'on'
];

error_log("Environment set up");

// Initialize other superglobals
$_GET = [];
$_POST = [];
$_COOKIE = [];
$_FILES = [];

// Define header function in global scope
if (!function_exists('header')) {
    function header($string, $replace = true, $http_response_code = null) {
        error_log("Header called: " . $string);
        if (strpos($string, 'Location:') === 0) {
            error_log("Redirect attempted to: " . substr($string, 10));
            throw new Exception("Redirect caught: " . substr($string, 10));
        }
    }
}

// Register error handler
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    error_log("PHP Error [$errno]: $errstr in $errfile on line $errline");
    return false;
});

// Register shutdown function
register_shutdown_function(function() {
    $error = error_get_last();
    if ($error !== null) {
        error_log("Fatal error: " . print_r($error, true));
    }
});

error_log("Handlers registered");

// Start output buffering
ob_start();

try {
    error_log("About to include debug-index.php");
    require __DIR__ . '/debug-index.php';
    error_log("debug-index.php included successfully");
} catch (\Throwable $e) {
    if ($e->getMessage() !== "Exit called") {
        error_log("Error: " . $e->getMessage());
        error_log("Stack trace: " . $e->getTraceAsString());
    }
}

$output = ob_get_clean();
error_log("Output length: " . strlen($output));
if (strlen($output) > 0) {
    error_log("Output content: " . substr($output, 0, 1000));
}
echo $output;

