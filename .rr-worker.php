<?php
/**
 * RoadRunner Worker Script
 */

use Willhaben\RedirectService\Logger;
use Willhaben\RedirectService\RedirectService;
use Willhaben\RedirectService\RedirectException;

// Setup error handling
ini_set('display_errors', 'stderr');
ini_set('log_errors', '1');
ini_set('error_log', 'stderr');
error_reporting(E_ALL);

// Include configuration and autoloader
require_once __DIR__ . '/config/config.php';
require_once __DIR__ . '/vendor/autoload.php';

// Initialize logger
$logger = new Logger(WORKER_LOG_FILE, 'WORKER');
$logger->debug("Starting worker");

try {
    // Initialize redirect service
    $redirectService = new RedirectService(new Logger(REDIRECT_LOG_FILE, 'APP'));

    // Create worker
    $worker = Spiral\RoadRunner\Worker::create();
    $psrFactory = new Nyholm\Psr7\Factory\Psr17Factory();
    $psr7 = new Spiral\RoadRunner\Http\PSR7Worker($worker, $psrFactory, $psrFactory, $psrFactory);
    
    $logger->debug("Worker initialized successfully");
    
    while (true) {
        try {
            $request = $psr7->waitRequest();
            
            if ($request === null) {
                $logger->debug("Termination request received");
                break;
            }

            $path = $request->getUri()->getPath();
            $logger->debug("Processing request", ['path' => $path]);

            // Set up server environment
            $_SERVER = [
                'REQUEST_URI' => $path,
                'REQUEST_METHOD' => $request->getMethod(),
                'HTTP_HOST' => $request->getHeaderLine('Host') ?: 'localhost',
                'SCRIPT_NAME' => '/index.php',
                'DOCUMENT_ROOT' => APP_ROOT . '/public/member',
                'SCRIPT_FILENAME' => APP_ROOT . '/public/member/index.php',
                'PHP_SELF' => '/index.php',
                'REMOTE_ADDR' => '127.0.0.1',
                'SERVER_PROTOCOL' => 'HTTP/1.1'
            ];
            
            // Parse query parameters
            $_GET = [];
            parse_str($request->getUri()->getQuery(), $_GET);

            try {
                // Process the request based on URL pattern
                if (preg_match('#^/iad/kaufen-und-verkaufen/verkaeuferprofil/([0-9]+)/?$#i', $path, $matches)) {
                    $redirectService->handleSellerRedirect($matches[1]);
                } elseif (preg_match('#^/iad/kaufen-und-verkaufen/d/([\w-]+)-([0-9]+)/?$#i', $path, $matches)) {
                    $redirectService->handleProductRedirect($matches[1], $matches[2]);
                } else {
                    // Default: redirect to homepage
                    throw new RedirectException(BASE_URL, 302);
                }

            } catch (RedirectException $re) {
                $logger->debug("Handling redirect", [
                    'url' => $re->getUrl(),
                    'status' => $re->getStatus()
                ]);
                
                $response = $psrFactory->createResponse($re->getStatus())
                    ->withHeader('Location', $re->getUrl())
                    ->withBody($psrFactory->createStream(''));
                    
                $psr7->respond($response);
                continue;
            }
            
        } catch (\Throwable $e) {
            $logger->error("Error processing request", $e);
            
            while (ob_get_level() > 0) {
                ob_end_clean();
            }
            
            try {
                $psr7->respond(
                    $psrFactory->createResponse(500)
                        ->withHeader('Content-Type', 'text/plain')
                        ->withBody($psrFactory->createStream("Internal Server Error: " . $e->getMessage()))
                );
            } catch (\Throwable $innerException) {
                $logger->error("Failed to send error response", $innerException);
            }
        }
    }
} catch (\Throwable $e) {
    $logger->error("Fatal error", $e);
    exit(1);
}

$logger->debug("Worker stopped");
