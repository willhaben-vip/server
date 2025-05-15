<?php
namespace Willhaben\RedirectService;

/**
 * Scheduler for periodic article updates
 * Handles scheduling and execution of article update jobs
 */
class ArticleUpdateScheduler {
    private Logger $logger;
    private ArticleFetcher $fetcher;
    private bool $isRunning = false;
    private int $updateInterval = 300; // 5 minutes in seconds
    private int $jobInterval = 60; // Run job checks every 60 seconds
    private ?array $lastRunTime = [];
    private string $lockFile;
    
    /**
     * Constructor
     */
    public function __construct(Logger $logger, ArticleFetcher $fetcher) {
        $this->logger = $logger;
        $this->fetcher = $fetcher;
        $this->lockFile = APP_ROOT . '/data/article_update.lock';
        
        // Ensure data directory exists
        $dataDir = dirname($this->lockFile);
        if (!is_dir($dataDir)) {
            mkdir($dataDir, 0777, true);
        }
    }
    
    /**
     * Start the scheduler
     */
    public function start(): void {
        if ($this->isRunning) {
            $this->logger->debug("Scheduler already running");
            return;
        }
        
        $this->isRunning = true;
        $this->logger->debug("Article update scheduler started");
        
        // Run in the background (non-blocking)
        $this->run();
    }
    
    /**
     * Stop the scheduler
     */
    public function stop(): void {
        $this->isRunning = false;
        $this->logger->debug("Article update scheduler stopped");
        
        // Release lock if exists
        if (file_exists($this->lockFile)) {
            unlink($this->lockFile);
        }
    }
    
    /**
     * Run the scheduler
     */
    public function run(): void {
        // Check for lock file to prevent multiple instances
        if (file_exists($this->lockFile)) {
            $lockTime = filemtime($this->lockFile);
            $now = time();
            
            // If lock file is older than 30 minutes, assume stale and remove
            if ($now - $lockTime > 1800) {
                $this->logger->warning("Found stale lock file, removing");
                unlink($this->lockFile);
            } else {
                $this->logger->debug("Scheduler already running (lock file exists)");
                return;
            }
        }
        
        // Create lock file
        touch($this->lockFile);
        
        try {
            // Main scheduler loop
            while ($this->isRunning) {
                $this->executeScheduledJobs();
                
                // Sleep for interval period
                sleep($this->jobInterval);
            }
        } catch (\Exception $e) {
            $this->logger->error("Scheduler error: " . $e->getMessage());
        } finally {
            // Cleanup lock file
            if (file_exists($this->lockFile)) {
                unlink($this->lockFile);
            }
            
            $this->isRunning = false;
        }
    }
    
    /**
     * Execute scheduled jobs if it's time
     */
    private function executeScheduledJobs(): void {
        $this->logger->debug("Checking for scheduled jobs");
        
        // Get active sellers
        $sellers = $this->fetcher->getActiveSellers();
        
        foreach ($sellers as $sellerId) {
            // Check if it's time to run update for this seller
            if ($this->shouldRunUpdate($sellerId)) {
                $this->logger->debug("Executing article update job for seller", ['seller_id' => $sellerId]);
                
                try {
                    // Update seller articles
                    $result = $this->fetcher->fetchSellerArticles($sellerId);
                    
                    if ($result !== null) {
                        $this->logger->debug("Article update completed successfully", [
                            'seller_id' => $sellerId,
                            'articles_count' => count($result)
                        ]);
                    } else {
                        $this->logger->warning("Failed to update articles for seller", ['seller_id' => $sellerId]);
                    }
                } catch (\Exception $e) {
                    $this->logger->error("Error updating articles for seller", [
                        'seller_id' => $sellerId,
                        'error' => $e->getMessage()
                    ]);
                }
                
                // Update last run time for this seller
                $this->lastRunTime[$sellerId] = time();
            }
        }
    }
    
    /**
     * Check if an update should run for a seller
     */
    private function shouldRunUpdate(string $sellerId): bool {
        $now = time();
        
        // If no previous run time for this seller or enough time has passed
        if (!isset($this->lastRunTime[$sellerId]) || 
            ($now - $this->lastRunTime[$sellerId] >= $this->updateInterval)) {
            return true;
        }
        
        return false;
    }
    
    /**
     * Manually trigger an update for all sellers
     * 
     * @return array Results of the update operation
     */
    public function triggerUpdateAllSellers(): array {
        $this->logger->debug("Manually triggering update for all sellers");
        return $this->fetcher->updateAllSellerArticles();
    }
    
    /**
     * Manually trigger an update for a specific seller
     * 
     * @param string $sellerId The seller ID to update
     * @return array|null Articles fetched or null on failure
     */
    public function triggerUpdateSeller(string $sellerId): ?array {
        $this->logger->debug("Manually triggering update for seller", ['seller_id' => $sellerId]);
        return $this->fetcher->fetchSellerArticles($sellerId);
    }
    
    /**
     * Get the status of scheduled jobs
     * 
     * @return array Status information for scheduler
     */
    public function getStatus(): array {
        $now = time();
        $status = [
            'running' => $this->isRunning,
            'job_interval' => $this->jobInterval,
            'update_interval' => $this->updateInterval,
            'sellers' => []
        ];
        
        // Get active sellers
        $sellers = $this->fetcher->getActiveSellers();
        
        foreach ($sellers as $sellerId) {
            $lastRun = $this->lastRunTime[$sellerId] ?? null;
            $nextRun = $lastRun ? $lastRun + $this->updateInterval : $now;
            $timeUntilNextRun = $nextRun - $now;
            
            $status['sellers'][$sellerId] = [
                'last_run' => $lastRun ? date('Y-m-d H:i:s', $lastRun) : null,
                'next_run' => date('Y-m-d H:i:s', $nextRun),
                'time_until_next_run' => max(0, $timeUntilNextRun),
                'should_run_now' => $this->shouldRunUpdate($sellerId)
            ];
        }
        
        return $status;
    }
}

