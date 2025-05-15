# Use PHP 8.3 CLI image as base
FROM php:8.3-cli

# Install system dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    curl \
    zip \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install \
    opcache \
    sockets

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install RoadRunner
RUN curl -L https://github.com/roadrunner-server/roadrunner/releases/download/v2025.1.1/roadrunner-2025.1.1-linux-amd64.tar.gz > roadrunner.tar.gz \
    && tar -xzf roadrunner.tar.gz \
    && mv roadrunner-2025.1.1-linux-amd64/rr /usr/local/bin/ \
    && chmod +x /usr/local/bin/rr \
    && rm -rf roadrunner.tar.gz roadrunner-2025.1.1-linux-amd64

# Set working directory
WORKDIR /app

# Create directory structure
RUN mkdir -p \
    src \
    config \
    logs/php/tmp \
    logs/roadrunner \
    logs/application \
    public/member

# Copy composer files first for better caching
COPY composer.json composer.lock ./

# Install dependencies
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN composer clear-cache && \
    composer config --global process-timeout 2000 && \
    composer install --no-dev --optimize-autoloader

# Copy application files
COPY src/ src/
COPY config/ config/
COPY public/ public/
COPY .rr.yaml .rr-worker.php ./

# Create log files and set permissions
RUN touch \
    logs/application/redirect.log \
    logs/roadrunner/server.log \
    logs/roadrunner/error.log \
    logs/roadrunner/worker.log \
    logs/php/error.log \
    && chmod -R 777 logs \
    && chown -R www-data:www-data logs

# Configure PHP
COPY docker/php.ini /usr/local/etc/php/conf.d/custom.ini

# Expose RoadRunner port
EXPOSE 8080

# Set runtime environment variables
ENV RR_DEBUG=1
ENV RR_WORKER_DEBUG=1

# Start RoadRunner with debug output
CMD ["rr", "serve", "--debug"]

