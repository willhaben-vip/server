<?php
namespace Willhaben\RedirectService;

/**
 * Core service for handling redirects
 */
class RedirectService {
    private Logger $logger;
    private ?RedirectTracker $tracker = null;
    private const DEFAULT_REDIRECT_STATUS = 301; // Always use permanent redirects
    private const WILLHABEN_SELLER_URL_PATTERN = '#https?://(?:www\.)?willhaben\.at/(?:.+)?/(?:seller-profile|user)/(\d+)#i';

    public function __construct(Logger $logger) {
        $this->logger = $logger;
        $this->tracker = new RedirectTracker($logger);
    }

    /**
     * Verify seller ID and get their URL slug
     */
    public function verifySellerAndGetSlug(string $sellerId): ?string {
        // Sanitize seller ID (numeric only)
        $sellerId = preg_replace('/[^0-9]/', '', $sellerId);
        
        $this->logger->debug("Verifying seller", ['id' => $sellerId]);

        // Check if seller ID is in our map
        if (isset(SELLER_MAP[$sellerId])) {
            return SELLER_MAP[$sellerId];
        }

        // Look for seller JSON file in various directories
        foreach (scandir(APP_ROOT . '/public/member') as $item) {
            if (is_dir(APP_ROOT . '/public/member/' . $item) && $item != '.' && $item != '..') {
                $jsonFile = APP_ROOT . '/public/member/' . $item . '/' . $sellerId . '.json';
                if (file_exists($jsonFile)) {
                    return $item;
                }
            }
        }

        return null;
    }

    /**
     * Handle a seller profile redirect
     */
    public function handleSellerRedirect(string $sellerId): void {
        $this->logger->debug("Processing seller redirect", ['id' => $sellerId]);

        // Store seller information in tracker
        if ($this->tracker) {
            $this->tracker->trackSeller($sellerId);
        }

        $sellerSlug = $this->verifySellerAndGetSlug($sellerId);
        if ($sellerSlug) {
            $url = BASE_URL . '/' . $sellerSlug . '/';
            $this->logger->redirect($url, self::DEFAULT_REDIRECT_STATUS);
            throw new RedirectException($url, self::DEFAULT_REDIRECT_STATUS);
        }

        // If seller not found, redirect to homepage with permanent redirect
        $this->logger->debug("Invalid seller ID, redirecting to homepage", ['id' => $sellerId]);
        throw new RedirectException(BASE_URL, self::DEFAULT_REDIRECT_STATUS);
    }

    /**
     * Handle a product redirect
     */
    public function handleProductRedirect(string $productSlug, string $productId): void {
        $this->logger->debug("Processing product redirect", [
            'slug' => $productSlug,
            'id' => $productId
        ]);

        // For now, we'll use rene.kapusta as the default seller
        $sellerSlug = 'rene.kapusta';
        $url = BASE_URL . '/' . $sellerSlug . '/' . $productSlug . '-' . $productId;
        
        $this->logger->redirect($url, self::DEFAULT_REDIRECT_STATUS);
        throw new RedirectException($url, self::DEFAULT_REDIRECT_STATUS);
    }

    /**
     * Handle a default redirect to homepage
     */
    public function handleDefaultRedirect(): void {
        $this->logger->debug("Processing default redirect to homepage");
        throw new RedirectException(BASE_URL, self::DEFAULT_REDIRECT_STATUS);
    }
    
    /**
     * Handle a marketplace redirect: willhaben.vip/<username slug>/marketplace/<article id>
     * Redirects to: https://willhaben.at/iad/object?adId=<article id>
     */
    public function handleMarketplaceRedirect(string $usernameSlug, string $articleId): void {
        $this->logger->debug("Processing marketplace redirect", [
            'username' => $usernameSlug,
            'article_id' => $articleId
        ]);
        
        // Track this redirect
        if ($this->tracker) {
            $this->tracker->trackRedirect($articleId);
        }
        
        // Construct the redirect URL
        $url = WILLHABEN_AT_BASE_URL . '/iad/object?adId=' . $articleId;
        
        $this->logger->redirect($url, self::DEFAULT_REDIRECT_STATUS);
        throw new RedirectException($url, self::DEFAULT_REDIRECT_STATUS);
    }
    
    /**
     * Transform a direct buy link to our marketplace pattern
     * Example: https://www.willhaben.at/iad/kaufen-und-verkaufen/d/10-x-dvd-kinder-ab-0-1-6-1141031082/?checkoutMode=direct
     * To: willhaben.vip/<username slug>/marketplace/<article id>
     */
    public function transformDirectBuyLink(string $directBuyUrl, ?string $usernameSlug = null): string {
        // Extract article ID from URL
        if (preg_match('/-(\d+)\/?(\?|$)/', $directBuyUrl, $matches)) {
            $articleId = $matches[1];
            
            // Use provided username slug or default
            $slug = $usernameSlug ?: DEFAULT_SELLER_SLUG;
            
            return BASE_URL . '/' . $slug . '/marketplace/' . $articleId;
        }
        
        // If unable to parse, return original URL
        $this->logger->debug("Unable to transform direct buy link", ['url' => $directBuyUrl]);
        return $directBuyUrl;
    }

    /**
     * Extract seller ID from a willhaben.at URL 
     * Examples:
     * - https://www.willhaben.at/iad/kaufen-und-verkaufen/seller-profile/34434899
     * - https://willhaben.at/iad/user/34434899
     * 
     * @param string $url The URL to extract seller ID from
     * @return string|null The extracted seller ID or null if not found
     */
    public function extractSellerIdFromUrl(string $url): ?string {
        if (preg_match(self::WILLHABEN_SELLER_URL_PATTERN, $url, $matches)) {
            // Sanitize seller ID (numeric only)
            $sellerId = preg_replace('/[^0-9]/', '', $matches[1]);
            $this->logger->debug("Extracted seller ID from URL", [
                'url' => $url,
                'seller_id' => $sellerId
            ]);
            return $sellerId;
        }
        
        $this->logger->debug("Could not extract seller ID from URL", ['url' => $url]);
        return null;
    }

    /**
     * Handle a willhaben.at seller profile redirect
     * Process URLs like:
     * - https://www.willhaben.at/iad/kaufen-und-verkaufen/seller-profile/34434899
     * - https://willhaben.at/iad/user/34434899
     */
    public function handleWillhabenSellerRedirect(string $url): void {
        $sellerId = $this->extractSellerIdFromUrl($url);
        
        if ($sellerId) {
            $this->logger->debug("Processing willhaben.at seller redirect", [
                'url' => $url,
                'seller_id' => $sellerId
            ]);
            
            // Handle the seller redirect
            $this->handleSellerRedirect($sellerId);
        } else {
            // If we can't extract seller ID, redirect to homepage
            $this->logger->debug("Invalid willhaben.at seller URL, redirecting to homepage", ['url' => $url]);
            throw new RedirectException(BASE_URL, self::DEFAULT_REDIRECT_STATUS);
        }
    }
}
