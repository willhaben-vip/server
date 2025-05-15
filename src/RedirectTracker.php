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
     * Get tracking data from JSON
     */
    private function getArticleTrackingJson(string $articleId): ?array {
        return $this->jsonData[$articleId] ?? null;
    }
}

