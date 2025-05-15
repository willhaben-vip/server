<?php
// Basic error configuration
ini_set('display_errors', 'stderr');
ini_set('log_errors', '1');
ini_set('error_log', 'stderr');
error_reporting(E_ALL);

// Force errors to stderr
fwrite(STDERR, "[TEST INIT] Worker starting initialization\n");

// Debug output
error_log("[TEST] Simple worker starting at " . date('Y-m-d H:i:s'));

// Check file descriptors
error_log("[TEST] Checking file descriptors");
$stdin_meta = stream_get_meta_data(STDIN);
$stdout_meta = stream_get_meta_data(STDOUT);
error_log("[TEST] STDIN: " . print_r($stdin_meta, true));
error_log("[TEST] STDOUT: " . print_r($stdout_meta, true));
error_log("[TEST] STDIN readable: " . (is_resource(STDIN) && feof(STDIN) === false ? 'Yes' : 'No'));
error_log("[TEST] STDOUT writable: " . (is_resource(STDOUT) && !feof(STDOUT) ? 'Yes' : 'No'));

// Check environment variables
error_log("[TEST] Checking environment variables");
$env_vars = [
    'RR_RELAY' => getenv('RR_RELAY'),
    'RR_RPC' => getenv('RR_RPC'),
    'PHP_CLI_SERVER_WORKERS' => getenv('PHP_CLI_SERVER_WORKERS'),
    'RR_VERSION' => getenv('RR_VERSION'),
    'RR_DEBUG' => getenv('RR_DEBUG'),
    'RR_ENV' => getenv('RR_ENV')
];
error_log("[TEST] Environment: " . print_r($env_vars, true));

// Include autoloader
require_once __DIR__ . '/vendor/autoload.php';

// Import necessary classes
use Spiral\RoadRunner\Worker;
use Spiral\RoadRunner\Http\PSR7Worker;
use Nyholm\Psr7;

// Verify the Worker environment before creating
$workerEnv = [
    'rr_relay' => getenv('RR_RELAY'),
    'stdin' => defined('STDIN') ? 'defined' : 'undefined',
    'stdout' => defined('STDOUT') ? 'defined' : 'undefined',
    'stderr' => defined('STDERR') ? 'defined' : 'undefined'
];
error_log("[TEST] Worker environment: " . print_r($workerEnv, true));

try {
    // Verify stream status
    if (!is_resource(STDIN) || feof(STDIN)) {
        error_log("[TEST] ERROR: STDIN is not a valid resource or is at EOF");
        fwrite(STDERR, "[TEST] STDIN is not a valid resource or is at EOF\n");
    }
    
    if (!is_resource(STDOUT) || feof(STDOUT)) {
        error_log("[TEST] ERROR: STDOUT is not a valid resource or is at EOF");
        fwrite(STDERR, "[TEST] STDOUT is not a valid resource or is at EOF\n");
    }
    
    // Create PSR-7 worker with extensive error handling
    error_log("[TEST] Creating worker");
    try {
        $worker = Worker::create();
        error_log("[TEST] Worker instance created successfully");
    } catch (\Throwable $e) {
        error_log("[TEST] CRITICAL ERROR creating worker: " . $e->getMessage());
        error_log("[TEST] Trace: " . $e->getTraceAsString());
        fwrite(STDERR, "[TEST] CRITICAL ERROR creating worker: " . $e->getMessage() . "\n");
        throw $e;
    }
    
    $psrFactory = new Psr7\Factory\Psr17Factory();
    
    try {
        $psr7 = new PSR7Worker($worker, $psrFactory, $psrFactory, $psrFactory);
        error_log("[TEST] PSR7Worker instance created successfully");
    } catch (\Throwable $e) {
        error_log("[TEST] CRITICAL ERROR creating PSR7Worker: " . $e->getMessage());
        error_log("[TEST] Trace: " . $e->getTraceAsString());
        fwrite(STDERR, "[TEST] CRITICAL ERROR creating PSR7Worker: " . $e->getMessage() . "\n");
        throw $e;
    }
    
    error_log("[TEST] Worker created successfully");

    // Handle requests in a loop
    while (true) {
        // Wait for the request
        error_log("[TEST] Waiting for request");
        try {
            fwrite(STDERR, "[TEST] About to wait for request\n");
            $request = $psr7->waitRequest();
            fwrite(STDERR, "[TEST] Request received\n");
        } catch (\Throwable $e) {
            error_log("[TEST] ERROR waiting for request: " . $e->getMessage());
            error_log("[TEST] Trace: " . $e->getTraceAsString());
            fwrite(STDERR, "[TEST] ERROR waiting for request: " . $e->getMessage() . "\n");
            throw $e;
        }
        
        // Terminate if no request (RoadRunner stopped)
        if ($request === null) {
            error_log("[TEST] Received null request, exiting");
            fwrite(STDERR, "[TEST] Received null request, exiting\n");
            break;
        }
        
        // Log the request
        error_log("[TEST] Request received: " . $request->getUri()->getPath());
        
        // Create a simple response
        $response = $psrFactory->createResponse(200)
            ->withHeader('Content-Type', 'text/html; charset=utf-8')
            ->withBody($psrFactory->createStream("<html><body><h1>Hello World!</h1><p>This is a test response from RoadRunner.</p></body></html>"));
        
        // Send the response
        error_log("[TEST] Sending response");
        try {
            fwrite(STDERR, "[TEST] About to send response\n");
            $psr7->respond($response);
            fwrite(STDERR, "[TEST] Response sent successfully\n");
        } catch (\Throwable $e) {
            error_log("[TEST] ERROR sending response: " . $e->getMessage());
            error_log("[TEST] Trace: " . $e->getTraceAsString());
            fwrite(STDERR, "[TEST] ERROR sending response: " . $e->getMessage() . "\n");
            throw $e;
        }
        error_log("[TEST] Response sent");
    }
} catch (\Throwable $e) {
    $errorMsg = "[TEST] FATAL ERROR: " . $e->getMessage();
    $errorTrace = "[TEST] Trace: " . $e->getTraceAsString();
    
    error_log($errorMsg);
    error_log($errorTrace);
    
    // Write directly to STDERR to ensure the message is captured
    fwrite(STDERR, $errorMsg . "\n");
    fwrite(STDERR, $errorTrace . "\n");
    
    // Additional diagnostic information
    try {
        fwrite(STDERR, "[TEST] PHP version: " . PHP_VERSION . "\n");
        fwrite(STDERR, "[TEST] OS: " . PHP_OS . "\n");
        fwrite(STDERR, "[TEST] Directory: " . __DIR__ . "\n");
        fwrite(STDERR, "[TEST] Loaded extensions: " . implode(", ", get_loaded_extensions()) . "\n");
    } catch (\Throwable $e2) {
        fwrite(STDERR, "[TEST] Could not print diagnostic info: " . $e2->getMessage() . "\n");
    }
    
    // Exit with error code
    exit(1);
}

error_log("[TEST] Worker stopped");

