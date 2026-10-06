-- ============================================================
-- ANALYTICS TABLES
-- Подготовленные таблицы для анализа
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- ------------------------------------------------------------
-- Customers
-- ------------------------------------------------------------

CREATE TABLE analytics.customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    customer_zip_code_prefix TEXT NOT NULL,
    customer_city TEXT NOT NULL,
    customer_state TEXT NOT NULL
);

INSERT INTO analytics.customers (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM raw.customers;

-- ------------------------------------------------------------
-- Categories
-- ------------------------------------------------------------

CREATE TABLE analytics.categories (
    product_category_name TEXT PRIMARY KEY,
    product_category_name_english TEXT
);

INSERT INTO analytics.categories (
    product_category_name,
    product_category_name_english
)
SELECT
    category_names.product_category_name,
    raw.categories.product_category_name_english
FROM (
    SELECT product_category_name
    FROM raw.categories

    UNION

    SELECT product_category_name
    FROM raw.products
    WHERE product_category_name IS NOT NULL
) AS category_names
LEFT JOIN raw.categories
    USING (product_category_name);

-- ------------------------------------------------------------
-- Products
-- ------------------------------------------------------------

CREATE TABLE analytics.products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT,
    product_name_length INTEGER,
    product_description_length INTEGER,
    product_photos_qty INTEGER,
    product_weight_g INTEGER,
    product_length_cm INTEGER,
    product_height_cm INTEGER,
    product_width_cm INTEGER,

    FOREIGN KEY (product_category_name)
        REFERENCES analytics.categories(product_category_name)
);

INSERT INTO analytics.products (
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    product_id,
    product_category_name,
    product_name_lenght,
    product_description_lenght,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM raw.products;

-- ------------------------------------------------------------
-- Sellers
-- ------------------------------------------------------------

CREATE TABLE analytics.sellers (
    seller_id TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT NOT NULL,
    seller_city TEXT NOT NULL,
    seller_state TEXT NOT NULL
);

INSERT INTO analytics.sellers (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM raw.sellers;

-- ------------------------------------------------------------
-- Orders
-- ------------------------------------------------------------

CREATE TABLE analytics.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    order_status TEXT NOT NULL,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP NOT NULL,

    FOREIGN KEY (customer_id)
        REFERENCES analytics.customers(customer_id)
);

INSERT INTO analytics.orders (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM raw.orders;

-- ------------------------------------------------------------
-- Order Items
-- ------------------------------------------------------------

CREATE TABLE analytics.order_items (
    order_id TEXT NOT NULL,
    order_item_id INTEGER NOT NULL,
    product_id TEXT NOT NULL,
    seller_id TEXT NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    freight_value NUMERIC(10, 2) NOT NULL,

    PRIMARY KEY (order_id, order_item_id),

    FOREIGN KEY (order_id)
        REFERENCES analytics.orders(order_id),

    FOREIGN KEY (product_id)
        REFERENCES analytics.products(product_id),

    FOREIGN KEY (seller_id)
        REFERENCES analytics.sellers(seller_id)
);

INSERT INTO analytics.order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
FROM raw.order_items;

-- ------------------------------------------------------------
-- Payments
-- ------------------------------------------------------------

CREATE TABLE analytics.payments (
    order_id TEXT NOT NULL,
    payment_sequential INTEGER NOT NULL,
    payment_type TEXT NOT NULL,
    payment_installments INTEGER NOT NULL,
    payment_value NUMERIC(10, 2) NOT NULL,

    PRIMARY KEY (order_id, payment_sequential),

    FOREIGN KEY (order_id)
        REFERENCES analytics.orders(order_id)
);

INSERT INTO analytics.payments (
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
FROM raw.payments;

-- ------------------------------------------------------------
-- Reviews
-- ------------------------------------------------------------

CREATE TABLE analytics.reviews (
    review_id TEXT NOT NULL,
    order_id TEXT NOT NULL,
    review_score INTEGER NOT NULL,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP NOT NULL,
    review_answer_timestamp TIMESTAMP NOT NULL,

    PRIMARY KEY (review_id, order_id),

    FOREIGN KEY (order_id)
        REFERENCES analytics.orders(order_id)
);

INSERT INTO analytics.reviews (
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
)
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
FROM raw.reviews;

-- ------------------------------------------------------------
-- Geolocation
-- ------------------------------------------------------------

CREATE TABLE analytics.geolocation (
    geolocation_zip_code_prefix TEXT PRIMARY KEY,
    geolocation_lat DOUBLE PRECISION NOT NULL,
    geolocation_lng DOUBLE PRECISION NOT NULL,
    geolocation_city TEXT NOT NULL,
    geolocation_state TEXT NOT NULL
);

WITH unique_geolocation AS (
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    FROM raw.geolocation
),

coordinates AS (
    SELECT
        geolocation_zip_code_prefix,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY geolocation_lat)
            AS geolocation_lat,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY geolocation_lng)
            AS geolocation_lng

    FROM unique_geolocation
    GROUP BY geolocation_zip_code_prefix
),

city_state_counts AS (
    SELECT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state,
        COUNT(*) AS frequency,

        ROW_NUMBER() OVER (
            PARTITION BY geolocation_zip_code_prefix
            ORDER BY
                COUNT(*) DESC,
                geolocation_city,
                geolocation_state
        ) AS rn

    FROM unique_geolocation

    GROUP BY
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state
),

city_state AS (
    SELECT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state
    FROM city_state_counts
    WHERE rn = 1
)

INSERT INTO analytics.geolocation (
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
)
SELECT
    coordinates.geolocation_zip_code_prefix,
    coordinates.geolocation_lat,
    coordinates.geolocation_lng,
    city_state.geolocation_city,
    city_state.geolocation_state

FROM coordinates

JOIN city_state
    USING (geolocation_zip_code_prefix);

COMMIT;