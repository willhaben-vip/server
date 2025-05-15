<?php
/**
 * RoadRunner Worker Script
 */

use Willhaben\RedirectService\Logger;
use Willhaben\RedirectService\RedirectService;
use Willhaben\RedirectService\RedirectException;
use Nyholm\Psr7;

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

function serveStaticFile(string $path, Psr7\Factory\Psr17Factory $psrFactory, Logger $logger): \Psr\Http\Message\ResponseInterface {
    // Use relative path structure based on current directory
    $basePath = rtrim(__DIR__ . '/public/member', '/');
    
    // If path is empty or just /, default to signup/index.htm
    if ($path === '/' || $path === '') {
        $path = '/signup/index.htm';
    }
    
    // Normalize path: remove leading slash if present
    if (str_starts_with($path, '/')) {
        $path = substr($path, 1);
    }
    
    // Properly join paths to avoid double slashes
    $fullPath = $basePath . '/' . $path;
    
    // Normalize path to remove any potential double slashes
    $fullPath = str_replace('//', '/', $fullPath);
    
    $logger->debug("Static file request", [
        'original_path' => $path,
        'normalized_path' => $path,
        'base_path' => $basePath,
        'full_path' => $fullPath,
        'file_exists' => file_exists($fullPath) ? 'true' : 'false',
        'is_readable' => is_readable($fullPath) ? 'true' : 'false',
        'current_dir' => getcwd(),
        'script_dir' => __DIR__
    ]);
    
    // Try resolving the real path for debugging
    $attemptedRealPath = realpath($fullPath);
    
    $logger->debug("Static file full path resolution", [
        'input_path' => $path,
        'full_path' => $fullPath,
        'real_path_attempt' => $attemptedRealPath ?: 'false',
        'exists' => file_exists($fullPath) ? 'true' : 'false',
        'is_file' => is_file($fullPath) ? 'true' : 'false',
        'is_readable' => is_readable($fullPath) ? 'true' : 'false',
        'is_dir' => is_dir($fullPath) ? 'true' : 'false'
    ]);
    
    // Validate path to prevent directory traversal
    $realPath = realpath($fullPath);
    $publicMemberPath = realpath($basePath);
    
    if ($realPath === false || !str_starts_with($realPath, $publicMemberPath)) {
        $logger->debug("Directory traversal attempt or invalid path", [
            'path' => $path,
            'real_path' => $realPath ?: 'false',
            'public_member_path' => $publicMemberPath
        ]);
        
        // Default to signup page instead of redirecting
        $fullPath = $basePath . '/signup/index.htm';
        $realPath = realpath($fullPath);
        
        if ($realPath === false) {
            $response = $psrFactory->createResponse(404)
                ->withHeader('Content-Type', 'text/plain')
                ->withBody($psrFactory->createStream('File not found: signup/index.htm'));
            return $response;
        }
    }
    
    if (!file_exists($fullPath)) {
        // Try to append index.htm if directory
        if (is_dir($fullPath)) {
            $fullPath = rtrim($fullPath, '/');
            if (file_exists($fullPath . '/index.htm')) {
                $fullPath .= '/index.htm';
                $logger->debug("Using index.htm", ['path' => $fullPath]);
            } elseif (file_exists($fullPath . '/index.html')) {
                $fullPath .= '/index.html';
                $logger->debug("Using index.html", ['path' => $fullPath]);
            } else {
                $logger->debug("Directory index not found", ['dir' => $fullPath]);
                // Default to signup/index.htm instead of redirecting
                $fullPath = $basePath . '/signup/index.htm';
                // Normalize path again to avoid any potential double slashes
                $fullPath = str_replace('//', '/', $fullPath);
            }
        } else {
            $logger->debug("File not found", ['path' => $fullPath]);
            // Default to signup/index.htm instead of redirecting
            $fullPath = $basePath . '/signup/index.htm';
            // Normalize path again to avoid any potential double slashes
            $fullPath = str_replace('//', '/', $fullPath);
        }
        
        $logger->debug("Defaulting to fallback file", [
            'fallback_path' => $fullPath,
            'fallback_exists' => file_exists($fullPath) ? 'true' : 'false',
            'fallback_readable' => is_readable($fullPath) ? 'true' : 'false'
        ]);
    }
    
    if (!is_file($fullPath) || !is_readable($fullPath)) {
        $logger->debug("File not readable", ['path' => $fullPath]);
        $response = $psrFactory->createResponse(404)
            ->withHeader('Content-Type', 'text/plain')
            ->withBody($psrFactory->createStream('File not found or not readable'));
        return $response;
    }

    $mimeTypes = [
        'htm' => 'text/html',
        'html' => 'text/html',
        'css' => 'text/css',
        'js' => 'application/javascript',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'xml' => 'application/xml',
        'md' => 'text/markdown',
    ];

    $ext = strtolower(pathinfo($fullPath, PATHINFO_EXTENSION));
    $contentType = $mimeTypes[$ext] ?? 'application/octet-stream';
    
    try {
        $size = filesize($fullPath);
        $logger->debug("Reading file", [
            'path' => $fullPath, 
            'real_path' => realpath($fullPath) ?: 'false',
            'size' => $size, 
            'type' => $contentType
        ]);
        
        if ($size > 1024 * 1024) { // If file is larger than 1MB
            $stream = fopen($fullPath, 'r');
            if ($stream === false) {
                throw new \RuntimeException("Failed to open file: $fullPath");
            }
            $body = $psrFactory->createStreamFromResource($stream);
        } else {
            $content = file_get_contents($fullPath);
            if ($content === false) {
                throw new \RuntimeException("Failed to read file: $fullPath");
            }
            $body = $psrFactory->createStream($content);
        }
        
        $logger->debug("Successfully read file", ['path' => $fullPath]);
        $response = $psrFactory->createResponse(200)
            ->withHeader('Content-Type', $contentType)
            ->withHeader('Content-Length', (string)$size)
            ->withBody($body);
        
        $logger->debug("Static file response", [
            'status' => $response->getStatusCode(),
            'content_type' => $response->getHeaderLine('Content-Type'),
            'content_length' => $response->getHeaderLine('Content-Length')
        ]);
        
        return $response;
            
    } catch (\Throwable $e) {
        $logger->error("Failed to serve file", $e);
        return redirectToSignup($psrFactory, $logger);
    }
}

