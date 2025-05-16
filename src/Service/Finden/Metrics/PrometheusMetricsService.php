<?php

declare(strict_types=1);

namespace App\Service\Finden\Metrics;

use App\Service\Finden\Contracts\MetricsInterface;
use Psr\Log\LoggerInterface;

/**
 * Prometheus implementation of the metrics interface.
 * 
 * Collects and formats metrics in the Prometheus exposition format.
 */
class PrometheusMetricsService implements MetricsInterface
{
    /**
     * @var array Collected counters
     */
    private array $counters = [];
    
    /**
     * @var array Collected gauges
     */
    private array $gauges = [];
    
    /**
     * @var array Collected histograms
     */
    private array $histograms = [];
    
    /**
     * @var array Active timers
     */
    private array $timers = [];
    
    /**
     * @var LoggerInterface Logger for metrics operations
     */
    private LoggerInterface $logger;
    
    /**
     * @var string The namespace prefix for all metrics
     */
    private string $namespace;

    /**
     * Constructor.
     *
     * @param LoggerInterface $logger Logger for metrics operations
     * @param string $namespace The namespace prefix for all metrics
     */
    public function __construct(LoggerInterface $logger, string $namespace = 'finden')
    {
        $this->logger = $logger;
        $this->namespace = $namespace;
    }

    /**
     * {@inheritdoc}
     */
    public function incrementCounter(string $name, float $value = 1.0, array $labels = []): void
    {
        $metricName = $this->formatMetricName($name);
        $labelKey = $this->formatLabelsKey($labels);
        
        if (!isset($this->counters[$metricName])) {
            $this->counters[$metricName] = [
                'help' => "Counter for {$name}",
                'type' => 'counter',
                'values' => [],
            ];
        }
        
        if (!isset($this->counters[$metricName]['values'][$labelKey])) {
            $this->counters[$metricName]['values'][$labelKey] = [
                'labels' => $labels,
                'value' => 0,
            ];
        }
        
        $this->counters[$metricName]['values'][$labelKey]['value'] += $value;
    }

