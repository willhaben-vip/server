#!/usr/bin/env python3
"""
Script to update product JSON files with image URLs from product pages.

This script:
1. Reads JSON files in the current directory
2. Extracts product URLs
3. Fetches product pages and extracts JSON-LD data
4. Updates the original JSON files with image URLs
"""

import json
import os
import asyncio
import logging
import sys
import random
import time
import hashlib
import pathlib
import json
import uuid
import socket
import re
import urllib.parse
import argparse
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple, Union, Set

import aiohttp
from aiohttp import ClientError
import extruct
from w3lib.html import get_base_url

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Set to DEBUG for more verbose logging
logger.setLevel(logging.DEBUG)

# Constants
EXCLUDED_FILES = ['__example-page-data.qwad.json']
CACHE_DIR = '.cache'
SKU_DATA_DIR = '.'  # Directory to store individual SKU JSON-LD data
SKU_FILE_PREFIX = 'sku-'  # Prefix for SKU JSON files
STATE_FILE = '.wh_scraper_state.json'  # File to store progress state
USER_AGENTS = [
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0',
    'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/119.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/119.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36'
]
COMMON_HEADERS = {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
    'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Cache-Control': 'max-age=0',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
    'Referer': 'https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/',
    'DNT': '1'
}
MAX_CONCURRENT_REQUESTS = 1
REQUEST_TIMEOUT = 60  # seconds
MAX_RETRIES = 5
BASE_RETRY_DELAY = 300  # seconds (5 minutes)
MIN_REQUEST_DELAY = 120  # seconds (2 minutes)
MAX_REQUEST_DELAY = 300  # seconds (5 minutes)
CACHE_EXPIRY = 86400 * 7  # 7 days in seconds
SESSION_RATE_LIMIT = 0.02  # requests per SESSION_RATE_PERIOD (1 per 50 minutes)
SESSION_RATE_PERIOD = 3000  # seconds (50 minutes)
MAX_QUEUE_SIZE = 100  # maximum number of queued requests
PROXY_CHECK_TIMEOUT = 10  # seconds
PROXY_ROTATION_THRESHOLD = 3  # failures before rotating proxy
SESSION_RECOVERY_DELAY = 30 * 60  # 30 minutes before trying again after severe rate limiting
# Optional proxy configuration
# Format: ["http://user:pass@host:port", "http://host:port"]
PROXIES = [
    # Add your proxies here
]  

# Browser fingerprinting data
BROWSER_FINGERPRINTS = [
    {
        "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept_language": "en-US,en;q=0.9,de;q=0.8",
        "accept_encoding": "gzip, deflate, br",
        "sec_ch_ua": '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        "sec_ch_ua_platform": '"macOS"',
        "sec_ch_ua_mobile": "?0"
    },
    {
        "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        "accept_language": "de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7",
        "accept_encoding": "gzip, deflate, br",
        "sec_ch_ua": '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        "sec_ch_ua_platform": '"Windows"',
        "sec_ch_ua_mobile": "?0"
    },
    {
        "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/119.0",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "accept_language": "de,en-US;q=0.7,en;q=0.3",
        "accept_encoding": "gzip, deflate, br",
        "sec_fetch_dest": "document",
        "sec_fetch_mode": "navigate",
        "sec_fetch_site": "none",
        "sec_fetch_user": "?1"
    }
]

def get_cache_path(url: str) -> pathlib.Path:
    """Generate a cache file path for a URL."""
    # Create cache directory if it doesn't exist
    cache_dir = pathlib.Path(CACHE_DIR)
    cache_dir.mkdir(exist_ok=True)
    
    # Create a hash of the URL to use as the filename
    url_hash = hashlib.md5(url.encode()).hexdigest()
    return cache_dir / f"{url_hash}.html"


def is_cache_valid(cache_path: pathlib.Path) -> bool:
    """Check if cache file exists and is not expired."""
    if not cache_path.exists():
        return False
    
    # Check if the cache is too old
    cache_age = time.time() - cache_path.stat().st_mtime
    return cache_age < CACHE_EXPIRY


def read_cache(cache_path: pathlib.Path) -> Optional[str]:
    """Read content from cache file."""
    try:
        return cache_path.read_text(encoding="utf-8")
    except Exception as e:
        logger.warning(f"Error reading cache file {cache_path}: {e}")
        return None


def write_cache(cache_path: pathlib.Path, content: str) -> bool:
    """Write content to cache file."""
    try:
        cache_path.write_text(content, encoding="utf-8")
        return True
    except Exception as e:
        logger.warning(f"Error writing to cache file {cache_path}: {e}")
        return False


class ProxyManager:
    """Manager for proxy rotation and health checking."""
    def __init__(self, proxies: List[str] = None):
        self.proxies = proxies or PROXIES
        self.available_proxies = self.proxies.copy() if self.proxies else []
        self.failed_proxies: Dict[str, int] = {}  # proxy -> failure count
        self.proxy_last_used: Dict[str, float] = {}  # proxy -> timestamp
        self.current_proxy: Optional[str] = None
        self.lock = asyncio.Lock()
        
        # Generate a unique session ID
        self.session_id = str(uuid.uuid4())[:8]
        logger.info(f"ProxyManager initialized with {len(self.available_proxies)} proxies")
    
    async def get_proxy(self) -> Optional[str]:
        """Get a healthy proxy from the pool."""
        async with self.lock:
            if not self.available_proxies:
                # Try to recover some proxies
                self._recover_failed_proxies()
                if not self.available_proxies:
                    return None
            
            # If we already have a current proxy that's working, keep using it
            if self.current_proxy and self.current_proxy in self.available_proxies:
                # Check if we've used this proxy recently
                last_used = self.proxy_last_used.get(self.current_proxy, 0)
                if time.time() - last_used > 60:  # Give 60s between uses of the same proxy
                    self.proxy_last_used[self.current_proxy] = time.time()
                    return self.current_proxy
            
            # Rotate to a new proxy
            for proxy in self.available_proxies:
                # Check if we've used this proxy recently
                last_used = self.proxy_last_used.get(proxy, 0)
                if time.time() - last_used > 60:  # Give 60s between uses of the same proxy
                    self.current_proxy = proxy
                    self.proxy_last_used[proxy] = time.time()
                    logger.info(f"Rotating to proxy: {self._mask_proxy(proxy)}")
                    return proxy
            
            # All proxies have been used recently, use the least recently used one
            if self.available_proxies:
                least_recent_proxy = min(
                    self.available_proxies, 
                    key=lambda p: self.proxy_last_used.get(p, 0)
                )
                self.current_proxy = least_recent_proxy
                self.proxy_last_used[least_recent_proxy] = time.time()
                logger.info(f"Using least recent proxy: {self._mask_proxy(least_recent_proxy)}")
                return least_recent_proxy
            
            return None
    
    def _mask_proxy(self, proxy: str) -> str:
        """Mask proxy credentials for logging."""
        if not proxy:
            return "None"
        if '@' in proxy:
            # For proxies with auth
            parts = proxy.split('@')
            auth_part = parts[0]
            rest = '@'.join(parts[1:])
            
            # Mask the auth part
            masked_auth = auth_part.split('://')[0] + '://' + 'xxxxx:xxxxx'
            return masked_auth + '@' + rest
        return proxy
    
    async def check_proxy_health(self, proxy: str) -> bool:
        """Check if a proxy is working."""
        test_url = "https://www.google.com"
        try:
            connector = aiohttp.TCPConnector(ssl=False)
            async with aiohttp.ClientSession(connector=connector) as session:
                async with session.get(
                    test_url, 
                    proxy=proxy, 
                    timeout=PROXY_CHECK_TIMEOUT
                ) as response:
                    return response.status == 200
        except Exception as e:
            logger.debug(f"Proxy health check failed for {self._mask_proxy(proxy)}: {e}")
            return False
    
    async def mark_proxy_failure(self, proxy: str) -> None:
        """Mark a proxy as having failed and potentially remove it from rotation."""
        if not proxy:
            return
            
        async with self.lock:
            current_failures = self.failed_proxies.get(proxy, 0)
            self.failed_proxies[proxy] = current_failures + 1
            
            logger.warning(f"Proxy {self._mask_proxy(proxy)} failure count: {current_failures + 1}")
            
            if current_failures + 1 >= PROXY_ROTATION_THRESHOLD:
                if proxy in self.available_proxies:
                    self.available_proxies.remove(proxy)
                    logger.warning(f"Removed failing proxy from rotation: {self._mask_proxy(proxy)}")
                
                # If this was our current proxy, clear it
                if self.current_proxy == proxy:
                    self.current_proxy = None
    
    def _recover_failed_proxies(self) -> None:
        """Recover some failed proxies if we're running low."""
        if len(self.available_proxies) > 3:
            return
            
        # Add back proxies with the fewest failures
        failed_proxies = sorted(
            self.failed_proxies.items(), 
            key=lambda x: x[1]
        )
        
        for proxy, _ in failed_proxies:
            if proxy not in self.available_proxies and proxy in self.proxies:
                self.available_proxies.append(proxy)
                logger.info(f"Recovered proxy for use: {self._mask_proxy(proxy)}")
                self.failed_proxies[proxy] = 0
                
                # Stop once we've recovered enough
                if len(self.available_proxies) >= 3:
                    break


