<?php
namespace Willhaben\RedirectService;

use Spiral\RoadRunner\Jobs\JobsInterface;
use Spiral\RoadRunner\Jobs\Task\ReceivedTaskInterface;

/**
 * Job handler for scheduled article updates
 */
class ArticleUpdateJob {
    private Logger $logger;
    private ArticleFetcher $fetcher;
    private RedirectTracker $tracker;
    private ArticleUpdateScheduler $scheduler;
    
    /**
     * Constructor - initializes dependencies
     */
    public function __construct(Logger $logger) {
        $this->logger = $logger;
        $this->tracker = new RedirectTracker($logger);
        $this->fetcher = new ArticleFetcher($logger, $this->tracker);
        $this->scheduler = new ArticleUpdateScheduler($logger, $this->fetcher);
    }
    
    /**
     * Initialize the job handler
     */
    public function initialize(): void {
        $this->logger->debug("Article update job handler initialized");
    }
    
    /**
     * Process a received job task
     * 
     * @param ReceivedTaskInterface $task The received task
     * @return void
     */
    public function process(ReceivedTaskInterface $task): void {
        try {
            $this->logger->debug("Processing article update job", [
                'task_id' => $task->getId(),
                'task_name' => $task->getName(),
                'queue' => $task->getQueue()
            ]);
            
            // Check if it's a specific seller update or all sellers
            $payload = json_decode($task->getPayload(), true) ?: [];
            $sellerId = $payload['seller_id'] ?? null;
            
            if ($sellerId) {
                // Update specific seller
                $this->logger->debug("Updating specific seller", ['seller_id' => $sellerId]);
                $result = $this->fetcher->fetchSellerArticles($sellerId);
                
                if ($result !== null) {
                    $this->logger->debug("Seller update completed", [
                        'seller_id' => $sellerId,
                        'articles_count' => count($result)
                    ]);
                } else {
                    $this->logger->warning("Failed to update seller articles", ['seller_id' => $sellerId]);
                }
            } else {
                // Update all sellers
                $this->logger->debug("Updating all active sellers");
                $results = $this->fetcher->updateAllSellerArticles();
                
                foreach ($results as $sellerId => $status) {
                    $this->logger->debug("Seller update status", [
                        'seller_id' => $sellerId,
                        'status' => $status['status'],
                        'articles_count' => $status['status'] === 'success' ? $status['articles_count'] : 0
                    ]);
                }
            }
            
            $this->logger->debug("Article update job completed", ['task_id' => $task->getId()]);
            
            // Send acknowledgment (success)
            $task->getQueue()->ack($task);
            
        } catch (\Throwable $e) {
            $this->logger->error("Error processing article update job", [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            // Send negative acknowledgment (failure)
            $task->getQueue()->nack($task);
        }
    }
    
    /**
     * Queue a job to update a specific seller
     * 
     * @param JobsInterface $jobs The jobs queue
     * @param string $sellerId The seller ID to update
     * @return void
     */
    public function queueSellerUpdate(JobsInterface $jobs, string $sellerId): void {
        try {
            $payload = json_encode(['seller_id' => $sellerId]);
            
            $task = $jobs->create('article-update-job', $payload, [
                'queue' => 'article-update',
                'priority' => 10
            ]);
            
            $jobs->push($task);
            
            $this->logger->debug("Queued seller update job", ['seller_id' => $sellerId]);
        } catch (\Throwable $e) {
            $this->logger->error("Failed to queue seller update job", [
                'seller_id' => $sellerId,
                'error' => $e->getMessage()
            ]);
        }
    }
    
    /**
     * Queue a job to update all sellers
     * 
     * @param JobsInterface $jobs The jobs queue
     * @return void
     */
    public function queueAllSellersUpdate(JobsInterface $jobs): void {
        try {
            $task = $jobs->create('article-update-job', '', [
                'queue' => 'article-update',
                'priority' => 10
            ]);
            
            $jobs->push($task);
            
            $this->logger->debug("Queued update job for all sellers");
        } catch (\Throwable $e) {
            $this->logger->error("Failed to queue update job for all sellers", [
                'error' => $e->getMessage()
            ]);
        }
    }
    
    /**
     * Manually trigger an update for all sellers (for testing)
     * 
     * @return array Status information
     */
    public function triggerManualUpdate(): array {
        $this->logger->debug("Manually triggering update for all sellers");
        return $this->fetcher->updateAllSellerArticles();
    }
}

