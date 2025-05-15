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

// Ensure log directories exist with proper permissions
foreach ([LOG_DIR, APPLICATION_LOG_DIR, ROADRUNNER_LOG_DIR] as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }
}

// Touch log files to ensure they exist
foreach ([REDIRECT_LOG_FILE, WORKER_LOG_FILE, ERROR_LOG_FILE] as $file) {
    if (!file_exists($file)) {
        touch($file);
        chmod($file, 0666);
    }
}
