FROM wordpress:6.9-php8.3-apache

RUN pecl install redis \
    && docker-php-ext-enable redis
