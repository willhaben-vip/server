<?php
namespace Willhaben\RedirectService;

/**
 * Service for fetching article data from willhaben.at API
 */
class ArticleFetcher {
    private Logger $logger;
    private RedirectTracker $tracker;
    private string $baseApiUrl = 'https://www.willhaben.at/webapi/iad/userfolders/all/';
    private int $maxRetries = 3;
    private int $retryDelay = 2; // seconds
    
    /**
     * Constructor
     */
    public function __construct(Logger $logger, RedirectTracker $tracker) {
        $this->logger = $logger;
        $this->tracker = $tracker;
    }
    
    /**
     * Fetch articles for a seller, respecting rate limits
     * 
     * @param string $sellerId The Willhaben seller ID
     * @return array|null Array of articles or null if fetching failed
     */
    public function fetchSellerArticles(string $sellerId): ?array {
        // Check if we can fetch (rate limiting)
        if (!$this->tracker->canFetchSellerArticles($sellerId)) {
            $this->logger->debug("Rate limit active for seller, skipping fetch", ['seller_id' => $sellerId]);
            return null;
        }
        
        $this->logger->debug("Fetching articles for seller", ['seller_id' => $sellerId]);
        
        // Build the API URL
        $url = $this->baseApiUrl . $sellerId;
        
        // Record API call attempt
        $this->tracker->updateLastApiCall($sellerId);
        
        // Fetch data with retry mechanism
        $response = $this->fetchWithRetry($url);
        
        if ($response === null) {
            $this->logger->error("Failed to fetch articles after retries", ['seller_id' => $sellerId]);
            return null;
        }
        
        // Parse and normalize the data
        $articles = $this->parseArticles($response, $sellerId);
        
        if (empty($articles)) {
            $this->logger->warning("No articles found for seller", ['seller_id' => $sellerId]);
            return [];
        }
        
        // Store the articles in our database
        $this->tracker->storeSellerArticles($sellerId, $articles);
        
        $this->logger->debug("Successfully fetched and stored articles", [
            'seller_id' => $sellerId,
            'count' => count($articles)
        ]);
        
        return $articles;
    }
    
    /**
     * Fetch data from URL with retry mechanism
     * 
     * @param string $url The URL to fetch
     * @return string|null Response body or null if all retries failed
     */
    private function fetchWithRetry(string $url): ?string {
        $attempts = 0;
        
        while ($attempts < $this->maxRetries) {
            try {
                $response = $this->makeHttpRequest($url);
                
                if ($response !== null) {
                    return $response;
                }
            } catch (\Exception $e) {
                $this->logger->warning("HTTP request failed", [
                    'url' => $url,
                    'attempt' => $attempts + 1,
                    'error' => $e->getMessage()
                ]);
            }
            
            // Exponential backoff for retries
            $sleepTime = $this->retryDelay * pow(2, $attempts);
            sleep($sleepTime);
            
            $attempts++;
        }
        
        return null;
    }
    
    /**
     * Make HTTP request to URL
     * 
     * @param string $url The URL to request
     * @return string|null Response body or null on failure
     */
    private function makeHttpRequest(string $url): ?string {
        $ch = curl_init();
        
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_HTTPHEADER => [
                'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                'Accept: application/json'
            ]
        ]);
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        
        curl_close($ch);
        
        if ($error || $httpCode >= 400) {
            $this->logger->warning("HTTP request failed", [
                'url' => $url,
                'http_code' => $httpCode,
                'error' => $error
            ]);
            return null;
        }
        
        return $response;
    }
    
    /**
     * Parse and normalize articles from API response
     * 
     * @param string $response JSON response from the API
     * @param string $sellerId The seller ID
     * @return array Normalized array of article data
     */
    private function parseArticles(string $response, string $sellerId): array {
        $data = json_decode($response, true);
        $articles = [];
        
        if (!$data || !isset($data['advertList']) || !is_array($data['advertList'])) {
            $this->logger->warning("Invalid API response format", ['seller_id' => $sellerId]);
            return [];
        }
        
        foreach ($data['advertList'] as $item) {
            // Skip items without ID
            if (!isset($item['id'])) {
                continue;
            }
            
            // Normalize article data
            $article = [
                'id' => $item['id'],
                'title' => $item['description'] ?? 'Unknown Title',
                'price' => $item['price'] ?? null,
                'currency' => $item['currency'] ?? 'EUR',
                'status' => $item['status'] ?? 'active',
                'publish_date' => $item['publishDate'] ?? null,
                'seller_id' => $sellerId,
                'url' => WILLHABEN_AT_BASE_URL . '/iad/object?adId=' . $item['id'],
                'image_url' => $item['imageUrl'] ?? null,
                'data' => $item, // Store complete raw data
            ];
            
            $articles[] = $article;
        }
        
        return $articles;
    }
    
    /**
     * Get all active sellers that need updates
     * 
     * @return array Array of seller IDs
     */
    public function getActiveSellers(): array {
        // For now, just return the sellers from the SELLER_MAP constant
        return array_keys(SELLER_MAP);
    }
    
    /**
     * Update articles for all active sellers, respecting rate limits
     * 
     * @return array Status of update operations
     */
    public function updateAllSellerArticles(): array {
        $result = [];
        $sellers = $this->getActiveSellers();
        
        foreach ($sellers as $sellerId) {
            // Check rate limiting
            if (!$this->tracker->canFetchSellerArticles($sellerId)) {
                $result[$sellerId] = [
                    'status' => 'skipped',
                    'reason' => 'rate_limited'
                ];
                continue;
            }
            
            // Fetch and store articles
            $articles = $this->fetchSellerArticles($sellerId);
            
            if ($articles === null) {
                $result[$sellerId] = [
                    'status' => 'error',
                    'reason' => 'fetch_failed'
                ];
            } else {
                $result[$sellerId] = [
                    'status' => 'success',
                    'articles_count' => count($articles)
                ];
            }
        }
        
        return $result;
    }
}

