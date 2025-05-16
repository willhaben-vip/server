# Finden Service Dashboard Documentation

## Overview

The Finden Service Dashboard provides comprehensive monitoring of the image search functionality, including service performance, error rates, cache effectiveness, and resource usage. This dashboard helps operators identify issues, optimize performance, and ensure the service meets its SLAs.

The dashboard is organized into several key sections:
- **Service Overview**: High-level metrics showing service health and error rates
- **Cache Performance**: Metrics related to cache hit ratios and effectiveness
- **Resource Usage**: System resource utilization for the service

## Dashboard Access

- **URL**: https://grafana:3000/d/finden-metrics
- **Refresh Rate**: 10 seconds (configurable in the top-right corner)
- **Default Time Range**: 6 hours (configurable in the top-right corner)

## Panel Descriptions

### Service Overview

#### Finden Service Error Rate

This panel displays the error rate for the Finden service over time.

**Metrics Displayed**:
- `job:finden_error_rate:5m`: Error rate calculated over a 5-minute window

**Thresholds**:
- **Red line (0.05)**: Critical threshold indicating an error rate above 5% which requires immediate attention

**Use Cases**:
- **Monitoring Service Health**: Quick view of service stability
- **Incident Detection**: Spikes indicate potential issues requiring investigation
- **SLA Monitoring**: Ensure error rates are below acceptable thresholds

**Troubleshooting High Error Rates**:
1. Check application logs for specific error messages
2. Verify Willhaben API status and connectivity
3. Examine image processing service for issues
4. Check the error distribution details in related panels
5. Correlate with resource usage spikes

### Cache Performance

#### Cache Hit Ratio

This panel shows the cache hit ratio over time, indicating cache effectiveness.

**Metrics Displayed**:
- `job:finden_cache_hit_ratio:5m`: Percentage of cache requests that resulted in hits over a 5-minute window

**Thresholds**:
- **Red (below 0.7)**: Poor cache performance, cache hit ratio below 70%
- **Yellow (0.7-0.8)**: Marginal cache performance
- **Green (above 0.8)**: Good cache performance

**Use Cases**:
- **Cache Efficiency Monitoring**: Ensure cache is effectively reducing backend load
- **Performance Optimization**: Low hit rates may indicate opportunities for cache tuning
- **Cost Control**: Effective caching reduces API calls and processing costs

**Troubleshooting Low Cache Hit Ratio**:
1. Check cache key generation logic
2. Review cache invalidation policies
3. Examine TTL settings for cached items
4. Analyze request patterns for cache-unfriendly behaviors
5. Verify cache storage is functioning properly

### Resource Usage

#### Memory Usage

This panel displays the memory usage of the Finden service over time.

**Metrics Displayed**:
- `process_resident_memory_bytes{job="roadrunner"}`: Physical memory used by the RoadRunner process in GB

**Thresholds**:
- **Red line (1.5 GB)**: Critical threshold indicating potential memory issues

**Use Cases**:
- **Resource Planning**: Understand memory requirements for the service
- **Performance Monitoring**: Memory spikes can indicate inefficient processing
- **Capacity Planning**: Ensure sufficient resources are allocated

**Troubleshooting High Memory Usage**:
1. Check for memory leaks in the image processing service
2. Review size of processed images
3. Examine concurrent request patterns
4. Verify garbage collection is functioning properly
5. Consider scaling resources if consistently high

#### CPU Usage

This panel displays the CPU usage rate of the Finden service over time.

**Metrics Displayed**:
- `rate(process_cpu_seconds_total{job="roadrunner"}[5m])`: CPU usage rate over a 5-minute window

**Thresholds**:
- **Red line (0.8)**: Critical threshold indicating CPU usage over 80%

**Use Cases**:
- **Performance Monitoring**: Identify CPU bottlenecks
- **Capacity Planning**: Ensure adequate CPU resources
- **Scaling Decisions**: Determine when to scale horizontally or vertically

**Troubleshooting High CPU Usage**:
1. Identify CPU-intensive operations in the application
2. Examine image processing algorithms for optimizations
3. Check for concurrent processing of large images
4. Review background tasks and their scheduling
5. Consider optimizing or scaling if consistently high

## Common Use Cases

### Incident Response

1. **Service Degradation**:
   - Check error rate panel first
   - Correlate with resource usage (memory/CPU)
   - Examine logs for specific error messages
   - Reference runbooks for specific alerts

2. **Performance Issues**:
   - Check cache hit ratio panel
   - Examine resource usage trends
   - Analyze request patterns and volume
   - Correlate with API integration metrics

### Capacity Planning

1. **Resource Scaling Decisions**:
   - Monitor memory and CPU trends over time
   - Correlate with user traffic patterns
   - Establish baseline performance metrics
   - Plan scaling based on peak usage patterns

2. **Cache Optimization**:
   - Analyze cache hit ratio trends
   - Identify frequently missed cache items
   - Adjust cache TTL and policies
   - Implement predictive caching for common queries

## Alert Threshold Explanations

| Metric | Warning Threshold | Critical Threshold | Rationale |
|--------|-------------------|-------------------|-----------|
| Error Rate | 1% | 5% | Based on SLA requirement of 99.9% success rate |
| Cache Hit Ratio | 70% | N/A | Optimal performance requires at least 70% hit rate |
| Memory Usage | N/A | 1.5 GB | Based on container limits and observed performance |
| CPU Usage | N/A | 80% | Ensure headroom for traffic spikes |

## Dashboard Refresh Settings

