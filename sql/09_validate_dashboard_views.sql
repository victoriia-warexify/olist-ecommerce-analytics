\set ON_ERROR_STOP on

-- ============================================================
-- DASHBOARD VIEWS VALIDATION
-- ============================================================
--
-- Validates dashboard views against the analytical source
-- tables and checks that their documented grain is preserved.
-- ============================================================

-- ------------------------------------------------------------
-- 1. dashboard_orders
-- ------------------------------------------------------------

WITH source AS (
    SELECT
        COUNT(*) AS orders,
        COUNT(*) FILTER (
            WHERE order_status = 'delivered'
        ) AS delivered_orders,
        COUNT(*) FILTER (
            WHERE order_status = 'canceled'
        ) AS canceled_orders

    FROM analytics.orders
),

dashboard AS (
    SELECT
        COUNT(*) AS rows_count,
        COUNT(DISTINCT order_id) AS distinct_orders,

        COUNT(*) FILTER (
            WHERE is_delivered
        ) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE is_canceled
        ) AS canceled_orders

    FROM analytics.dashboard_orders
)

SELECT
    'dashboard_orders_row_count_matches'
        AS check_name,

    s.orders::NUMERIC
        AS expected_value,

    d.rows_count::NUMERIC
        AS actual_value,

    ABS(
        s.orders - d.rows_count
    )::NUMERIC AS difference,

    CASE
        WHEN s.orders = d.rows_count
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_orders_order_id_unique',

    d.rows_count::NUMERIC,
    d.distinct_orders::NUMERIC,

    ABS(
        d.rows_count - d.distinct_orders
    )::NUMERIC,

    CASE
        WHEN d.rows_count = d.distinct_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM dashboard AS d

UNION ALL

SELECT
    'dashboard_orders_delivered_count_matches',

    s.delivered_orders::NUMERIC,
    d.delivered_orders::NUMERIC,

    ABS(
        s.delivered_orders
        - d.delivered_orders
    )::NUMERIC,

    CASE
        WHEN s.delivered_orders
           = d.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_orders_canceled_count_matches',

    s.canceled_orders::NUMERIC,
    d.canceled_orders::NUMERIC,

    ABS(
        s.canceled_orders
        - d.canceled_orders
    )::NUMERIC,

    CASE
        WHEN s.canceled_orders
           = d.canceled_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

-- ------------------------------------------------------------
-- 1.2 dashboard_orders additive metrics
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value

    FROM analytics.payments

    GROUP BY
        order_id
),

source AS (
    SELECT
        SUM(oi.items_count) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS items_sold,

        SUM(oi.product_value) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS product_gmv,

        SUM(p.payment_value) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS total_payment_value

    FROM analytics.orders AS o

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)
),

dashboard AS (
    SELECT
        SUM(items_count) FILTER (
            WHERE is_delivered
        ) AS items_sold,

        SUM(product_value) FILTER (
            WHERE is_delivered
        ) AS product_gmv,

        SUM(total_payment_value) FILTER (
            WHERE is_delivered
        ) AS total_payment_value

    FROM analytics.dashboard_orders
)