class BrowserSession:
    """Manages browser-like behavior and session state."""
    def __init__(self):
        self.fingerprint = random.choice(BROWSER_FINGERPRINTS)
        self.cookies = {}
        self.session_id = str(uuid.uuid4())[:8]
        self.last_request_time = 0
        self.visit_history = []
        
    def get_headers(self) -> Dict[str, str]:
        """Get browser-like headers."""
        headers = {
            "User-Agent": self.fingerprint["user_agent"],
            "Accept": self.fingerprint["accept"],
            "Accept-Language": self.fingerprint["accept_language"],
            "Accept-Encoding": self.fingerprint["accept_encoding"],
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1",
            "DNT": "1",
        }
        
        # Add browser-specific headers
        if "sec_ch_ua" in self.fingerprint:
            headers["sec-ch-ua"] = self.fingerprint["sec_ch_ua"]
            headers["sec-ch-ua-platform"] = self.fingerprint["sec_ch_ua_platform"]
            headers["sec-ch-ua-mobile"] = self.fingerprint["sec_ch_ua_mobile"]
        
        if "sec_fetch_dest" in self.fingerprint:
            headers["sec-fetch-dest"] = self.fingerprint["sec_fetch_dest"]
            headers["sec-fetch-mode"] = self.fingerprint["sec_fetch_mode"]
            headers["sec-fetch-site"] = self.fingerprint["sec_fetch_site"]
            headers["sec-fetch-user"] = self.fingerprint["sec_fetch_user"]
        
        # Add common headers
        if random.random() > 0.5:
            headers["Cache-Control"] = random.choice(["max-age=0", "no-cache"])
            
        # Add referrer if we have history
        if self.visit_history and random.random() > 0.3:
            headers["Referer"] = random.choice(self.visit_history)
            
        return headers
    
    def record_visit(self, url: str) -> None:
        """Record URL visit in history."""
        self.visit_history.append(url)
        self.last_request_time = time.time()
        
        # Keep history limited to last 10 URLs
        if len(self.visit_history) > 10:
            self.visit_history = self.visit_history[-10:]


def get_proxy_for_session(session: aiohttp.ClientSession) -> Optional[str]:
    """Get a proxy from the pool if available."""
    if not PROXIES:
        return None
    
    return random.choice(PROXIES)


class RateLimiter:
    """Simple rate limiter to control the request rate."""
    def __init__(self, rate_limit: int, period: int):
        self.rate_limit = rate_limit  # requests per period
        self.period = period  # in seconds
        self.timestamps = []
        self.lock = asyncio.Lock()

    async def acquire(self):
        """Acquire permission to make a request, waiting if necessary."""
        async with self.lock:
            now = time.time()
            
            # Remove timestamps older than our period
            self.timestamps = [ts for ts in self.timestamps if now - ts < self.period]
            
            # Wait if we've reached the limit
            if len(self.timestamps) >= self.rate_limit:
                oldest = min(self.timestamps)
                wait_time = self.period - (now - oldest) + random.uniform(60, 120)  # Add extra 1-2 minutes
                if wait_time > 0:
                    logger.info(f"Rate limit reached, waiting {wait_time:.2f}s before next request...")
                    await asyncio.sleep(wait_time)
                    # Recalculate now
                    now = time.time()
                    self.timestamps = [ts for ts in self.timestamps if now - ts < self.period]
            
            # Add current timestamp
            self.timestamps.append(now)


class RequestQueue:
    """Queue for managing and tracking pending requests."""
    def __init__(self, max_size: int = MAX_QUEUE_SIZE):
        self.queue = asyncio.Queue(max_size)
        self.pending = set()  # Store only URL strings, not tuples
        self.lock = asyncio.Lock()
    
    async def put(self, item):
        """
        Add a URL and its product reference to the queue if the URL is not already pending.
        
        Args:
            item: A tuple of (url, product_ref, filename) where:
                - url is a string
                - product_ref is a dict
                - filename is a string (optional)
        
        Returns:
            bool: True if the item was added, False otherwise
        """
        if not isinstance(item, tuple) or len(item) < 2:
            logger.error(f"Invalid item type for queue: {type(item)}. Expected (url, product_ref[, filename]) tuple.")
            return False
        
        # Extract URL (first element) regardless of tuple length
        url = item[0]
        product_ref = item[1]
        
        if not isinstance(url, str):
            logger.error(f"URL in tuple is not a string: {type(url)}")
            return False
            
        if not isinstance(product_ref, dict):
            logger.error(f"Product reference in tuple is not a dictionary: {type(product_ref)}")
            return False
        
        async with self.lock:
            if url not in self.pending:
                logger.debug(f"Adding URL to queue: {url}")
                await self.queue.put(item)  # Put the full tuple in the queue
                self.pending.add(url)  # Add only the URL to the pending set
                return True
            else:
                logger.debug(f"URL already in queue: {url}")
                return False
    
    async def get(self, timeout=None):
        """
        Get an item from the queue.
        
        Args:
            timeout: Optional timeout in seconds
            
        Returns:
            tuple: A tuple of (url, product_ref)
            
        Raises:
            asyncio.TimeoutError: If timeout is specified and no item is available within the timeout period
        """
        if timeout is not None:
            return await asyncio.wait_for(self.queue.get(), timeout=timeout)
        return await self.queue.get()
    
    def task_done(self, url: str):
        """
        Mark a URL as processed.
        
        Args:
            url: The URL string (not the tuple) that has been processed
        """
        self.queue.task_done()
        self.pending.discard(url)
        logger.debug(f"Marked URL as processed: {url}")
    
    async def join(self):
        """Wait for all tasks to be completed."""
        await self.queue.join()
        
    @property
    def pending_count(self):
        """Get the number of pending items."""
        return len(self.pending)


