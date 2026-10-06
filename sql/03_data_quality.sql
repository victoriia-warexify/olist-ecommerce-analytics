-- ============================================================
-- DATA QUALITY CHECKS
-- ============================================================

-- ------------------------------------------------------------
-- 1. Row counts
-- ------------------------------------------------------------

SELECT 'orders' AS table_name, COUNT(*) AS rows
FROM raw.orders

UNION ALL

SELECT 'customers', COUNT(*)
FROM raw.customers

UNION ALL

SELECT 'order_items', COUNT(*)
FROM raw.order_items

UNION ALL

SELECT 'products', COUNT(*)
FROM raw.products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM raw.sellers

UNION ALL

SELECT 'payments', COUNT(*)
FROM raw.payments

UNION ALL

SELECT 'reviews', COUNT(*)
FROM raw.reviews

UNION ALL

SELECT 'categories', COUNT(*)
FROM raw.categories

UNION ALL

SELECT 'geolocation', COUNT(*)
FROM raw.geolocation;

-- ------------------------------------------------------------
-- 2. Missing values
-- ------------------------------------------------------------

-- Orders
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL) AS order_status,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS order_purchase_timestamp,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS order_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS order_delivered_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS order_delivered_customer_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS order_estimated_delivery_date
FROM raw.orders;

-- Customers
SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS customer_id,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS customer_unique_id,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS customer_zip_code_prefix,
    COUNT(*) FILTER (WHERE customer_city IS NULL) AS customer_city,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS customer_state
FROM raw.customers;


-- Order Items
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS order_id,
    COUNT(*) FILTER (WHERE order_item_id IS NULL) AS order_item_id,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS seller_id,
    COUNT(*) FILTER (WHERE shipping_limit_date IS NULL) AS shipping_limit_date,
    COUNT(*) FILTER (WHERE price IS NULL) AS price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS freight_value
FROM raw.order_items;


-- Products
SELECT
    COUNT(*) FILTER (WHERE product_id IS NULL) AS product_id,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS product_category_name,
    COUNT(*) FILTER (WHERE product_name_lenght IS NULL) AS product_name_lenght,
    COUNT(*) FILTER (WHERE product_description_lenght IS NULL) AS product_description_lenght,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS product_photos_qty,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS product_weight_g,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS product_length_cm,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS product_height_cm,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS product_width_cm
FROM raw.products;


-- Sellers
SELECT
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS seller_id,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) AS seller_zip_code_prefix,
    COUNT(*) FILTER (WHERE seller_city IS NULL) AS seller_city,
    COUNT(*) FILTER (WHERE seller_state IS NULL) AS seller_state
FROM raw.sellers;


-- Payments
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS order_id,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL) AS payment_sequential,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS payment_type,
    COUNT(*) FILTER (WHERE payment_installments IS NULL) AS payment_installments,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS payment_value
FROM raw.payments;


-- Reviews
SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL) AS review_id,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS order_id,
    COUNT(*) FILTER (WHERE review_score IS NULL) AS review_score,
    COUNT(*) FILTER (WHERE review_comment_title IS NULL) AS review_comment_title,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL) AS review_comment_message,
    COUNT(*) FILTER (WHERE review_creation_date IS NULL) AS review_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) AS review_answer_timestamp
FROM raw.reviews;


-- Categories
SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS product_category_name,
    COUNT(*) FILTER (WHERE product_category_name_english IS NULL) AS product_category_name_english
FROM raw.categories;


-- Geolocation
SELECT
    COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) AS geolocation_zip_code_prefix,
    COUNT(*) FILTER (WHERE geolocation_lat IS NULL) AS geolocation_lat,
    COUNT(*) FILTER (WHERE geolocation_lng IS NULL) AS geolocation_lng,
    COUNT(*) FILTER (WHERE geolocation_city IS NULL) AS geolocation_city,
    COUNT(*) FILTER (WHERE geolocation_state IS NULL) AS geolocation_state
FROM raw.geolocation;

-- ------------------------------------------------------------
-- 3. Duplicate checks
-- ------------------------------------------------------------

-- Orders
SELECT
    'orders' AS table_name,
    COUNT(*) - COUNT(DISTINCT (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date
    )) AS duplicate_rows
FROM raw.orders

UNION ALL

-- Customers
SELECT
    'customers',
    COUNT(*) - COUNT(DISTINCT (
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    ))
FROM raw.customers

UNION ALL

