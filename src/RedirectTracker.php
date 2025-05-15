<?php
namespace Willhaben\RedirectService;

/**
 * Tracks redirects and stores statistics
 */
class RedirectTracker {
    private Logger $logger;
    private string $storageType;
    private string $storagePath;
    private ?\PDO $db = null;
    private array $jsonData = [];

    public function __construct(Logger $logger) {
        $this->logger = $logger;
        $this->storageType = TRACKING_STORAGE_TYPE;
        $this->storagePath = TRACKING_STORAGE_PATH;
        
        // Ensure the data directory exists
        $dataDir = dirname($this->storagePath);
        if (!is_dir($dataDir)) {
            mkdir($dataDir, 0777, true);
        }

        // Initialize storage
        $this->initialize();
    }

    /**
     * Initialize storage (database or JSON file)
     */
    private function initialize(): void {
        try {
            if ($this->storageType === 'sqlite') {
                $this->initializeSqlite();
            } else {
                $this->initializeJson();
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to initialize tracking storage", $e);
        }
    }

    /**
     * Initialize SQLite database
     */
    private function initializeSqlite(): void {
        $this->db = new \PDO('sqlite:' . $this->storagePath);
        $this->db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
        
        // Create table if it doesn't exist
        $this->db->exec('
            CREATE TABLE IF NOT EXISTS article_redirects (
                article_id TEXT PRIMARY KEY,
                redirect_count INTEGER NOT NULL DEFAULT 1,
                first_redirect_timestamp TEXT NOT NULL,
                last_redirect_timestamp TEXT NOT NULL
            )
        ');
        
        // Create seller articles table if it doesn't exist
        $this->db->exec('
            CREATE TABLE IF NOT EXISTS seller_articles (
                seller_id TEXT,
                article_id TEXT,
                article_data TEXT NOT NULL,
                last_updated TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT "active",
                PRIMARY KEY (seller_id, article_id)
            )
        ');
        
        // Create sellers table if it doesn't exist
        $this->db->exec('
            CREATE TABLE IF NOT EXISTS sellers (
                seller_id TEXT PRIMARY KEY,
                first_tracked_timestamp TEXT NOT NULL,
                last_updated TEXT NOT NULL,
                last_api_call TEXT,
                active INTEGER NOT NULL DEFAULT 1
            )
        ');
        
        $this->logger->debug("SQLite tracking database initialized", ['path' => $this->storagePath]);
    }

    /**
     * Initialize JSON storage
     */
    private function initializeJson(): void {
        if (file_exists($this->storagePath)) {
            $content = file_get_contents($this->storagePath);
            $this->jsonData = json_decode($content, true) ?: [];
        } else {
            $this->jsonData = [];
            file_put_contents($this->storagePath, json_encode($this->jsonData));
        }
        
        $this->logger->debug("JSON tracking storage initialized", ['path' => $this->storagePath]);
    }

    /**
     * Track a redirect for an article
     */
    public function trackRedirect(string $articleId): void {
        try {
            if ($this->storageType === 'sqlite') {
                $this->trackRedirectSqlite($articleId);
            } else {
                $this->trackRedirectJson($articleId);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to track redirect", $e);
        }
    }

    /**
     * Track a redirect using SQLite
     */
    private function trackRedirectSqlite(string $articleId): void {
        $now = date('Y-m-d H:i:s');
        
        // Check if article exists
        $stmt = $this->db->prepare('SELECT redirect_count FROM article_redirects WHERE article_id = :article_id');
        $stmt->execute(['article_id' => $articleId]);
        
        if ($stmt->fetch()) {
            // Update existing record
            $updateStmt = $this->db->prepare('
                UPDATE article_redirects 
                SET redirect_count = redirect_count + 1, 
                    last_redirect_timestamp = :timestamp 
                WHERE article_id = :article_id
            ');
            $updateStmt->execute([
                'article_id' => $articleId,
                'timestamp' => $now
            ]);
        } else {
            // Insert new record
            $insertStmt = $this->db->prepare('
                INSERT INTO article_redirects 
                (article_id, redirect_count, first_redirect_timestamp, last_redirect_timestamp) 
                VALUES (:article_id, 1, :timestamp, :timestamp)
            ');
            $insertStmt->execute([
                'article_id' => $articleId,
                'timestamp' => $now
            ]);
        }
        
        $this->logger->debug("Tracked redirect for article", ['id' => $articleId]);
    }

    /**
     * Track a redirect using JSON
     */
    private function trackRedirectJson(string $articleId): void {
        $now = date('Y-m-d H:i:s');
        
        if (isset($this->jsonData[$articleId])) {
            // Update existing record
            $this->jsonData[$articleId]['redirect_count']++;
            $this->jsonData[$articleId]['last_redirect_timestamp'] = $now;
        } else {
            // Create new record
            $this->jsonData[$articleId] = [
                'redirect_count' => 1,
                'first_redirect_timestamp' => $now,
                'last_redirect_timestamp' => $now
            ];
        }
        
        // Save to file
        file_put_contents($this->storagePath, json_encode($this->jsonData, JSON_PRETTY_PRINT));
        
        $this->logger->debug("Tracked redirect for article", ['id' => $articleId]);
    }

    /**
     * Get tracking data for an article
     */
    public function getArticleTracking(string $articleId): ?array {
        try {
            if ($this->storageType === 'sqlite') {
                return $this->getArticleTrackingSqlite($articleId);
            } else {
                return $this->getArticleTrackingJson($articleId);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to get article tracking", $e);
            return null;
        }
    }

    /**
     * Get tracking data from SQLite
     */
    private function getArticleTrackingSqlite(string $articleId): ?array {
        $stmt = $this->db->prepare('SELECT * FROM article_redirects WHERE article_id = :article_id');
        $stmt->execute(['article_id' => $articleId]);
        
        $result = $stmt->fetch(\PDO::FETCH_ASSOC);
        return $result ?: null;
    }

    /**
     * Track a seller (create or update seller data)
     */
    public function trackSeller(string $sellerId): void {
        try {
            if ($this->storageType === 'sqlite') {
                $this->trackSellerSqlite($sellerId);
            } else {
                $this->trackSellerJson($sellerId);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to track seller", $e);
        }
    }

    /**
     * Track a seller using SQLite
     */
    private function trackSellerSqlite(string $sellerId): void {
        $now = date('Y-m-d H:i:s');
        
        // Check if seller exists
        $stmt = $this->db->prepare('SELECT seller_id FROM sellers WHERE seller_id = :seller_id');
        $stmt->execute(['seller_id' => $sellerId]);
        
        if ($stmt->fetch()) {
            // Update existing record
            $updateStmt = $this->db->prepare('
                UPDATE sellers 
                SET last_updated = :timestamp 
                WHERE seller_id = :seller_id
            ');
            $updateStmt->execute([
                'seller_id' => $sellerId,
                'timestamp' => $now
            ]);
        } else {
            // Insert new record
            $insertStmt = $this->db->prepare('
                INSERT INTO sellers 
                (seller_id, first_tracked_timestamp, last_updated) 
                VALUES (:seller_id, :timestamp, :timestamp)
            ');
            $insertStmt->execute([
                'seller_id' => $sellerId,
                'timestamp' => $now
            ]);
        }
        
        $this->logger->debug("Tracked seller", ['id' => $sellerId]);
    }

    /**
     * Track a seller using JSON
     */
    private function trackSellerJson(string $sellerId): void {
        $now = date('Y-m-d H:i:s');
        
        // Initialize sellers data if not exists
        if (!isset($this->jsonData['sellers'])) {
            $this->jsonData['sellers'] = [];
        }
        
        if (isset($this->jsonData['sellers'][$sellerId])) {
            // Update existing record
            $this->jsonData['sellers'][$sellerId]['last_updated'] = $now;
        } else {
            // Create new record
            $this->jsonData['sellers'][$sellerId] = [
                'first_tracked_timestamp' => $now,
                'last_updated' => $now,
                'active' => true
            ];
        }
        
        // Save to file
        file_put_contents($this->storagePath, json_encode($this->jsonData, JSON_PRETTY_PRINT));
        
        $this->logger->debug("Tracked seller", ['id' => $sellerId]);
    }

    /**
     * Check if a seller can be fetched from API based on rate limit (5 minutes)
     */
    public function canFetchSellerArticles(string $sellerId): bool {
        try {
            if ($this->storageType === 'sqlite') {
                return $this->canFetchSellerArticlesSqlite($sellerId);
            } else {
                return $this->canFetchSellerArticlesJson($sellerId);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to check fetch availability", $e);
            return false;
        }
    }

    /**
     * Check if a seller can be fetched using SQLite (based on 5 minute rate limit)
     */
    private function canFetchSellerArticlesSqlite(string $sellerId): bool {
        // Get the last API call timestamp for this seller
        $stmt = $this->db->prepare('SELECT last_api_call FROM sellers WHERE seller_id = :seller_id');
        $stmt->execute(['seller_id' => $sellerId]);
        $result = $stmt->fetch(\PDO::FETCH_ASSOC);
        
        // If no previous API call or null value, can fetch
        if (!$result || $result['last_api_call'] === null) {
            return true;
        }
        
        // Calculate time difference (5 minute rate limit)
        $lastCallTime = strtotime($result['last_api_call']);
        $currentTime = time();
        $diffMinutes = ($currentTime - $lastCallTime) / 60;
        
        // Can fetch if more than 5 minutes since last call
        return $diffMinutes >= 5;
    }

    /**
     * Check if a seller can be fetched using JSON (based on 5 minute rate limit)
     */
    private function canFetchSellerArticlesJson(string $sellerId): bool {
        // If sellers data doesn't exist or this seller doesn't exist, can fetch
        if (!isset($this->jsonData['sellers']) || !isset($this->jsonData['sellers'][$sellerId])) {
            return true;
        }
        
        // If no last_api_call timestamp, can fetch
        if (!isset($this->jsonData['sellers'][$sellerId]['last_api_call'])) {
            return true;
        }
        
        // Calculate time difference (5 minute rate limit)
        $lastCallTime = strtotime($this->jsonData['sellers'][$sellerId]['last_api_call']);
        $currentTime = time();
        $diffMinutes = ($currentTime - $lastCallTime) / 60;
        
        // Can fetch if more than 5 minutes since last call
        return $diffMinutes >= 5;
    }

    /**
     * Update the last API call timestamp for a seller
     */
    public function updateLastApiCall(string $sellerId): void {
        try {
            if ($this->storageType === 'sqlite') {
                $this->updateLastApiCallSqlite($sellerId);
            } else {
                $this->updateLastApiCallJson($sellerId);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to update last API call timestamp", $e);
        }
    }

    /**
     * Update the last API call timestamp for a seller using SQLite
     */
    private function updateLastApiCallSqlite(string $sellerId): void {
        $now = date('Y-m-d H:i:s');
        
        // Check if seller exists
        $stmt = $this->db->prepare('SELECT seller_id FROM sellers WHERE seller_id = :seller_id');
        $stmt->execute(['seller_id' => $sellerId]);
        
        if ($stmt->fetch()) {
            // Update existing record
            $updateStmt = $this->db->prepare('
                UPDATE sellers 
                SET last_api_call = :timestamp 
                WHERE seller_id = :seller_id
            ');
            $updateStmt->execute([
                'seller_id' => $sellerId,
                'timestamp' => $now
            ]);
        } else {
            // Insert new record
            $insertStmt = $this->db->prepare('
                INSERT INTO sellers 
                (seller_id, first_tracked_timestamp, last_updated, last_api_call) 
                VALUES (:seller_id, :timestamp, :timestamp, :timestamp)
            ');
            $insertStmt->execute([
                'seller_id' => $sellerId,
                'timestamp' => $now
            ]);
        }
        
        $this->logger->debug("Updated last API call for seller", ['id' => $sellerId]);
    }

    /**
     * Update the last API call timestamp for a seller using JSON
     */
    private function updateLastApiCallJson(string $sellerId): void {
        $now = date('Y-m-d H:i:s');
        
        // Initialize sellers data if not exists
        if (!isset($this->jsonData['sellers'])) {
            $this->jsonData['sellers'] = [];
        }
        
        if (isset($this->jsonData['sellers'][$sellerId])) {
            // Update existing record
            $this->jsonData['sellers'][$sellerId]['last_api_call'] = $now;
            $this->jsonData['sellers'][$sellerId]['last_updated'] = $now;
        } else {
            // Create new record
            $this->jsonData['sellers'][$sellerId] = [
                'first_tracked_timestamp' => $now,
                'last_updated' => $now,
                'last_api_call' => $now,
                'active' => true
            ];
        }
        
        // Save to file
        file_put_contents($this->storagePath, json_encode($this->jsonData, JSON_PRETTY_PRINT));
        
        $this->logger->debug("Updated last API call for seller", ['id' => $sellerId]);
    }

    /**
     * Store seller articles in the database
     */
    public function storeSellerArticles(string $sellerId, array $articles): void {
        try {
            if ($this->storageType === 'sqlite') {
                $this->storeSellerArticlesSqlite($sellerId, $articles);
            } else {
                $this->storeSellerArticlesJson($sellerId, $articles);
            }
        } catch (\Exception $e) {
            $this->logger->error("Failed to store seller articles", $e);
        }
    }

    /**
     * Store seller articles using SQLite
     */
    private function storeSellerArticlesSqlite(string $sellerId, array $articles): void {
        $now = date('Y-m-d H:i:s');
        
        // Start transaction for better performance
        $this->db->beginTransaction();
        
        try {
            // First, mark all existing articles for this seller as inactive
            $updateStmt = $this->db->prepare('
                UPDATE seller_articles 
                SET status = "inactive" 
                WHERE seller_id = :seller_id
            ');
            $updateStmt->execute(['seller_id' => $sellerId]);
            
            // Prepare statements for insert/update
            $insertStmt = $this->db->prepare('
                INSERT OR REPLACE INTO seller_articles 
                (seller_id, article_id, article_data, last_updated, status) 
                VALUES (:seller_id, :article_id, :article_data, :timestamp, :status)
            ');
            
            // Process each article
            foreach ($articles as $article) {
                // Ensure we have an article_id
                if (!isset($article['id'])) {
                    $this->logger->warning("Article missing ID", ['seller_id' => $sellerId]);
                    continue;
    /**
     * Get tracking data from JSON
     */
    private function getArticleTrackingJson(string $articleId): ?array {
        return $this->jsonData[$articleId] ?? null;
    }
}