async def fetch_url(session: Optional[aiohttp.ClientSession], url: str, retries: int = MAX_RETRIES) -> Optional[str]:
    """Fetch a URL with retries and aggressive rate limiting."""
    # Check cache first
    cache_path = get_cache_path(url)
    if is_cache_valid(cache_path):
        logger.info(f"Using cached content for {url}")
        cached_content = read_cache(cache_path)
        if cached_content:
            return cached_content
    
    # Add a human-like pause before making the request
    human_delay = random.uniform(1, 5) + random.uniform(0, 2)
    await asyncio.sleep(human_delay)
    
    # Simulate "thinking time" and vary it based on URL complexity
    thinking_time = len(url) % 5 + random.uniform(1, 3)
    await asyncio.sleep(thinking_time)
    
    for attempt in range(retries):
        # Calculate exponential backoff delay with jitter
        backoff_delay = BASE_RETRY_DELAY * (2 ** attempt) + random.uniform(1, 5)
        # Cap the delay at a reasonable maximum
        backoff_delay = min(backoff_delay, 120)
        
        # Use a different user agent for each retry
        user_agent = random.choice(USER_AGENTS)
        headers = COMMON_HEADERS.copy()
        headers['User-Agent'] = user_agent
        
        # Add some randomness to request headers to look more human-like
        if random.random() > 0.5:
            headers['Accept-Encoding'] = random.choice(['gzip, deflate', 'gzip, deflate, br'])
        
        # Sometimes include a different referer
        if random.random() > 0.7:
            headers['Referer'] = 'https://www.google.com/search?q=willhaben'
        
        # Flag to check if we need to create a new session
        should_create_session = session is None
        session_to_use = session
        
        try:
            # Create a new session if needed for this request
            if should_create_session:
                conn = aiohttp.TCPConnector(
                    ssl=False,
                    ttl_dns_cache=300,  # Cache DNS results for 5 minutes
                    enable_cleanup_closed=True
                )
                session_to_use = aiohttp.ClientSession(
                    connector=conn,
                    timeout=aiohttp.ClientTimeout(total=REQUEST_TIMEOUT)
                )
                
            # Get a proxy for this request if available
            proxy = get_proxy_for_session(session_to_use)
            
            proxy_info = f" via proxy {proxy}" if proxy else ""
            logger.info(f"Requesting {url}{proxy_info} with User-Agent: {user_agent[:30]}...")
            
            async with session_to_use.get(
                url,
                timeout=REQUEST_TIMEOUT,
                headers=headers,
                proxy=proxy
            ) as response:
                if response.status == 200:
                    # Success! Get the content
                    content = await response.text()
                    # Cache the response
                    if content and len(content) > 100:  # Only cache non-empty responses
                        write_cache(cache_path, content)
                    # Add a random delay before returning to avoid overwhelming the server
                    await asyncio.sleep(random.uniform(MIN_REQUEST_DELAY, MAX_REQUEST_DELAY))
                    # Close session if we created it
                    if should_create_session and session_to_use is not None:
                        await session_to_use.close()
                    return content
                elif response.status == 429:  # Too Many Requests
                    logger.warning(f"Rate limited (429) for {url}, waiting longer before retry")
                    # Use a much longer delay for rate limit errors
                    wait_time = backoff_delay * 3 + random.uniform(300, 600)  # 5-10 minutes
                    logger.warning(f"Rate limited (429). Implementing long cooldown of {wait_time:.2f}s for {url}")
                    # Close session if we created it since we'll create a new one on retry
                    if should_create_session and session_to_use is not None:
                        await session_to_use.close()
                        session_to_use = None
                    await asyncio.sleep(wait_time)
                    
                    # After a rate limit, we should be extremely cautious
                    if attempt < retries - 1:
                        logger.info("After rate limit, adding additional cooldown period...")
                        await asyncio.sleep(random.uniform(120, 240))  # Additional 2-4 minute cooldown
                        
                elif response.status == 403:  # Forbidden
                    logger.warning(f"Received 403 Forbidden for {url}, may be blocked")
                    # Even longer delay for this - potential IP ban/block
                    wait_time = backoff_delay * 4 + random.uniform(600, 1200)  # 10-20 minutes
                    logger.warning(f"Possible blocking detected. Implementing very long cooldown of {wait_time:.2f}s")
                    # Close session if we created it since we'll create a new one on retry
                    if should_create_session and session_to_use is not None:
                        await session_to_use.close()
                        session_to_use = None
                    await asyncio.sleep(wait_time)
                else:
                    logger.warning(f"Failed to fetch {url}, status code: {response.status}")
                    # Close session if we created it since we'll create a new one on retry
                    if should_create_session and session_to_use is not None:
                        await session_to_use.close()
                        session_to_use = None
        except (ClientError, asyncio.TimeoutError, aiohttp.ClientError) as e:
            logger.warning(f"Error fetching {url} (attempt {attempt+1}/{retries}): {e}")
            # Always close session on error if we created it
            if should_create_session and session_to_use is not None:
                try:
                    await session_to_use.close()
                except Exception as close_err:
                    logger.warning(f"Error closing session: {close_err}")
                session_to_use = None
        
        if attempt < retries - 1:
            logger.info(f"Retrying {url} in {backoff_delay:.2f} seconds (attempt {attempt+1}/{retries})")
            await asyncio.sleep(backoff_delay)
    
    # Final cleanup
    if should_create_session and session_to_use is not None:
        try:
            await session_to_use.close()
        except Exception as e:
            logger.warning(f"Error closing session on final cleanup: {e}")
    
    logger.error(f"Failed to fetch {url} after {retries} attempts")
    return None


def extract_sku_from_url(url: str) -> Optional[str]:
    """Extract SKU (article ID) from a willhaben product URL."""
    try:
        # Try to extract from URL path segment
        # Pattern: /d/name-xxxxxxxx/ where xxxxxxxx is the SKU
        match = re.search(r'/d/[^/]+-(\d+)/?', url)
        if match:
            return match.group(1)
        
        # Try to extract from query parameters
        parsed_url = urllib.parse.urlparse(url)
        query_params = urllib.parse.parse_qs(parsed_url.query)
        if 'sku' in query_params:
            return query_params['sku'][0]
        if 'id' in query_params:
            return query_params['id'][0]
        
        # Last resort: extract last segment from URL path
        path_segments = parsed_url.path.strip('/').split('/')
        if path_segments:
            last_segment = path_segments[-1]
            if last_segment.isdigit():
                return last_segment
        
        # If all attempts failed
        logger.warning(f"Could not extract SKU from URL: {url}")
        # Use a hash of the URL as fallback
        hash_obj = hashlib.md5(url.encode('utf-8'))
        return f"hash-{hash_obj.hexdigest()[:8]}"
    except Exception as e:
        logger.error(f"Error extracting SKU from URL {url}: {e}")
        return None


def extract_sku_from_product(product: Dict) -> Optional[str]:
    """Extract SKU from product data."""
    try:
        # Check for explicit SKU fields
        if 'sku' in product:
            return str(product['sku'])
        if 'productID' in product:
            return str(product['productID'])
        if 'identifier' in product:
            return str(product['identifier'])
        
        # Check for potential ID fields
        if 'id' in product:
            return str(product['id'])
        
        # Check for URL and try to extract from there
        if 'url' in product and isinstance(product['url'], str):
            url_sku = extract_sku_from_url(product['url'])
            if url_sku:
                return url_sku
                
        logger.warning(f"Could not extract SKU from product data")
        return None
    except Exception as e:
        logger.error(f"Error extracting SKU from product data: {e}")
        return None


def save_json_ld_data(data: List[Dict], sku: str) -> bool:
    """Save JSON-LD data to a file named sku-<article_id>.json."""
    try:
        if not data:
            logger.warning(f"No JSON-LD data to save for SKU {sku}")
            return False
            
        # Create directory if it doesn't exist
        pathlib.Path(SKU_DATA_DIR).mkdir(exist_ok=True)
        
        # Generate filename
        file_path = pathlib.Path(SKU_DATA_DIR) / f"{SKU_FILE_PREFIX}{sku}.json"
        
        # Save to file with pretty formatting
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            
        logger.info(f"Saved JSON-LD data to {file_path}")
        return True
    except Exception as e:
        logger.error(f"Error saving JSON-LD data for SKU {sku}: {e}")
        return False


class StateManager:
    """Manages the state of processed URLs and SKUs for resuming."""
    def __init__(self, state_file: str = STATE_FILE):
        self.state_file = state_file
        self.processed_urls = set()
        self.processed_skus = set()
        self.file_progress = {}  # filename -> list of processed URLs
        self.cached_operations = 0  # Counter for cached operations
        self.total_processed = 0  # Counter for total processed operations
        self.lock = asyncio.Lock()
        self._load_state()
    
    def _load_state(self) -> None:
        """Load state from file if it exists."""
        try:
            state_path = pathlib.Path(self.state_file)
            if state_path.exists():
                with open(state_path, 'r', encoding='utf-8') as f:
                    state = json.load(f)
                
                self.processed_urls = set(state.get('processed_urls', []))
                self.processed_skus = set(state.get('processed_skus', []))
                self.file_progress = state.get('file_progress', {})
                self.cached_operations = state.get('cached_operations', 0)
                self.total_processed = state.get('total_processed', 0)
                
                logger.info(f"Loaded state: {len(self.processed_urls)} URLs and {len(self.processed_skus)} SKUs processed")
                logger.info(f"Cached operations: {self.cached_operations}/{self.total_processed}")
                
                # Log progress for each file
                for filename, urls in self.file_progress.items():
                    logger.info(f"  File {filename}: {len(urls)} URLs processed")
            else:
                logger.info("No existing state file, starting fresh")
        except Exception as e:
            logger.warning(f"Failed to load state: {e}")
            # Initialize with empty state
            self.processed_urls = set()
            self.processed_skus = set()
            self.file_progress = {}
            self.cached_operations = 0
            self.total_processed = 0
    
    async def save_state(self) -> None:
        """Save current state to file."""
        async with self.lock:
            try:
                state = {
                    'processed_urls': list(self.processed_urls),
                    'processed_skus': list(self.processed_skus),
                    'file_progress': self.file_progress,
                    'cached_operations': self.cached_operations,
                    'total_processed': self.total_processed,
                    'last_updated': datetime.now().isoformat()
                }
                
                with open(self.state_file, 'w', encoding='utf-8') as f:
                    json.dump(state, f, indent=2, ensure_ascii=False)
                
                logger.debug(f"Saved state: {len(self.processed_urls)} URLs processed, {self.cached_operations} cached operations")
            except Exception as e:
                logger.error(f"Failed to save state: {e}")
    
    async def mark_processed(self, url: str, sku: str, filename: str, used_cache: bool = False) -> None:
        """Mark a URL and SKU as processed."""
        async with self.lock:
            self.processed_urls.add(url)
            if sku:
                self.processed_skus.add(sku)
            
            # Update file progress
            if filename not in self.file_progress:
                self.file_progress[filename] = []
            
            if url not in self.file_progress[filename]:
                self.file_progress[filename].append(url)
            
            # Update cache statistics
            self.total_processed += 1
            if used_cache:
                self.cached_operations += 1
                
            # Save state after each update
            await self.save_state()
    
    def is_processed(self, url: str) -> bool:
        """Check if a URL has already been processed."""
        return url in self.processed_urls
    
    def is_sku_processed(self, sku: str) -> bool:
        """Check if a SKU has already been processed."""
        return sku in self.processed_skus
    
    def is_file_processed(self, filename: str) -> bool:
        """Check if a file has been completely processed."""
        # Check if file exists in progress tracking and has entries
        if filename not in self.file_progress:
            return False
        
        # Check if the file has at least some processed URLs
        if len(self.file_progress[filename]) == 0:
            return False
            
        # File is considered processed if it has more than a threshold of URLs completed
        # For simplicity, any file with 5+ processed URLs is considered "done"
        # This can be adjusted based on your specific needs
        return len(self.file_progress[filename]) >= 5
        
    def should_process_file(self, filename: str) -> bool:
        """Determine if a file should be processed based on resume mode."""
        # In non-resume mode, process all files
        try:
            if not args.resume:
                return True
        except NameError:
            # args might not be defined yet if called before parse_arguments()
            return True
            
        # In resume mode, only process files that haven't been completed
        return not self.is_file_processed(filename)
    
    def get_cached_count(self) -> int:
        """Get the count of operations that used cached data."""
        return self.cached_operations
    
    def get_processed_count(self) -> int:
        """Get the total count of processed operations."""
        return self.total_processed