/**
 * Redirects to the signup page
 */
function redirectToSignup(Psr7\Factory\Psr17Factory $psrFactory, Logger $logger): \Psr\Http\Message\ResponseInterface {
    $redirectUrl = '/signup';
    $logger->debug("Redirecting to signup page", ['url' => $redirectUrl]);
    
    return $psrFactory->createResponse(302)
        ->withHeader('Location', $redirectUrl)
        ->withBody($psrFactory->createStream(''));
}

try {
    // Initialize redirect service
    $redirectService = new RedirectService(new Logger(REDIRECT_LOG_FILE, 'APP'));

    // Create worker
    $worker = Spiral\RoadRunner\Worker::create();
    $psrFactory = new Psr7\Factory\Psr17Factory();
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
            $logger->debug("Request received", [
                'path' => $path,
                'method' => $request->getMethod(),
                'uri' => (string)$request->getUri(),
                'headers' => $request->getHeaders(),
                'server_info' => [
                    'cwd' => getcwd(),
                    'script_dir' => __DIR__,
                    'document_root' => dirname(__DIR__) . '/public/member'
                ]
            ]);
            
            $logger->debug("Processing request", [
                'path' => $path,
                'method' => $request->getMethod(),
                'headers' => $request->getHeaders()
            ]);
            
            // Log if the path looks like a static file path
            $isRootPath = ($path === '/' || $path === '');
            $isStaticPattern = preg_match('#^/(member|signup|admin|sysadmin)(/.*)?$#', $path);
            $logger->debug("Path classification", [
                'path' => $path,
                'is_root_path' => $isRootPath ? 'true' : 'false',
                'matches_static_pattern' => $isStaticPattern ? 'true' : 'false',
                'static_pattern' => '#^/(member|signup|admin|sysadmin)(/.*)?$#'
            ]);

            // Set up server environment
            $_SERVER = [
                'REQUEST_URI' => $path,
                'REQUEST_METHOD' => $request->getMethod(),
                'HTTP_HOST' => $request->getHeaderLine('Host') ?: 'localhost',
                'SCRIPT_NAME' => '/index.php',
                'DOCUMENT_ROOT' => dirname(__DIR__) . '/public/member',
                'SCRIPT_FILENAME' => dirname(__DIR__) . '/public/member/index.php',
                'PHP_SELF' => '/index.php',
                'REMOTE_ADDR' => '127.0.0.1',
                'SERVER_PROTOCOL' => 'HTTP/1.1'
            ];
            
            // Parse query parameters
            $_GET = [];
            parse_str($request->getUri()->getQuery(), $_GET);

            try {
                // Static file handling for member paths and root path
                // Check if path is the root path ('/' or empty)
                if ($path === '/' || $path === '' || $path === '/signup' || $path === '/signup/') {
                    $logger->debug("Root or signup path detected, serving signup page", [
                        'path' => $path,
                        'serving_file' => '/signup/index.htm',
                        'full_path' => '/app/public/member/signup/index.htm'
                    ]);
                    
                    // Directly serve the file based on the path
                    $filePath = ($path === '/' || $path === '') ? '/signup/index.htm' : $path;
                    $response = serveStaticFile($filePath, $psrFactory, $logger);
                    $psr7->respond($response);
                    continue;
                }

                // Pattern for static file paths including rene.kapusta
                $pattern = '#^/(member|signup|admin|sysadmin|rene\.kapusta)(/.*)?$#';
                $logger->debug("Checking static path pattern", [
                    'path' => $path,
                    'pattern' => $pattern,
                    'preg_match_result' => (int)preg_match($pattern, $path),
                    'preg_last_error' => preg_last_error(),
                    'preg_last_error_msg' => preg_last_error_msg()
                ]);
                if (preg_match($pattern, $path, $matches)) {
                    $logger->debug("Static path match found", [
                        'original_path' => $path,
                        'matched_prefix' => $matches[1],
                        'matched_suffix' => $matches[2] ?? '',
                        'normalized_path' => rtrim($path, '/'),
                        'raw_matches' => $matches
                    ]);
                    
                    // Normalize path to handle both with and without trailing slash
                    $normalizedPath = rtrim($path, '/');
                    
                    $response = serveStaticFile($normalizedPath, $psrFactory, $logger);
                    $logger->debug("Static file response complete", [
                        'status' => $response->getStatusCode(),
                        'headers' => $response->getHeaders(),
                        'body_size' => $response->getBody()->getSize()
                    ]);
                    
                    // For 4xx or 5xx responses, redirect to signup instead
                    if ($response->getStatusCode() >= 400) {
                        $logger->debug("Static file error response, redirecting to signup", [
                            'original_status' => $response->getStatusCode()
                        ]);
                        $psr7->respond(redirectToSignup($psrFactory, $logger));
                    } else {
                        $psr7->respond($response);
                    }
                    continue; // Skip the rest of the request processing
                }
                
                // Process the request based on URL pattern
                if (preg_match('#^/iad/kaufen-und-verkaufen/verkaeuferprofil/([0-9]+)/?$#i', $path, $matches)) {
                    $redirectService->handleSellerRedirect($matches[1]);
                } elseif (preg_match('#^/iad/kaufen-und-verkaufen/d/([\w-]+)-([0-9]+)/?$#i', $path, $matches)) {
                    $redirectService->handleProductRedirect($matches[1], $matches[2]);
                } else {
                    // Instead of redirecting to BASE_URL, redirect to /signup
                    $logger->debug("Unmatched path, redirecting to signup page");
                    $psr7->respond(redirectToSignup($psrFactory, $logger));
                    continue;
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
