# willhaben.vip - AI Agent Instructions for Creating Member Profiles

This document provides detailed instructions for an AI agent to generate a complete willhaben.vip member profile page. Follow these steps to create a fully functional, SEO-optimized, and accessible HTML page that displays seller information, location, and product listings from willhaben.at.

## Table of Contents

1. [Data Collection Requirements](#1-data-collection-requirements)
2. [File Structure and Setup](#2-file-structure-and-setup)
3. [HTML Structure Implementation](#3-html-structure-implementation)
4. [Schema.org Data Implementation](#4-schemaorg-data-implementation)
5. [OpenStreetMap Integration](#5-openstreetmap-integration)
6. [Product Listing Generation](#6-product-listing-generation)
7. [Styling and Responsive Design](#7-styling-and-responsive-design)
8. [Accessibility Implementation](#8-accessibility-implementation)
9. [Redirect Functionality](#9-redirect-functionality)
10. [Error Handling](#10-error-handling)
11. [Validation and Testing](#11-validation-and-testing)
12. [Deployment](#12-deployment)

---

## 1. Data Collection Requirements

Before generating the profile page, collect the following information about the member:

### Seller Information
- **User ID**: Numerical ID from willhaben.at (e.g., 34434899)
- **Name**: Seller's display name
- **Location**: City and postal code (e.g., 3100 St. Pölten)
- **Member Since**: Registration date (e.g., May 2020)
- **Response Time**: Typical response time (e.g., "Within 10 Minutes")
- **Rating**: Seller rating (e.g., 5/5)
- **Shipping Options**: Available shipping methods (e.g., "Post, Selbstabholung")

### Location Data
- **Coordinates**: Latitude and longitude of seller's city location (e.g., 48.2000° N, 15.6167° E)
- **Region**: State or province (e.g., Niederösterreich)
- **Country**: Country code (e.g., AT for Austria)

### Product Data
For each product (minimum 3, recommended 5-10):
- **Product ID**: Unique identifier from willhaben.at
- **Title**: Product name
- **Description**: Short description including condition
- **Price**: Amount and currency (e.g., 9,00 €)
- **Image URL**: Product image link (if available)
- **Product URL**: Direct link to product on willhaben.at
- **Availability**: In stock, sold, etc.
- **Shipping Information**: Shipping options, costs

### Example Data JSON Structure
```json
{
  "seller": {
    "id": "34434899",
    "name": "Rene",
    "location": "3100 St. Pölten",
    "coordinates": [48.2000, 15.6167],
    "region": "Niederösterreich",
    "country": "AT",
    "memberSince": "2020-05-13",
    "responseTime": "Innerhalb von 10 Minuten",
    "rating": 5,
    "ratingCount": 1,
    "shippingOptions": ["Post", "Selbstabholung"]
  },
  "products": [
    {
      "id": "1998346331",
      "title": "Groß, größer, am größten",
      "description": "Buch - Deutsch, gebraucht",
      "price": 9.00,
      "currency": "EUR",
      "imageUrl": "https://www.willhaben.at/iad/image/upload/t_zoom_compressed/v1/19a7ff73-ec4d-4b38-8a22-5cc5d81df45/1998346331",
      "productUrl": "https://www.willhaben.at/iad/kaufen-und-verkaufen/d/gross-groesser-am-groessten-1998346331/",
      "availability": "InStock",
      "condition": "UsedCondition"
    }
    // Additional products...
  ]
}
```

---

## 2. File Structure and Setup

Create the following file structure:

```
/username/
  ├── index.htm     # Main profile page
  └── assets/       # Optional directory for local assets
      ├── css/      # Optional separate CSS if not inline
      └── js/       # Optional separate JavaScript if not inline
```

Where `username` is the seller's name in lowercase, with spaces replaced by underscores.

---

## 3. HTML Structure Implementation

### Basic HTML5 Structure

```html
<!DOCTYPE html>
<html lang="de-AT">
<head>
    <!-- Meta tags -->
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>[Seller Name]s Verkäuferprofil - willhaben.vip</title>
    
    <!-- SEO meta tags -->
    <meta name="description" content="...">
    <meta name="author" content="[Seller Name]">
    <meta name="robots" content="index, follow">
    
    <!-- OpenGraph & Twitter Cards -->
    <!-- Schema.org JSON-LD -->
    <!-- CSS styles -->
    
    <!-- Leaflet for OpenStreetMap -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    
    <!-- Redirect implementation -->
    <meta http-equiv="refresh" content="60;url=https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]">
</head>
<body>
    <main class="profile-section" role="main">
        <!-- Seller profile -->
        <!-- Location map -->
        <!-- Product listings -->
        <!-- Redirect notice -->
    </main>
    
    <!-- JavaScript -->
</body>
</html>
```

### Required Meta Tags

Implement these essential meta tags:

```html
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>[Seller Name]s Verkäuferprofil - willhaben.vip</title>
<meta name="description" content="Verkäuferprofil von [Seller Name] in [Location] mit Top-Bewertungen. Schnelle Antwortzeit innerhalb von [Response Time].">
<meta name="author" content="[Seller Name]">
<meta name="robots" content="index, follow">
<meta name="theme-color" content="#2196F3">

<!-- Security headers -->
<meta http-equiv="Content-Security-Policy" content="default-src 'self' https://www.willhaben.at https://*.openstreetmap.org https://*.openstreetmap.fr https://*.openstreetmap.de https://unpkg.com; img-src 'self' https://www.willhaben.at https://*.tile.openstreetmap.org https://*.openstreetmap.fr https://*.openstreetmap.de https://tile.openstreetmap.org https://api.openstreetmap.org https://unpkg.com data:; style-src 'self' 'unsafe-inline' https://unpkg.com https://*.openstreetmap.org; script-src 'self' 'unsafe-inline' https://unpkg.com https://*.openstreetmap.org; connect-src 'self' https://*.tile.openstreetmap.org https://*.openstreetmap.fr https://*.openstreetmap.de https://tile.openstreetmap.org https://api.openstreetmap.org https://unpkg.com; font-src 'self' https://unpkg.com data:; worker-src 'self' blob:; child-src 'self' blob:; object-src 'none'; manifest-src 'self';">
<meta http-equiv="Strict-Transport-Security" content="max-age=31536000; includeSubDomains">
<meta http-equiv="X-Content-Type-Options" content="nosniff">
<meta http-equiv="X-XSS-Protection" content="0">
<meta http-equiv="Permissions-Policy" content="ch-ua-model=*, ch-ua-platform-version=*, interest-cohort=()">
```

### OpenGraph and Twitter Card Tags

```html
<!-- OpenGraph Meta Tags -->
<meta property="og:title" content="[Seller Name]s Verkäuferprofil - willhaben.at">
<meta property="og:description" content="Verkäuferprofil von [Seller Name] in [Location] mit Top-Bewertungen. Schnelle Antwortzeit innerhalb von [Response Time].">
<meta property="og:type" content="profile">
<meta property="og:url" content="https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]">
<meta property="og:locale" content="de_AT">
<meta property="og:image" content="https://www.willhaben.at/mmo/logo.png">
<meta property="og:image:alt" content="Willhaben Logo">
<meta property="profile:username" content="[Seller Name]">

<!-- Twitter Card Meta Tags -->
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="[Seller Name]s Verkäuferprofil - willhaben.at">
<meta name="twitter:description" content="Verkäuferprofil von [Seller Name] in [Location] mit Top-Bewertungen.">
<meta name="twitter:image" content="https://www.willhaben.at/mmo/logo.png">
```

### Main Profile Structure

```html
<main class="profile-section" role="main">
    <h1 id="profile-title">Verkäuferprofil: [Seller Name]</h1>
    
    <!-- Profile Information -->
    <section id="profile-info" role="region" aria-labelledby="profile-title">
        <p><strong>Standort:</strong> <span id="seller-location">[Location]</span></p>
        <p><strong>Mitglied seit:</strong> <span id="member-since">[Member Since]</span></p>
        <p><strong>Antwortzeit:</strong> <span id="response-time">[Response Time]</span></p>
        <p><strong>Zuletzt online:</strong> <span id="last-online">[Last Online]</span></p>
        <p>
            <strong>Bewertung:</strong>
            <span class="rating" aria-label="[Rating] von 5 Sternen">★★★★★</span>
            <span class="meta-info">([Rating]/5 auf PayLivery)</span>
        </p>
        <p><strong>Versandoptionen:</strong> <span id="shipping-options">[Shipping Options]</span></p>
    </section>

    <!-- Location Map -->
    <section id="location-map" class="map-container" role="region" aria-labelledby="map-heading">
        <h2 id="map-heading" class="visually-hidden">Standortkarte</h2>
        <div id="osm-map" class="osm-map" aria-label="OpenStreetMap zeigt [Location], Österreich" tabindex="0"></div>
        <div class="map-label" id="map-label" aria-live="polite">[Location], [Region]</div>
    </section>

    <!-- Product Listings -->
    <section id="latest-products" role="region" aria-labelledby="products-heading">
        <h2 id="products-heading">Aktuelle Angebote</h2>
        <div class="product-list">
            <!-- Product items will be generated here -->
        </div>
    </section>

    <!-- Redirect Notice -->
    <div class="countdown" role="status" aria-live="polite">
        <p>Weiterleitung zum Verkäuferprofil auf willhaben.at in <span id="countdown">60</span> Sekunden...</p>
        <div class="direct-link-btn">
            <a href="https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]" 
               class="btn btn-primary" 
               aria-label="Direkt zum Verkäuferprofil auf willhaben.at">
                Direkt zum Willhaben Profil
            </a>
        </div>
    </div>
</main>
```

---

## 4. Schema.org Data Implementation

Add the following Schema.org structured data using JSON-LD format:

### Person Schema
```html
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "Person",
    "name": "[Seller Name]",
    "address": {
        "@type": "PostalAddress",
        "addressLocality": "[Location]",
        "addressCountry": "[Country]"
    },
    "memberOf": {
        "@type": "Organization",
        "name": "Willhaben",
        "url": "https://www.willhaben.at"
    },
    "aggregateRating": {
        "@type": "AggregateRating",
        "ratingValue": "[Rating]",
        "bestRating": "5",
        "ratingCount": "[Rating Count]",
        "reviewCount": "[Rating Count]"
    },
    "knowsAbout": ["[Category1]", "[Category2]", "[Category3]"],
    "description": "Verkäuferprofil von [Seller Name] mit verschiedenen Produkten",
    "memberSince": "[ISO Date, e.g. 2020-05-13]",
    "potentialAction": {
        "@type": "ViewAction",
        "target": "https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]"
    }
}
</script>
```

### Organization Schema
```html
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": "Willhaben Marketplace",
    "url": "https://www.willhaben.at",
    "logo": "https://www.willhaben.at/mmo/logo.png",
    "sameAs": "https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]"
}
</script>
```

### ItemList Schema for Products
```html
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "ItemList",
    "itemListElement": [
        {
            "@type": "ListItem",
            "position": 1,
            "item": {
                "@type": "Product",
                "name": "[Product Title]",
                "sku": "[Product ID]",
                "url": "https://www.willhaben.at/iad/kaufen-und-verkaufen/d/[product-slug]-[Product ID]/",
                "description": "[Product Description]",
                "image": "[Product Image URL]",
                "offers": {
                    "@type": "Offer",
                    "price": "[Price]",
                    "priceCurrency": "EUR",
                    "availability": "https://schema.org/[Availability]",
                    "availabilityStarts": "[ISO Date, e.g. 2025-05-01T00:00:00+02:00]",
                    "itemCondition": "https://schema.org/[Condition]",
                    "seller": {
                        "@type": "Person",
                        "name": "[Seller Name]"
                    },
                    "deliveryLeadTime": {
                        "@type": "QuantitativeValue",
                        "minValue": "1",
                        "maxValue": "3",
                        "unitCode": "DAY"
                    }
                }
            }
        },
        // Repeat for each product, incrementing the position value
    ]
}
</script>
```

---

## 5. OpenStreetMap Integration

Implement OpenStreetMap using Leaflet.js to display the seller's location:

### Map Initialization JavaScript

```javascript
// Initialize OpenStreetMap with Leaflet
document.addEventListener('DOMContentLoaded', function() {
    // Define city coordinates
    const sellerCoords = [[Latitude], [Longitude]]; // e.g. [48.2000, 15.6167] for St. Pölten
    
    // Define coordinates for major nearby cities
    const majorCities = [
        {name: "Wien", coords: [48.2082, 16.3719]},
        {name: "Linz", coords: [48.3064, 14.2858]}
        // Add more cities as needed for context
    ];
    
    // Create bounds to show all locations
    const locations = [sellerCoords, ...majorCities.map(city => city.coords)];
    const bounds = L.latLngBounds(locations);
    
    // Initialize map with better zoom for context
    const map = L.map('osm-map', {
        zoomControl: true,
        scrollWheelZoom: false, // Disable scroll wheel zoom for better page scrolling
        keyboard: true,         // Enable keyboard navigation
        tap: true              // Enable tap for touch devices
    });
    
    // Fit map to show all locations
    map.fitBounds(bounds, { padding: [30, 30] });

    // Add OpenStreetMap tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> Mitwirkende',
        maxZoom: 19,
        minZoom: 7,
        tileSize: 512,
        zoomOffset: -1
    }).addTo(map);

    // Add marker for seller location with special styling
    const sellerIcon = L.divIcon({
        className: 'main-location-marker',
        html: '<div style="background-color:#F44336;width:14px;height:14px;border-radius:50%;border:2px solid white;"></div>',
        iconSize: [18, 18],
        iconAnchor: [9, 9]
    });
    
    // Add seller marker
    const marker = L.marker(sellerCoords, {icon: sellerIcon, alt: "[Location]"}).addTo(map);
    marker.bindPopup("<b>[Location]</b><br>Standort").openPopup();

    // Add markers for major cities
    majorCities.forEach(city => {
        const cityMarker = L.marker(city.coords).addTo(map);
        cityMarker.bindPopup(`<b>${city.name}</b>`);
    });

    // Update map label based on zoom level
    map.on('zoomend moveend', function() {
        const currentZoom = map.getZoom();
        const mapLabel = document.getElementById('map-label');
        
        if (currentZoom >= 12) {
            mapLabel.textContent = "[Location], [Region]";
        } else if (currentZoom >= 9) {
            mapLabel.textContent = "[Location] und Umgebung";
        } else {
            mapLabel.textContent = "[Region], [Country]";
        }
    });

    // Add keyboard accessibility
    const mapElement = document.getElementById('osm-map');
    mapElement.addEventListener('keydown', function(e) {
        // Pan with arrow keys
        if (e.key === 'ArrowUp') {
            e.preventDefault();
            map.panBy([0, -50]);
        } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            map.panBy([0, 50]);
        } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            map.panBy([-50, 0]);
        } else if (e.key === 'ArrowRight') {
            e.preventDefault();
            map.panBy([50, 0]);
        } else if (e.key === '+' || e.key === '=') {
            e.preventDefault();
            map.zoomIn();
        } else if (e.key === '-' || e.key === '_') {
            e.preventDefault();
            map.zoomOut();
        } else if (e.key === 'Home') {
            e.preventDefault();
            map.fitBounds(bounds, { padding: [30, 30] });
        }
    });
});
```

### Map Container Styling

```css
/* Map Container Styles */
.map-container {
    width: 100%;
    height: 400px; /* Fixed height */
    position: relative;
    margin: 2rem 0;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    transition: all 0.3s ease;
    z-index: 1; /* Ensure map is above other elements */
}

.map-container:hover {
    box-shadow: 0 6px 16px rgba(0, 0, 0, 0.2);
}

.map-container:focus-within {
    box-shadow: 0 0 0 3px rgba(33, 150, 243, 0.5), 0 6px 16px rgba(0, 0, 0, 0.2);
    outline: none;
}

.osm-map {
    width: 100%;
    height: 100%;
    border-radius: 8px;
}

.map-label {
    position: absolute;
    bottom: 40px;
    left: 20px;
    padding: 8px 16px;
    background-color: rgba(255, 255, 255, 0.9);
    color: #333;
    border-radius: 4px;
    font-size: 1rem;
    font-weight: bold;
    z-index: 1000; /* Above Leaflet controls */
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
    pointer-events: none; /* Allow clicks to pass through to map */
}

/* Custom marker styling */
.main-location-marker div {
    box-shadow: 0 0 0 4px rgba(244, 67, 54, 0.4);
    animation: pulse 2s infinite;
}

@keyframes pulse {
    0% {
        box-shadow: 0 0 0 0 rgba(244, 67, 54, 0.7);
    }
    70% {
        box-shadow: 0 0 0 10px rgba(244, 67, 54, 0);
    }
    100% {
        box-shadow: 0 0 0 0 rgba(244, 67, 54, 0);
    }
}

/* Enhanced popup styling */
.leaflet-popup-content-wrapper {
    border-radius: 4px;
    padding: 0;
    overflow: hidden;
}

.leaflet-popup-content {
    margin: 12px;
    line-height: 1.5;
}
```

### Responsive Map Adjustments

```css
@media (max-width: 600px) {
    .map-container {
        height: 300px; /* Smaller height on mobile */
    }
    .map-label {
        bottom: 40px;
        left: 10px;
        font-size: 0.9rem;
        padding: 6px 12px;
    }
}
```

---

## 6. Product Listing Generation

Generate product listing cards with the following template:

### Product Item Template

```html
<div class="product-item" tabindex="0">
    <div class="product-image-container">
        <img src="[Product Image URL]" 
             alt="[Product Title]" 
             class="product-image" 
             loading="lazy"
             onerror="this.onerror=null; this.parentElement.innerHTML='<div class=\'image-placeholder\'>Bild nicht verfügbar</div>'"
        >
    </div>
    <div class="product-content">
        <h3>
            <a href="[Product URL]">
                [Product Title]
            </a>
        </h3>
        <p class="product-details">[Product Description]</p>
        <p class="price">[Price] €</p>
        <p class="meta-info">ID: [Product ID]</p>
        <p class="shipping-info">[Shipping Information]</p>
        <div class="product-footer">
            <a href="[Product URL]" 
               class="btn btn-primary" 
               aria-label="Zum Angebot: [Product Title]">
                Zum Angebot
            </a>
        </div>
    </div>
</div>
```

### Product Styling

```css
.product-list {
    margin-top: 1rem;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
    gap: 1.5rem;
}

.product-item {
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    height: 100%;
    outline: none;
}

.product-item:hover, .product-item:focus {
    transform: translateY(-5px);
    box-shadow: 0 5px 15px rgba(0,0,0,0.1);
}

.product-item h3 {
    margin: 0 0 0.5rem 0;
    color: #333;
    font-size: 1rem;
    min-height: 2.4em;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
}

.product-image-container {
    position: relative;
    width: 100%;
    height: 150px;
    margin-bottom: 1rem;
    border-radius: 4px;
    overflow: hidden;
    background-color: #f5f5f5;
    display: flex;
    align-items: center;
    justify-content: center;
}

.product-image {
    width: 100%;
    height: 100%;
    object-fit: contain;
    transition: transform 0.3s ease;
}

.product-item:hover .product-image {
    transform: scale(1.05);
}

.image-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    width: 100%;
    background-color: #f5f5f5;
    color: #666;
    font-size: 0.9rem;
    text-align: center;
}

.price {
    font-weight: bold;
    color: #2196F3;
    font-size: 1.2rem;
    margin: 0.5rem 0;
}

.product-details {
    color: #666;
    font-size: 0.9rem;
    margin: 0.5rem 0;
}

.shipping-info {
    color: #2196F3;
    font-size: 0.8rem;
    margin-top: 0.5rem;
}

.availability {
    color: #4CAF50;
    font-size: 0.8rem;
    font-weight: bold;
}

.meta-info {
    font-size: 0.8rem;
    color: #999;
    margin: 0.25rem 0;
}

.product-content {
    flex-grow: 1;
    display: flex;
    flex-direction: column;
}

.product-footer {
    margin-top: auto;
    padding-top: 0.5rem;
    text-align: center;
}
```

### Responsive Product Design

```css
@media (max-width: 768px) {
    .product-list {
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 1rem;
    }
    
    .product-item {
        padding: 0.75rem;
    }
    
    .product-image-container {
        height: 120px;
    }
    
    .product-item h3 {
        font-size: 0.9rem;
    }
    
    .price {
        font-size: 1rem;
    }
}

@media (max-width: 480px) {
    .product-list {
        grid-template-columns: 1fr;
    }
    
    .product-image-container {
        height: 180px;
    }
}
```

---

## 7. Styling and Responsive Design

Implement these core styles for the overall page structure:

### Core Styles

```css
body {
    font-family: Arial, sans-serif;
    max-width: 800px;
    margin: 2rem auto;
    padding: 0 1rem;
    line-height: 1.6;
    color: #333;
}

.profile-section {
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 2rem;
    margin: 1rem 0;
    background-color: #fff;
}

h1 {
    color: #333;
    margin-top: 0;
}

h2 {
    color: #333;
    margin: 1.5rem 0 1rem;
}

a {
    color: #2196F3;
    text-decoration: none;
}

a:hover {
    text-decoration: underline;
}

.rating {
    color: #ff9800;
    font-weight: bold;
}

.countdown {
    text-align: center;
    margin-top: 2rem;
    padding: 1.5rem;
    color: #666;
    background-color: #f5f5f5;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.05);
}
```

### Button Styles

```css
.btn {
    display: inline-block;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    text-align: center;
    font-weight: bold;
    cursor: pointer;
    transition: all 0.3s ease;
    text-decoration: none;
    border: none;
    font-size: 0.9rem;
    min-width: 120px;
}

.btn-primary {
    background-color: #2196F3;
    color: white;
    box-shadow: 0 2px 4px rgba(33, 150, 243, 0.3);
}

.btn-primary:hover {
    background-color: #1976D2;
    box-shadow: 0 4px 8px rgba(33, 150, 243, 0.4);
    transform: translateY(-2px);
}

.direct-link-btn {
    margin-top: 1rem;
    text-align: center;
}
```

### Footer Styling

```css
footer {
    margin-top: 2rem;
    color: #555;
}

footer a {
    color: #2196F3;
    text-decoration: none;
}

footer a:hover {
    text-decoration: underline;
}

footer h3 {
    font-size: 1.1rem;
    margin-bottom: 0.5rem;
    color: #333;
}
```

### Responsive Layout

```css
@media (max-width: 768px) {
    body {
        margin: 1rem auto;
    }
    
    .profile-section {
        padding: 1.5rem;
    }
    
    h1 {
        font-size: 1.5rem;
    }
    
    h2 {
        font-size: 1.2rem;
    }
}

@media (max-width: 480px) {
    body {
        margin: 0.5rem auto;
    }
    
    .profile-section {
        padding: 1rem;
        border-radius: 0;
    }
    
    .countdown {
        padding: 1rem;
    }
    
    .btn {
        width: 100%;
        margin-bottom: 0.5rem;
    }
}
```

---

## 8. Accessibility Implementation

Ensure your profile page is accessible with these implementations:

### Visually Hidden Elements

```css
.visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    padding: 0;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    border: 0;
}
```

### ARIA Roles and Attributes

- Add proper ARIA roles to main content sections
- Include `aria-labelledby` where appropriate to associate headings with content
- Use `aria-live` regions for dynamic content like the countdown timer
- Ensure all interactive elements have appropriate states and labels

### Focus Management

```css
/* Add focus styles for interactive elements */
a:focus,
button:focus,
.product-item:focus,
.osm-map:focus {
    outline: 2px solid #2196F3;
    outline-offset: 2px;
}

/* Remove default focus outline when custom styles are applied */
a:focus-visible,
button:focus-visible,
.product-item:focus-visible,
.osm-map:focus-visible {
    outline: 2px solid #2196F3;
    outline-offset: 2px;
}
```

### Keyboard Navigation

Add keyboard navigation for all interactive elements:

```javascript
// Make product items keyboard navigable
document.querySelectorAll('.product-item').forEach(item => {
    item.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
            const link = this.querySelector('a');
            if (link) link.click();
        }
    });
});
```

### Contrast and Typography

- Ensure sufficient color contrast (minimum 4.5:1 for normal text, 3:1 for large text)
- Use relative font sizes (rem/em) for better scalability
- Avoid using color alone to convey information

---

## 9. Redirect Functionality

Implement a countdown timer and redirection to the original willhaben.at profile:

```javascript
// Countdown timer
let seconds = 60;
const countdownElement = document.getElementById('countdown');
const profileUrl = 'https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]';

const countdownTimer = setInterval(function() {
    seconds--;
    if (countdownElement) {
        countdownElement.textContent = seconds;
    }
    if (seconds <= 0) {
        clearInterval(countdownTimer);
        window.location.href = profileUrl;
    }
}, 1000);

// Fallback redirect
setTimeout(function() {
    window.location.href = profileUrl;
}, 60000);

// Event tracking for direct link
document.querySelectorAll('.direct-link-btn a').forEach(function(link) {
    link.addEventListener('click', function(e) {
        // Stop the automatic redirect if user clicks the button
        clearInterval(countdownTimer);
        // Could add analytics tracking here if needed
        console.log('Direct link clicked');
    });
});
```

---

## 10. Error Handling

Include error handling for common issues:

### Image Loading Errors

Handle image loading failures with fallback content:

```html
<img src="[Product Image URL]" 
     alt="[Product Title]" 
     class="product-image" 
     loading="lazy"
     onerror="this.onerror=null; this.parentElement.innerHTML='<div class=\'image-placeholder\'>Bild nicht verfügbar</div>'"
>
```

### API Data Loading Errors

When loading data from external sources, include error handling:

```javascript
// Example error handling when fetching product data
function loadProducts() {
    fetch('https://example.com/api/products/[SELLER_ID]')
        .then(response => {
            if (!response.ok) {
                throw new Error('Network response was not ok');
            }
            return response.json();
        })
        .then(data => {
            // Process and display product data
            displayProducts(data);
        })
        .catch(error => {
            console.error('Error fetching products:', error);
            // Display fallback content
            document.getElementById('latest-products').innerHTML = `
                <div class="error-message">
                    <p>Produkte konnten nicht geladen werden. Bitte besuchen Sie das <a href="https://www.willhaben.at/iad/kaufen-und-verkaufen/verkaeuferprofil/[SELLER_ID]">Original-Profil</a>.</p>
                </div>
            `;
        });
}
```

### Map Loading Errors

Handle errors with OpenStreetMap:

```javascript
// Error handling for map initialization
try {
    // Initialize map
    const map = L.map('osm-map', {
        zoomControl: true,
        scrollWheelZoom: false,
        keyboard: true,
        tap: true
    });
    
    // Fit map and add tile layer
    // ...
} catch (error) {
    console.error('Error initializing map:', error);
    // Display a fallback message
    document.getElementById('location-map').innerHTML = `
        <div class="error-message">
            <p>Karte konnte nicht geladen werden. Standort: [Location], [Region].</p>
        </div>
    `;
}
```

### Error Styling

Add styling for error messages:

```css
.error-message {
    background-color: #f8f8f8;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    padding: 1rem;
    text-align: center;
    color: #666;
    margin: 1rem 0;
}

.error-message p {
    margin: 0;
}

.error-message a {
    color: #2196F3;
    text-decoration: none;
    font-weight: bold;
}

.error-message a:hover {
    text-decoration: underline;
}
```

---

## 11. Validation and Testing

Implement thorough validation and testing procedures to ensure a high-quality profile page:

### HTML Validation

Validate your HTML code using the W3C Markup Validation Service:

1. Use the [W3C Markup Validation Service](https://validator.w3.org/)
2. Fix any validation errors and warnings
3. Verify that all HTML tags are properly closed
4. Ensure all required attributes are present

### Schema.org Validation

Validate your structured data using the Schema.org Validator:

1. Use the [Schema.org Validator](https://validator.schema.org/) or [Google's Structured Data Testing Tool](https://search.google.com/structured-data/testing-tool)
2. Ensure all required properties for each schema type are present
3. Check for syntax errors in your JSON-LD
4. Verify that all URLs, dates, and numbers are properly formatted

### Cross-Browser Testing

Test your profile page in different browsers:

1. Chrome
2. Firefox
3. Safari
4. Edge
5. Mobile browsers (Chrome for Android, Safari for iOS)

### Responsive Design Testing

Verify that your profile page looks and functions correctly at different screen sizes:

1. Desktop (1920×1080, 1366×768)
2. Tablet (768×1024, 1024×768)
3. Mobile (375×667, 414×896)

### Accessibility Testing

Verify accessibility compliance:

1. Use [WAVE Web Accessibility Evaluation Tool](https://wave.webaim.org/)
2. Test keyboard navigation through all interactive elements
3. Verify proper focus management
4. Check color contrast ratios (minimum 4.5:1 for normal text)
5. Ensure all images have appropriate alt text
6. Test with a screen reader (e.g., VoiceOver, NVDA, or JAWS)

### Performance Testing

Check performance metrics:

1. Use Lighthouse in Chrome DevTools
2. Aim for scores above 90 in Performance, Accessibility, Best Practices, and SEO
3. Verify that total page size is under 500KB (excluding product images)
4. Ensure loading time is less than 2 seconds on a standard connection

### Functional Testing

Verify all functionality works correctly:

1. Test the redirect countdown timer
2. Verify all product links open correctly
3. Test the map zooming and panning
4. Ensure images load properly and fallbacks work
5. Test interactive elements with both mouse and keyboard

---

## 12. Deployment

Follow these steps to deploy your profile page:

### Deployment Checklist

1. **Final File Review**:
   - Verify all placeholders have been replaced with actual data
   - Check for any remaining TODO comments
   - Ensure all debugging code is removed (console.log statements, etc.)

2. **Minification** (Optional):
   - Minify CSS and JavaScript to reduce file size
   - Consider using tools like [HTML Minifier](https://www.willpeavy.com/tools/minifier/)

3. **Image Optimization**:
   - Ensure all images are properly compressed
   - Verify that WebP or AVIF formats are used when possible

4. **Server Configuration**:
   - Set up proper HTTP response headers for security:
     ```
     Content-Security-Policy: [Your CSP Policy]
     Strict-Transport-Security: max-age=31536000; includeSubDomains
     X-Content-Type-Options: nosniff
     X-Frame-Options: SAMEORIGIN
     Permissions-Policy: ch-ua-model=*, ch-ua-platform-version=*, interest-cohort=()
     ```
   - Enable GZIP or Brotli compression
   - Configure cache headers for static assets

5. **SSL Certificate**:
   - Ensure HTTPS is properly configured
   - Verify SSL certificate is valid and not expired

6. **Backup**:
   - Create a backup of the profile page files

### Upload Procedure

1. Upload all files to the server using SFTP or Git
2. Verify all files were uploaded correctly
3. Check file permissions (typically 644 for files and 755 for directories)

### Post-Deployment Verification

After deployment, perform these final checks:

1. Visit the profile page URL
2. Verify all content loads correctly
3. Check that redirect functionality works
4. Confirm the map loads properly
5. Test all product links
6. Verify that all images load
7. Check page load time in a real environment

### DNS and Redirect Configuration

If using a custom domain:

1. Ensure DNS records are properly configured
2. Set up 301 redirects for any old URLs

### Monitoring

Set up monitoring for the profile page:

1. Implement basic analytics tracking
2. Consider setting up uptime monitoring
3. Check for 404 errors and broken links

---

## Quality Assurance Steps

Implement these quality assurance steps to ensure consistent high-quality profile pages:

### Content Quality Checks

1. **Text Quality**:
   - Check for grammar and spelling errors
   - Ensure all text is properly translated to German
   - Verify that product descriptions are informative and accurate

2. **Image Quality**:
   - Verify that product images are clear and properly cropped
   - Ensure all images have appropriate alt text
   - Check for broken or missing images

3. **Data Consistency**:
   - Verify consistency in price formatting (e.g., "9,00 €")
   - Ensure consistent date formatting
   - Check that seller information is consistently formatted

### SEO Optimization Checks

1. **Meta Tags**:
   - Verify title and description meta tags are appropriate lengths
   - Ensure OpenGraph and Twitter Card meta tags are present
   - Check that canonical URLs are properly set

2. **Schema.org Implementation**:
   - Verify all required schema types are implemented
   - Ensure all schema properties are properly filled
   - Check for any missing or invalid values

3. **URL Structure**:
   - Ensure URLs are properly formatted
   - Verify that all URLs use HTTPS
   - Check for any 404 errors or redirects

### Performance Optimization Checks

1. **Resource Loading**:
   - Verify that resources load in the proper order
   - Ensure critical CSS is inlined
   - Check that JavaScript doesn't block rendering

2. **Image Optimization**:
   - Verify images are properly sized for their containers
   - Ensure images use lazy loading where appropriate
   - Check that responsive images are properly implemented

3. **Code Efficiency**:
   - Check for redundant or unused CSS
   - Verify that JavaScript is optimized
   - Ensure no unnecessary libraries or dependencies are included

---

## Final Review Process

Before declaring the profile page complete, follow this final review process:

### Comprehensive Validation

1. Run the page through HTML validators
2. Validate all structured data
3. Check accessibility compliance
4. Verify responsive design across multiple devices
5. Test all interactive elements

### Brand Compliance

1. Ensure all branding elements are correctly implemented
2. Verify that colors and fonts match brand guidelines
3. Check that logos and icons are properly displayed

### Security Audit

1. Verify that Content Security Policy is properly configured
2. Check for any potential XSS vulnerabilities
3. Ensure all external resources are loaded securely

### Final Checklist

Complete this final checklist before submitting:

- [ ] All placeholder text has been replaced with actual data
- [ ] All images load correctly and have appropriate alt text
- [ ] Map displays correctly and shows the right location
- [ ] Schema.org structured data is complete and valid
- [ ] All meta tags are correctly implemented
- [ ] Responsive design works across all device sizes
- [ ] All interactive elements are accessible via keyboard
- [ ] Redirect functionality works correctly
- [ ] All product links point to the correct URLs
- [ ] Page loads quickly and efficiently
- [ ] Security headers are properly configured
- [ ] Content is properly formatted and translated to German

---

By following these instructions, you can create a high-quality willhaben.vip member profile page that accurately represents the seller and their products, functions correctly across all devices, and adheres to web standards and best practices.