def check_existing_sku_data(sku: str) -> Optional[List[Dict]]:
    """
    Check if there's already an existing JSON file for the SKU and read its data.
    
    Args:
        sku: The SKU/article ID to check
        
    Returns:
        List[Dict] if valid data exists, None otherwise
    """
    try:
        file_path = pathlib.Path(SKU_DATA_DIR) / f"{SKU_FILE_PREFIX}{sku}.json"
        
        # Check if file exists
        if not file_path.exists():
            return None
            
        # Check age of file - consider recent files valid without re-validation
        file_age = time.time() - file_path.stat().st_mtime
        recent_threshold = 60 * 60 * 24 * 7  # 7 days
        
        # Read file content
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        # Basic validation - must be a list of dictionaries
        if not isinstance(data, list):
            logger.warning(f"Invalid data format in existing SKU file {file_path} (not a list)")
            return None
            
        # At least one item should be present with a type
        if not data or not any('@type' in item for item in data if isinstance(item, dict)):
            logger.warning(f"No valid JSON-LD objects found in existing SKU file {file_path}")
            return None
            
        # If the file is recent enough, we trust it without deeper validation
        if file_age < recent_threshold:
            logger.info(f"Found recent valid SKU data file: {file_path}")
            return data
            
        # For older files, do more thorough validation
        # Look for product-specific fields that indicate valid product data
        product_fields = ['name', 'description', 'offers', 'brand', 'image']
        has_product_fields = False
        
        for item in data:
            if not isinstance(item, dict):
                continue
                
            # Check if it's a product and has some required fields
            if item.get('@type') in ['Product', 'Offer', 'WebPage', 'ItemPage'] and \
               any(field in item for field in product_fields):
                has_product_fields = True
                break
                
        if has_product_fields:
            logger.info(f"Found valid SKU data file: {file_path}")
            return data
        else:
            logger.warning(f"Existing SKU file {file_path} lacks product data")
            return None
            
    except json.JSONDecodeError:
        logger.warning(f"Invalid JSON in existing SKU file for {sku}")
        return None
    except Exception as e:
        logger.warning(f"Error checking existing SKU data for {sku}: {e}")
        return None


def extract_json_ld(html: str, url: str) -> List[Dict]:
    """Extract JSON-LD data from HTML."""
    base_url = get_base_url(html, url)
    data = extruct.extract(html, base_url=base_url, syntaxes=['json-ld'])
    return data.get('json-ld', [])


def extract_image_urls(json_ld_data: List[Dict]) -> List[str]:
    """Extract image URLs from JSON-LD data."""
    image_urls = []
    
    for item in json_ld_data:
        # Check for different image property patterns in JSON-LD
        if isinstance(item.get('image'), str):
            image_urls.append(item['image'])
        elif isinstance(item.get('image'), list):
            image_urls.extend([img for img in item['image'] if isinstance(img, str)])
        elif isinstance(item.get('image'), dict) and 'url' in item['image']:
            image_urls.append(item['image']['url'])
            
        # Check for other image properties
        for prop in ['thumbnail', 'primaryImageOfPage']:
            if isinstance(item.get(prop), str):
                image_urls.append(item[prop])
            elif isinstance(item.get(prop), dict) and 'url' in item[prop]:
                image_urls.append(item[prop]['url'])
    
    return list(set(image_urls))  # Remove duplicates


def find_json_files() -> List[str]:
    """Find JSON files in the current directory, excluding specified files."""
    json_files = []
    for filename in os.listdir('.'):
        if filename.endswith('.json') and filename not in EXCLUDED_FILES:
            json_files.append(filename)
    return json_files


def extract_product_urls(json_data: List[Dict]) -> List[Tuple[str, Dict]]:
    """
    Extract product URLs from JSON data.
    Returns a list of tuples (url, product_reference) where product_reference
    is a reference to the product object in the JSON data.
    """
    product_data = []
    
    for item in json_data:
        if isinstance(item, dict) and item.get('@type') == 'ItemList':
            item_list = item.get('itemListElement', [])
            for list_item in item_list:
                if isinstance(list_item, dict) and list_item.get('@type') == 'ListItem':
                    product = list_item.get('item', {})
                    if isinstance(product, dict) and product.get('@type') == 'Product':
                        url = product.get('url')
                        if url:
                            try:
                                # Verify that URL is a string
                                if not isinstance(url, str):
                                    logger.error(f"Skipping non-string URL: {url} (type: {type(url)})")
                                    continue
                                    
                                # Verify that product is indeed a dictionary
                                if not isinstance(product, dict):
                                    logger.error(f"Skipping non-dictionary product: {product} (type: {type(product)})")
                                    continue
                                    
                                logger.debug(f"Extracted product URL: {url}")
                                product_data.append((url, product))
                            except Exception as e:
                                logger.error(f"Error processing product: {e}")
    
    return product_data


