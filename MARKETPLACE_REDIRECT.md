# Willhaben Marketplace Redirect System

## Table of Contents
- [Overview](#overview)
- [Configuration and Setup](#configuration-and-setup)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Development and Contribution Guidelines](#development-and-contribution-guidelines)
- [Performance and Scaling](#performance-and-scaling)

## Overview

The Marketplace Redirect System provides a clean, branded URL pattern for willhaben marketplace listings. It also tracks redirect statistics for analytics purposes.

### Key Features

- **Custom URL Pattern**: Transforms willhaben.at marketplace URLs into a branded format  
  `willhaben.vip/<username slug>/marketplace/<article id>`
- **Redirect Tracking**: Records statistics for each redirect, including counts and timestamps
- **Link Transformation**: Utility to convert "direkt kaufen" links to the new marketplace pattern
- **Flexible Storage**: Configurable backend storage using either SQLite or JSON

### Architecture

The system consists of the following components:

1. **RedirectService**: Handles the core redirect logic and URL transformations
2. **RedirectTracker**: Manages the tracking database and statistics
3. **Configuration**: Settings in config.php for customizing behavior
4. **Test Suite**: Comprehensive test script for validation

## Configuration and Setup

### Prerequisites

- PHP 7.4 or later
- SQLite3 PHP extension (when using SQLite storage)
- Write permissions for the `/data` directory

### Installation

The system is integrated into the existing codebase. No additional installation steps are required beyond the standard deployment process.

### Configuration Options

All configuration is managed in `config/config.php`:

```php
// Willhaben.at base URL for constructing redirects
define('WILLHABEN_AT_BASE_URL', 'https://willhaben.at');

// Default seller slug used when username is not provided
define('DEFAULT_SELLER_SLUG', 'rene.kapusta');

// Tracking system configuration
define('TRACKING_STORAGE_TYPE', 'sqlite'); // Options: 'sqlite' or 'json'
define('TRACKING_STORAGE_PATH', APP_ROOT . '/data/redirect_tracking.' . 
       (TRACKING_STORAGE_TYPE === 'sqlite' ? 'db' : 'json'));
```

### Directory Structure

```
server/
├── config/
│   └── config.php            # Configuration settings
├── data/                     # Directory for tracking data (auto-created)
│   └── redirect_tracking.db  # SQLite database (or .json if configured)
├── src/
│   ├── RedirectService.php   # Core redirect functionality
│   └── RedirectTracker.php   # Tracking functionality
└── test-redirect.php         # Test suite
```

## Usage Examples

### Marketplace URL Pattern

The system handles URLs in the following format:
```
willhaben.vip/<username slug>/marketplace/<article id>
```

For example:
```
willhaben.vip/rene.kapusta/marketplace/1141031082
```

This URL redirects the user to:
```
https://willhaben.at/iad/object?adId=1141031082
```

### Transforming Direct Buy Links

You can programmatically transform "direkt kaufen" links using the RedirectService:

```php
$redirectService = new RedirectService($logger);

// Original direct buy URL
$directBuyUrl = "https://www.willhaben.at/iad/kaufen-und-verkaufen/d/10-x-dvd-kinder-ab-0-1-6-1141031082/?checkoutMode=direct";

// Transform to marketplace URL
$marketplaceUrl = $redirectService->transformDirectBuyLink($directBuyUrl);
// Result: https://willhaben.vip/rene.kapusta/marketplace/1141031082

// With custom username
$customUrl = $redirectService->transformDirectBuyLink($directBuyUrl, "custom-user");
// Result: https://willhaben.vip/custom-user/marketplace/1141031082
```

### Accessing Tracking Data

You can retrieve tracking statistics for a specific article:

```php
$logger = new Logger(REDIRECT_LOG_FILE);
$tracker = new RedirectTracker($logger);

// Get tracking data for an article
$articleId = "1141031082";
$data = $tracker->getArticleTracking($articleId);

// $data contains:
// [
//   'article_id' => '1141031082',
//   'redirect_count' => 42,
//   'first_redirect_timestamp' => '2025-05-15 10:00:00',
//   'last_redirect_timestamp' => '2025-05-15 15:30:00'
// ]
```

## Testing

### Running the Test Suite

A comprehensive test script is included to validate all functionality:

```bash
# From the server directory
php test-redirect.php
```

The test suite verifies:
- URL pattern matching
- Redirect tracking functionality
- Link transformation
- Edge cases
- Storage persistence

### Manual Testing

You can manually test the redirect by accessing:
```
http://localhost/rene.kapusta/marketplace/1141031082
```

To test the direct buy link transformation, you can create a simple PHP script:
```php
require_once 'config/config.php';
require_once 'src/Logger.php';
require_once 'src/RedirectService.php';

$logger = new \Willhaben\RedirectService\Logger(REDIRECT_LOG_FILE);
$service = new \Willhaben\RedirectService\RedirectService($logger);

$result = $service->transformDirectBuyLink("https://www.willhaben.at/iad/kaufen-und-verkaufen/d/example-1141031082/?checkoutMode=direct");
echo $result;
```

## Troubleshooting

### Common Issues

#### Missing /data Directory
**Symptoms**: Errors related to file permissions or non-existent paths.
**Solution**: Ensure the `/data` directory exists and has proper write permissions:
```bash
mkdir -p data
chmod 777 data
```

#### SQLite Extension Not Available
**Symptoms**: PDO errors when using SQLite storage.
**Solution**: Either install the SQLite extension or switch to JSON storage in config.php:
```php
define('TRACKING_STORAGE_TYPE', 'json');
```

#### Incorrect Redirect Patterns
**Symptoms**: URLs not redirecting correctly.
**Solution**: Verify the URL format matches the expected pattern:
```
willhaben.vip/<username slug>/marketplace/<article id>
```

### Debugging

1. **Enable Detailed Logging**: Set higher verbosity in the logger to see more detailed information.

2. **Examine Tracking Data**: Check the database or JSON file in the data directory to verify tracking information.

3. **Run Test Script**: The `test-redirect.php` script provides detailed output and can identify issues.

## Development and Contribution Guidelines

### Adding New Features

1. **URL Patterns**: When adding new patterns, update:
   - `RedirectService.php`: Add a new handler method
   - `debug-index.php`: Add the pattern matching logic
   - Test script: Add test cases

2. **Tracking Fields**: To add new tracking fields:
   - Update `RedirectTracker.php`: Modify database schema and methods
   - Update the tracking storage format

### Code Style

Maintain the existing coding style:
- PSR-12 compatible
- Descriptive method names
- Thorough error handling
- Comprehensive comments
- Type hinting for parameters and return values

### Testing

All new features should include:
- Test cases in the test script
- Edge case handling
- Performance considerations

## Performance and Scaling

### Storage Considerations

- **SQLite**: Good for moderate traffic (up to ~100 req/sec)
  - Pros: ACID compliance, atomic operations
  - Cons: Potential locking issues under high concurrency

- **JSON**: Simple but less scalable
  - Pros: No external dependencies
  - Cons: File locking issues, entire file must be read/written

### Scaling Strategies

For high-traffic scenarios:

1. **Database Upgrade**: Consider migrating to MySQL/PostgreSQL
   - Modify `RedirectTracker.php` to support additional database backends
   - Add connection pooling for better performance

2. **Caching Layer**: Implement memcached/redis for frequently accessed articles
   - Add caching logic in `RedirectTracker.php`
   - Configure TTL values appropriately

3. **Sharding**: For massive scale, implement sharding by article ID
   - Split tracking data across multiple databases
   - Use consistent hashing for lookups

### Performance Monitoring

Monitor the system for:
- Response time of redirects
- Storage size growth
- Database locking issues (if using SQLite)
- High-volume articles that may need special handling

---

## Support and Maintenance

For questions or support, contact:
- Development Team: dev@willhaben.at
- DevOps: devops@willhaben.at

Last updated: May 15, 2025