-- Order Items
SELECT
    'order_items',
    COUNT(*) - COUNT(DISTINCT (
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    ))
FROM raw.order_items

UNION ALL

-- Products
SELECT
    'products',
    COUNT(*) - COUNT(DISTINCT (
        product_id,
        product_category_name,
        product_name_lenght,
        product_description_lenght,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    ))
FROM raw.products

UNION ALL

-- Sellers
SELECT
    'sellers',
    COUNT(*) - COUNT(DISTINCT (
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    ))
FROM raw.sellers

UNION ALL

-- Payments
SELECT
    'payments',
    COUNT(*) - COUNT(DISTINCT (
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value
    ))
FROM raw.payments

UNION ALL

-- Reviews
SELECT
    'reviews',
    COUNT(*) - COUNT(DISTINCT (
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp
    ))
FROM raw.reviews

UNION ALL

-- Categories
SELECT
    'categories',
    COUNT(*) - COUNT(DISTINCT (
        product_category_name,
        product_category_name_english
    ))
FROM raw.categories

UNION ALL

-- Geolocation
SELECT
    'geolocation',
    COUNT(*) - COUNT(DISTINCT (
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    ))
FROM raw.geolocation;

-- ------------------------------------------------------------
-- 4. Key checks
-- ------------------------------------------------------------

-- Orders: order_id
SELECT
    'orders' AS table_name,
    'order_id' AS key_columns,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE order_id IS NULL
    ) AS null_key_rows,
    COUNT(DISTINCT order_id) AS distinct_keys,
    COUNT(*) FILTER (
        WHERE order_id IS NOT NULL
    ) - COUNT(DISTINCT order_id) AS duplicate_key_rows
FROM raw.orders

UNION ALL

-- Customers: customer_id
SELECT
    'customers',
    'customer_id',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE customer_id IS NULL
    ),
    COUNT(DISTINCT customer_id),
    COUNT(*) FILTER (
        WHERE customer_id IS NOT NULL
    ) - COUNT(DISTINCT customer_id)
FROM raw.customers

UNION ALL

-- Order Items: order_id + order_item_id
SELECT
    'order_items',
    'order_id + order_item_id',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE order_id IS NULL
           OR order_item_id IS NULL
    ),
    COUNT(DISTINCT (order_id, order_item_id)) FILTER (
        WHERE order_id IS NOT NULL
          AND order_item_id IS NOT NULL
    ),
    COUNT(*) FILTER (
        WHERE order_id IS NOT NULL
          AND order_item_id IS NOT NULL
    )
    - COUNT(DISTINCT (order_id, order_item_id)) FILTER (
        WHERE order_id IS NOT NULL
          AND order_item_id IS NOT NULL
    )
FROM raw.order_items

UNION ALL

-- Products: product_id
SELECT
    'products',
    'product_id',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE product_id IS NULL
    ),
    COUNT(DISTINCT product_id),
    COUNT(*) FILTER (
        WHERE product_id IS NOT NULL
    ) - COUNT(DISTINCT product_id)
FROM raw.products

UNION ALL

-- Sellers: seller_id
SELECT
    'sellers',
    'seller_id',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE seller_id IS NULL
    ),
    COUNT(DISTINCT seller_id),
    COUNT(*) FILTER (
        WHERE seller_id IS NOT NULL
    ) - COUNT(DISTINCT seller_id)
FROM raw.sellers

UNION ALL

-- Payments: order_id + payment_sequential
SELECT
    'payments',
    'order_id + payment_sequential',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE order_id IS NULL
           OR payment_sequential IS NULL
    ),
    COUNT(DISTINCT (order_id, payment_sequential)) FILTER (
        WHERE order_id IS NOT NULL
          AND payment_sequential IS NOT NULL
    ),
    COUNT(*) FILTER (
        WHERE order_id IS NOT NULL
          AND payment_sequential IS NOT NULL
    )
    - COUNT(DISTINCT (order_id, payment_sequential)) FILTER (
        WHERE order_id IS NOT NULL
          AND payment_sequential IS NOT NULL
    )
FROM raw.payments

UNION ALL

-- Reviews: review_id + order_id
SELECT
    'reviews',
    'review_id + order_id',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE review_id IS NULL
           OR order_id IS NULL
    ),
    COUNT(DISTINCT (review_id, order_id)) FILTER (
        WHERE review_id IS NOT NULL
          AND order_id IS NOT NULL
    ),
    COUNT(*) FILTER (
        WHERE review_id IS NOT NULL
          AND order_id IS NOT NULL
    )
    - COUNT(DISTINCT (review_id, order_id)) FILTER (
        WHERE review_id IS NOT NULL
          AND order_id IS NOT NULL
    )
