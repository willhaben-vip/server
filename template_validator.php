#!/usr/bin/env php
<?php
/**
 * Alertmanager Template Validator
 * 
 * This script validates Alertmanager template files for common syntax issues:
 * - Balanced template delimiters {{ and }}
 * - Balanced define/end blocks
 * - Common syntax patterns
 * - Potential HTML escaping issues
 * 
 * Usage: php template_validator.php <template_filename>
 */

if ($argc < 2) {
    echo "Error: Missing template filename.\n";
    echo "Usage: php template_validator.php <template_filename>\n";
    exit(1);
}

$filename = $argv[1];

if (!file_exists($filename)) {
    echo "Error: File '$filename' not found.\n";
    exit(1);
}

echo "Validating template file: $filename\n";
echo "--------------------------------\n";

// Read the template file
$content = file_get_contents($filename);
if ($content === false) {
    echo "Error: Failed to read template file.\n";
    exit(1);
}

$issues = [];
$warnings = [];
$successMessages = [];

// Check for balanced delimiters
$openingDelimiters = substr_count($content, '{{');
$closingDelimiters = substr_count($content, '}}');

if ($openingDelimiters === $closingDelimiters) {
    $successMessages[] = "✓ Template delimiters '{{' and '}}' are balanced ($openingDelimiters pairs)";
} else {
    $issues[] = "✗ Unbalanced template delimiters: {{: $openingDelimiters, }}: $closingDelimiters";
}

// Check for balanced define and end blocks
preg_match_all('/\{\{\s*define\s+["\']([^"\']+)["\']\s*\}\}/', $content, $defineMatches);
$defineCount = count($defineMatches[0]);
$endCount = preg_match_all('/\{\{\s*end\s*\}\}/', $content);

if ($defineCount === $endCount) {
    $successMessages[] = "✓ Define/end blocks are balanced ($defineCount blocks)";
} else {
    $issues[] = "✗ Unbalanced define/end blocks: define: $defineCount, end: $endCount";
    
    // List all defined templates
    echo "\nDefined templates:\n";
    foreach ($defineMatches[1] as $templateName) {
        echo "  - $templateName\n";
    }
}

// Check for potentially missing HTML escaping in variables
preg_match_all('/\{\{\s*\.([a-zA-Z0-9_\.]+)\s*\}\}/', $content, $varMatches);
preg_match_all('/\{\{\s*html\s+\.([a-zA-Z0-9_\.]+)\s*\}\}/', $content, $htmlEscapedMatches);

$unescapedVars = array_diff($varMatches[1], $htmlEscapedMatches[1]);
if (!empty($unescapedVars)) {
    $warnings[] = "⚠ Potential HTML escaping issues. The following variables may need 'html' escaping:";
    foreach (array_unique($unescapedVars) as $var) {
        $warnings[] = "  - .$var";
    }
}

// Check for common syntax issues
$syntaxPatterns = [
    'With blocks' => ['/\{\{\s*with\s+/', '/\{\{\s*end\s*\}\}/'],
    'Range blocks' => ['/\{\{\s*range\s+/', '/\{\{\s*end\s*\}\}/'],
    'If blocks' => ['/\{\{\s*if\s+/', '/\{\{\s*end\s*\}\}/'],
    'Template calls' => ['/\{\{\s*template\s+"[^"]+"/', null],
];

foreach ($syntaxPatterns as $patternName => [$openPattern, $closePattern]) {
    $openCount = preg_match_all($openPattern, $content);
    
    if ($openCount > 0) {
        if ($closePattern !== null) {
            $closeCount = preg_match_all($closePattern, $content);
            if ($openCount === $closeCount) {
                $successMessages[] = "✓ $patternName are properly balanced ($openCount)";
            } else {
                $issues[] = "✗ Unbalanced $patternName: open: $openCount, close: $closeCount";
            }
        } else {
            $successMessages[] = "✓ Found $openCount $patternName";
        }
    }
}

// Check for unusual combinations
if (preg_match('/\{\{\{\s*/', $content)) {
    $warnings[] = "⚠ Found '{{{' pattern - this might be a syntax error or a typo";
}

if (preg_match('/\}\}\}/', $content)) {
    $warnings[] = "⚠ Found '}}}' pattern - this might be a syntax error or a typo";
}

// Output results
echo "\nValidation Results:\n";
echo "==================\n";

if (empty($issues) && empty($warnings)) {
    echo "✅ No issues found! The template appears to be valid.\n";
} else {
    if (!empty($issues)) {
        echo "\nErrors:\n";
        foreach ($issues as $issue) {
            echo "$issue\n";
        }
    }
    
    if (!empty($warnings)) {
        echo "\nWarnings:\n";
        foreach ($warnings as $warning) {
            echo "$warning\n";
        }
    }
}

if (!empty($successMessages)) {
    echo "\nSuccess Checks:\n";
    foreach ($successMessages as $message) {
        echo "$message\n";
    }
}

// Quick content overview
$templateLines = explode("\n", $content);
$lineCount = count($templateLines);
echo "\nTemplate Overview:\n";
echo "Total lines: $lineCount\n";

// Output line count and template structure summary
$definedTemplates = [];
foreach ($defineMatches[1] as $index => $templateName) {
    $definedTemplates[] = $templateName;
}

if (!empty($definedTemplates)) {
    echo "Defined templates: " . implode(", ", $definedTemplates) . "\n";
}

// Exit with status code based on validation
exit(empty($issues) ? 0 : 1);

