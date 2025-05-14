# Use PHP 8.4 CLI image as base
FROM php:8.4-cli

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    zip \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install \
    opcache

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

# Copy application files
COPY . .

# Install dependencies
RUN composer install --no-dev --optimize-autoloader

# Create log directory and set permissions
RUN mkdir -p public/logs \
    && touch public/logs/redirect.log \
    && touch public/logs/roadrunner.log \
    && touch public/logs/roadrunner_error.log \
    && touch public/logs/php_error.log \
    && chmod -R 777 public/logs

# Configure PHP
COPY docker/php.ini /usr/local/etc/php/conf.d/custom.ini

# Expose RoadRunner port
EXPOSE 8080

# Start RoadRunner
CMD ["rr", "serve"]

