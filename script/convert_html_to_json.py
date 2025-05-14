#!/usr/bin/env python3
"""
Script to convert HTML files to JSON format for processing by update_product_images.py.

This script:
1. Reads HTML files
2. Extracts structured data using extruct
3. Saves the data in a format compatible with update_product_images.py
"""

import os
import sys
import json
import time
import argparse
import logging
import hashlib
from typing import Dict, List, Any, Optional, Tuple

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

def extract_json_ld(html: str, url: str) -> List[Dict]:
    """
    Extract JSON-LD data from HTML, with enhanced support for script tags.
    
    This function first uses extruct library, then falls back to direct script tag
    parsing if no ItemList is found in the extruct results.
    """
    import re
    import json
    
    # First try using extruct
    base_url = get_base_url(html, url)
    data = extruct.extract(html, base_url=base_url, syntaxes=['json-ld'])
    json_ld_data = data.get('json-ld', [])
    
    # Check if we already found an ItemList
    for item in json_ld_data:
        if isinstance(item, dict) and item.get('@type') == 'ItemList':
            logger.debug("Found ItemList using extruct")
            return json_ld_data
            
    # If we didn't find an ItemList, manually parse script tags
    logger.debug("No ItemList found with extruct, attempting manual script tag parsing")
    script_pattern = re.compile(r'<script\s+type="application/ld\+json">(.*?)</script>', re.DOTALL)
    matches = script_pattern.findall(html)
    
    manual_json_ld = []
    for match in matches:
        try:
            # Parse the JSON content
            json_content = json.loads(match.strip())
            
            # Check if this is the ItemList we're looking for
            if isinstance(json_content, dict) and json_content.get('@type') == 'ItemList':
                logger.info("Found ItemList in script tag")
                manual_json_ld.append(json_content)
                # We can return immediately since we found what we need
                return manual_json_ld
            else:
                manual_json_ld.append(json_content)
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse JSON-LD from script tag: {e}")
    
    # If we found any JSON-LD data manually, return it
    if manual_json_ld:
        logger.info(f"Found {len(manual_json_ld)} JSON-LD blocks in script tags")
        return manual_json_ld
        
    # Otherwise, return whatever extruct found (which might be empty)
    return json_ld_data

def extract_microdata(html: str, url: str) -> List[Dict]:
    """Extract microdata from HTML."""
    base_url = get_base_url(html, url)
    data = extruct.extract(html, base_url=base_url, syntaxes=['microdata'])
    return data.get('microdata', [])

def convert_to_compatible_format(data: List[Dict], source_file: str) -> List[Dict]:
    """
    Convert extracted data to a format compatible with update_product_images.py.
    Preserves existing ItemList structures if found.
    """
    # First, check if we already have an ItemList with product data
    for item in data:
        if isinstance(item, dict) and item.get('@type') == 'ItemList':
            # Check if this ItemList has valid products
            item_list_elements = item.get('itemListElement', [])
            if item_list_elements and isinstance(item_list_elements, list):
                # Check if elements have product data
                has_valid_products = False
                for element in item_list_elements:
                    if (isinstance(element, dict) and 
                        element.get('@type') == 'ListItem' and
                        isinstance(element.get('item'), dict) and
                        element.get('item', {}).get('@type') == 'Product'):
                        # Found at least one valid product
                        has_valid_products = True
                        break
                
                if has_valid_products:
                    logger.info(f"Found existing ItemList with {len(item_list_elements)} products")
                    # Return the ItemList as-is
                    return [item]
    
    # If we get here, we need to construct a product list
    product_list = []
    
    # Look for individual products
    for item in data:
        # Check for direct products
        if isinstance(item, dict) and item.get('@type') == 'Product':
            logger.debug(f"Found standalone Product: {item.get('name', 'unknown')}")
            product_list.append({
                'item': item,
                '@type': 'ListItem'
            })
        # Check for other structures that might contain product data
        elif isinstance(item, dict):
            # Handle Person objects with products
            if item.get('@type') == 'Person' and 'offers' in item:
                logger.debug(f"Found Person with offers: {item.get('name', 'unknown')}")
                offers = item.get('offers', [])
                if isinstance(offers, list):
                    for offer in offers:
                        if isinstance(offer, dict) and offer.get('@type') == 'Offer':
                            # Create a product from offer
                            product = {
                                '@type': 'Product',
                                'name': offer.get('name', f'Offer from {item.get("name", "unknown")}'),
                                'description': offer.get('description', ''),
                                'offers': offer
                            }
                            if 'image' in offer:
                                product['image'] = offer['image']
                            product_list.append({
                                'item': product,
                                '@type': 'ListItem'
                            })
            
            # Handle direct offer objects
            elif item.get('@type') == 'Offer':
                logger.debug(f"Found standalone Offer")
                # Create a product from the offer
                product = {
                    '@type': 'Product',
                    'name': item.get('name', f'Offer from {source_file}'),
                    'description': item.get('description', ''),
                    'offers': item
                }
                if 'image' in item:
                    product['image'] = item['image']
                product_list.append({
                    'item': product,
                    '@type': 'ListItem'
                })
            
            # Try to find products in any other object types
            elif any(key in item for key in ['product', 'item', 'offers']):
                for key in ['product', 'item', 'offers']:
                    if key in item and isinstance(item[key], dict) and item[key].get('@type') == 'Product':
                        logger.debug(f"Found Product in {key} property")
                        product_list.append({
                            'item': item[key],
                            '@type': 'ListItem'
                        })

    # If no products found, create placeholder
    if not product_list:
        logger.warning(f"No product data found in {source_file}, creating placeholder")
        product = {
            '@type': 'Product',
            'name': f'Product from {source_file}',
            'description': 'Placeholder product',
            'url': f'https://example.com/placeholder-{int(time.time())}'
        }
        product_list.append({
            'item': product,
            '@type': 'ListItem'
        })

    # Wrap in ItemList
    return [{
        '@type': 'ItemList',
        'itemListElement': product_list
    }]

