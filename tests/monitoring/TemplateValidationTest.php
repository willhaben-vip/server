<?php

namespace Tests\Monitoring;

use PHPUnit\Framework\TestCase;

/**
 * Test case for validating Alertmanager templates
 */
class TemplateValidationTest extends TestCase
{
    // Path to templates directory
    private const TEMPLATES_DIR = __DIR__ . '/../../docker/alertmanager/templates';

    // Required template files
    private const REQUIRED_TEMPLATES = [
        'email.tmpl',
        'slack.tmpl',
        'pagerduty.tmpl',
    ];

    // Sample alert data for testing
    private array $sampleAlerts = [];

    protected function setUp(): void
    {
        // Create sample data for different alert scenarios
        $this->sampleAlerts = [
            'firing' => $this->createSampleAlert('firing', 'critical', 'High CPU Usage', 'CPU usage above 90%'),
            'resolved' => $this->createSampleAlert('resolved', 'warning', 'High Memory Usage', 'Memory usage has returned to normal'),
            'info' => $this->createSampleAlert('firing', 'info', 'Backup Completed', 'Daily backup has completed successfully'),
            'warning' => $this->createSampleAlert('firing', 'warning', 'High Disk Usage', 'Disk usage above 80%'),
            'critical' => $this->createSampleAlert('firing', 'critical', 'Service Down', 'The payment service is down'),
            'complex' => $this->createComplexAlert(),
        ];
    }

    /**
     * Test if all required template files exist
     */
    public function testTemplateFilesExist(): void
    {
        foreach (self::REQUIRED_TEMPLATES as $template) {
            $templatePath = self::TEMPLATES_DIR . '/' . $template;
            $this->assertFileExists(
                $templatePath,
                "Required template file $template does not exist"
            );
        }
    }

    /**
     * Test template syntax using basic validation
     */
    public function testTemplateSyntax(): void
    {
        foreach (self::REQUIRED_TEMPLATES as $template) {
            $templatePath = self::TEMPLATES_DIR . '/' . $template;
            
            if (!file_exists($templatePath)) {
                $this->markTestSkipped("Template file $template does not exist");
                continue;
            }
            
            $templateContent = file_get_contents($templatePath);
            $this->assertNotFalse($templateContent, "Failed to read template file: $template");
            
            // Check for basic Go template syntax errors
            $this->assertMatchesRegularExpression(
                '/{{.*?}}/',
                $templateContent,
                "No template variables found in $template"
            );
            
            // Check for balanced opening and closing braces
            $openingBraces = substr_count($templateContent, '{{');
            $closingBraces = substr_count($templateContent, '}}');
            $this->assertEquals(
                $openingBraces,
                $closingBraces,
                "Unbalanced template braces in $template: $openingBraces opening vs $closingBraces closing"
            );
        }
    }

    /**
     * Test required template definitions
     */
    public function testRequiredTemplateDefinitions(): void
    {
        // Check if email template contains required definitions
        $emailPath = self::TEMPLATES_DIR . '/email.tmpl';
        if (file_exists($emailPath)) {
            $emailContent = file_get_contents($emailPath);
            $this->assertNotFalse($emailContent);
            
            $requiredDefinitions = [
                '{{ define "email.subject" }}',
                '{{ define "email.html" }}',
                '{{ define "email.text" }}'
            ];
            
            foreach ($requiredDefinitions as $definition) {
                $this->assertStringContainsString(
                    $definition,
                    $emailContent,
                    "Email template missing required definition: $definition"
                );
            }
        }
        
        // Check if slack template contains required definitions
        $slackPath = self::TEMPLATES_DIR . '/slack.tmpl';
        if (file_exists($slackPath)) {
            $slackContent = file_get_contents($slackPath);
            $this->assertNotFalse($slackContent);
            
            $this->assertStringContainsString(
                '{{ define "slack.default.message" }}',
                $slackContent,
                "Slack template missing required definition: slack.default.message"
            );
        }
        
        // Check if pagerduty template contains required definitions
        $pagerdutyPath = self::TEMPLATES_DIR . '/pagerduty.tmpl';
        if (file_exists($pagerdutyPath)) {
            $pagerdutyContent = file_get_contents($pagerdutyPath);
            $this->assertNotFalse($pagerdutyContent);
            
            $this->assertStringContainsString(
                '{{ define "pagerduty.default.description" }}',
                $pagerdutyContent,
                "PagerDuty template missing required definition: pagerduty.default.description"
            );
        }
    }

