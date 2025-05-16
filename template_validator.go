package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"regexp"
	"strings"
	"text/template"
)

// TemplateValidator checks Alertmanager templates for syntax issues
type TemplateValidator struct {
	FileName    string
	Content     string
	Errors      []string
	Warnings    []string
	Definitions map[string]bool
}

// NewTemplateValidator creates a new template validator for the given file
func NewTemplateValidator(fileName string) (*TemplateValidator, error) {
	content, err := ioutil.ReadFile(fileName)
	if err != nil {
		return nil, fmt.Errorf("error reading file %s: %v", fileName, err)
	}

	return &TemplateValidator{
		FileName:    fileName,
		Content:     string(content),
		Errors:      []string{},
		Warnings:    []string{},
		Definitions: make(map[string]bool),
	}, nil
}

// Validate performs all validation checks
func (v *TemplateValidator) Validate() bool {
	v.validateTemplateDefinitions()
	v.validateTemplateSyntax()
	v.validateCommonIssues()
	
	return len(v.Errors) == 0
}

// validateTemplateDefinitions checks for properly defined and closed templates
func (v *TemplateValidator) validateTemplateDefinitions() {
	// Find all template definitions
	defineRegex := regexp.MustCompile(`{{-?\s*define\s+"([^"]+)"\s*-?}}`)
	endRegex := regexp.MustCompile(`{{-?\s*end\s*-?}}`)
	
	defines := defineRegex.FindAllStringSubmatch(v.Content, -1)
	endCount := len(endRegex.FindAllString(v.Content, -1))
	
	if len(defines) != endCount {
		v.Errors = append(v.Errors, fmt.Sprintf("Mismatch between 'define' (%d) and 'end' (%d) statements", 
			len(defines), endCount))
	}
	
	for _, match := range defines {
		if len(match) > 1 {
			templateName := match[1]
			if _, exists := v.Definitions[templateName]; exists {
				v.Errors = append(v.Errors, fmt.Sprintf("Duplicate template definition: %s", templateName))
			} else {
				v.Definitions[templateName] = true
			}
		}
	}
}

// validateTemplateSyntax checks if the template can be parsed by Go's template engine
func (v *TemplateValidator) validateTemplateSyntax() {
	_, err := template.New(v.FileName).Parse(v.Content)
	if err != nil {
		v.Errors = append(v.Errors, fmt.Sprintf("Template syntax error: %v", err))
	}
}

// validateCommonIssues checks for common mistakes in Alertmanager templates
func (v *TemplateValidator) validateCommonIssues() {
	// Check for missing variable escaping
	if strings.Contains(v.Content, "{{.") && !strings.Contains(v.Content, "{{.}}") {
		// Look for unescaped variables in places where HTML would be expected
		riskContexts := []string{"title", "text", "summary", "description"}
		
		for _, context := range riskContexts {
			regex := regexp.MustCompile(fmt.Sprintf(`%s[^}]*{{\.([^|]*)}}`, context))
			matches := regex.FindAllString(v.Content, -1)
			
			for _, match := range matches {
				if !strings.Contains(match, "|") && !strings.Contains(match, "reReplaceAll") && !strings.Contains(match, "html") {
					v.Warnings = append(v.Warnings, fmt.Sprintf("Potential unescaped variable in HTML context: %s", match))
				}
			}
		}
	}
	
	// Check for unclosed action blocks
	openActions := strings.Count(v.Content, "{{")
	closeActions := strings.Count(v.Content, "}}")
	if openActions != closeActions {
		v.Errors = append(v.Errors, fmt.Sprintf("Mismatch between opening '{{' (%d) and closing '}}' (%d) delimiters", 
			openActions, closeActions))
	}
	
	// Check for undefined variables or functions
	commonFunctions := []string{"toUpper", "toLower", "title", "reReplaceAll", "join", "printf", "index", "len"}
	definedFunctions := map[string]bool{}
	
	for _, fn := range commonFunctions {
		definedFunctions[fn] = true
	}
	
	funcRegex := regexp.MustCompile(`{{[^}]*\s+(\w+)\s+[^}]*}}`)
	funcMatches := funcRegex.FindAllStringSubmatch(v.Content, -1)
	
	for _, match := range funcMatches {
		if len(match) > 1 {
			function := match[1]
			if !definedFunctions[function] && !strings.HasPrefix(function, ".") && !strings.HasPrefix(function, "define") && function != "if" && function != "else" && function != "end" && function != "range" && function != "template" && function != "with" {
				v.Warnings = append(v.Warnings, fmt.Sprintf("Potential undefined function call: %s", function))
			}
		}
	}
}

// PrintResults prints validation results
func (v *TemplateValidator) PrintResults() {
	if len(v.Errors) == 0 && len(v.Warnings) == 0 {
		fmt.Printf("✅ File %s is valid and free of common issues.\n", v.FileName)
		return
	}
	
	fmt.Printf("Results for %s:\n", v.FileName)
	
	if len(v.Errors) > 0 {
		fmt.Println("\n❌ ERRORS:")
		for i, err := range v.Errors {
			fmt.Printf("%d. %s\n", i+1, err)
		}
	}
	
	if len(v.Warnings) > 0 {
		fmt.Println("\n⚠️  WARNINGS:")
		for i, warning := range v.Warnings {
			fmt.Printf("%d. %s\n", i+1, warning)
		}
	}
	
	fmt.Println()
	if len(v.Definitions) > 0 {
		fmt.Println("Found template definitions:")
		for name := range v.Definitions {
			fmt.Printf("- %s\n", name)
		}
	}
}

func main() {
	// Parse command line arguments
	fileName := flag.String("file", "slack.tmpl", "Template file to validate")
	flag.Parse()
	
	validator, err := NewTemplateValidator(*fileName)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	
	isValid := validator.Validate()
	validator.PrintResults()
	
	if !isValid {
		os.Exit(1)
	}
}

