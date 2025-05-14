<?php
namespace Willhaben\RedirectService;

/**
 * Shared logging utility for both worker and application
 */
class Logger {
    private string $logFile;
    private string $context;

    public function __construct(string $logFile, string $context = '') {
        $this->logFile = $logFile;
        $this->context = $context;
        
        // Log directory is ensured to exist by config.php
    }

    /**
     * Log a message with optional context
     */
    public function log(string $message, array $data = []): void {
        $timestamp = date('Y-m-d H:i:s');
        $context = $this->context ? "[$this->context] " : '';
        $logEntry = "[{$timestamp}] {$context}{$message}";
        
        if (!empty($data)) {
            $logEntry .= ' ' . json_encode($data, JSON_UNESCAPED_SLASHES);
        }
        
        $logEntry .= PHP_EOL;
        
        error_log($logEntry);
        file_put_contents($this->logFile, $logEntry, FILE_APPEND);
    }

    /**
     * Log an error message
     */
    public function error(string $message, ?\Throwable $e = null): void {
        $data = [];
        if ($e !== null) {
            $data['error'] = $e->getMessage();
            $data['trace'] = $e->getTraceAsString();
        }
        
        $this->log("ERROR: $message", $data);
    }

    /**
     * Log a debug message
     */
    public function debug(string $message, array $data = []): void {
        $this->log("DEBUG: $message", $data);
    }

    /**
     * Log a redirect
     */
    public function redirect(string $url, int $status = 301): void {
        $this->log("Redirecting to: $url", ['status' => $status]);
    }
}