- **Auto Refresh**: 10s (default)
- **Configurable Ranges**: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h, 2h, 1d
- **Time Range Selector**: Located in top-right corner
- **Quick Ranges**: Last 5 minutes to Last 5 years

**Best Practices**:
- Use shorter refresh intervals (5-10s) during incident investigation
- Use longer intervals (1m+) for trend analysis to reduce database load
- Set custom time ranges to match specific incident windows

## Related Resources

- [Finden Service Runbooks](/docs/runbooks/finden)
- [Alert Rules Documentation](/MONITORING.md)
- [Prometheus Query Reference](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Reference](https://grafana.com/docs/grafana/latest/dashboards/)

## Monitoring System Reliability

### Backup Procedures

#### Prometheus Data Backup

Prometheus time-series data is stored in the `/prometheus` volume and should be backed up regularly:

1. **Daily Local Backups**:
   ```bash
   # Create snapshot of Prometheus data
   curl -X POST http://prometheus:9090/-/snapshot
   # This creates a snapshot in /prometheus/snapshots/ that can be backed up
   ```

2. **Weekly Full Backups**:
   ```bash
   # Stop Prometheus temporarily
   docker-compose stop prometheus
   
   # Backup the entire data directory
   tar -czf prometheus-data-$(date +%Y%m%d).tar.gz /path/to/prometheus_data
   
   # Start Prometheus
   docker-compose start prometheus
   ```

3. **Backup Retention Policy**:
   - Daily snapshots: Keep for 7 days
   - Weekly full backups: Keep for 3 months
   - Monthly full backups: Keep for 1 year

#### Grafana Dashboard Backup

Grafana dashboards should be backed up using the following methods:

1. **Version Control**:
   - All dashboard JSON files are stored in the Git repository under `docker/grafana/dashboards/`
   - Changes should be committed to version control

2. **Dashboard Export**:
   - From Grafana UI: Dashboard Settings → JSON Model → Copy to clipboard or Save to file
   - Via API:
   ```bash
   curl -X GET http://admin:admin@grafana:3000/api/dashboards/uid/finden-metrics \
     -H "Accept: application/json" \
     --output finden-metrics-$(date +%Y%m%d).json
   ```

3. **Automated Backups**:
   ```bash
   # Script to backup all dashboards (to be scheduled via cron)
   ./scripts/backup-grafana-dashboards.sh
   ```

### High Availability Setup

The monitoring stack supports high availability configurations:

#### Prometheus HA Setup

1. **Primary-Secondary Configuration**:
   - Two Prometheus instances running in different environments
   - Thanos sidecar for long-term storage with object storage backend
   - Thanos query component for unified view across Prometheus instances

2. **Alertmanager Cluster**:
   - Multiple Alertmanager instances in cluster mode
   - Configuration in `docker/alertmanager/alertmanager.yml`:
   ```yaml
   cluster:
     peers:
       - alertmanager1:9094
       - alertmanager2:9094
       - alertmanager3:9094
   ```

3. **Load Balancing**:
   - Use nginx or traefik for load balancing across instances
   - Health checks configured to detect unhealthy instances

#### Grafana HA Setup

1. **Multi-Instance Deployment**:
   - Multiple Grafana instances behind load balancer
   - Shared PostgreSQL database for user sessions and configurations
   - Shared file storage for plugin storage

2. **Configuration**:
   ```ini
   [database]
   type = postgres
   host = postgresql:5432
   user = grafana
   password = grafana_password
   ```

### Metric Retention Policies

Metrics retention is configured for optimal performance and storage usage:

1. **Prometheus Retention**:
   - Hot storage (in-memory): 15 days
   - Storage size limit: 5GB
   - WAL retention: 12 hours
   - Configuration in `docker/prometheus/prometheus.yml`:
   ```yaml
   storage:
     tsdb:
       path: /prometheus
       retention:
         time: 15d
         size: 5GB
       wal:
         retention:
           time: 12h
   ```

2. **Long-term Storage**:
   - Historical metrics older than 15 days are archived to object storage
   - Accessible via Thanos query interface
   - Compressed and downsampled for efficiency

3. **Retention Guidelines**:
   - High-resolution metrics (10s interval): 15 days
   - Medium-resolution metrics (1m interval): 3 months
   - Low-resolution metrics (5m interval): 1 year

### Recovery Procedures

In case of monitoring system failure, follow these recovery steps:

#### Prometheus Recovery

1. **From Snapshots**:
   ```bash
   # Stop Prometheus
   docker-compose stop prometheus
   
   # Clear corrupted data
   rm -rf /path/to/prometheus_data/*
   
   # Restore from snapshot
   tar -xzf prometheus-data-20250510.tar.gz -C /path/to/prometheus_data
   
   # Start Prometheus
   docker-compose start prometheus
   ```

2. **Rebuild from Scratch**:
   - If snapshots are unavailable, a fresh Prometheus instance will begin collecting new data
   - Historical data will be permanently lost unless backed up externally

#### Grafana Recovery

1. **Dashboard Restoration**:
   - Import dashboard JSON files from version control or backups
   - Via UI: Dashboard → Import → Upload JSON file
   - Via API:
   ```bash
   curl -X POST http://admin:admin@grafana:3000/api/dashboards/db \
     -H "Content-Type: application/json" \
     -d @finden-metrics.json
   ```

2. **Complete Environment Recovery**:
   ```bash
   # Deploy from scratch using Docker Compose
   docker-compose up -d
   
   # Restore dashboards
   ./scripts/restore-grafana-dashboards.sh
   ```

By following these procedures, the monitoring system maintains high reliability and data integrity even in failure scenarios.

