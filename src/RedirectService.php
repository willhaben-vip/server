<?php
namespace Willhaben\RedirectService;

/**
 * Core service for handling redirects
 */
class RedirectService {
    private $logger;

    public function __construct(Logger $logger) {
        $this->logger = $logger;
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

        $sellerSlug = $this->verifySellerAndGetSlug($sellerId);
        if ($sellerSlug) {
            $url = BASE_URL . '/' . $sellerSlug . '/';
            $this->logger->redirect($url, 301);
            throw new RedirectException($url, 301);
        }

        // If seller not found, redirect to homepage
        $this->logger->debug("Invalid seller ID, redirecting to homepage", ['id' => $sellerId]);
        throw new RedirectException(BASE_URL, 302);
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
        
        $this->logger->redirect($url, 301);
        throw new RedirectException($url, 301);
    }
}

