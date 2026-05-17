# Multi-stage Dockerfile for Laravel
# Stages: vendor (composer), node_builder (assets), runtime (php-fpm)

FROM composer:2 AS vendor
WORKDIR /var/www/html
COPY composer.json composer.lock ./
# Install PHP dependencies (no autoload yet to keep layer small)
RUN composer install --no-dev --no-scripts --prefer-dist --no-interaction --no-progress --no-autoloader

FROM node:18-alpine AS node_builder
WORKDIR /var/www/html
COPY package*.json ./
RUN npm ci --silent
COPY . .
RUN npm run build --silent

FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
    icu \
    libzip \
    libpng \
    libjpeg-turbo \
    freetype \
    icu-dev \
    libzip-dev \
    zlib-dev \
    oniguruma-dev \
    freetype-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    git \
    $PHPIZE_DEPS \
    && docker-php-ext-configure intl \
    && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install pdo pdo_mysql zip intl mbstring exif pcntl bcmath opcache gd

# Provide composer from the composer image
COPY --from=vendor /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy application source
COPY . .

# Copy prepared vendor and node assets from build stages
COPY --from=vendor /var/www/html/vendor ./vendor
COPY --from=node_builder /var/www/html/public/build ./public/build

# Optimize autoloader in the final image
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative --no-interaction --no-ansi

# Ensure storage and cache are writable
RUN chmod -R 775 storage bootstrap/cache database \
    && chown -R www-data:www-data storage bootstrap/cache database

RUN touch /var/www/html/database/database.sqlite

EXPOSE 10000
CMD sh -c "chmod -R 775 storage bootstrap/cache database && php artisan optimize:clear && php artisan migrate --force --seed && php artisan serve --host=0.0.0.0 --port=10000"