# Changelog

All notable changes to the INSTANTpay+ project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2025-05-15

### Added
- **Deployment**: Comprehensive logging system with timestamps and log file rotation
- **Deployment**: Container health check mechanism with configurable retries and timeouts
- **Deployment**: Automated backup system for volumes and database before deployment
- **Deployment**: Rollback functionality to restore from backups if deployment fails
- **Deployment**: Environment validation with comprehensive pre-flight checks

### Changed
- **DevOps**: Complete rewrite of `deploy.production.sh` with improved structure and error handling
- **DevOps**: Migrated volume management to use external volumes for better persistence
- **DevOps**: Consolidated Laravel artisan commands into a single optimization flow
- **DevOps**: Replaced hardcoded sleep commands with intelligent container readiness checks
- **DevOps**: Made Docker image references configurable via constants

### Fixed
- **Deployment**: Fixed issue with volume mounting that caused persistent data loss
- **Deployment**: Resolved environment file inconsistencies during deployment
- **Deployment**: Fixed permissions issues with Laravel storage directories
- **Deployment**: Addressed database migration reliability problems
- **Deployment**: Fixed incomplete Octane server management during deployment

### Security
- **Deployment**: Improved SSH command execution with proper error handling
- **Deployment**: Added validation checks for environment credentials
- **Deployment**: Enhanced error reporting to prevent exposing sensitive information

## [1.1.0] - 2025-04-30

Initial versioned release.

