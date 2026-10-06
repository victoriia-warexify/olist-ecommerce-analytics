-- ============================================================
-- ANALYTICS LAYER VALIDATION
-- Проверка подготовленного слоя analytics
-- ============================================================


-- ------------------------------------------------------------
-- 1. Row counts
-- ------------------------------------------------------------

SELECT
    'customers' AS table_name,
    (SELECT COUNT(*) FROM raw.customers) AS raw_rows,
    (SELECT COUNT(*) FROM analytics.customers) AS analytics_rows

UNION ALL

SELECT
    'products',
    (SELECT COUNT(*) FROM raw.products),
    (SELECT COUNT(*) FROM analytics.products)

UNION ALL

SELECT
    'sellers',
    (SELECT COUNT(*) FROM raw.sellers),
    (SELECT COUNT(*) FROM analytics.sellers)

UNION ALL

SELECT
    'orders',
    (SELECT COUNT(*) FROM raw.orders),
    (SELECT COUNT(*) FROM analytics.orders)

UNION ALL

SELECT
    'order_items',
    (SELECT COUNT(*) FROM raw.order_items),
    (SELECT COUNT(*) FROM analytics.order_items)

UNION ALL

SELECT
    'payments',
    (SELECT COUNT(*) FROM raw.payments),
    (SELECT COUNT(*) FROM analytics.payments)

UNION ALL

SELECT
    'reviews',
    (SELECT COUNT(*) FROM raw.reviews),
    (SELECT COUNT(*) FROM analytics.reviews);

-- ------------------------------------------------------------
-- 2. Categories
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS categories,
    COUNT(*) FILTER (
        WHERE product_category_name_english IS NULL
    ) AS categories_without_translation
FROM analytics.categories;

SELECT COUNT(*) AS products_with_missing_category
FROM analytics.products AS p
LEFT JOIN analytics.categories AS c
    USING (product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND c.product_category_name IS NULL;

-- ------------------------------------------------------------
-- 3. Geolocation
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS unique_zip_prefixes
FROM analytics.geolocation;

SELECT
    geolocation_zip_code_prefix,
    COUNT(*) AS rows
FROM analytics.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 4. Required fields
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (
        WHERE customer_id IS NULL
           OR customer_unique_id IS NULL
    ) AS customers_invalid
FROM analytics.customers;


SELECT
    COUNT(*) FILTER (
        WHERE order_id IS NULL
           OR customer_id IS NULL
           OR order_status IS NULL
           OR order_purchase_timestamp IS NULL
    ) AS orders_invalid
FROM analytics.orders;


SELECT
    COUNT(*) FILTER (
        WHERE order_id IS NULL
           OR order_item_id IS NULL
           OR product_id IS NULL
           OR seller_id IS NULL
    ) AS order_items_invalid
FROM analytics.order_items;

-- ------------------------------------------------------------
-- 5. Relationship validation
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS unmatched_order_customers
FROM analytics.orders AS o
LEFT JOIN analytics.customers AS c
    USING (customer_id)
WHERE c.customer_id IS NULL;


SELECT
    COUNT(*) AS unmatched_order_items
FROM analytics.order_items AS oi
LEFT JOIN analytics.orders AS o
    USING (order_id)
WHERE o.order_id IS NULL;


SELECT
    COUNT(*) AS unmatched_products
FROM analytics.order_items AS oi
LEFT JOIN analytics.products AS p
    USING (product_id)
WHERE p.product_id IS NULL;


SELECT
    COUNT(*) AS unmatched_sellers
FROM analytics.order_items AS oi
LEFT JOIN analytics.sellers AS s
    USING (seller_id)
WHERE s.seller_id IS NULL;

-- ------------------------------------------------------------
-- 6. Geolocation coverage
-- ------------------------------------------------------------

SELECT COUNT(DISTINCT customer_zip_code_prefix)
    AS customer_zip_prefixes_without_geolocation
FROM analytics.customers AS c
LEFT JOIN analytics.geolocation AS g
    ON c.customer_zip_code_prefix =
       g.geolocation_zip_code_prefix
WHERE g.geolocation_zip_code_prefix IS NULL;


SELECT COUNT(DISTINCT seller_zip_code_prefix)
    AS seller_zip_prefixes_without_geolocation
FROM analytics.sellers AS s
LEFT JOIN analytics.geolocation AS g
    ON s.seller_zip_code_prefix =
       g.geolocation_zip_code_prefix
WHERE g.geolocation_zip_code_prefix IS NULL;