async def process_json_file(filename: str, semaphore: asyncio.Semaphore, rate_limiter: RateLimiter, state_manager: StateManager) -> None:
    """Process a single JSON file."""
    try:
        # Check if we should process this file in resume mode
        if not state_manager.should_process_file(filename):
            logger.info(f"Skipping {filename} - already processed in previous run")
            return
            
        # Load JSON file
        with open(filename, 'r') as file:
            json_data = json.load(file)
        
        logger.info(f"Processing {filename}")
        
        # Extract product URLs and references
        product_data = extract_product_urls(json_data)
        if not product_data:
            logger.warning(f"No product URLs found in {filename}")
            return
        
        logger.info(f"Found {len(product_data)} products in {filename}")
        
        # Create a request queue
        request_queue = RequestQueue()
        
        # Create a session for HTTP requests with cookies enabled and connection pooling
        conn = aiohttp.TCPConnector(
            limit=MAX_CONCURRENT_REQUESTS,
            ssl=False,
            ttl_dns_cache=300,  # Cache DNS results for 5 minutes
            enable_cleanup_closed=True,
            force_close=False,
            limit_per_host=1  # Limit connections per host
        )
        
        # Use a cookie jar to maintain session cookies
        cookie_jar = aiohttp.CookieJar(unsafe=True)  # Allow cookies from non-secure connections
        
        # Create client session with the connection
        async with aiohttp.ClientSession(
            connector=conn,
            cookie_jar=cookie_jar,
            timeout=aiohttp.ClientTimeout(total=REQUEST_TIMEOUT * 2)
        ) as session:
            # Add all product URLs to the queue (skipping already processed ones in resume mode)
            logger.info(f"Found {len(product_data)} products in {filename}")
            queued_count = 0
            skipped_count = 0
            
            for url, product_ref in product_data:
                try:
                    # Skip already processed URLs in resume mode
                    try:
                        if args.resume and state_manager.is_processed(url):
                            logger.info(f"Skipping already processed URL: {url}")
                            skipped_count += 1
                            continue
                    except NameError:
                        # args might not be defined yet
                        pass
                    
                    # Extract SKU to check if processed
                    sku = extract_sku_from_product(product_ref) or extract_sku_from_url(url)
                    try:
                        if sku and args.resume and state_manager.is_sku_processed(sku):
                            logger.info(f"Skipping already processed SKU: {sku}")
                            skipped_count += 1
                            continue
                    except NameError:
                        # args might not be defined yet
                        pass
                        
                    logger.info(f"Adding to queue: URL={url}, product_ref type={type(product_ref)}, filename={filename}")
                    added = await request_queue.put((url, product_ref, filename))  # Include filename for tracking
                    if added:
                        logger.debug(f"Added to queue: {url}")
                        queued_count += 1
                    else:
                        logger.debug(f"Skipped duplicate URL in queue: {url}")
                        skipped_count += 1
                except Exception as e:
                    logger.error(f"Error adding URL to queue: {url}, error: {e}")
                    skipped_count += 1
                    
            logger.info(f"Added {queued_count} URLs to queue, skipped {skipped_count} URLs")
            
            logger.info(f"Queue contains {request_queue.pending_count} pending URLs")
            
            # Create worker tasks to process the queue
            tasks = []
            for i in range(MAX_CONCURRENT_REQUESTS):
                logger.debug(f"Creating worker {i+1}/{MAX_CONCURRENT_REQUESTS}")
                try:
                    task = asyncio.create_task(
                        worker(session, request_queue, semaphore, rate_limiter, state_manager)
                    )
                    tasks.append(task)
                except Exception as e:
                    logger.error(f"Error creating worker task: {e}")
            
            # Wait for the queue to be processed
            try:
                logger.debug(f"Waiting for queue to complete processing ({request_queue.pending_count} items pending)")
                # Use a shorter timeout for development or testing
                timeout = 600 if args.verbose else 3600  # 10 minutes in verbose mode, 1 hour otherwise
                await asyncio.wait_for(request_queue.join(), timeout=timeout)
                logger.debug(f"Queue processing complete")
            except asyncio.TimeoutError:
                logger.error(f"Timeout waiting for queue to complete")
                # Continue anyway
            except KeyboardInterrupt:
                logger.info("Keyboard interrupt detected, initiating graceful shutdown")
            except Exception as e:
                logger.error(f"Error waiting for queue: {e}")
            
            # Cancel worker tasks with proper cleanup
            logger.debug("Cancelling worker tasks")
            for task in tasks:
                if not task.done():
                    task.cancel()
            
            # Wait for tasks to be cancelled with timeout
            try:
                # Only wait a short time for tasks to clean up
                await asyncio.wait_for(
                    asyncio.gather(*tasks, return_exceptions=True),
                    timeout=5.0
                )
                logger.debug("Worker tasks cancelled successfully")
            except asyncio.TimeoutError:
                logger.warning("Some worker tasks did not shut down gracefully")
            except asyncio.CancelledError:
                logger.debug("Task cancellation interrupted")
            except Exception as e:
                logger.error(f"Error during worker task cleanup: {e}")

        # Save updated JSON data
        with open(filename, 'w') as file:
            json.dump(json_data, file, indent=2)
        
        logger.info(f"Updated {filename} successfully")
    
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing JSON in {filename}: {e}")
    except Exception as e:
        logger.error(f"Error processing {filename}: {e}")


