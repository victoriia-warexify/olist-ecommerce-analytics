\set ON_ERROR_STOP on

-- ============================================================
-- DASHBOARD VIEWS
-- ============================================================
--
-- Views prepared for the Power BI dashboard.
--
-- Business rules:
-- - order counts and status metrics may use all orders;
-- - sales, item and customer purchase metrics use delivered orders;
-- - product_gmv excludes freight;
-- - total_payment_value is kept separate from product_gmv;
-- - customer_unique_id identifies a buyer;
-- - reviews are aggregated to order level before joining.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Orders dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 order
--
-- This is the main order-level dataset for Power BI.
-- Child tables are aggregated before joining in order to avoid
-- row multiplication.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW analytics.dashboard_orders AS

WITH order_items_agg AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        COUNT(
            DISTINCT product_id
        ) AS unique_products_count,

        COUNT(
            DISTINCT seller_id
        ) AS sellers_count,

        SUM(price) AS product_value,

        SUM(freight_value) AS freight_value

    FROM analytics.order_items

    GROUP BY
        order_id
),
payments_agg AS (
    SELECT
        order_id,

        COUNT(*) AS payment_records_count,

        SUM(payment_value) AS total_payment_value

    FROM analytics.payments

    GROUP BY
        order_id
),
reviews_agg AS (
    SELECT
        order_id,

        COUNT(*) AS review_records_count,

        AVG(review_score)::DOUBLE PRECISION
            AS avg_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,

        COUNT(*) AS delivered_orders_count

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        c.customer_unique_id
)
SELECT
    -- --------------------------------------------------------
    -- Order identifiers
    -- --------------------------------------------------------

    o.order_id,
    o.customer_id,
    c.customer_unique_id,


    -- --------------------------------------------------------
    -- Order status
    -- --------------------------------------------------------

    o.order_status,

    (o.order_status = 'delivered')
        AS is_delivered,

    (o.order_status = 'canceled')
        AS is_canceled,


    -- --------------------------------------------------------
    -- Purchase date
    -- --------------------------------------------------------

    o.order_purchase_timestamp,

    o.order_purchase_timestamp::date
        AS order_purchase_date,

    DATE_TRUNC(
        'month',
        o.order_purchase_timestamp
    )::date AS order_month,

    EXTRACT(
        YEAR FROM o.order_purchase_timestamp
    )::INTEGER AS order_year,

    EXTRACT(
        MONTH FROM o.order_purchase_timestamp
    )::INTEGER AS order_month_number,


    -- --------------------------------------------------------
    -- Customer
    -- --------------------------------------------------------

    c.customer_city,
    c.customer_state,

    COALESCE(
        co.delivered_orders_count,
        0
    ) AS customer_delivered_orders,

    (
        COALESCE(
            co.delivered_orders_count,
            0
        ) > 1
    ) AS is_repeat_customer,


    -- --------------------------------------------------------
    -- Items
    -- --------------------------------------------------------

    COALESCE(
        oi.items_count,
        0
    ) AS items_count,

    COALESCE(
        oi.unique_products_count,
        0
    ) AS unique_products_count,

    COALESCE(
        oi.sellers_count,
        0
    ) AS sellers_count,

    oi.product_value,
    oi.freight_value,


    -- --------------------------------------------------------
    -- Payments
    -- --------------------------------------------------------

    COALESCE(
        p.payment_records_count,
        0
    ) AS payment_records_count,

    p.total_payment_value,


    -- --------------------------------------------------------
    -- Reviews
    -- --------------------------------------------------------

    COALESCE(
        r.review_records_count,
        0
    ) AS review_records_count,

    r.avg_review_score,


    -- --------------------------------------------------------
    -- Delivery timestamps
    -- --------------------------------------------------------

    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,


    -- --------------------------------------------------------
    -- Delivery metrics
    -- --------------------------------------------------------

    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
        THEN
            EXTRACT(
                EPOCH FROM (
                    o.order_delivered_customer_date
                    - o.order_purchase_timestamp
                )
            ) / 86400.0
    END AS delivery_time_days,

    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN
            o.order_delivered_customer_date::date
            - o.order_estimated_delivery_date::date
    END AS delivery_deviation_days,

    CASE
        WHEN o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN
            o.order_delivered_customer_date::date
            > o.order_estimated_delivery_date::date
    END AS is_late

FROM analytics.orders AS o

JOIN analytics.customers AS c
    USING (customer_id)

LEFT JOIN order_items_agg AS oi
    USING (order_id)

LEFT JOIN payments_agg AS p
    USING (order_id)

LEFT JOIN reviews_agg AS r
    USING (order_id)

LEFT JOIN customer_orders AS co
    USING (customer_unique_id);

