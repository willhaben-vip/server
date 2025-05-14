<?php
require_once __DIR__ . '/vendor/autoload.php';

ini_set('display_errors', 'stderr');
error_reporting(E_ALL);

use Spiral\RoadRunner\Worker;
use Spiral\RoadRunner\Http\PSR7Worker;
use Nyholm\Psr7;


// Enable debug logging
error_log("Worker starting up");

// Create PSR-7 worker
$worker = Worker::create();
$psrFactory = new Psr7\Factory\Psr17Factory();

$psr7 = new PSR7Worker($worker, $psrFactory, $psrFactory, $psrFactory);

error_log("Worker initialized");



while (true) {
    try {
        error_log("Waiting for request...");
        $request = $psr7->waitRequest();

        if ($request === null) {
            error_log("Null request received, breaking loop");
            break;
        }

        error_log("Request received: " . $request->getUri()->getPath());

        // Set up environment
        $_SERVER = [
            'REQUEST_URI' => $request->getUri()->getPath(),
            'REQUEST_METHOD' => $request->getMethod(),
            'HTTP_HOST' => $request->getUri()->getHost() ?: 'willhaben.vip',
            'REMOTE_ADDR' => '127.0.0.1',
            'SERVER_PROTOCOL' => 'HTTP/1.1',
            'SERVER_NAME' => 'willhaben.vip',
            'SERVER_PORT' => 8080,
            'SCRIPT_NAME' => '/index.php',
            'SCRIPT_FILENAME' => __DIR__ . '/public/index.php',
            'PHP_SELF' => '/index.php',
            'DOCUMENT_ROOT' => __DIR__ . '/public',
            'REQUEST_TIME' => time(),
            'REQUEST_TIME_FLOAT' => microtime(true),
            'HTTPS' => 'on'
        ];

        // Copy all request headers
        foreach ($request->getHeaders() as $name => $values) {
            $name = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
            $_SERVER[$name] = implode(', ', $values);
        }

        // Initialize other superglobals
        $_GET = [];
        parse_str($request->getUri()->getQuery(), $_GET);
        $_POST = [];
        $_COOKIE = [];
        foreach ($request->getHeader('Cookie') as $cookie) {
            parse_str(strtr($cookie, ['; ' => '&']), $parsed);
            $_COOKIE = array_merge($_COOKIE, $parsed);
        }
        $_FILES = [];

        // Ensure clean output buffer state
        while (ob_get_level() > 0) {
            ob_end_clean();
        }

        // Start fresh output buffer
        ob_start();

        try {
            error_log("Including index.php");
            require __DIR__ . '/public/index.php';
            error_log("index.php included successfully");

            // If we get here, no redirect was triggered
            $output = ob_get_clean();
            error_log("Output captured length: " . strlen($output));

            // Create normal response
            $response = $psrFactory->createResponse(200)
                ->withHeader('Content-Type', 'text/html')
                ->withHeader('Server', 'RoadRunner')
                ->withBody($psrFactory->createStream($output));

        } catch (RedirectException $e) {
            ob_end_clean();
            error_log("Redirect caught: " . $e->getUrl());

            $response = $psrFactory->createResponse($e->getStatus())
                ->withHeader('Location', $e->getUrl())
                ->withHeader('Server', 'RoadRunner');
        }

        error_log("Sending response");
        $psr7->respond($response);
        error_log("Response sent");

    } catch (\Throwable $e) {
        error_log("Error in worker: " . $e->getMessage() . "\n" . $e->getTraceAsString());

        try {
            // Ensure clean output buffer state
            while (ob_get_level() > 0) {
                ob_end_clean();
            }

            // Create error response
            $response = $psrFactory->createResponse(500)
                ->withHeader('Content-Type', 'text/plain')
                ->withHeader('Server', 'RoadRunner')
                ->withBody($psrFactory->createStream('Internal Server Error: ' . $e->getMessage()));

            $psr7->respond($response);
        } catch (\Throwable $e2) {
            error_log("Error sending error response: " . $e2->getMessage() . "\n" . $e2->getTraceAsString());
        }
    }
}
