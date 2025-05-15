<?php
/**
 * Shared configuration file for RoadRunner worker and application
 */

// Define application root if not already defined
if (!defined('APP_ROOT')) {
    define('APP_ROOT', dirname(__DIR__));
}

// Path constants
define('LOG_DIR', APP_ROOT . '/logs');
define('APPLICATION_LOG_DIR', LOG_DIR . '/application');
define('ROADRUNNER_LOG_DIR', LOG_DIR . '/roadrunner');

// Log file paths
define('REDIRECT_LOG_FILE', APPLICATION_LOG_DIR . '/redirect.log');
define('WORKER_LOG_FILE', ROADRUNNER_LOG_DIR . '/worker.log');
define('ERROR_LOG_FILE', ROADRUNNER_LOG_DIR . '/error.log');

// For backward compatibility
define('LOG_FILE', REDIRECT_LOG_FILE);

// Application constants
define('BASE_URL', 'https://willhaben.vip');
define('WILLHABEN_AT_BASE_URL', 'https://willhaben.at');
define('DEFAULT_SELLER_SLUG', 'rene.kapusta');
define('SELLER_MAP', [
    '34434899' => 'rene.kapusta'
]);

// Tracking system constants
define('TRACKING_STORAGE_TYPE', 'sqlite'); // Options: 'sqlite' or 'json'
define('TRACKING_STORAGE_PATH', APP_ROOT . '/data/redirect_tracking.' . (TRACKING_STORAGE_TYPE === 'sqlite' ? 'db' : 'json'));

// Article tracking and update system constants
define('ARTICLE_LOG_FILE', APPLICATION_LOG_DIR . '/articles.log');
define('ARTICLE_UPDATE_INTERVAL', 300); // 5 minutes in seconds
define('ARTICLE_API_BASE_URL', 'https://www.willhaben.at/webapi/iad/userfolders/all/');
define('ARTICLE_API_RETRY_ATTEMPTS', 3);
define('ARTICLE_API_RETRY_DELAY', 2); // Initial delay in seconds (will use exponential backoff)

// Data directories
define('DATA_DIR', APP_ROOT . '/data');
define('ARTICLES_DATA_DIR', DATA_DIR . '/articles');

// Ensure log and data directories exist with proper permissions
foreach ([LOG_DIR, APPLICATION_LOG_DIR, ROADRUNNER_LOG_DIR, DATA_DIR, ARTICLES_DATA_DIR] as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }
}

// Touch log files to ensure they exist
foreach ([REDIRECT_LOG_FILE, WORKER_LOG_FILE, ERROR_LOG_FILE, ARTICLE_LOG_FILE] as $file) {
    if (!file_exists($file)) {
        touch($file);
        chmod($file, 0666);
    }
}

// Verify SQLite database setup
function verifySqliteSetup() {
    if (TRACKING_STORAGE_TYPE === 'sqlite') {
        try {
            // Check if SQLite extension is loaded
            if (!extension_loaded('pdo_sqlite')) {
                error_log('ERROR: PDO SQLite extension is not loaded. Article tracking requires SQLite.');
                return false;
            }
            
            // Create or verify the database file
            if (!file_exists(dirname(TRACKING_STORAGE_PATH))) {
                mkdir(dirname(TRACKING_STORAGE_PATH), 0777, true);
            }
            
            // Test database connection
            $db = new PDO('sqlite:' . TRACKING_STORAGE_PATH);
            $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            
            // Verify we can execute a simple query
            $result = $db->query('SELECT 1')->fetch();
            
            return true;
        } catch (Exception $e) {
            error_log('ERROR setting up SQLite database: ' . $e->getMessage());
            return false;
        }
    }
    
    return true; // Not using SQLite, so no verification needed
}

// Additional configuration for article tracking
define('ARTICLE_UPDATE_LOCK_FILE', DATA_DIR . '/article_update.lock');
define('ARTICLE_SCHEDULER_ENABLED', true);
define('ARTICLE_MAX_CACHE_AGE', 86400); // 24 hours in seconds

// Set up error handling
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    error_log("Error [$errno]: $errstr in $errfile on line $errline");
    return true;
});

set_exception_handler(function($exception) {
    error_log("Exception: " . $exception->getMessage() . " in " . $exception->getFile() . " on line " . $exception->getLine());
});

// Verify SQLite setup on startup
verifySqliteSetup();