    /**
     * Test HTML structure in email template
     */
    public function testHtmlStructure(): void
    {
        $emailPath = self::TEMPLATES_DIR . '/email.tmpl';
        if (!file_exists($emailPath)) {
            $this->markTestSkipped("Email template file does not exist");
            return;
        }
        
        $emailContent = file_get_contents($emailPath);
        $this->assertNotFalse($emailContent);
        
        // Check for required HTML tags
        $requiredHtmlTags = [
            '<!DOCTYPE html>',
            '<html',
            '<head',
            '<body',
            '</html>',
            '</head>',
            '</body>'
        ];
        
        foreach ($requiredHtmlTags as $tag) {
            $this->assertStringContainsString(
                $tag,
                $emailContent,
                "Email HTML template missing required tag: $tag"
            );
        }
        
        // Check for meta tags that improve email client compatibility
        $metaTags = [
            '<meta charset',
            '<meta name="viewport"'
        ];
        
        foreach ($metaTags as $tag) {
            $this->assertStringContainsString(
                $tag,
                $emailContent,
                "Email HTML template missing recommended meta tag: $tag"
            );
        }
    }

    /**
     * Test for proper variable escaping
     */
    public function testVariableEscaping(): void
    {
        foreach (self::REQUIRED_TEMPLATES as $template) {
            $templatePath = self::TEMPLATES_DIR . '/' . $template;
            
            if (!file_exists($templatePath)) {
                $this->markTestSkipped("Template file $template does not exist");
                continue;
            }
            
            $templateContent = file_get_contents($templatePath);
            $this->assertNotFalse($templateContent, "Failed to read template file: $template");
            
            // Variables should be properly escaped in HTML contexts
            if ($template === 'email.tmpl') {
                // Look for HTML escaping in email template
                // Proper usage would be {{ $var | safeHTML }} or {{ $var | html }}
                $this->assertMatchesRegularExpression(
                    '/{{.*?\| *(html|safeHTML).*?}}/',
                    $templateContent,
                    "Email template may not be properly escaping HTML variables"
                );
            }
            
            // Check for URLs being properly handled
            $this->assertMatchesRegularExpression(
                '/{{.*?\| *(urlquery|safeURL).*?}}/',
                $templateContent,
                "Template $template may not be properly escaping URL variables"
            );
        }
    }

    /**
     * Helper function to create a sample alert for testing
     */
    private function createSampleAlert(string $status, string $severity, string $alertName, string $description): array
    {
        return [
            'status' => $status,
            'labels' => [
                'alertname' => $alertName,
                'severity' => $severity,
                'instance' => 'test-instance:9090',
                'job' => 'test-job',
            ],
            'annotations' => [
                'summary' => $alertName,
                'description' => $description,
            ],
            'startsAt' => '2025-05-16T10:00:00Z',
            'endsAt' => $status === 'resolved' ? '2025-05-16T10:30:00Z' : '0001-01-01T00:00:00Z',
            'generatorURL' => 'http://prometheus.example.org/graph?g0.expr=up%3D%3D0',
        ];
    }

    /**
     * Create a more complex alert with additional data
     */
    private function createComplexAlert(): array
    {
        return [
            'status' => 'firing',
            'labels' => [
                'alertname' => 'APIHighResponseTime',
                'severity' => 'critical',
                'instance' => 'api-server:8080',
                'job' => 'api-monitoring',
                'endpoint' => '/api/payments',
                'method' => 'POST',
                'team' => 'payments',
            ],
            'annotations' => [
                'summary' => 'API endpoint response time is too high',
                'description' => 'The /api/payments endpoint is responding in >500ms for over 5 minutes',
                'dashboard' => 'https://grafana.example.org/d/api-performance',
                'runbook' => 'https://wiki.example.org/runbooks/high-api-latency',
                'impact' => 'Payment processing may be delayed',
                'actions' => 'Check database performance and API server resources',
            ],
            'startsAt' => '2025-05-16T09:15:00Z',
            'endsAt' => '0001-01-01T00:00:00Z',
            'generatorURL' => 'http://prometheus.example.org/graph?g0.expr=api_response_time_seconds%7Bendpoint%3D%22%2Fapi%2Fpayments%22%7D+%3E+0.5',
            'fingerprint' => '1a2b3c4d5e6f7g8h',
        ];
    }
}