async def worker(
    session: aiohttp.ClientSession, 
    request_queue: RequestQueue, 
    semaphore: asyncio.Semaphore, 
    rate_limiter: RateLimiter,
    state_manager: StateManager
) -> None:
    """
    Worker function that processes URLs from the queue.
    
    Args:
        session: The shared aiohttp ClientSession
        request_queue: Queue of URLs to process
        semaphore: Semaphore to limit concurrent requests
        rate_limiter: Rate limiter to control request frequency
        state_manager: State manager to track progress
    """
    # Generate a unique ID for this worker for logging
    worker_id = str(uuid.uuid4())[:6]
    logger.info(f"Worker {worker_id} started")
    
    # Track empty queue occurrences to determine when to exit
    empty_queue_count = 0
    max_empty_count = 5  # Exit after checking an empty queue this many times
    
    # Create a worker-specific session with its own connection pool
    current_session = None
    session_renewal_count = 0
    session_max_renewal = 5  # Renew session after this many requests
    
    # Track session health and error patterns
    session_health = 100  # Health score from 0-100
    error_types = {}  # Track frequency of different error types
    last_errors = []  # Recent errors for pattern detection
    backoff_base = 1.0  # Base backoff time in seconds, adjusted dynamically
    consecutive_errors = 0  # Track consecutive errors

    # Helper function to safely create or renew a session with optimized settings
    async def create_safe_session(force_new=False, error_type=None):
        nonlocal current_session, session_health, error_types, backoff_base, consecutive_errors
        
        # Update error tracking if an error type was provided
        if error_type:
            if error_type in error_types:
                error_types[error_type] += 1
            else:
                error_types[error_type] = 1
                
            # Add to recent errors list (keep last 5)
            last_errors.append(error_type)
            if len(last_errors) > 5:
                last_errors.pop(0)
                
            # Consecutive errors tracking
            consecutive_errors += 1
            
            # Decrease session health based on error type
            if error_type in ('connection', 'timeout'):
                session_health -= 30  # Connection errors impact health more
            elif error_type in ('http_error', 'rate_limit'):
                session_health -= 20
            else:
                session_health -= 10
                
            # Adjust base backoff time based on error patterns
            if consecutive_errors > 3:
                backoff_base = min(backoff_base * 1.5, 10.0)  # Increase backoff up to 10s
        else:
            # Reset consecutive errors on successful operations
            consecutive_errors = 0
            # Slowly recover session health on success
            session_health = min(100, session_health + 5)
        
        # Force session renewal if health is too low
        if session_health < 40:
            logger.warning(f"Worker {worker_id}: Session health low ({session_health}), forcing renewal")
            force_new = True
            # Reset health after renewal
            session_health = 70  # Start new session at 70% health
        
        # Ensure we have a running event loop
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            logger.error(f"Worker {worker_id}: No running event loop found when creating session")
            return False
        
        # Close existing session if it exists and is not already closed
        if current_session is not None and (force_new or not current_session.closed):
            try:
                if not current_session.closed:
                    # Set a brief timeout for closing to avoid hanging
                    close_task = asyncio.create_task(current_session.close())
                    try:
                        await asyncio.wait_for(close_task, timeout=3.0)
                        logger.debug(f"Worker {worker_id} closed previous session successfully")
                    except asyncio.TimeoutError:
                        logger.warning(f"Worker {worker_id} session close timed out")
            except Exception as e:
                logger.warning(f"Worker {worker_id} error closing previous session: {e}")
            finally:
                # Set to None to ensure we don't try to reuse an errored session
                current_session = None
        
        # If not forced and session is still valid, return
        if not force_new and current_session is not None and not current_session.closed:
            logger.debug(f"Worker {worker_id} reusing existing healthy session")
            return True
            
        # Calculate retry parameters based on error history
        max_retries = 3 + (consecutive_errors // 2)  # Increase retries after multiple errors
        max_retries = min(max_retries, 6)  # But cap at reasonable value
        
        retry_count = 0
        
        # Calculate backoff with jitter to avoid thundering herd
        def get_backoff_time(attempt):
            # Exponential backoff with jitter and ceiling
            jitter = random.uniform(0.8, 1.2)
            backoff_time = backoff_base * (2 ** attempt) * jitter
            return min(backoff_time, 30.0)  # Cap at 30 seconds
        
        while retry_count < max_retries:
            try:
                # Create connection with optimized pool settings based on observed patterns
                use_limit = 1
                use_limit_per_host = 1
                
                # Set DNS cache TTL longer for stable hosts
                dns_cache_ttl = 300  # 5 minutes default
                
                # For unstable connections (based on error history), use stricter settings
                if consecutive_errors > 2:
                    dns_cache_ttl = 60  # Shorter DNS cache when seeing many errors
                
                # Create optimized connection pool
                conn = aiohttp.TCPConnector(
                    ssl=False, 
                    limit=use_limit,  # Overall connection limit
                    limit_per_host=use_limit_per_host,  # Per-host connection limit
                    ttl_dns_cache=dns_cache_ttl,  # DNS cache TTL
                    enable_cleanup_closed=True,  # Clean up closed transports
                    force_close=consecutive_errors > 3,  # Force close if we've had many errors
                    keepalive_timeout=30.0 if session_health > 70 else 5.0  # Shorter keepalive for unhealthy sessions
                )
                
                # Calculate appropriate timeout based on network conditions
                timeout_factor = 1.0 + (consecutive_errors * 0.5)  # Increase timeout after errors
                total_timeout = REQUEST_TIMEOUT * timeout_factor
                
                # Create session with optimized settings
                current_session = aiohttp.ClientSession(
                    connector=conn,
                    timeout=aiohttp.ClientTimeout(
                        total=total_timeout,
                        connect=min(30.0, total_timeout / 3),  # Connect timeout
                        sock_read=min(30.0, total_timeout / 2),  # Socket read timeout
                        sock_connect=min(30.0, total_timeout / 3)  # Socket connect timeout
                    ),
                    # Add client tracing for internal error monitoring
                    trace_configs=[]
                )
                logger.debug(f"Worker {worker_id} created a new session (health: {session_health}, consecutive errors: {consecutive_errors})")
                return True
            except Exception as e:
                retry_count += 1
                logger.error(f"Worker {worker_id} failed to create session (attempt {retry_count}/{max_retries}): {e}")
                
                # Use exponential backoff with jitter
                backoff_time = get_backoff_time(retry_count)
                logger.debug(f"Retrying session creation in {backoff_time:.2f}s")
                await asyncio.sleep(backoff_time)
        
        logger.critical(f"Worker {worker_id} failed to create session after {max_retries} attempts")
        return False
    
    try:
        # Create an operations counter
        operations_total = 0
        operations_success = 0
        last_operation_time = time.time()
        
        # Setup monitoring of worker health
        task_start_time = time.time()
        
        # Define adaptive settings for session renewal
        session_health_check_interval = 10  # Check session health every N requests
        session_renewal_strategy = "adaptive"  # Can be "fixed", "adaptive", or "error-based"
        
        # Create initial session outside the main loop
        session_created = await create_safe_session()
        if not session_created:
            logger.error(f"Worker {worker_id} could not create initial session, exiting")
            return
            
        logger.debug(f"Worker {worker_id} created its own session")
        
        # Pending operations tracking for safe cancellation
        pending_operation = None
        operation_start_time = None
        
        # Task in progress tracking
        current_url = None
        current_task_start = None
        
        while True:
            try:
                # Check worker health and prevent deadlock
                current_time = time.time()
                worker_runtime = current_time - task_start_time
                idle_time = current_time - last_operation_time
                
                # Alert if worker appears to be stuck (no operation in 5 minutes)
                if idle_time > 300 and operations_total > 0:
                    logger.warning(f"Worker {worker_id} may be stuck. Idle for {idle_time:.2f}s, considering session renewal")
                    # Force session renewal if worker appears stuck
                    session_created = await create_safe_session(force_new=True, error_type="worker_stuck")
                    if session_created:
                        session_renewal_count = 0
                        last_operation_time = current_time  # Reset idle timer
                    else:
                        logger.error(f"Worker {worker_id} stuck and failed to renew session. Will try to continue.")
                
                # Implement adaptive session renewal strategy
                should_renew_session = False
                
                if session_renewal_strategy == "fixed":
                    # Traditional fixed count renewal
                    should_renew_session = session_renewal_count >= session_max_renewal
                elif session_renewal_strategy == "adaptive":
                    # Adaptive renewal based on:
                    # 1. Request count
                    # 2. Session age
                    # 3. Error rate
                    session_age = time.time() - task_start_time
                    error_rate = (operations_total - operations_success) / max(1, operations_total)
                    
                    # Calculate renewal threshold based on multiple factors
                    session_age_threshold = 3600  # 1 hour
                    session_age = time.time() - task_start_time
                    
                    # Consider renewing if:
                    # 1. Session has been used for several requests
                    # 2. Session is old
                    # 3. Error rate is above threshold
                    should_renew_session = (
                        session_renewal_count >= session_max_renewal or
                        session_age > session_age_threshold or
                        error_rate > 0.2 or  # More than 20% errors
                        session_health < 60   # Health score below 60%
                    )
                elif session_renewal_strategy == "error-based":
                    # Renew only in response to specific errors
                    should_renew_session = consecutive_errors > 2
                
                # Implement session renewal if needed
                if should_renew_session:
                    logger.info(f"Worker {worker_id} renewing session (strategy: {session_renewal_strategy})")
                    session_created = await create_safe_session(force_new=True)
                    if session_created:
                        session_renewal_count = 0
                        logger.debug(f"Worker {worker_id} renewed session successfully")
                    else:
                        logger.error(f"Worker {worker_id} failed to renew session")
                
                # Try to get an item from the queue with a short timeout
                try:
                    # Use a short timeout to detect empty queues without blocking indefinitely
                    item = await asyncio.wait_for(request_queue.get(), timeout=5.0)
                    empty_queue_count = 0  # Reset empty queue counter when we get an item
                    
                    # Update operational metrics
                    operations_total += 1
                    last_operation_time = time.time()
                    
                    # Process the URL - extract URL, product_ref and filename from item
                    url = "unknown"
                    product_ref = None
                    filename = "unknown_file"
                    
                    # Extract components from the queue item
                    if isinstance(item, tuple):
                        if len(item) >= 3:
                            url, product_ref, filename = item
                        elif len(item) >= 2:
                            url, product_ref = item
                            filename = "unknown_file"
                        logger.debug(f"Worker {worker_id} processing: URL={url}, product_ref type={type(product_ref)}")
                    
                    # Process the URL
                    success = False
                    used_cache = False
                    try:
                        logger.info(f"Processing URL {url}")
                        try:
                            # Verify we have a running event loop before proceeding - with more robust checking
                            have_valid_loop = False
                            try:
                                loop = asyncio.get_running_loop()
                                if not loop.is_closed():
                                    have_valid_loop = True
                                else:
                                    logger.error(f"Worker {worker_id}: Event loop is closed when processing URL {url}")
                            except RuntimeError:
                                logger.error(f"Worker {worker_id}: No running event loop when processing URL {url}")
                            
                            if not have_valid_loop:
                                logger.error(f"Cannot process URL {url} without a valid event loop")
                                # Mark this URL for retry later rather than failing permanently
                                await asyncio.sleep(1.0)  # Short pause before continuing
                                # We'll skip this URL and let the queue retry it later
                                continue
                                
                            # Check if session is valid before proceeding
                            if current_session is None or current_session.closed:
                                logger.warning(f"Session is closed or None before processing URL {url}, creating new session")
                                session_created = await create_safe_session(force_new=True, error_type="invalid_session")
                                if not session_created:
                                    logger.error(f"Failed to create new session for URL {url}, skipping")
                                    # Add short backoff before continuing
                                    await asyncio.sleep(2.0)
                                    continue
                                    
                            # Double-check session validity before processing
                            if current_session is not None and not current_session.closed:
                                success, used_cache = await process_product_url(current_session, url, product_ref, semaphore, rate_limiter)
                                logger.debug(f"Process result: {'Success' if success else 'Failed'} (cached: {used_cache}) for URL {url}")
                                # Update success metrics
                                if success:
                                    operations_success += 1
                                    # Reset the consecutive error counter on success
                                    consecutive_errors = 0
                                # Increment session usage counter for renewal tracking
                                if not used_cache:
                                    session_renewal_count += 1
                            else:
                                logger.error(f"Could not create a valid session for URL {url}")
                                success = False
                                used_cache = False
                        except aiohttp.ClientConnectionError as e:
                            logger.error(f"Connection error for URL {url}: {e}")
                            # Use a more robust event loop check before session renewal
                            try:
                                loop = asyncio.get_running_loop()
                                if not loop.is_closed():
                                    # Renew session immediately on connection error using the safe helper
                                    session_created = await create_safe_session(force_new=True, error_type="connection")
                                    if session_created:
                                        session_renewal_count = 0
                                        logger.debug(f"Worker {worker_id} created new session after connection error")
                                    else:
                                        logger.error(f"Failed to create new session after connection error for URL {url}")
                                else:
                                    logger.error(f"Event loop closed during connection error handling for URL {url}")
                            except RuntimeError:
                                logger.error(f"No running event loop during connection error handling for URL {url}")
                            
                            # Sleep longer to give system time to recover
                            await asyncio.sleep(5.0)
                            continue
                        except aiohttp.ClientError as e:
                            logger.error(f"Client error for URL {url}: {e}")
                            # Check for valid event loop before attempting session renewal
                            try:
                                loop = asyncio.get_running_loop()
                                if not loop.is_closed():
                                    # For other client errors, we'll also try to renew the session
                                    session_created = await create_safe_session(force_new=True, error_type="http_error")
                                    if session_created:
                                        session_renewal_count = 0
                                        logger.debug(f"Session renewed after client error")
                                else:
                                    logger.error(f"Event loop closed during client error handling for URL {url}")
                            except RuntimeError:
                                logger.error(f"No running event loop during client error handling for URL {url}")
                            
                            # Add backoff even if session renewal failed
                            await asyncio.sleep(5.0)
                            continue
                        except asyncio.TimeoutError as e:
                            logger.error(f"Timeout error for URL {url}: {e}")
                            # Check for valid event loop before attempting session renewal
                            try:
                                loop = asyncio.get_running_loop()
                                if not loop.is_closed():
                                    # For timeout errors, we'll also try to renew the session with a longer backoff
                                    session_created = await create_safe_session(force_new=True, error_type="timeout")
                                    if session_created:
                                        session_renewal_count = 0
                                        logger.debug(f"Session renewed after timeout error")
                                else:
                                    logger.error(f"Event loop closed during timeout error handling for URL {url}")
                            except RuntimeError:
                                logger.error(f"No running event loop during timeout error handling for URL {url}")
                            
                            # Add a longer delay for timeout errors
                            await asyncio.sleep(10.0)
                            continue
                        
                        # Mark as processed in state manager if processing was successful
                        if success and state_manager is not None:
                            try:
                                sku = extract_sku_from_product(product_ref) or extract_sku_from_url(url)
                                await state_manager.mark_processed(url, sku, filename, used_cache)
                                logger.debug(f"Successfully processed URL and marked in state manager: {url}")
                            except Exception as state_error:
                                logger.error(f"Error updating state manager for URL {url}: {state_error}")
                        elif not success:
                            logger.warning(f"Failed to process URL: {url}")
                    except Exception as e:
                        logger.error(f"Error in worker {worker_id} processing URL {url}: {e}", exc_info=True)
                        success = False
                    finally:
                        # Mark task as done to ensure queue moves forward
                        try:
                            # Verify we have a valid event loop for task completion
                            have_valid_loop = False
                            try:
                                loop = asyncio.get_running_loop()
                                if not loop.is_closed():
                                    have_valid_loop = True
                            except RuntimeError:
                                logger.error(f"No running event loop when marking task as done for URL {url}")
                            
                            if have_valid_loop:
                                request_queue.task_done(url)
                                logger.debug(f"Marked URL as complete in queue: {url}")
                                logger.debug(f"Queue size after task completion: {request_queue.pending_count} items pending")
                                
                                # Check remaining queue size
                                if request_queue.pending_count == 0:
                                    logger.info(f"Queue is now empty, worker will check a few more times")
                                else:
                                    logger.debug(f"Queue still has {request_queue.pending_count} items, continuing")
                            else:
                                logger.error(f"Could not mark URL {url} as done due to invalid event loop")
                        except Exception as e:
                            logger.error(f"Error marking URL {url} as done in queue: {e}")
                            # Try to recover from event loop or queue errors by creating a new session
                            try:
                                # Check if we have a valid event loop
                                loop_valid = False
                                try:
                                    loop = asyncio.get_running_loop()
                                    if not loop.is_closed():
                                        loop_valid = True
                                except RuntimeError:
                                    logger.error(f"No running event loop when attempting recovery for URL {url}")
                                
                                # Only attempt recovery with a valid event loop
                                if loop_valid:
                                    # Force safe session renewal on queue errors
                                    session_created = await create_safe_session(force_new=True, error_type="queue_error")
                                    if session_created:
                                        logger.debug(f"Created new session after queue task completion error")
                                    else:
                                        logger.warning(f"Failed to create new session after queue task completion error")
                            except Exception as session_error:
                                logger.error(f"Failed to recover from queue task completion error: {session_error}")
                else:
                    logger.error(f"Invalid item type in queue: {type(item)}")
                    # Mark as done even if invalid to avoid queue getting stuck
                    try:
                        request_queue.queue.task_done()
                    except Exception as e:
                        logger.error(f"Error marking invalid item as done: {e}")
                        # Try to recover from queue errors
                        try:
                            # Force safe session renewal on queue errors
                            await create_safe_session(force_new=True, error_type="queue_error")
                        except Exception as session_error:
                            logger.error(f"Failed to create new session after queue error: {session_error}")
                except asyncio.TimeoutError:
                    # No item in queue within timeout - could be empty
                    empty_queue_count += 1
                    logger.debug(f"Worker {worker_id}: Queue empty or timeout ({empty_queue_count}/{max_empty_count})")
                    
                    # If we've seen an empty queue multiple times, we're done
                    if empty_queue_count >= max_empty_count:
                        logger.info(f"Worker {worker_id} detected consistently empty queue, exiting")
                        break
                    
                    # Short wait before checking again
                    await asyncio.sleep(1.0)
                    continue
            except asyncio.CancelledError:
                # Task was cancelled, try to complete the current operation if possible
                logger.info(f"Worker {worker_id} received cancellation signal, cleaning up")
                raise  # Re-raise to be caught by the outer try
            except Exception as e:
                logger.error(f"Unexpected error in worker {worker_id}: {e}")
                # Shorter sleep on error
                await asyncio.sleep(0.5)
                # Don't increment empty queue counter for errors
    except asyncio.CancelledError:
        # Task was cancelled, try to complete the current operation if possible
        logger.info(f"Worker {worker_id} received cancellation signal, cleaning up")
        try:
            # Try to mark the current task as done if possible
            if 'url' in locals() and url != "unknown":
                request_queue.task_done(url)
                logger.debug(f"Marked URL as done during cancellation: {url}")
        except Exception as e:
            # Log errors during cleanup
            logger.warning(f"Error marking task done during cancellation: {e}")
            
        # If there's a current operation in progress, try to save any partial progress
        try:
            if 'url' in locals() and 'product_ref' in locals() and 'filename' in locals() and url != "unknown" and product_ref is not None:
                # Try to update state manager if we've made any progress
                if state_manager is not None:
                    sku = extract_sku_from_product(product_ref) or extract_sku_from_url(url)
                    if sku:
                        # Mark as partially processed to avoid losing progress
                        await state_manager.mark_processed(url, sku, filename, False)
                        logger.info(f"Saved partial progress for URL {url} during cancellation")
        except Exception as e:
            logger.warning(f"Failed to save partial progress during cancellation: {e}")
            
        # Try to close the session if we created our own
        if current_session and not current_session.closed:
            try:
                # Ensure we have a running event loop for session.close()
                try:
                    asyncio.get_running_loop()
                    await current_session.close()
                    logger.debug(f"Worker {worker_id} closed session during cancellation")
                except RuntimeError:
                    logger.warning(f"Worker {worker_id}: No running event loop for session closure during cancellation")
                    # Can't do await, but mark as None so we don't try to use it elsewhere
                    current_session = None
            except Exception as e:
                logger.warning(f"Error closing session during cancellation: {e}")
                current_session = None
                
        logger.info(f"Worker {worker_id} shutting down")
        return  # Use return instead of break to make it clear we're exiting
    except Exception as e:
        logger.error(f"Fatal error in worker {worker_id}: {e}", exc_info=True)
    
    # Ensure proper session cleanup in the finally block
    finally:
        # Clean up our own session if we created one
        if current_session is not None:
            try:
                # Check for running event loop before attempting to close
                try:
                    loop = asyncio.get_running_loop()
                    if loop.is_closed():
                        logger.warning(f"Worker {worker_id}: Event loop is closed during cleanup")
                        current_session = None
                    elif not current_session.closed:
                        await current_session.close()
                        logger.debug(f"Worker {worker_id} closed its session")
                except RuntimeError:
                    logger.warning(f"Worker {worker_id}: No running event loop for final session closure")
                    # We can't properly close it, but we'll set it to None to prevent reuse
                    current_session = None
            except Exception as e:
                logger.warning(f"Error closing session in worker {worker_id}: {e}")
                current_session = None
                
        # Ensure we report completion even if there were errors
        logger.info(f"Worker {worker_id} has completed. Processed {operations_total} URLs, {operations_success} successful ({((operations_success/max(1, operations_total))*100):.2f}%)")
                
        logger.info(f"Worker {worker_id} has completed")


async def process_product_url(
    session: aiohttp.ClientSession,
    url: str,
    product_ref: Dict,
    semaphore: asyncio.Semaphore,
    rate_limiter: RateLimiter
) -> Tuple[bool, bool]:
    """
    Process a product URL and update the product reference.
    
    Returns:
        Tuple[bool, bool]: (success, used_cache)
            - success: True if processing was successful, False otherwise
            - used_cache: True if cached data was used, False otherwise
    """
    try:
        # Check if session is valid before proceeding
        if session is None or session.closed:
            logger.error(f"Invalid session provided for URL {url}")
            return False, False
            
        async with semaphore:
            # Wait for rate limiter with a timeout
            try:
                await asyncio.wait_for(rate_limiter.acquire(), timeout=30.0)
            except asyncio.TimeoutError:
                logger.warning(f"Rate limiter acquisition timed out for {url}, proceeding anyway")
            
            # No need for additional delays when checking cache - let the rate limiter handle this
            
            # Get SKU from product_ref or from URL first to check for existing data
            sku = extract_sku_from_product(product_ref) or extract_sku_from_url(url)
            if not sku:
                logger.warning(f"Could not determine SKU for {url}")
                sku = f"unknown-{int(time.time())}"
                
            # Check if we already have valid data for this SKU
            existing_data = check_existing_sku_data(sku)
            if existing_data:
                logger.info(f"Using existing SKU data for {sku} from file, skipping HTTP request")
                
                # Extract image URLs from existing data
                image_urls = extract_image_urls(existing_data)
                if not image_urls:
                    logger.warning(f"No image URLs found in existing data for SKU {sku}")
                else:
                    logger.info(f"Found {len(image_urls)} images in existing data for SKU {sku}")
                    
                # Update product reference with image URLs
                try:
                    product_ref['image'] = image_urls[0] if len(image_urls) == 1 else image_urls
                    logger.info(f"Updated product with image URL(s): {image_urls[0] if len(image_urls) == 1 else len(image_urls)} images from existing data")
                    logger.debug(f"Successfully processed {url} using cached data")
                    # Return (success, used_cache)
                    return True, True
                except Exception as e:
                    logger.error(f"Error updating product reference with image URLs from existing data: {e}")
                    return False, False
        
        # If no existing data is found, proceed with HTTP request
        logger.info(f"No existing data found for SKU {sku}, fetching product page: {url}")
        html = await fetch_url(session, url)
        
        if not html:
            logger.error(f"Failed to fetch content for {url}")
            return False, False
        
        # Extract JSON-LD data
        json_ld_data = extract_json_ld(html, url)
        if not json_ld_data:
            logger.warning(f"No JSON-LD data found for {url}")
            return False, False
        
        # Save JSON-LD data to file
        saved = save_json_ld_data(json_ld_data, sku)
        if saved:
            logger.info(f"Successfully saved JSON-LD data for SKU {sku}")
        else:
            logger.warning(f"Failed to save JSON-LD data for SKU {sku}")
        
        # Extract image URLs
        image_urls = extract_image_urls(json_ld_data)
        if not image_urls:
            logger.warning(f"No image URLs found for {url}")
            # Continue anyway since we may have already saved the JSON-LD data
        else:
            logger.info(f"Found {len(image_urls)} images for {url}")
            
            # Update product reference with image URLs
            try:
                product_ref['image'] = image_urls[0] if len(image_urls) == 1 else image_urls
                logger.info(f"Updated product with image URL(s): {image_urls[0] if len(image_urls) == 1 else len(image_urls)} images")
            except Exception as e:
                logger.error(f"Error updating product reference with image URLs: {e}")
                return False, False
                
        # If we got here, processing was successful (without using cache)
        return True, False
    except Exception as e:
        logger.error(f"Unexpected error processing URL {url}: {e}")
        return False, False


async def main():
    """Main function to process all JSON files."""
    try:
        # Find JSON files
        json_files = find_json_files()
        if not json_files:
            logger.warning("No JSON files found to process")
            return
        
        logger.info(f"Found {len(json_files)} JSON files to process")
        
        # Create a semaphore to limit concurrent requests
        semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
        
        # Create a rate limiter using command line arguments
        # Prioritize command line arguments over defaults
        rate_limit = args.rate_limit
        rate_period = args.rate_period
        
        # Override hardcoded SESSION values with command line values
        global SESSION_RATE_LIMIT, SESSION_RATE_PERIOD
        if rate_limit is not None:
            SESSION_RATE_LIMIT = rate_limit
        if rate_period is not None:
            SESSION_RATE_PERIOD = rate_period
        
        # Log the actual values being used
        logger.info(f"Using rate limit: {SESSION_RATE_LIMIT} requests per {SESSION_RATE_PERIOD}s")
        rate_limiter = RateLimiter(SESSION_RATE_LIMIT, SESSION_RATE_PERIOD)
        
        # Create state manager for tracking progress
        state_manager = StateManager()
        
        # Sort files to process converted files first (they're more likely to have good data)
        # This can help with caching
        sorted_files = sorted(json_files, key=lambda f: 0 if f.startswith("fd") else 1)
        
        # Process each JSON file one at a time to avoid overwhelming the server
        for filename in sorted_files:
            # Skip files based on max requests if specified
            if hasattr(args, 'max_requests') and args.max_requests is not None:
                if len(state_manager.processed_urls) >= args.max_requests:
                    logger.info(f"Reached max requests limit ({args.max_requests}), stopping")
                    break
            
            # Check if file has already been fully processed in resume mode
            if hasattr(args, 'resume') and args.resume and state_manager.is_file_processed(filename):
                logger.info(f"Skipping {filename} - already fully processed (resume mode)")
                continue
                
            logger.info(f"Starting to process {filename}")
            try:
                await process_json_file(filename, semaphore, rate_limiter, state_manager)
                logger.info(f"Completed processing {filename}")
            except Exception as e:
                logger.error(f"Error processing {filename}: {e}")
            
            # Add a delay between files, shorter for fully cached operations
            if state_manager.get_cached_count() > 0 and state_manager.get_cached_count() == state_manager.get_processed_count():
                # If all operations were cached, use a shorter delay
                delay = random.uniform(30, 60)  # 30s-1min for cached ops
                logger.info(f"All operations were cached, using shorter delay: {delay:.2f}s")
            else:
                # Normal delay between files
                delay = random.uniform(300, 600)  # 5-10 minutes
                logger.info(f"Waiting {delay:.2f}s before processing next file...")
            
            await asyncio.sleep(delay)
        
        logger.info("All JSON files processed successfully")
    
    except Exception as e:
        logger.error(f"Error in main process: {e}")



def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Process product URLs from JSON files')
    
    parser.add_argument('--resume', action='store_true', 
                      help='Resume from last successful request')
    
    parser.add_argument('--rate-limit', type=float, default=SESSION_RATE_LIMIT,
                      help=f'Rate limit (requests per period, default: {SESSION_RATE_LIMIT})')
    
    parser.add_argument('--rate-period', type=int, default=SESSION_RATE_PERIOD,
                      help=f'Rate limit period in seconds (default: {SESSION_RATE_PERIOD})')
    
    parser.add_argument('--max-requests', type=int, default=None,
                      help='Maximum number of requests to make (default: unlimited)')
    
    parser.add_argument('--verbose', action='store_true',
                      help='Enable verbose logging')
    
    return parser.parse_args()


if __name__ == "__main__":
    # Parse command line arguments
    args = parse_arguments()
    
    # Set logging level based on verbose flag
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    # Check for required dependencies
    try:
        import aiohttp
        import extruct
        import w3lib
    except ImportError as e:
        logger.error(f"Missing required dependency: {e}")
        logger.info("Please install required packages: pip install aiohttp extruct w3lib")
        sys.exit(1)
    
    # Set a random seed based on current time
    random.seed(time.time())
    
    # Add a small startup delay
    time.sleep(random.uniform(1, 3))
    
    # Log the script configuration
    logger.info(f"Starting with MAX_CONCURRENT_REQUESTS={MAX_CONCURRENT_REQUESTS}, "
                f"MAX_RETRIES={MAX_RETRIES}, BASE_RETRY_DELAY={BASE_RETRY_DELAY}s, "
                f"Rate limit={SESSION_RATE_LIMIT} per {SESSION_RATE_PERIOD}s")
    
    # Count existing SKU files to report
    try:
        existing_sku_files = list(pathlib.Path(SKU_DATA_DIR).glob(f"{SKU_FILE_PREFIX}*.json"))
        if existing_sku_files:
            logger.info(f"Found {len(existing_sku_files)} existing SKU data files that may be reused")
    except Exception as e:
        logger.warning(f"Error counting existing SKU files: {e}")
    
    # Run the main function
    asyncio.run(main())