FROM raw.reviews

UNION ALL

-- Categories: product_category_name
SELECT
    'categories',
    'product_category_name',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE product_category_name IS NULL
    ),
    COUNT(DISTINCT product_category_name),
    COUNT(*) FILTER (
        WHERE product_category_name IS NOT NULL
    ) - COUNT(DISTINCT product_category_name)
FROM raw.categories;

-- ------------------------------------------------------------
-- 5. Relationship checks
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Foreign keys without matching parent records
-- ------------------------------------------------------------

SELECT
    'orders.customer_id → customers.customer_id' AS relationship,
    COUNT(*) AS unmatched_child_keys
FROM (
    SELECT customer_id
    FROM raw.orders

    EXCEPT

    SELECT customer_id
    FROM raw.customers
) AS unmatched

UNION ALL

SELECT
    'order_items.order_id → orders.order_id',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.order_items

    EXCEPT

    SELECT order_id
    FROM raw.orders
) AS unmatched

UNION ALL

SELECT
    'order_items.product_id → products.product_id',
    COUNT(*)
FROM (
    SELECT product_id
    FROM raw.order_items

    EXCEPT

    SELECT product_id
    FROM raw.products
) AS unmatched

UNION ALL

SELECT
    'order_items.seller_id → sellers.seller_id',
    COUNT(*)
FROM (
    SELECT seller_id
    FROM raw.order_items

    EXCEPT

    SELECT seller_id
    FROM raw.sellers
) AS unmatched

UNION ALL

SELECT
    'payments.order_id → orders.order_id',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.payments

    EXCEPT

    SELECT order_id
    FROM raw.orders
) AS unmatched

UNION ALL

SELECT
    'reviews.order_id → orders.order_id',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.reviews

    EXCEPT

    SELECT order_id
    FROM raw.orders
) AS unmatched;

-- ------------------------------------------------------------
-- Parent records without matching child records
-- ------------------------------------------------------------

SELECT
    'customers without orders' AS check_name,
    COUNT(*) AS missing_related_keys
FROM (
    SELECT customer_id
    FROM raw.customers

    EXCEPT

    SELECT customer_id
    FROM raw.orders
) AS missing

UNION ALL

SELECT
    'orders without order_items',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.orders

    EXCEPT

    SELECT order_id
    FROM raw.order_items
) AS missing

UNION ALL

SELECT
    'products without order_items',
    COUNT(*)
FROM (
    SELECT product_id
    FROM raw.products

    EXCEPT

    SELECT product_id
    FROM raw.order_items
) AS missing

UNION ALL

SELECT
    'sellers without order_items',
    COUNT(*)
FROM (
    SELECT seller_id
    FROM raw.sellers

    EXCEPT

    SELECT seller_id
    FROM raw.order_items
) AS missing

UNION ALL

SELECT
    'orders without payments',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.orders

    EXCEPT

    SELECT order_id
    FROM raw.payments
) AS missing

UNION ALL

SELECT
    'orders without reviews',
    COUNT(*)
FROM (
    SELECT order_id
    FROM raw.orders

    EXCEPT

    SELECT order_id
    FROM raw.reviews
) AS missing;

-- ------------------------------------------------------------
-- Product categories without translation
-- ------------------------------------------------------------

SELECT COUNT(*) AS categories_without_translation
FROM (
    SELECT DISTINCT product_category_name
    FROM raw.products
    WHERE product_category_name IS NOT NULL

    EXCEPT

    SELECT product_category_name
    FROM raw.categories
) AS missing;

-- ------------------------------------------------------------
-- Zip prefixes without geolocation
-- ------------------------------------------------------------

SELECT COUNT(*) AS customer_zip_prefixes_without_geolocation
FROM (
    SELECT DISTINCT customer_zip_code_prefix
    FROM raw.customers

    EXCEPT

    SELECT geolocation_zip_code_prefix
    FROM raw.geolocation
) AS missing;


SELECT COUNT(*) AS seller_zip_prefixes_without_geolocation
FROM (
    SELECT DISTINCT seller_zip_code_prefix
    FROM raw.sellers

    EXCEPT

    SELECT geolocation_zip_code_prefix
    FROM raw.geolocation
) AS missing;