-- ------------------------------------------------------------
-- 2. Order categories dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 order × product category
--
-- Used for category-level sales and assortment analysis.
--
-- Financial values remain additive because order items are
-- aggregated directly from the order-item grain.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW
    analytics.dashboard_order_categories AS

SELECT
    -- --------------------------------------------------------
    -- Order
    -- --------------------------------------------------------

    oi.order_id,


    -- --------------------------------------------------------
    -- Category
    -- --------------------------------------------------------

    COALESCE(
        p.product_category_name,
        'unknown'
    ) AS product_category_name,

    COALESCE(
        c.product_category_name_english,
        p.product_category_name,
        'Unknown'
    ) AS category_name,


    -- --------------------------------------------------------
    -- Items and assortment
    -- --------------------------------------------------------

    COUNT(*) AS items_count,

    COUNT(
        DISTINCT oi.product_id
    ) AS unique_products_count,

    COUNT(
        DISTINCT oi.seller_id
    ) AS sellers_count,


    -- --------------------------------------------------------
    -- Financial values
    -- --------------------------------------------------------

    SUM(oi.price) AS product_value,

    SUM(oi.freight_value) AS freight_value

FROM analytics.order_items AS oi

JOIN analytics.products AS p
    USING (product_id)

LEFT JOIN analytics.categories AS c
    USING (product_category_name)

GROUP BY
    oi.order_id,

    COALESCE(
        p.product_category_name,
        'unknown'
    ),

    COALESCE(
        c.product_category_name_english,
        p.product_category_name,
        'Unknown'
    );

-- ------------------------------------------------------------
-- 3. Order-sellers dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 order × seller
--
-- Used for seller-level and geographic analysis.
--
-- Multiple items from the same seller within one order are
-- aggregated before joining with seller and geolocation data.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW
    analytics.dashboard_order_sellers AS

WITH order_seller_agg AS (
    SELECT
        order_id,
        seller_id,

        COUNT(*) AS items_count,

        COUNT(
            DISTINCT product_id
        ) AS unique_products_count,

        SUM(price) AS product_value,

        SUM(freight_value) AS freight_value

    FROM analytics.order_items

    GROUP BY
        order_id,
        seller_id
),

order_seller_geo AS (
    SELECT
        osa.order_id,
        osa.seller_id,

        osa.items_count,
        osa.unique_products_count,
        osa.product_value,
        osa.freight_value,

        s.seller_city,
        s.seller_state,

        c.customer_city,
        c.customer_state,

        customer_geo.geolocation_lat
            AS customer_lat,

        customer_geo.geolocation_lng
            AS customer_lng,

        seller_geo.geolocation_lat
            AS seller_lat,

        seller_geo.geolocation_lng
            AS seller_lng,

        (
            customer_geo.geolocation_zip_code_prefix
                IS NOT NULL

            AND seller_geo.geolocation_zip_code_prefix
                IS NOT NULL

            AND customer_geo.geolocation_state
                = c.customer_state

            AND seller_geo.geolocation_state
                = s.seller_state

            AND customer_geo.geolocation_lat
                BETWEEN -34 AND 6

            AND customer_geo.geolocation_lng
                BETWEEN -74 AND -28

            AND seller_geo.geolocation_lat
                BETWEEN -34 AND 6

            AND seller_geo.geolocation_lng
                BETWEEN -74 AND -28
        ) AS has_valid_geolocation

    FROM order_seller_agg AS osa

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.customers AS c
        USING (customer_id)

    JOIN analytics.sellers AS s
        USING (seller_id)

    LEFT JOIN analytics.geolocation AS customer_geo
        ON c.customer_zip_code_prefix =
           customer_geo.geolocation_zip_code_prefix

    LEFT JOIN analytics.geolocation AS seller_geo
        ON s.seller_zip_code_prefix =
           seller_geo.geolocation_zip_code_prefix
)

SELECT
    -- --------------------------------------------------------
    -- Keys
    -- --------------------------------------------------------

    order_id,
    seller_id,


    -- --------------------------------------------------------
    -- Seller and customer geography
    -- --------------------------------------------------------

    seller_city,
    seller_state,

    customer_city,
    customer_state,

    customer_lat,
    customer_lng,

    seller_lat,
    seller_lng,

    has_valid_geolocation,


    -- --------------------------------------------------------
    -- Items
    -- --------------------------------------------------------

    items_count,
    unique_products_count,


    -- --------------------------------------------------------
    -- Financial values
    -- --------------------------------------------------------

    product_value,
    freight_value,


    -- --------------------------------------------------------
    -- Approximate customer-seller distance
    -- --------------------------------------------------------

    CASE
        WHEN has_valid_geolocation
        THEN
            6371 * ACOS(
                LEAST(
                    1.0,
                    GREATEST(
                        -1.0,

                        SIN(
                            RADIANS(customer_lat)
                        )
                        *
                        SIN(
                            RADIANS(seller_lat)
                        )

                        +

                        COS(
                            RADIANS(customer_lat)
                        )
                        *
                        COS(
                            RADIANS(seller_lat)
                        )
                        *
                        COS(
                            RADIANS(
                                seller_lng
                                - customer_lng
                            )
                        )
                    )
                )
            )
    END AS distance_km

