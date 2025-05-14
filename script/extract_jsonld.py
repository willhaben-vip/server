#!/usr/bin/env python3
import json
import re
from pathlib import Path

# Function to extract JSON-LD objects from HTML file
def extract_jsonld(html_file):
    html_content = html_file.read_text(encoding='utf-8')
    
    # Find all JSON-LD script tags using regex
    pattern = r'<script type="application/ld\+json">\s*(.*?)\s*</script>'
    matches = re.findall(pattern, html_content, re.DOTALL)
    
    # Parse each JSON-LD object and add to result array
    result = []
    for json_str in matches:
        try:
            json_obj = json.loads(json_str)
            result.append(json_obj)
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON-LD: {e}")
    
    return result

# Main execution
def main():
    # Define file paths
    input_file = Path('./index.v4.htm')
    output_file = Path('./34434899.json')
    
    # Extract JSON-LD objects
    jsonld_objects = extract_jsonld(input_file)
    
    # Write to output file with pretty formatting
    with output_file.open('w', encoding='utf-8') as f:
        json.dump(jsonld_objects, f, indent=2, ensure_ascii=False)
    
    print(f"Successfully extracted {len(jsonld_objects)} JSON-LD objects to {output_file}")

if __name__ == "__main__":
    main()

