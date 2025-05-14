<?php
namespace Willhaben\RedirectService;

/**
 * Exception class for handling redirects in the application
 */
class RedirectException extends \Exception {
    private $url;
    private $status;

    public function __construct($url, $status = 302) {
        $this->url = $url;
        $this->status = $status;
        parent::__construct("Redirect to: " . $url);
    }

    public function getUrl() {
        return $this->url;
    }

    public function getStatus() {
        return $this->status;
    }
}