FROM order_seller_geo;

-- ------------------------------------------------------------
-- 4. Order geography dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 order
--
-- Aggregates seller-level geography to the order level.
--
-- max_seller_distance_km is available only when valid
-- geolocation exists for every seller in the order.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW
    analytics.dashboard_order_geography AS

WITH order_geo AS (
    SELECT
        order_id,

        COUNT(*) AS seller_pairs_count,

        COUNT(*) FILTER (
            WHERE has_valid_geolocation
        ) AS valid_geo_pairs_count,

        MAX(distance_km) FILTER (
            WHERE has_valid_geolocation
        ) AS max_seller_distance_km,

        AVG(distance_km) FILTER (
            WHERE has_valid_geolocation
        ) AS avg_seller_distance_km

    FROM analytics.dashboard_order_sellers

    GROUP BY
        order_id
)

SELECT
    order_id,

    seller_pairs_count,
    valid_geo_pairs_count,

    (
        seller_pairs_count
        = valid_geo_pairs_count
    ) AS has_complete_geolocation,

    CASE
        WHEN seller_pairs_count
             = valid_geo_pairs_count
        THEN max_seller_distance_km
    END AS max_seller_distance_km,

    CASE
        WHEN seller_pairs_count
             = valid_geo_pairs_count
        THEN avg_seller_distance_km
    END AS avg_seller_distance_km

FROM order_geo;

-- ------------------------------------------------------------
-- 5. Payments dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 payment record
--
-- Used for payment-method and installment analysis.
--
-- One order may have multiple payment records, therefore
-- payment-level metrics must not be interpreted as order-level
-- metrics without additional aggregation or filtering.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW
    analytics.dashboard_payments AS

WITH payment_counts AS (
    SELECT
        order_id,

        COUNT(*) AS payment_records_count

    FROM analytics.payments

    GROUP BY
        order_id
)

SELECT
    -- --------------------------------------------------------
    -- Keys
    -- --------------------------------------------------------

    p.order_id,
    p.payment_sequential,


    -- --------------------------------------------------------
    -- Payment
    -- --------------------------------------------------------

    p.payment_type,
    p.payment_installments,
    p.payment_value,

    pc.payment_records_count,

    (
        pc.payment_records_count = 1
    ) AS is_single_payment_order,


    -- --------------------------------------------------------
    -- Installment data quality
    -- --------------------------------------------------------

    (
        p.payment_type = 'credit_card'
        AND p.payment_installments > 0
    ) AS has_valid_installments,

    (
        p.payment_type = 'credit_card'
        AND (
            p.payment_installments IS NULL
            OR p.payment_installments <= 0
        )
    ) AS has_invalid_installments

FROM analytics.payments AS p

JOIN payment_counts AS pc
    USING (order_id);

-- ------------------------------------------------------------
-- 6. Installment-order dashboard view
-- ------------------------------------------------------------
--
-- Grain:
--     1 row = 1 order
--
-- Contains the same analytical sample used for the statistical
-- installment analysis:
--
-- - delivered orders only;
-- - exactly one payment record per order;
-- - credit-card payments only;
-- - payment_installments > 0;
-- - order-level product value is aggregated before joining.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW
    analytics.dashboard_installment_orders AS

WITH single_payment_orders AS (
    SELECT
        p.order_id

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id

    HAVING COUNT(*) = 1
),

order_product_value AS (
    SELECT
        order_id,

        SUM(price) AS product_gmv

    FROM analytics.order_items

    GROUP BY
        order_id
)

SELECT
    -- --------------------------------------------------------
    -- Order
    -- --------------------------------------------------------

    p.order_id,

    o.order_purchase_timestamp::date
        AS order_purchase_date,

    DATE_TRUNC(
        'month',
        o.order_purchase_timestamp
    )::date AS order_month,


    -- --------------------------------------------------------
    -- Customer
    -- --------------------------------------------------------

    c.customer_unique_id,
    c.customer_state,


    -- --------------------------------------------------------
    -- Payment
    -- --------------------------------------------------------

    p.payment_installments AS installments,
    p.payment_value,


    -- --------------------------------------------------------
    -- Order product value
    -- --------------------------------------------------------

    opv.product_gmv

FROM analytics.payments AS p

JOIN single_payment_orders AS spo
    USING (order_id)

JOIN analytics.orders AS o
    USING (order_id)

JOIN analytics.customers AS c
    USING (customer_id)

JOIN order_product_value AS opv
    USING (order_id)

WHERE p.payment_type = 'credit_card'
  AND p.payment_installments > 0;