def process_html_file(html_file: str, output_file: Optional[str] = None) -> str:
    """
    Process an HTML file and convert it to JSON.
    
    Args:
        html_file: Path to the HTML file
        output_file: Optional path for the output file
        
    Returns:
        Path to the generated JSON file
    """
    try:
        # Read the HTML file
        logger.info(f"Reading HTML file: {html_file}")
        with open(html_file, 'r', encoding='utf-8') as f:
            html_content = f.read()
            
        # Extract structured data
        logger.info("Extracting structured data")
        json_ld_data = extract_json_ld(html_content, "file://" + os.path.abspath(html_file))
        microdata = extract_microdata(html_content, "file://" + os.path.abspath(html_file))
        
        # Combine data
        all_data = json_ld_data + microdata
        
        if not all_data:
            logger.warning(f"No structured data found in {html_file}")
            # Create minimal data
            all_data = [{
                '@type': 'Product',
                'name': f'Product from {html_file}',
                'description': 'Auto-generated product',
                'url': f'https://example.com/product-{int(time.time())}'
            }]
        
        # Convert to compatible format
        compatible_data = convert_to_compatible_format(all_data, html_file)
        
        # Generate output filename if not provided
        if not output_file:
            # Create a hash of the input filename
            file_hash = hashlib.md5(html_file.encode()).hexdigest()
            # Use the first 8 characters of the hash
            file_prefix = file_hash[:8]
            output_file = f"{file_prefix}.json"
        
        # Save to JSON file
        logger.info(f"Saving to {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(compatible_data, f, indent=2)
            
        return output_file
        
    except Exception as e:
        logger.error(f"Error processing {html_file}: {e}")
        return None

def main():
    """Main function to process HTML files."""
    parser = argparse.ArgumentParser(description='Convert HTML files to JSON format')
    
    parser.add_argument('html_files', nargs='+', help='HTML files to process')
    parser.add_argument('--output', '-o', help='Output file (default: auto-generated)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    if len(args.html_files) > 1 and args.output:
        logger.warning("Output file specified with multiple input files - will be ignored")
        args.output = None
    
    processed_files = []
    for html_file in args.html_files:
        if os.path.exists(html_file):
            output = process_html_file(html_file, args.output if len(args.html_files) == 1 else None)
            if output:
                processed_files.append(output)
        else:
            logger.error(f"File not found: {html_file}")
    
    if processed_files:
        logger.info(f"Successfully processed {len(processed_files)} files:")
        for file in processed_files:
            logger.info(f"  - {file}")
        logger.info("You can now run update_product_images.py to process these files")
    else:
        logger.error("No files were successfully processed")

if __name__ == "__main__":
    main()