SELECT
    'dashboard_orders_items_sold_matches'
        AS check_name,

    s.items_sold::NUMERIC
        AS expected_value,

    d.items_sold::NUMERIC
        AS actual_value,

    ABS(
        s.items_sold - d.items_sold
    )::NUMERIC AS difference,

    CASE
        WHEN s.items_sold = d.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_orders_product_gmv_matches',

    ROUND(s.product_gmv, 2),
    ROUND(d.product_gmv, 2),

    ROUND(
        ABS(
            s.product_gmv
            - d.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(s.product_gmv, 2)
           = ROUND(d.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_orders_payment_value_matches',

    ROUND(s.total_payment_value, 2),
    ROUND(d.total_payment_value, 2),

    ROUND(
        ABS(
            s.total_payment_value
            - d.total_payment_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.total_payment_value, 2)
           = ROUND(d.total_payment_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

-- ------------------------------------------------------------
-- 2. dashboard_order_categories
-- ------------------------------------------------------------

WITH grain_check AS (
    SELECT
        COUNT(*) AS rows_count,

        COUNT(
            DISTINCT (
                order_id,
                product_category_name
            )
        ) AS distinct_pairs

    FROM analytics.dashboard_order_categories
),

source AS (
    SELECT
        COUNT(*) AS items_count,
        SUM(price) AS product_value,
        SUM(freight_value) AS freight_value

    FROM analytics.order_items
),

dashboard AS (
    SELECT
        SUM(items_count) AS items_count,
        SUM(product_value) AS product_value,
        SUM(freight_value) AS freight_value

    FROM analytics.dashboard_order_categories
)

SELECT
    'dashboard_categories_grain_unique'
        AS check_name,

    g.rows_count::NUMERIC,
    g.distinct_pairs::NUMERIC,

    ABS(
        g.rows_count - g.distinct_pairs
    )::NUMERIC AS difference,

    CASE
        WHEN g.rows_count = g.distinct_pairs
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM grain_check AS g

UNION ALL

SELECT
    'dashboard_categories_items_match',

    s.items_count::NUMERIC,
    d.items_count::NUMERIC,

    ABS(
        s.items_count - d.items_count
    )::NUMERIC,

    CASE
        WHEN s.items_count = d.items_count
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_categories_product_value_matches',

    ROUND(s.product_value, 2),
    ROUND(d.product_value, 2),

    ROUND(
        ABS(
            s.product_value
            - d.product_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.product_value, 2)
           = ROUND(d.product_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_categories_freight_matches',

    ROUND(s.freight_value, 2),
    ROUND(d.freight_value, 2),

    ROUND(
        ABS(
            s.freight_value
            - d.freight_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.freight_value, 2)
           = ROUND(d.freight_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

-- ------------------------------------------------------------
-- 3. dashboard_order_sellers
-- ------------------------------------------------------------

WITH grain_check AS (
    SELECT
        COUNT(*) AS rows_count,

        COUNT(
            DISTINCT (
                order_id,
                seller_id
            )
        ) AS distinct_pairs

    FROM analytics.dashboard_order_sellers
),

source AS (
    SELECT
        COUNT(*) AS items_count,
        SUM(price) AS product_value,
        SUM(freight_value) AS freight_value

    FROM analytics.order_items
),

dashboard AS (
    SELECT
        SUM(items_count) AS items_count,
        SUM(product_value) AS product_value,
        SUM(freight_value) AS freight_value

    FROM analytics.dashboard_order_sellers
)

SELECT
    'dashboard_sellers_grain_unique'
        AS check_name,

    g.rows_count::NUMERIC,
    g.distinct_pairs::NUMERIC,

    ABS(
        g.rows_count - g.distinct_pairs
    )::NUMERIC AS difference,

    CASE
        WHEN g.rows_count = g.distinct_pairs
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM grain_check AS g

UNION ALL

SELECT
    'dashboard_sellers_items_match',

    s.items_count::NUMERIC,
    d.items_count::NUMERIC,

    ABS(
        s.items_count - d.items_count
    )::NUMERIC,

    CASE
        WHEN s.items_count = d.items_count
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_sellers_product_value_matches',

    ROUND(s.product_value, 2),
    ROUND(d.product_value, 2),

    ROUND(
        ABS(
            s.product_value
            - d.product_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.product_value, 2)
           = ROUND(d.product_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_sellers_freight_matches',

    ROUND(s.freight_value, 2),
    ROUND(d.freight_value, 2),

    ROUND(
        ABS(
            s.freight_value
            - d.freight_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.freight_value, 2)
           = ROUND(d.freight_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

-- ------------------------------------------------------------
-- 4. Geography consistency
-- ------------------------------------------------------------

SELECT
    'seller_geo_flag_distance_consistent'
        AS check_name,

    0::NUMERIC AS expected_value,

    COUNT(*) FILTER (
        WHERE
            (
                has_valid_geolocation
                AND distance_km IS NULL
            )
            OR
            (
                NOT has_valid_geolocation
                AND distance_km IS NOT NULL
            )
    )::NUMERIC AS actual_value,

    COUNT(*) FILTER (
        WHERE
            (
                has_valid_geolocation
                AND distance_km IS NULL
            )
            OR
            (
                NOT has_valid_geolocation
                AND distance_km IS NOT NULL
            )
    )::NUMERIC AS difference,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE
                (
                    has_valid_geolocation
                    AND distance_km IS NULL
                )
                OR
                (
                    NOT has_valid_geolocation
                    AND distance_km IS NOT NULL
                )
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.dashboard_order_sellers

UNION ALL

SELECT
    'negative_distance',

    0::NUMERIC,

    COUNT(*) FILTER (
        WHERE distance_km < 0
    )::NUMERIC,

    COUNT(*) FILTER (
        WHERE distance_km < 0
    )::NUMERIC,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE distance_km < 0
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM analytics.dashboard_order_sellers;

-- ------------------------------------------------------------
-- 4.2 dashboard_order_geography
-- ------------------------------------------------------------

WITH grain_check AS (
    SELECT
        COUNT(*) AS rows_count,
        COUNT(DISTINCT order_id) AS distinct_orders

    FROM analytics.dashboard_order_geography
),

consistency AS (
    SELECT
        COUNT(*) FILTER (
            WHERE
                (
                    has_complete_geolocation
                    AND max_seller_distance_km IS NULL
                )
                OR
                (
                    NOT has_complete_geolocation
                    AND max_seller_distance_km IS NOT NULL
                )
        ) AS violations

    FROM analytics.dashboard_order_geography
)

SELECT
    'dashboard_order_geography_grain_unique'
        AS check_name,

    g.rows_count::NUMERIC,
    g.distinct_orders::NUMERIC,

    ABS(
        g.rows_count - g.distinct_orders
    )::NUMERIC AS difference,

    CASE
        WHEN g.rows_count = g.distinct_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM grain_check AS g

UNION ALL

SELECT
    'dashboard_order_geography_complete_flag_consistent',

    0::NUMERIC,
    c.violations::NUMERIC,
    c.violations::NUMERIC,

    CASE
        WHEN c.violations = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM consistency AS c;

-- ------------------------------------------------------------
-- 5. dashboard_payments
-- ------------------------------------------------------------

WITH source AS (
    SELECT
        COUNT(*) AS records,
        SUM(payment_value) AS payment_value

    FROM analytics.payments
),

dashboard AS (
    SELECT
        COUNT(*) AS records,

        COUNT(
            DISTINCT (
                order_id,
                payment_sequential
            )
        ) AS distinct_records,

        SUM(payment_value) AS payment_value

    FROM analytics.dashboard_payments
)

SELECT
    'dashboard_payments_record_count_matches'
        AS check_name,

    s.records::NUMERIC,
    d.records::NUMERIC,

    ABS(
        s.records - d.records
    )::NUMERIC AS difference,

    CASE
        WHEN s.records = d.records
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_payments_grain_unique',

    d.records::NUMERIC,
    d.distinct_records::NUMERIC,

    ABS(
        d.records - d.distinct_records
    )::NUMERIC,

    CASE
        WHEN d.records = d.distinct_records
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM dashboard AS d

UNION ALL

SELECT
    'dashboard_payments_value_matches',

    ROUND(s.payment_value, 2),
    ROUND(d.payment_value, 2),

    ROUND(
        ABS(
            s.payment_value
            - d.payment_value
        ),
        2
    ),

    CASE
        WHEN ROUND(s.payment_value, 2)
           = ROUND(d.payment_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

-- ------------------------------------------------------------
-- 6. dashboard_installment_orders
-- ------------------------------------------------------------

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
),

source AS (
    SELECT
        COUNT(*) AS orders,
        SUM(opv.product_gmv) AS product_gmv

    FROM analytics.payments AS p

    JOIN single_payment_orders AS spo
        USING (order_id)

    JOIN order_product_value AS opv
        USING (order_id)

    WHERE p.payment_type = 'credit_card'
      AND p.payment_installments > 0
),

dashboard AS (
    SELECT
        COUNT(*) AS rows_count,
        COUNT(DISTINCT order_id) AS distinct_orders,
        SUM(product_gmv) AS product_gmv

    FROM analytics.dashboard_installment_orders
)

SELECT
    'dashboard_installments_order_count_matches'
        AS check_name,

    s.orders::NUMERIC,
    d.rows_count::NUMERIC,

    ABS(
        s.orders - d.rows_count
    )::NUMERIC AS difference,

    CASE
        WHEN s.orders = d.rows_count
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM source AS s
CROSS JOIN dashboard AS d

UNION ALL

SELECT
    'dashboard_installments_order_id_unique',

    d.rows_count::NUMERIC,
    d.distinct_orders::NUMERIC,

    ABS(
        d.rows_count
        - d.distinct_orders
    )::NUMERIC,

    CASE
        WHEN d.rows_count = d.distinct_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM dashboard AS d

UNION ALL

SELECT
    'dashboard_installments_gmv_matches',

    ROUND(s.product_gmv, 2),
    ROUND(d.product_gmv, 2),

    ROUND(
        ABS(
            s.product_gmv
            - d.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(s.product_gmv, 2)
           = ROUND(d.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM source AS s
CROSS JOIN dashboard AS d;