    /**
     * {@inheritdoc}
     */
    public function setGauge(string $name, float $value, array $labels = []): void
    {
        $metricName = $this->formatMetricName($name);
        $labelKey = $this->formatLabelsKey($labels);
        
        if (!isset($this->gauges[$metricName])) {
            $this->gauges[$metricName] = [
                'help' => "Gauge for {$name}",
                'type' => 'gauge',
                'values' => [],
            ];
        }
        
        $this->gauges[$metricName]['values'][$labelKey] = [
            'labels' => $labels,
            'value' => $value,
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function recordTiming(string $name, float $durationSeconds, array $labels = []): void
    {
        $metricName = $this->formatMetricName($name);
        $labelKey = $this->formatLabelsKey($labels);
        
        if (!isset($this->histograms[$metricName])) {
            $this->histograms[$metricName] = [
                'help' => "Histogram for {$name} duration in seconds",
                'type' => 'histogram',
                'values' => [],
                'buckets' => [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
            ];
        }
        
        if (!isset($this->histograms[$metricName]['values'][$labelKey])) {
            $this->histograms[$metricName]['values'][$labelKey] = [
                'labels' => $labels,
                'sum' => 0,
                'count' => 0,
                'buckets' => array_fill_keys(
                    $this->histograms[$metricName]['buckets'], 
                    0
                ),
            ];
        }
        
        // Update the histogram
        $histogram = &$this->histograms[$metricName]['values'][$labelKey];
        $histogram['sum'] += $durationSeconds;
        $histogram['count']++;
        
        // Update buckets
        foreach ($this->histograms[$metricName]['buckets'] as $bucket) {
            if ($durationSeconds <= $bucket) {
                $histogram['buckets'][$bucket]++;
            }
        }
    }

    /**
     * {@inheritdoc}
     */
    public function startTimer(string $name, array $labels = []): string
    {
        $timerId = uniqid('timer_', true);
        $this->timers[$timerId] = [
            'name' => $name,
            'labels' => $labels,
            'start' => microtime(true),
        ];
        
        return $timerId;
    }

    /**
     * {@inheritdoc}
     */
    public function stopTimer(string $timerId, array $labels = []): float
    {
        if (!isset($this->timers[$timerId])) {
            $this->logger->warning('Attempted to stop non-existent timer', ['timer_id' => $timerId]);
            return 0.0;
        }
        
        $timer = $this->timers[$timerId];
        $duration = microtime(true) - $timer['start'];
        
        // Merge the original labels with any new ones
        $mergedLabels = array_merge($timer['labels'], $labels);
        
        // Record the timing
        $this->recordTiming($timer['name'], $duration, $mergedLabels);
        
        // Clean up
        unset($this->timers[$timerId]);
        
        return $duration;
    }

    /**
     * {@inheritdoc}
     */
    public function recordMemoryUsage(string $name, int $memoryBytes, array $labels = []): void
    {
        $memoryMB = $memoryBytes / (1024 * 1024); // Convert to MB for readability
        $this->setGauge("{$name}_memory_mb", $memoryMB, $labels);
    }

    /**
     * {@inheritdoc}
     */
    public function recordCacheOperation(string $operation, array $labels = []): void
    {
        $validOperations = ['hit', 'miss', 'set', 'delete'];
        
        if (!in_array($operation, $validOperations)) {
            $this->logger->warning('Invalid cache operation type', [
                'operation' => $operation,
                'valid_operations' => implode(', ', $validOperations),
            ]);
            return;
        }
        
        $this->incrementCounter("cache_{$operation}_total", 1.0, $labels);
    }

    /**
     * {@inheritdoc}
     */
    public function recordError(string $type, array $labels = []): void
    {
        $this->incrementCounter('error_total', 1.0, array_merge(['error_type' => $type], $labels));
    }

    /**
     * {@inheritdoc}
     */
    public function export(): string
    {
        $output = [];
        
        // Export counters
        foreach ($this->counters as $name => $counter) {
            $output[] = "# HELP {$name} {$counter['help']}";
            $output[] = "# TYPE {$name} {$counter['type']}";
            
            foreach ($counter['values'] as $value) {
                $labelString = $this->formatLabelsString($value['labels']);
                $output[] = "{$name}{$labelString} {$value['value']}";
            }
        }
        
        // Export gauges
        foreach ($this->gauges as $name => $gauge) {
            $output[] = "# HELP {$name} {$gauge['help']}";
            $output[] = "# TYPE {$name} {$gauge['type']}";
            
            foreach ($gauge['values'] as $value) {
                $labelString = $this->formatLabelsString($value['labels']);
                $output[] = "{$name}{$labelString} {$value['value']}";
            }
        }
        
        // Export histograms
        foreach ($this->histograms as $name => $histogram) {
            $output[] = "# HELP {$name} {$histogram['help']}";
            $output[] = "# TYPE {$name} {$histogram['type']}";
            
            foreach ($histogram['values'] as $value) {
                $baseLabels = $value['labels'];
                
                // Output bucket counts
                foreach ($histogram['buckets'] as $bucket) {
                    $labels = array_merge($baseLabels, ['le' => (string)$bucket]);
                    $labelString = $this->formatLabelsString($labels);
                    $output[] = "{$name}_bucket{$labelString} {$value['buckets'][$bucket]}";
                }
                
                // Add +Inf bucket
                $labels = array_merge($baseLabels, ['le' => '+Inf']);
                $labelString = $this->formatLabelsString($labels);
                $output[] = "{$name}_bucket{$labelString} {$value['count']}";
                
                // Output sum and count
                $labelString = $this->formatLabelsString($baseLabels);
                $output[] = "{$name}_sum{$labelString} {$value['sum']}";
                $output[] = "{$name}_count{$labelString} {$value['count']}";
            }
        }
        
        return implode("\n", $output) . "\n";
    }
    
    /**
     * Format a metric name with the namespace prefix.
     *
     * @param string $name The metric name
     * @return string The formatted metric name
     */
    private function formatMetricName(string $name): string
    {
        return "{$this->namespace}_{$name}";
    }
    
    /**
     * Format labels into a string key for internal storage.
     *
     * @param array $labels The labels array
     * @return string A string key
     */
    private function formatLabelsKey(array $labels): string
    {
        if (empty($labels)) {
            return '';
        }
        
        ksort($labels);
        $parts = [];
        
        foreach ($labels as $key => $value) {
            $parts[] = "{$key}=\"{$value}\"";
        }
        
        return implode(',', $parts);
    }
    
    /**
     * Format labels into a Prometheus-compatible string.
     *
     * @param array $labels The labels array
     * @return string The formatted labels string
     */
    private function formatLabelsString(array $labels): string
    {
        if (empty($labels)) {
            return '';
        }
        
        ksort($labels);
        $parts = [];
        
        foreach ($labels as $key => $value) {
            // Escape any double quotes in the label value
            $escapedValue = str_replace('"', '\\"', (string)$value);
            // Replace newlines and backslashes
            $escapedValue = str_replace(["\n", "\\"], ["\\n", "\\\\"], $escapedValue);
            $parts[] = "{$key}=\"{$escapedValue}\"";
        }
        
        return '{' . implode(',', $parts) . '}';
    }
    
    /**
     * Reset all metrics.
     * 
     * Useful for testing or when metrics need to be refreshed.
     * 
     * @return void
     */
    public function reset(): void
    {
        $this->counters = [];
        $this->gauges = [];
        $this->histograms = [];
        $this->timers = [];
        
        $this->logger->info('All metrics have been reset');
    }
    
    /**
     * Validate a metric name.
     * 
     * Ensures the metric name complies with Prometheus naming conventions.
     * 
     * @param string $name The metric name to validate
     * @return bool True if the name is valid
     */
    public function validateMetricName(string $name): bool
    {
        // Prometheus metric names must match [a-zA-Z_:][a-zA-Z0-9_:]*
        return (bool) preg_match('/^[a-zA-Z_:][a-zA-Z0-9_:]*$/', $name);
    }
    
    /**
     * Save metrics to persistent storage.
     * 
     * @param string $filePath Path to save metrics to
     * @return bool True if metrics were successfully saved
     */
    public function saveMetrics(string $filePath): bool
    {
        try {
            $data = [
                'counters' => $this->counters,
                'gauges' => $this->gauges,
                'histograms' => $this->histograms,
                'timestamp' => time(),
            ];
            
            $serialized = serialize($data);
            $result = file_put_contents($filePath, $serialized);
            
            if ($result === false) {
                $this->logger->error('Failed to save metrics to file', ['file' => $filePath]);
                return false;
            }
            
            $this->logger->info('Metrics saved to file', [
                'file' => $filePath,
                'size' => strlen($serialized),
                'metrics_count' => count($this->counters) + count($this->gauges) + count($this->histograms),
            ]);
            
            return true;
        } catch (\Throwable $e) {
            $this->logger->error('Exception while saving metrics', [
                'exception' => $e->getMessage(),
                'file' => $filePath,
            ]);
            
            return false;
        }
    }
    
    /**
     * Load metrics from persistent storage.
     * 
     * @param string $filePath Path to load metrics from
     * @param bool $merge Whether to merge with existing metrics or replace them
     * @return bool True if metrics were successfully loaded
     */
    public function loadMetrics(string $filePath, bool $merge = false): bool
    {
        if (!file_exists($filePath)) {
            $this->logger->warning('Metrics file does not exist', ['file' => $filePath]);
            return false;
        }
        
        try {
            $serialized = file_get_contents($filePath);
            
            if ($serialized === false) {
                $this->logger->error('Failed to read metrics file', ['file' => $filePath]);
                return false;
            }
            
            $data = unserialize($serialized);
            
            if (!is_array($data) || 
                !isset($data['counters']) || 
                !isset($data['gauges']) || 
                !isset($data['histograms'])) {
                $this->logger->error('Invalid metrics data format', ['file' => $filePath]);
                return false;
            }
            
            // Handle merging or replacing metrics
            if (!$merge) {
                $this->reset();
            }
            
            // Merge or replace the metrics
            $this->counters = $merge 
                ? array_merge($this->counters, $data['counters']) 
                : $data['counters'];
                
            $this->gauges = $merge 
                ? array_merge($this->gauges, $data['gauges']) 
                : $data['gauges'];
                
            $this->histograms = $merge 
                ? array_merge($this->histograms, $data['histograms']) 
                : $data['histograms'];
            
            $this->logger->info('Metrics loaded from file', [
                'file' => $filePath,
                'timestamp' => $data['timestamp'] ?? 'unknown',
                'metrics_count' => count($this->counters) + count($this->gauges) + count($this->histograms),
                'mode' => $merge ? 'merge' : 'replace',
            ]);
            
            return true;
        } catch (\Throwable $e) {
            $this->logger->error('Exception while loading metrics', [
                'exception' => $e->getMessage(),
                'file' => $filePath,
            ]);
            
            return false;
        }
    }
    
    /**
     * Get a lock to ensure thread safety when modifying metrics.
     * 
     * This is a simple implementation and might need to be enhanced
     * in a highly concurrent environment.
     * 
     * @param string $lockName Name of the lock
     * @param int $timeout Timeout in seconds
     * @return bool True if a lock was acquired
     */
    private function acquireLock(string $lockName, int $timeout = 5): bool
    {
        $lockFile = sys_get_temp_dir() . "/metrics_{$lockName}.lock";
        $startTime = time();
        
        // Try to acquire the lock with a timeout
        while (time() - $startTime < $timeout) {
            $fp = fopen($lockFile, 'w+');
            
            if ($fp === false) {
                $this->logger->warning('Failed to open lock file', ['file' => $lockFile]);
                return false;
            }
            
            if (flock($fp, LOCK_EX | LOCK_NB)) {
                // Register a shutdown function to release the lock
                register_shutdown_function(function() use ($fp) {
                    flock($fp, LOCK_UN);
                    fclose($fp);
                });
                
                return true;
            }
            
            fclose($fp);
            usleep(100000); // Sleep for 100ms before retrying
        }
        
        $this->logger->warning('Failed to acquire lock within timeout', [
            'lock' => $lockName,
            'timeout' => $timeout,
        ]);
        
        return false;
    }

