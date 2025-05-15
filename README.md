# willhaben.vip Server

willhaben.vip Server is the backend system for handling willhaben.vip redirects and functionality.

## Features

### Marketplace Redirect System

The marketplace redirect system provides a clean, branded URL pattern for willhaben marketplace listings while tracking redirect statistics.

#### Overview

- Creates friendly URLs in the format: `willhaben.vip/<username>/marketplace/<article-id>`
- Redirects to the appropriate willhaben.at article page
- Tracks redirect counts and timestamps for analytics
- Transforms direct buy links to the new marketplace pattern

#### Quick Start

1. **Access a marketplace URL:**
   ```
   willhaben.vip/rene.kapusta/marketplace/1141031082
   ```

2. **Transform a direct buy link:**
   ```php
   $redirectService = new RedirectService($logger);
   $marketplaceUrl = $redirectService->transformDirectBuyLink($directBuyUrl);
   ```

3. **View tracking statistics:**
   ```php
   $tracker = new RedirectTracker($logger);
   $stats = $tracker->getArticleTracking("1141031082");
   ```

#### Deployment Notes

- Requires write access to the `/data` directory
- Uses SQLite by default (can be configured to use JSON)
- No database migrations needed (auto-creates schema)

[📄 Detailed Documentation](MARKETPLACE_REDIRECT.md)

## Setup and Installation

See [DEVOPS.md](DEVOPS.md) for deployment and infrastructure setup information.

## Testing

Run the test suite:

```bash
php test-redirect.php
```

## License

See [LICENSE](LICENSE) file for details.
