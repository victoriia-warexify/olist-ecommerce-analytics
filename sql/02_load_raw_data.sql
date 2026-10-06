-- ============================================================
-- LOAD RAW DATA
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

TRUNCATE TABLE
    raw.orders,
    raw.customers,
    raw.order_items,
    raw.products,
    raw.sellers,
    raw.payments,
    raw.reviews,
    raw.categories,
    raw.geolocation;


-- Orders
\copy raw.orders FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Customers
\copy raw.customers FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Order Items
\copy raw.order_items FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Products
\copy raw.products FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Sellers
\copy raw.sellers FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Payments
\copy raw.payments FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Reviews
\copy raw.reviews FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true);

-- Categories
\copy raw.categories FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true);

-- Geolocation
\copy raw.geolocation FROM 'data/raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true);

COMMIT;