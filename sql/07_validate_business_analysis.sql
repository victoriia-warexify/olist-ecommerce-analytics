\set ON_ERROR_STOP on

-- ============================================================
-- BUSINESS ANALYSIS VALIDATION
-- ============================================================

-- This file validates the assumptions and consistency
-- of metrics calculated in 06_business_analysis.sql.
--
-- Unless stated otherwise, a validation check should return:
--
-- violations = 0
-- status     = PASS


-- ------------------------------------------------------------
-- 1. General business metrics validation
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 1.1 Reference totals
-- ------------------------------------------------------------

-- These totals are used as reference values for later
-- validation checks.

WITH delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
),

order_items_agg AS (
    SELECT
        oi.order_id,

        COUNT(*) AS items_count,

        SUM(oi.price)
            AS product_value

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.order_id
),

payments_agg AS (
    SELECT
        p.order_id,

        SUM(p.payment_value)
            AS payment_value

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id
),

customer_orders AS (
    SELECT
        customer_unique_id,

        COUNT(*) AS orders_count

    FROM delivered_orders

    GROUP BY
        customer_unique_id
)

SELECT
    -- Orders
    (
        SELECT COUNT(*)
        FROM delivered_orders
    ) AS delivered_orders,

    -- Customers
    (
        SELECT COUNT(*)
        FROM customer_orders
    ) AS delivered_customers,

    (
        SELECT COUNT(*)
        FROM customer_orders
        WHERE orders_count > 1
    ) AS repeat_customers,

    -- Items
    (
        SELECT SUM(items_count)
        FROM order_items_agg
    ) AS items_sold,

    -- Financial metrics
    ROUND(
        (
            SELECT SUM(product_value)
            FROM order_items_agg
        ),
        2
    ) AS product_gmv,

    ROUND(
        (
            SELECT SUM(payment_value)
            FROM payments_agg
        ),
        2
    ) AS total_payment_value;


-- ------------------------------------------------------------
-- 1.2 Delivered-order coverage and grain checks
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

payments_agg AS (
    SELECT
        order_id,

        SUM(payment_value)
            AS payment_value

    FROM analytics.payments

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
),

joined_orders AS (
    SELECT
        d.order_id,
        d.customer_unique_id,

        oi.items_count,
        oi.product_value,

        p.payment_value

    FROM delivered_orders AS d

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)
)

SELECT
    'delivered_orders_without_items'
        AS check_name,

    COUNT(*) FILTER (
        WHERE items_count IS NULL
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE items_count IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM joined_orders

UNION ALL

SELECT
    'delivered_orders_without_payment'
        AS check_name,

    COUNT(*) FILTER (
        WHERE payment_value IS NULL
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE payment_value IS NULL
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE payment_value IS NULL
        ) = 1
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END AS status

FROM joined_orders

UNION ALL

SELECT
    'delivered_orders_without_customer_unique_id'
        AS check_name,

    COUNT(*) FILTER (
        WHERE customer_unique_id IS NULL
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE customer_unique_id IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM joined_orders

UNION ALL

SELECT
    'order_level_join_duplicates'
        AS check_name,

    COUNT(*) - COUNT(DISTINCT order_id)
        AS violations,

    CASE
        WHEN COUNT(*) = COUNT(DISTINCT order_id)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM joined_orders;

-- ------------------------------------------------------------
-- 2. Monthly business dynamics validation
-- ------------------------------------------------------------

-- Monthly additive metrics must reconcile with the
-- corresponding overall metrics.


-- ------------------------------------------------------------
-- 2.1 Monthly totals reconciliation
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

payments_agg AS (
    SELECT
        order_id,

        SUM(payment_value)
            AS payment_value

    FROM analytics.payments

    GROUP BY
        order_id
),

order_level AS (
    SELECT
        o.order_id,

        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        o.order_status,

        c.customer_unique_id,

        oi.items_count,
        oi.product_value,

        p.payment_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)
),

overall_metrics AS (
    SELECT
        COUNT(*) AS total_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'delivered'
        ) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'canceled'
        ) AS canceled_orders,

        COALESCE(
            SUM(items_count) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS items_sold,

        COALESCE(
            SUM(product_value) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS product_gmv,

        COALESCE(
            SUM(payment_value) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS total_payment_value

    FROM order_level
),

monthly_metrics AS (
    SELECT
        month,

        COUNT(*) AS total_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'delivered'
        ) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'canceled'
        ) AS canceled_orders,

        COALESCE(
            SUM(items_count) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS items_sold,

        COALESCE(
            SUM(product_value) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS product_gmv,

        COALESCE(
            SUM(payment_value) FILTER (
                WHERE order_status = 'delivered'
            ),
            0
        ) AS total_payment_value

    FROM order_level

    GROUP BY
        month
),

monthly_totals AS (
    SELECT
        SUM(total_orders)
            AS total_orders,

        SUM(delivered_orders)
            AS delivered_orders,

        SUM(canceled_orders)
            AS canceled_orders,

        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv,

        SUM(total_payment_value)
            AS total_payment_value

    FROM monthly_metrics
)

SELECT
    'monthly_total_orders_match_overall'
        AS check_name,

    o.total_orders::NUMERIC
        AS expected_value,

    m.total_orders::NUMERIC
        AS actual_value,

    ABS(
        o.total_orders - m.total_orders
    )::NUMERIC AS difference,

    CASE
        WHEN o.total_orders = m.total_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_delivered_orders_match_overall',

    o.delivered_orders::NUMERIC,

    m.delivered_orders::NUMERIC,

    ABS(
        o.delivered_orders - m.delivered_orders
    )::NUMERIC,

    CASE
        WHEN o.delivered_orders = m.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_canceled_orders_match_overall',

    o.canceled_orders::NUMERIC,

    m.canceled_orders::NUMERIC,

    ABS(
        o.canceled_orders - m.canceled_orders
    )::NUMERIC,

    CASE
        WHEN o.canceled_orders = m.canceled_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_items_sold_match_overall',

    o.items_sold::NUMERIC,

    m.items_sold::NUMERIC,

    ABS(
        o.items_sold - m.items_sold
    )::NUMERIC,

    CASE
        WHEN o.items_sold = m.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_product_gmv_matches_overall',

    ROUND(
        o.product_gmv,
        2
    ),

    ROUND(
        m.product_gmv,
        2
    ),

    ROUND(
        ABS(
            o.product_gmv - m.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(o.product_gmv, 2)
           = ROUND(m.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_payment_value_matches_overall',

    ROUND(
        o.total_payment_value,
        2
    ),

    ROUND(
        m.total_payment_value,
        2
    ),

    ROUND(
        ABS(
            o.total_payment_value
            - m.total_payment_value
        ),
        2
    ),

    CASE
        WHEN ROUND(o.total_payment_value, 2)
           = ROUND(m.total_payment_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM overall_metrics AS o

CROSS JOIN monthly_totals AS m;


-- ------------------------------------------------------------
-- 3. Product and category analysis validation
-- ------------------------------------------------------------

-- Item counts and product GMV are additive across categories
-- and products and must reconcile with overall delivered totals.
--
-- Order counts are NOT additive across categories or products,
-- because one order can contain multiple categories/products.


-- ------------------------------------------------------------
-- 3.1 Category and product totals reconciliation
-- ------------------------------------------------------------

WITH reference_metrics AS (
    SELECT
        COUNT(*) AS items_sold,

        SUM(oi.price)
            AS product_gmv

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

delivered_items AS (
    SELECT
        oi.order_id,
        oi.product_id,
        oi.price,

        COALESCE(
            c.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.products AS p
        USING (product_id)

    LEFT JOIN analytics.categories AS c
        USING (product_category_name)

    WHERE o.order_status = 'delivered'
),

category_metrics AS (
    SELECT
        category,

        COUNT(*) AS items_sold,

        SUM(price)
            AS product_gmv

    FROM delivered_items

    GROUP BY
        category
),

product_metrics AS (
    SELECT
        product_id,
        category,

        COUNT(*) AS items_sold,

        SUM(price)
            AS product_gmv

    FROM delivered_items

    GROUP BY
        product_id,
        category
),

category_totals AS (
    SELECT
        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM category_metrics
),

product_totals AS (
    SELECT
        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM product_metrics
)

SELECT
    'category_items_match_overall'
        AS check_name,

    r.items_sold::NUMERIC
        AS expected_value,

    c.items_sold::NUMERIC
        AS actual_value,

    ABS(
        r.items_sold - c.items_sold
    )::NUMERIC AS difference,

    CASE
        WHEN r.items_sold = c.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN category_totals AS c

UNION ALL

SELECT
    'category_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        c.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - c.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(c.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN category_totals AS c

UNION ALL

SELECT
    'product_items_match_overall',

    r.items_sold::NUMERIC,

    p.items_sold::NUMERIC,

    ABS(
        r.items_sold - p.items_sold
    )::NUMERIC,

    CASE
        WHEN r.items_sold = p.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN product_totals AS p

UNION ALL

SELECT
    'product_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        p.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - p.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(p.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN product_totals AS p;

-- ------------------------------------------------------------
-- 3.2 Product/category grain and review checks
-- ------------------------------------------------------------

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.product_id,

        COALESCE(
            c.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.products AS p
        USING (product_id)

    LEFT JOIN analytics.categories AS c
        USING (product_category_name)

    WHERE o.order_status = 'delivered'
),

product_category_counts AS (
    SELECT
        product_id,

        COUNT(DISTINCT category)
            AS category_count

    FROM delivered_items

    GROUP BY
        product_id
),

category_sales AS (
    SELECT
        category,

        COUNT(DISTINCT order_id)
            AS orders

    FROM delivered_items

    GROUP BY
        category
),

product_sales AS (
    SELECT
        product_id,

        COUNT(DISTINCT order_id)
            AS orders

    FROM delivered_items

    GROUP BY
        product_id
),

order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

category_order_reviews AS (
    SELECT DISTINCT
        di.category,
        di.order_id,
        r.avg_order_review_score

    FROM delivered_items AS di

    LEFT JOIN order_reviews AS r
        USING (order_id)
),

category_reviews AS (
    SELECT
        category,

        COUNT(avg_order_review_score)
            AS orders_with_review

    FROM category_order_reviews

    GROUP BY
        category
),

product_order_reviews AS (
    SELECT DISTINCT
        di.product_id,
        di.order_id,
        r.avg_order_review_score

    FROM delivered_items AS di

    LEFT JOIN order_reviews AS r
        USING (order_id)
),

product_reviews AS (
    SELECT
        product_id,

        COUNT(avg_order_review_score)
            AS orders_with_review

    FROM product_order_reviews

    GROUP BY
        product_id
)

SELECT
    'products_mapped_to_multiple_categories'
        AS check_name,

    COUNT(*) AS violations,

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM product_category_counts

WHERE category_count > 1

UNION ALL

SELECT
    'category_review_coverage_exceeds_orders',

    COUNT(*),

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM category_sales AS cs

JOIN category_reviews AS cr
    USING (category)

WHERE cr.orders_with_review > cs.orders

UNION ALL

SELECT
    'product_review_coverage_exceeds_orders',

    COUNT(*),

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM product_sales AS ps

JOIN product_reviews AS pr
    USING (product_id)

WHERE pr.orders_with_review > ps.orders;

-- ------------------------------------------------------------
-- 4. Customer analysis validation
-- ------------------------------------------------------------

-- Customer-level metrics use customer_unique_id.
-- Customer behavior and value metrics use delivered orders only.


-- ------------------------------------------------------------
-- 4.1 Purchase frequency validation
-- ------------------------------------------------------------

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,

        COUNT(*) AS delivered_orders_count

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        c.customer_unique_id
),

frequency_distribution AS (
    SELECT
        CASE
            WHEN delivered_orders_count = 1 THEN '1 order'
            WHEN delivered_orders_count = 2 THEN '2 orders'
            WHEN delivered_orders_count = 3 THEN '3 orders'
            ELSE '4+ orders'
        END AS order_frequency,

        COUNT(*) AS customers

    FROM customer_orders

    GROUP BY
        CASE
            WHEN delivered_orders_count = 1 THEN '1 order'
            WHEN delivered_orders_count = 2 THEN '2 orders'
            WHEN delivered_orders_count = 3 THEN '3 orders'
            ELSE '4+ orders'
        END
),

reference_metrics AS (
    SELECT
        COUNT(*) AS delivered_customers,

        SUM(delivered_orders_count)
            AS delivered_orders,

        COUNT(*) FILTER (
            WHERE delivered_orders_count > 1
        ) AS repeat_customers

    FROM customer_orders
),

frequency_metrics AS (
    SELECT
        SUM(customers)
            AS delivered_customers,

        SUM(customers) FILTER (
            WHERE order_frequency <> '1 order'
        ) AS repeat_customers

    FROM frequency_distribution
)

SELECT
    'frequency_customers_match'
        AS check_name,

    r.delivered_customers::NUMERIC
        AS expected_value,

    f.delivered_customers::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_customers
        - f.delivered_customers
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_customers
           = f.delivered_customers
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN frequency_metrics AS f

UNION ALL

SELECT
    'frequency_repeat_customers_match',

    r.repeat_customers::NUMERIC,

    f.repeat_customers::NUMERIC,

    ABS(
        r.repeat_customers
        - f.repeat_customers
    )::NUMERIC,

    CASE
        WHEN r.repeat_customers
           = f.repeat_customers
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN frequency_metrics AS f

UNION ALL

SELECT
    'customer_order_counts_match_delivered_orders',

    (
        SELECT COUNT(*)
        FROM analytics.orders
        WHERE order_status = 'delivered'
    )::NUMERIC,

    r.delivered_orders::NUMERIC,

    ABS(
        (
            SELECT COUNT(*)
            FROM analytics.orders
            WHERE order_status = 'delivered'
        )
        - r.delivered_orders
    )::NUMERIC,

    CASE
        WHEN (
            SELECT COUNT(*)
            FROM analytics.orders
            WHERE order_status = 'delivered'
        ) = r.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r;


-- ------------------------------------------------------------
-- 4.2 Customer value reconciliation
-- ------------------------------------------------------------

-- Customer-level additive totals must reconcile with
-- overall delivered-order totals.

WITH order_items_agg AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

payments_agg AS (
    SELECT
        order_id,

        SUM(payment_value)
            AS payment_value

    FROM analytics.payments

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,

        oi.items_count,
        oi.product_value,

        p.payment_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

customer_metrics AS (
    SELECT
        customer_unique_id,

        COUNT(*) AS delivered_orders_count,

        SUM(items_count)
            AS items_bought,

        SUM(product_value)
            AS customer_gmv,

        SUM(payment_value)
            AS customer_payment_value

    FROM delivered_orders

    GROUP BY
        customer_unique_id
),

reference_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(DISTINCT customer_unique_id)
            AS delivered_customers,

        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv,

        SUM(payment_value)
            AS total_payment_value

    FROM delivered_orders
),

customer_totals AS (
    SELECT
        COUNT(*) AS delivered_customers,

        SUM(delivered_orders_count)
            AS delivered_orders,

        SUM(items_bought)
            AS items_sold,

        SUM(customer_gmv)
            AS product_gmv,

        SUM(customer_payment_value)
            AS total_payment_value

    FROM customer_metrics
)

SELECT
    'customer_count_matches_overall'
        AS check_name,

    r.delivered_customers::NUMERIC
        AS expected_value,

    c.delivered_customers::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_customers
        - c.delivered_customers
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_customers
           = c.delivered_customers
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN customer_totals AS c

UNION ALL

SELECT
    'customer_orders_match_overall',

    r.delivered_orders::NUMERIC,

    c.delivered_orders::NUMERIC,

    ABS(
        r.delivered_orders
        - c.delivered_orders
    )::NUMERIC,

    CASE
        WHEN r.delivered_orders
           = c.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN customer_totals AS c

UNION ALL

SELECT
    'customer_items_match_overall',

    r.items_sold::NUMERIC,

    c.items_sold::NUMERIC,

    ABS(
        r.items_sold
        - c.items_sold
    )::NUMERIC,

    CASE
        WHEN r.items_sold
           = c.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN customer_totals AS c

UNION ALL

SELECT
    'customer_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        c.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - c.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(c.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN customer_totals AS c


UNION ALL


SELECT
    'customer_payment_value_matches_overall',

    ROUND(
        r.total_payment_value,
        2
    ),

    ROUND(
        c.total_payment_value,
        2
    ),

    ROUND(
        ABS(
            r.total_payment_value
            - c.total_payment_value
        ),
        2
    ),

    CASE
        WHEN ROUND(r.total_payment_value, 2)
           = ROUND(c.total_payment_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN customer_totals AS c;


-- ------------------------------------------------------------
-- 4.3 New vs returning buyers validation
-- ------------------------------------------------------------

WITH customer_months AS (
    SELECT DISTINCT
        c.customer_unique_id,

        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
),

first_observed_purchase AS (
    SELECT
        customer_unique_id,

        MIN(month)
            AS first_order_month

    FROM customer_months

    GROUP BY
        customer_unique_id
),

monthly_customers AS (
    SELECT
        cm.month,

        COUNT(*) AS monthly_active_buyers,

        COUNT(*) FILTER (
            WHERE cm.month = fp.first_order_month
        ) AS new_buyers,

        COUNT(*) FILTER (
            WHERE cm.month > fp.first_order_month
        ) AS returning_buyers

    FROM customer_months AS cm

    JOIN first_observed_purchase AS fp
        USING (customer_unique_id)

    GROUP BY
        cm.month
)

SELECT
    'monthly_active_equals_new_plus_returning'
        AS check_name,

    COUNT(*) FILTER (
        WHERE monthly_active_buyers
              <> new_buyers + returning_buyers
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE monthly_active_buyers
                  <> new_buyers + returning_buyers
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM monthly_customers

UNION ALL

SELECT
    'each_customer_is_new_exactly_once',

    ABS(
        (
            SELECT COUNT(*)
            FROM first_observed_purchase
        )
        -
        (
            SELECT SUM(new_buyers)
            FROM monthly_customers
        )
    ) AS violations,

    CASE
        WHEN (
            SELECT COUNT(*)
            FROM first_observed_purchase
        )
        =
        (
            SELECT SUM(new_buyers)
            FROM monthly_customers
        )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status;


-- ------------------------------------------------------------
-- 4.4 Cohort retention validation
-- ------------------------------------------------------------

WITH customer_months AS (
    SELECT DISTINCT
        c.customer_unique_id,

        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS activity_month

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
),

customer_cohorts AS (
    SELECT
        customer_unique_id,

        MIN(activity_month)
            AS cohort_month

    FROM customer_months

    GROUP BY
        customer_unique_id
),

cohort_sizes AS (
    SELECT
        cohort_month,

        COUNT(*) AS cohort_size

    FROM customer_cohorts

    GROUP BY
        cohort_month
),

cohort_activity AS (
    SELECT
        cc.cohort_month,

        (
            EXTRACT(
                YEAR FROM AGE(
                    cm.activity_month,
                    cc.cohort_month
                )
            ) * 12
            +
            EXTRACT(
                MONTH FROM AGE(
                    cm.activity_month,
                    cc.cohort_month
                )
            )
        )::INTEGER AS month_number,

        COUNT(*) AS active_customers

    FROM customer_months AS cm

    JOIN customer_cohorts AS cc
        USING (customer_unique_id)

    GROUP BY
        cc.cohort_month,
        month_number
),

cohort_validation AS (
    SELECT
        ca.cohort_month,
        ca.month_number,
        ca.active_customers,
        cs.cohort_size

    FROM cohort_activity AS ca

    JOIN cohort_sizes AS cs
        USING (cohort_month)
)

SELECT
    'cohort_month_zero_equals_cohort_size'
        AS check_name,

    COUNT(*) FILTER (
        WHERE month_number = 0
          AND active_customers <> cohort_size
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE month_number = 0
              AND active_customers <> cohort_size
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM cohort_validation

UNION ALL

SELECT
    'cohort_active_customers_exceed_size',

    COUNT(*) FILTER (
        WHERE active_customers > cohort_size
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE active_customers > cohort_size
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM cohort_validation

UNION ALL

SELECT
    'negative_cohort_month_number',

    COUNT(*) FILTER (
        WHERE month_number < 0
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE month_number < 0
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM cohort_validation

UNION ALL

SELECT
    'cohort_customers_match_delivered_customers',

    ABS(
        (
            SELECT SUM(cohort_size)
            FROM cohort_sizes
        )
        -
        (
            SELECT COUNT(*)
            FROM customer_cohorts
        )
    ),

    CASE
        WHEN (
            SELECT SUM(cohort_size)
            FROM cohort_sizes
        )
        =
        (
            SELECT COUNT(*)
            FROM customer_cohorts
        )
        THEN 'PASS'
        ELSE 'FAIL'
    END;


-- ------------------------------------------------------------
-- 4.5 RFM validation
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,

        o.order_purchase_timestamp::date
            AS order_date,

        oi.product_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

analysis_date AS (
    SELECT
        MAX(order_date) + 1
            AS analysis_date

    FROM delivered_orders
),

rfm AS (
    SELECT
        d.customer_unique_id,

        (
            SELECT analysis_date
            FROM analysis_date
        ) - MAX(d.order_date)
            AS recency_days,

        COUNT(*) AS frequency,

        SUM(d.product_value)
            AS monetary

    FROM delivered_orders AS d

    GROUP BY
        d.customer_unique_id
),

reference_metrics AS (
    SELECT
        COUNT(DISTINCT customer_unique_id)
            AS delivered_customers,

        COUNT(*) AS delivered_orders,

        SUM(product_value)
            AS product_gmv

    FROM delivered_orders
),

rfm_totals AS (
    SELECT
        COUNT(*) AS customers,

        SUM(frequency)
            AS frequency,

        SUM(monetary)
            AS monetary

    FROM rfm
)

SELECT
    'rfm_customer_count_matches'
        AS check_name,

    r.delivered_customers::NUMERIC
        AS expected_value,

    t.customers::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_customers
        - t.customers
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_customers
           = t.customers
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN rfm_totals AS t

UNION ALL

SELECT
    'rfm_frequency_matches_delivered_orders',

    r.delivered_orders::NUMERIC,

    t.frequency::NUMERIC,

    ABS(
        r.delivered_orders
        - t.frequency
    )::NUMERIC,

    CASE
        WHEN r.delivered_orders
           = t.frequency
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN rfm_totals AS t

UNION ALL

SELECT
    'rfm_monetary_matches_product_gmv',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        t.monetary,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - t.monetary
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(t.monetary, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN rfm_totals AS t;


-- ------------------------------------------------------------
-- 4.6 RFM value checks
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,

        o.order_purchase_timestamp::date
            AS order_date,

        oi.product_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

analysis_date AS (
    SELECT
        MAX(order_date) + 1
            AS analysis_date

    FROM delivered_orders
),

rfm AS (
    SELECT
        d.customer_unique_id,

        (
            SELECT analysis_date
            FROM analysis_date
        ) - MAX(d.order_date)
            AS recency_days,

        COUNT(*) AS frequency,

        SUM(d.product_value)
            AS monetary

    FROM delivered_orders AS d

    GROUP BY
        d.customer_unique_id
)

SELECT
    'rfm_recency_less_than_one'
        AS check_name,

    COUNT(*) FILTER (
        WHERE recency_days < 1
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE recency_days < 1
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM rfm

UNION ALL

SELECT
    'rfm_frequency_less_than_one',

    COUNT(*) FILTER (
        WHERE frequency < 1
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE frequency < 1
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM rfm

UNION ALL

SELECT
    'rfm_null_monetary',

    COUNT(*) FILTER (
        WHERE monetary IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE monetary IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM rfm;

-- ------------------------------------------------------------
-- 5. Geographic analysis validation
-- ------------------------------------------------------------

-- Customer order, item and GMV totals are additive across
-- customer states and cities because every order has one
-- delivery location.
--
-- Unique customer counts are NOT necessarily additive across
-- states/cities because the same customer_unique_id can appear
-- at different delivery locations.
--
-- Seller item and GMV totals are additive across seller states.
-- Seller order counts are NOT additive because one order can
-- contain sellers from multiple states.


-- ------------------------------------------------------------
-- 5.1 Customer geography reconciliation
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,

        c.customer_state,
        c.customer_city,

        oi.items_count,
        oi.product_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS orders,

        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv

    FROM delivered_orders
),

state_metrics AS (
    SELECT
        customer_state,

        COUNT(*) AS orders,

        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv

    FROM delivered_orders

    GROUP BY
        customer_state
),

state_totals AS (
    SELECT
        SUM(orders)
            AS orders,

        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM state_metrics
),

city_metrics AS (
    SELECT
        customer_state,
        customer_city,

        COUNT(*) AS orders,

        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv

    FROM delivered_orders

    GROUP BY
        customer_state,
        customer_city
),

city_totals AS (
    SELECT
        SUM(orders)
            AS orders,

        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM city_metrics
)

SELECT
    'customer_state_orders_match_overall'
        AS check_name,

    r.orders::NUMERIC
        AS expected_value,

    s.orders::NUMERIC
        AS actual_value,

    ABS(
        r.orders - s.orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.orders = s.orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'customer_state_items_match_overall',

    r.items_sold::NUMERIC,

    s.items_sold::NUMERIC,

    ABS(
        r.items_sold - s.items_sold
    )::NUMERIC,

    CASE
        WHEN r.items_sold = s.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'customer_state_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        s.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - s.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(s.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'customer_city_orders_match_overall',

    r.orders::NUMERIC,

    c.orders::NUMERIC,

    ABS(
        r.orders - c.orders
    )::NUMERIC,

    CASE
        WHEN r.orders = c.orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN city_totals AS c

UNION ALL

SELECT
    'customer_city_items_match_overall',

    r.items_sold::NUMERIC,

    c.items_sold::NUMERIC,

    ABS(
        r.items_sold - c.items_sold
    )::NUMERIC,

    CASE
        WHEN r.items_sold = c.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN city_totals AS c

UNION ALL

SELECT
    'customer_city_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        c.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - c.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(c.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN city_totals AS c;


-- ------------------------------------------------------------
-- 5.2 Customer geography completeness
-- ------------------------------------------------------------

SELECT
    'delivered_orders_without_customer_state'
        AS check_name,

    COUNT(*) AS violations,

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.orders AS o

JOIN analytics.customers AS c
    USING (customer_id)

WHERE o.order_status = 'delivered'
  AND c.customer_state IS NULL

UNION ALL

SELECT
    'delivered_orders_without_customer_city',

    COUNT(*),

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM analytics.orders AS o

JOIN analytics.customers AS c
    USING (customer_id)

WHERE o.order_status = 'delivered'
  AND c.customer_city IS NULL;


-- ------------------------------------------------------------
-- 5.3 Seller geography reconciliation
-- ------------------------------------------------------------

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        oi.price,

        s.seller_state

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.sellers AS s
        USING (seller_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS items_sold,

        SUM(price)
            AS product_gmv

    FROM delivered_items
),

seller_state_metrics AS (
    SELECT
        seller_state,

        COUNT(*) AS items_sold,

        SUM(price)
            AS product_gmv

    FROM delivered_items

    GROUP BY
        seller_state
),

seller_state_totals AS (
    SELECT
        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM seller_state_metrics
)

SELECT
    'seller_state_items_match_overall'
        AS check_name,

    r.items_sold::NUMERIC
        AS expected_value,

    s.items_sold::NUMERIC
        AS actual_value,

    ABS(
        r.items_sold - s.items_sold
    )::NUMERIC AS difference,

    CASE
        WHEN r.items_sold = s.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN seller_state_totals AS s

UNION ALL

SELECT
    'seller_state_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        s.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - s.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(s.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN seller_state_totals AS s;


-- ------------------------------------------------------------
-- 5.4 Seller geography completeness
-- ------------------------------------------------------------

SELECT
    'delivered_items_without_seller_state'
        AS check_name,

    COUNT(*) AS violations,

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.order_items AS oi

JOIN analytics.orders AS o
    USING (order_id)

JOIN analytics.sellers AS s
    USING (seller_id)

WHERE o.order_status = 'delivered'
  AND s.seller_state IS NULL;


-- ------------------------------------------------------------
-- 5.5 Geolocation coverage and distance reconciliation
-- ------------------------------------------------------------

WITH order_seller_pairs AS (
    SELECT DISTINCT
        oi.order_id,
        oi.seller_id,
        o.customer_id

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

geolocation_coverage AS (
    SELECT
        COUNT(*) AS total_pairs,

        COUNT(*) FILTER (
            WHERE customer_geo.geolocation_zip_code_prefix IS NOT NULL
              AND seller_geo.geolocation_zip_code_prefix IS NOT NULL
        ) AS pairs_with_geolocation

    FROM order_seller_pairs AS osp

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
),

distances AS (
    SELECT
        osp.order_id,
        osp.seller_id,

        6371 * ACOS(
            LEAST(
                1.0,
                GREATEST(
                    -1.0,

                    COS(
                        RADIANS(
                            customer_geo.geolocation_lat
                        )
                    )
                    *
                    COS(
                        RADIANS(
                            seller_geo.geolocation_lat
                        )
                    )
                    *
                    COS(
                        RADIANS(
                            seller_geo.geolocation_lng
                            - customer_geo.geolocation_lng
                        )
                    )
                    +
                    SIN(
                        RADIANS(
                            customer_geo.geolocation_lat
                        )
                    )
                    *
                    SIN(
                        RADIANS(
                            seller_geo.geolocation_lat
                        )
                    )
                )
            )
        ) AS distance_km

    FROM order_seller_pairs AS osp

    JOIN analytics.customers AS c
        USING (customer_id)

    JOIN analytics.sellers AS s
        USING (seller_id)

    JOIN analytics.geolocation AS customer_geo
        ON c.customer_zip_code_prefix =
           customer_geo.geolocation_zip_code_prefix

    JOIN analytics.geolocation AS seller_geo
        ON s.seller_zip_code_prefix =
           seller_geo.geolocation_zip_code_prefix
),

distance_metrics AS (
    SELECT
        COUNT(distance_km)
            AS pairs_with_distance

    FROM distances
)

SELECT
    'geolocation_pairs_match_distance_pairs'
        AS check_name,

    g.pairs_with_geolocation::NUMERIC
        AS expected_value,

    d.pairs_with_distance::NUMERIC
        AS actual_value,

    ABS(
        g.pairs_with_geolocation
        - d.pairs_with_distance
    )::NUMERIC AS difference,

    CASE
        WHEN g.pairs_with_geolocation
           = d.pairs_with_distance
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM geolocation_coverage AS g

CROSS JOIN distance_metrics AS d;


-- ------------------------------------------------------------
-- 5.6 Distance value checks
-- ------------------------------------------------------------

WITH order_seller_pairs AS (
    SELECT DISTINCT
        oi.order_id,
        oi.seller_id,
        o.customer_id

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

distances AS (
    SELECT
        6371 * ACOS(
            LEAST(
                1.0,
                GREATEST(
                    -1.0,

                    COS(
                        RADIANS(
                            customer_geo.geolocation_lat
                        )
                    )
                    *
                    COS(
                        RADIANS(
                            seller_geo.geolocation_lat
                        )
                    )
                    *
                    COS(
                        RADIANS(
                            seller_geo.geolocation_lng
                            - customer_geo.geolocation_lng
                        )
                    )
                    +
                    SIN(
                        RADIANS(
                            customer_geo.geolocation_lat
                        )
                    )
                    *
                    SIN(
                        RADIANS(
                            seller_geo.geolocation_lat
                        )
                    )
                )
            )
        ) AS distance_km

    FROM order_seller_pairs AS osp

    JOIN analytics.customers AS c
        USING (customer_id)

    JOIN analytics.sellers AS s
        USING (seller_id)

    JOIN analytics.geolocation AS customer_geo
        ON c.customer_zip_code_prefix =
           customer_geo.geolocation_zip_code_prefix

    JOIN analytics.geolocation AS seller_geo
        ON s.seller_zip_code_prefix =
           seller_geo.geolocation_zip_code_prefix
)

SELECT
    'negative_customer_seller_distance'
        AS check_name,

    COUNT(*) FILTER (
        WHERE distance_km < 0
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE distance_km < 0
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM distances

UNION ALL

SELECT
    'distance_exceeds_half_earth_circumference',

    COUNT(*) FILTER (
        WHERE distance_km > PI() * 6371
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE distance_km > PI() * 6371
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM distances

UNION ALL

SELECT
    'null_distance_after_geo_join',

    COUNT(*) FILTER (
        WHERE distance_km IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE distance_km IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM distances;

-- ------------------------------------------------------------
-- 6. Seller analysis validation
-- ------------------------------------------------------------

-- Seller sales metrics use delivered orders only.
-- Item counts and product GMV are additive across sellers.
--
-- Order counts are NOT additive across sellers because one
-- order can contain multiple sellers.


-- ------------------------------------------------------------
-- 6.1 Seller totals reconciliation
-- ------------------------------------------------------------

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.seller_id,
        oi.product_id,
        oi.price

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(DISTINCT seller_id)
            AS active_sellers,

        COUNT(*)
            AS items_sold,

        SUM(price)
            AS product_gmv

    FROM delivered_items
),

seller_sales AS (
    SELECT
        seller_id,

        COUNT(DISTINCT order_id)
            AS orders,

        COUNT(*)
            AS items_sold,

        COUNT(DISTINCT product_id)
            AS sku_count,

        SUM(price)
            AS product_gmv

    FROM delivered_items

    GROUP BY
        seller_id
),

seller_totals AS (
    SELECT
        COUNT(*)
            AS active_sellers,

        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv

    FROM seller_sales
)

SELECT
    'seller_count_matches_overall'
        AS check_name,

    r.active_sellers::NUMERIC
        AS expected_value,

    s.active_sellers::NUMERIC
        AS actual_value,

    ABS(
        r.active_sellers
        - s.active_sellers
    )::NUMERIC AS difference,

    CASE
        WHEN r.active_sellers
           = s.active_sellers
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN seller_totals AS s

UNION ALL

SELECT
    'seller_items_match_overall',

    r.items_sold::NUMERIC,

    s.items_sold::NUMERIC,

    ABS(
        r.items_sold
        - s.items_sold
    )::NUMERIC,

    CASE
        WHEN r.items_sold
           = s.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN seller_totals AS s

UNION ALL

SELECT
    'seller_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        s.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - s.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(s.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN seller_totals AS s;


-- ------------------------------------------------------------
-- 6.2 Seller review validation
-- ------------------------------------------------------------

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.seller_id

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

seller_sales AS (
    SELECT
        seller_id,

        COUNT(DISTINCT order_id)
            AS orders

    FROM delivered_items

    GROUP BY
        seller_id
),

order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

seller_order_reviews AS (
    SELECT DISTINCT
        di.seller_id,
        di.order_id,
        r.avg_order_review_score

    FROM delivered_items AS di

    LEFT JOIN order_reviews AS r
        USING (order_id)
),

seller_reviews AS (
    SELECT
        seller_id,

        COUNT(avg_order_review_score)
            AS orders_with_review

    FROM seller_order_reviews

    GROUP BY
        seller_id
)

SELECT
    'seller_review_coverage_exceeds_orders'
        AS check_name,

    COUNT(*) AS violations,

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM seller_sales AS ss

JOIN seller_reviews AS sr
    USING (seller_id)

WHERE sr.orders_with_review > ss.orders;


-- ------------------------------------------------------------
-- 6.3 Seller GMV share validation
-- ------------------------------------------------------------

WITH seller_sales AS (
    SELECT
        oi.seller_id,

        SUM(oi.price)
            AS product_gmv

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.seller_id
),

seller_shares AS (
    SELECT
        seller_id,

        100.0
        * product_gmv
        / NULLIF(
            SUM(product_gmv) OVER (),
            0
        ) AS gmv_share

    FROM seller_sales
)

SELECT
    'seller_gmv_shares_sum_to_100'
        AS check_name,

    100.000000::NUMERIC
        AS expected_value,

    ROUND(
        SUM(gmv_share),
        6
    ) AS actual_value,

    ROUND(
        ABS(
            100.0 - SUM(gmv_share)
        ),
        6
    ) AS difference,

    CASE
        WHEN ROUND(
            SUM(gmv_share),
            6
        ) = 100.000000
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM seller_shares;


-- ------------------------------------------------------------
-- 6.4 Seller concentration validation
-- ------------------------------------------------------------

WITH seller_sales AS (
    SELECT
        oi.seller_id,

        SUM(oi.price)
            AS product_gmv

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.seller_id
),

seller_ranked AS (
    SELECT
        seller_id,
        product_gmv,

        ROW_NUMBER() OVER (
            ORDER BY
                product_gmv DESC,
                seller_id
        ) AS seller_rank,

        SUM(product_gmv) OVER ()
            AS total_gmv

    FROM seller_sales
),

concentration_metrics AS (
    SELECT
        COUNT(*) AS active_sellers,

        MAX(seller_rank)
            AS max_seller_rank,

        COUNT(DISTINCT seller_rank)
            AS distinct_ranks,

        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 10
        )
        / NULLIF(MAX(total_gmv), 0)
            AS top_10_share,

        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 50
        )
        / NULLIF(MAX(total_gmv), 0)
            AS top_50_share,

        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 100
        )
        / NULLIF(MAX(total_gmv), 0)
            AS top_100_share

    FROM seller_ranked
)

SELECT
    'seller_ranking_is_contiguous'
        AS check_name,

    CASE
        WHEN max_seller_rank = active_sellers
         AND distinct_ranks = active_sellers
        THEN 0
        ELSE 1
    END AS violations,

    CASE
        WHEN max_seller_rank = active_sellers
         AND distinct_ranks = active_sellers
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM concentration_metrics

UNION ALL

SELECT
    'seller_concentration_shares_not_monotonic',

    CASE
        WHEN top_10_share <= top_50_share
         AND top_50_share <= top_100_share
        THEN 0
        ELSE 1
    END,

    CASE
        WHEN top_10_share <= top_50_share
         AND top_50_share <= top_100_share
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM concentration_metrics

UNION ALL

SELECT
    'seller_concentration_share_above_100',

    CASE
        WHEN top_10_share <= 100
         AND top_50_share <= 100
         AND top_100_share <= 100
        THEN 0
        ELSE 1
    END,

    CASE
        WHEN top_10_share <= 100
         AND top_50_share <= 100
         AND top_100_share <= 100
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM concentration_metrics;

-- ------------------------------------------------------------
-- 7. Payment analysis validation
-- ------------------------------------------------------------

-- Payment metrics use delivered orders only.
--
-- One delivered order is known to have no payment record.
-- Therefore, payment-method order shares use delivered orders
-- with at least one payment record as the denominator.
--
-- Payment method usage is NOT additive across methods because
-- one order can use multiple payment methods.


-- ------------------------------------------------------------
-- 7.1 Payment method reconciliation
-- ------------------------------------------------------------

WITH delivered_payments AS (
    SELECT
        p.order_id,
        p.payment_type,
        p.payment_value

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(DISTINCT order_id)
            AS orders_with_payment,

        SUM(payment_value)
            AS total_payment_value

    FROM delivered_payments
),

payment_method_metrics AS (
    SELECT
        payment_type,

        COUNT(DISTINCT order_id)
            AS orders_using_method,

        SUM(payment_value)
            AS payment_value

    FROM delivered_payments

    GROUP BY
        payment_type
),

method_totals AS (
    SELECT
        SUM(payment_value)
            AS total_payment_value

    FROM payment_method_metrics
)

SELECT
    'payment_method_value_matches_overall'
        AS check_name,

    ROUND(
        r.total_payment_value,
        2
    ) AS expected_value,

    ROUND(
        m.total_payment_value,
        2
    ) AS actual_value,

    ROUND(
        ABS(
            r.total_payment_value
            - m.total_payment_value
        ),
        2
    ) AS difference,

    CASE
        WHEN ROUND(r.total_payment_value, 2)
           = ROUND(m.total_payment_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN method_totals AS m;


-- ------------------------------------------------------------
-- 7.2 Payment method shares
-- ------------------------------------------------------------

WITH delivered_payments AS (
    SELECT
        p.order_id,
        p.payment_type,
        p.payment_value

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

payment_method_metrics AS (
    SELECT
        payment_type,

        SUM(payment_value)
            AS payment_value

    FROM delivered_payments

    GROUP BY
        payment_type
),

payment_method_shares AS (
    SELECT
        payment_type,

        100.0
        * payment_value
        / NULLIF(
            SUM(payment_value) OVER (),
            0
        ) AS payment_value_share

    FROM payment_method_metrics
)

SELECT
    'payment_method_value_shares_sum_to_100'
        AS check_name,

    100.000000::NUMERIC
        AS expected_value,

    ROUND(
        SUM(payment_value_share),
        6
    ) AS actual_value,

    ROUND(
        ABS(
            100.0
            - SUM(payment_value_share)
        ),
        6
    ) AS difference,

    CASE
        WHEN ROUND(
            SUM(payment_value_share),
            6
        ) = 100.000000
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM payment_method_shares;


-- ------------------------------------------------------------
-- 7.3 Credit-card installment data quality
-- ------------------------------------------------------------

-- Installment analysis excludes credit-card payment records
-- where payment_installments is NULL or <= 0.
--
-- Such rows are reported as informational data-quality issues
-- rather than analytical failures.

WITH credit_card_payments AS (
    SELECT
        p.order_id,
        p.payment_installments,
        p.payment_value

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
)

SELECT
    'credit_card_nonpositive_installments'
        AS check_name,

    COUNT(*) FILTER (
        WHERE payment_installments IS NULL
           OR payment_installments <= 0
    ) AS anomalies,

    ROUND(
        COALESCE(
            SUM(payment_value) FILTER (
                WHERE payment_installments IS NULL
                   OR payment_installments <= 0
            ),
            0
        ),
        2
    ) AS affected_payment_value,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE payment_installments IS NULL
            OR payment_installments <= 0
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE payment_installments IS NULL
            OR payment_installments <= 0
        ) = 2
        AND ROUND(
            COALESCE(
                SUM(payment_value) FILTER (
                    WHERE payment_installments IS NULL
                    OR payment_installments <= 0
                ),
                0
            ),
            2
        ) = 188.63
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END AS status

FROM credit_card_payments;


-- ------------------------------------------------------------
-- 7.4 Credit-card installment record reconciliation
-- ------------------------------------------------------------

WITH credit_card_payments AS (
    SELECT
        p.order_id,
        p.payment_installments

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
),

installment_counts AS (
    SELECT
        COUNT(*) AS total_records,

        COUNT(*) FILTER (
            WHERE payment_installments > 0
        ) AS valid_records,

        COUNT(*) FILTER (
            WHERE payment_installments IS NULL
               OR payment_installments <= 0
        ) AS excluded_records

    FROM credit_card_payments
)

SELECT
    'credit_card_installment_records_reconcile'
        AS check_name,

    total_records::NUMERIC
        AS expected_value,

    (
        valid_records
        + excluded_records
    )::NUMERIC AS actual_value,

    ABS(
        total_records
        - valid_records
        - excluded_records
    )::NUMERIC AS difference,

    CASE
        WHEN total_records
           = valid_records + excluded_records
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM installment_counts;


-- ------------------------------------------------------------
-- 7.5 Credit-card orders excluded from installment analysis
-- ------------------------------------------------------------

-- An order is excluded from installment analysis only if it
-- has credit-card payments but none of those payment records
-- has payment_installments > 0.

WITH all_credit_card_orders AS (
    SELECT DISTINCT
        p.order_id

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
),

valid_credit_card_orders AS (
    SELECT DISTINCT
        p.order_id

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
      AND p.payment_installments > 0
)

SELECT
    'credit_card_orders_excluded_from_installment_analysis'
        AS check_name,

    COUNT(*) AS anomalies,

    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'

        WHEN COUNT(*) = 2
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END AS status

FROM all_credit_card_orders AS a

LEFT JOIN valid_credit_card_orders AS v
    USING (order_id)

WHERE v.order_id IS NULL;


-- ------------------------------------------------------------
-- 7.6 Order-level installment usage reconciliation
-- ------------------------------------------------------------

WITH valid_credit_card_payments AS (
    SELECT
        p.order_id,
        p.payment_installments

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
      AND p.payment_installments > 0
),

credit_card_orders AS (
    SELECT
        order_id,

        BOOL_OR(
            payment_installments > 1
        ) AS uses_installments

    FROM valid_credit_card_payments

    GROUP BY
        order_id
),

order_items_agg AS (
    SELECT
        order_id,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

credit_card_order_values AS (
    SELECT
        c.order_id,
        c.uses_installments,
        oi.product_value

    FROM credit_card_orders AS c

    LEFT JOIN order_items_agg AS oi
        USING (order_id)
),

reference_metrics AS (
    SELECT
        COUNT(*) AS credit_card_orders,

        SUM(product_value)
            AS product_gmv

    FROM credit_card_order_values
),

installment_groups AS (
    SELECT
        uses_installments,

        COUNT(*) AS orders,

        SUM(product_value)
            AS product_gmv

    FROM credit_card_order_values

    GROUP BY
        uses_installments
),

group_totals AS (
    SELECT
        SUM(orders)
            AS orders,

        SUM(product_gmv)
            AS product_gmv

    FROM installment_groups
)

SELECT
    'installment_groups_orders_match'
        AS check_name,

    r.credit_card_orders::NUMERIC
        AS expected_value,

    g.orders::NUMERIC
        AS actual_value,

    ABS(
        r.credit_card_orders
        - g.orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.credit_card_orders
           = g.orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN group_totals AS g

UNION ALL

SELECT
    'installment_groups_gmv_matches',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        g.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - g.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(g.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN group_totals AS g;


-- ------------------------------------------------------------
-- 7.7 Multiple-payment order validation
-- ------------------------------------------------------------

WITH payment_orders AS (
    SELECT
        p.order_id,

        COUNT(*)
            AS payment_records,

        COUNT(DISTINCT payment_type)
            AS payment_methods

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id
),

summary AS (
    SELECT
        COUNT(*) AS orders_with_payment,

        COUNT(*) FILTER (
            WHERE payment_records = 1
        ) AS single_payment_record_orders,

        COUNT(*) FILTER (
            WHERE payment_records > 1
        ) AS multiple_payment_record_orders,

        COUNT(*) FILTER (
            WHERE payment_methods = 1
        ) AS single_payment_method_orders,

        COUNT(*) FILTER (
            WHERE payment_methods > 1
        ) AS multiple_payment_method_orders

    FROM payment_orders
)

SELECT
    'payment_record_buckets_reconcile'
        AS check_name,

    orders_with_payment::NUMERIC
        AS expected_value,

    (
        single_payment_record_orders
        + multiple_payment_record_orders
    )::NUMERIC AS actual_value,

    ABS(
        orders_with_payment
        - single_payment_record_orders
        - multiple_payment_record_orders
    )::NUMERIC AS difference,

    CASE
        WHEN orders_with_payment
           =
           single_payment_record_orders
           + multiple_payment_record_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM summary

UNION ALL

SELECT
    'payment_method_buckets_reconcile',

    orders_with_payment::NUMERIC,

    (
        single_payment_method_orders
        + multiple_payment_method_orders
    )::NUMERIC,

    ABS(
        orders_with_payment
        - single_payment_method_orders
        - multiple_payment_method_orders
    )::NUMERIC,

    CASE
        WHEN orders_with_payment
           =
           single_payment_method_orders
           + multiple_payment_method_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM summary;


-- ------------------------------------------------------------
-- 7.8 Payment structure consistency
-- ------------------------------------------------------------

WITH payment_orders AS (
    SELECT
        p.order_id,

        COUNT(*)
            AS payment_records,

        COUNT(DISTINCT payment_type)
            AS payment_methods

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id
)

SELECT
    'payment_methods_exceed_payment_records'
        AS check_name,

    COUNT(*) FILTER (
        WHERE payment_methods > payment_records
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE payment_methods > payment_records
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM payment_orders

UNION ALL

SELECT
    'multiple_method_orders_without_multiple_records',

    COUNT(*) FILTER (
        WHERE payment_methods > 1
          AND payment_records <= 1
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE payment_methods > 1
              AND payment_records <= 1
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM payment_orders;


-- ------------------------------------------------------------
-- 7.9 Primary payment method validation
-- ------------------------------------------------------------

-- Primary payment method = payment method with the largest
-- aggregated payment value within an order.
--
-- payment_type is used as a deterministic tie-breaker.
--
-- Because one delivered order has no payment record, the
-- reference GMV here includes only delivered orders that have
-- at least one payment record.

WITH method_payments AS (
    SELECT
        p.order_id,
        p.payment_type,

        SUM(p.payment_value)
            AS method_payment_value

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id,
        p.payment_type
),

ranked_methods AS (
    SELECT
        order_id,
        payment_type,
        method_payment_value,

        ROW_NUMBER() OVER (
            PARTITION BY order_id

            ORDER BY
                method_payment_value DESC,
                payment_type
        ) AS payment_rank

    FROM method_payments
),

primary_methods AS (
    SELECT
        order_id,
        payment_type

    FROM ranked_methods

    WHERE payment_rank = 1
),

order_items_agg AS (
    SELECT
        oi.order_id,

        SUM(oi.price)
            AS product_value

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.order_id
),

eligible_orders AS (
    SELECT
        DISTINCT mp.order_id,
        oi.product_value

    FROM method_payments AS mp

    JOIN order_items_agg AS oi
        USING (order_id)
),

reference_metrics AS (
    SELECT
        COUNT(*) AS orders,

        SUM(product_value)
            AS product_gmv

    FROM eligible_orders
),

primary_method_metrics AS (
    SELECT
        COUNT(*) AS orders,

        SUM(e.product_value)
            AS product_gmv

    FROM primary_methods AS p

    JOIN eligible_orders AS e
        USING (order_id)
)

SELECT
    'primary_method_orders_match_payment_orders'
        AS check_name,

    r.orders::NUMERIC
        AS expected_value,

    p.orders::NUMERIC
        AS actual_value,

    ABS(
        r.orders - p.orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.orders = p.orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN primary_method_metrics AS p

UNION ALL

SELECT
    'primary_method_gmv_matches_eligible_gmv',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        p.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - p.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(p.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN primary_method_metrics AS p;

-- ------------------------------------------------------------
-- 8. Delivery analysis validation
-- ------------------------------------------------------------

-- Delivery metrics use delivered orders only.
--
-- Delivery timeliness is evaluated by calendar date:
--
-- actual_delivery_date > estimated_delivery_date -> late
-- actual_delivery_date <= estimated_delivery_date -> on time / early


-- ------------------------------------------------------------
-- 8.1 Delivery coverage and timeliness reconciliation
-- ------------------------------------------------------------

WITH delivered_orders AS (
    SELECT
        order_id,

        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date

    FROM analytics.orders

    WHERE order_status = 'delivered'
),

delivery_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(order_delivered_customer_date)
            AS orders_with_delivery_date,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
        ) AS orders_with_delivery_comparison,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
              AND order_delivered_customer_date::date
                  > order_estimated_delivery_date::date
        ) AS late_orders,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
              AND order_delivered_customer_date::date
                  <= order_estimated_delivery_date::date
        ) AS on_time_or_early_orders

    FROM delivered_orders
)

SELECT
    'delivery_classification_reconciles'
        AS check_name,

    orders_with_delivery_comparison::NUMERIC
        AS expected_value,

    (
        late_orders
        + on_time_or_early_orders
    )::NUMERIC AS actual_value,

    ABS(
        orders_with_delivery_comparison
        - late_orders
        - on_time_or_early_orders
    )::NUMERIC AS difference,

    CASE
        WHEN orders_with_delivery_comparison
           = late_orders + on_time_or_early_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM delivery_metrics;


-- ------------------------------------------------------------
-- 8.2 Delivery timestamp coverage
-- ------------------------------------------------------------

-- Missing timestamps are known source-data quality issues.
-- Expected anomaly counts were confirmed during validation.

WITH delivered_orders AS (
    SELECT
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date

    FROM analytics.orders

    WHERE order_status = 'delivered'
)

SELECT
    'missing_purchase_timestamp'
        AS check_name,

    COUNT(*) FILTER (
        WHERE order_purchase_timestamp IS NULL
    ) AS anomalies,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_purchase_timestamp IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM delivered_orders

UNION ALL

SELECT
    'missing_approval_timestamp',

    COUNT(*) FILTER (
        WHERE order_approved_at IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_approved_at IS NULL
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE order_approved_at IS NULL
        ) = 14
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END

FROM delivered_orders

UNION ALL

SELECT
    'missing_carrier_delivery_timestamp',

    COUNT(*) FILTER (
        WHERE order_delivered_carrier_date IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_delivered_carrier_date IS NULL
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE order_delivered_carrier_date IS NULL
        ) = 2
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END

FROM delivered_orders

UNION ALL

SELECT
    'missing_customer_delivery_timestamp',

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NULL
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NULL
        ) = 8
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END

FROM delivered_orders

UNION ALL

SELECT
    'missing_estimated_delivery_timestamp',

    COUNT(*) FILTER (
        WHERE order_estimated_delivery_date IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_estimated_delivery_date IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM delivered_orders;


-- ------------------------------------------------------------
-- 8.3 Delivery chronology checks
-- ------------------------------------------------------------

-- Invalid timestamp order is a known source-data quality issue.
-- Negative fulfillment-stage durations are excluded from
-- the corresponding metrics in 06_business_analysis.sql.

WITH delivered_orders AS (
    SELECT
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date

    FROM analytics.orders

    WHERE order_status = 'delivered'
)

SELECT
    'approval_before_purchase'
        AS check_name,

    COUNT(*) FILTER (
        WHERE order_approved_at IS NOT NULL
          AND order_purchase_timestamp IS NOT NULL
          AND order_approved_at
              < order_purchase_timestamp
    ) AS anomalies,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_approved_at IS NOT NULL
              AND order_purchase_timestamp IS NOT NULL
              AND order_approved_at
                  < order_purchase_timestamp
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM delivered_orders

UNION ALL

SELECT
    'carrier_before_approval',

    COUNT(*) FILTER (
        WHERE order_delivered_carrier_date IS NOT NULL
          AND order_approved_at IS NOT NULL
          AND order_delivered_carrier_date
              < order_approved_at
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_delivered_carrier_date IS NOT NULL
              AND order_approved_at IS NOT NULL
              AND order_delivered_carrier_date
                  < order_approved_at
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE order_delivered_carrier_date IS NOT NULL
              AND order_approved_at IS NOT NULL
              AND order_delivered_carrier_date
                  < order_approved_at
        ) = 1350
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END

FROM delivered_orders

UNION ALL

SELECT
    'customer_delivery_before_carrier',

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NOT NULL
          AND order_delivered_carrier_date IS NOT NULL
          AND order_delivered_customer_date
              < order_delivered_carrier_date
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_delivered_carrier_date IS NOT NULL
              AND order_delivered_customer_date
                  < order_delivered_carrier_date
        ) = 0
        THEN 'PASS'

        WHEN COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_delivered_carrier_date IS NOT NULL
              AND order_delivered_customer_date
                  < order_delivered_carrier_date
        ) = 23
        THEN 'KNOWN_DATA_ISSUE'

        ELSE 'FAIL'
    END

FROM delivered_orders

UNION ALL

SELECT
    'customer_delivery_before_purchase',

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NOT NULL
          AND order_purchase_timestamp IS NOT NULL
          AND order_delivered_customer_date
              < order_purchase_timestamp
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_purchase_timestamp IS NOT NULL
              AND order_delivered_customer_date
                  < order_purchase_timestamp
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM delivered_orders;


-- ------------------------------------------------------------
-- 8.4 Monthly delivery reconciliation
-- ------------------------------------------------------------

WITH delivered_orders AS (
    SELECT
        DATE_TRUNC(
            'month',
            order_purchase_timestamp
        )::date AS month,

        order_delivered_customer_date,
        order_estimated_delivery_date

    FROM analytics.orders

    WHERE order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(order_delivered_customer_date)
            AS orders_with_delivery_date,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
        ) AS orders_with_delivery_comparison

    FROM delivered_orders
),

monthly_metrics AS (
    SELECT
        month,

        COUNT(*) AS delivered_orders,

        COUNT(order_delivered_customer_date)
            AS orders_with_delivery_date,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
        ) AS orders_with_delivery_comparison

    FROM delivered_orders

    GROUP BY
        month
),

monthly_totals AS (
    SELECT
        SUM(delivered_orders)
            AS delivered_orders,

        SUM(orders_with_delivery_date)
            AS orders_with_delivery_date,

        SUM(orders_with_delivery_comparison)
            AS orders_with_delivery_comparison

    FROM monthly_metrics
)

SELECT
    'monthly_delivery_orders_match'
        AS check_name,

    r.delivered_orders::NUMERIC
        AS expected_value,

    m.delivered_orders::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_orders
        - m.delivered_orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_orders
           = m.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_delivery_date_coverage_matches',

    r.orders_with_delivery_date::NUMERIC,

    m.orders_with_delivery_date::NUMERIC,

    ABS(
        r.orders_with_delivery_date
        - m.orders_with_delivery_date
    )::NUMERIC,

    CASE
        WHEN r.orders_with_delivery_date
           = m.orders_with_delivery_date
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_delivery_comparison_matches',

    r.orders_with_delivery_comparison::NUMERIC,

    m.orders_with_delivery_comparison::NUMERIC,

    ABS(
        r.orders_with_delivery_comparison
        - m.orders_with_delivery_comparison
    )::NUMERIC,

    CASE
        WHEN r.orders_with_delivery_comparison
           = m.orders_with_delivery_comparison
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m;


-- ------------------------------------------------------------
-- 8.5 Customer-state delivery reconciliation
-- ------------------------------------------------------------

WITH delivered_orders AS (
    SELECT
        o.order_id,

        c.customer_state,

        o.order_delivered_customer_date,
        o.order_estimated_delivery_date

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(order_delivered_customer_date)
            AS orders_with_delivery_date,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
        ) AS orders_with_delivery_comparison

    FROM delivered_orders
),

state_metrics AS (
    SELECT
        customer_state,

        COUNT(*) AS delivered_orders,

        COUNT(order_delivered_customer_date)
            AS orders_with_delivery_date,

        COUNT(*) FILTER (
            WHERE order_delivered_customer_date IS NOT NULL
              AND order_estimated_delivery_date IS NOT NULL
        ) AS orders_with_delivery_comparison

    FROM delivered_orders

    GROUP BY
        customer_state
),

state_totals AS (
    SELECT
        SUM(delivered_orders)
            AS delivered_orders,

        SUM(orders_with_delivery_date)
            AS orders_with_delivery_date,

        SUM(orders_with_delivery_comparison)
            AS orders_with_delivery_comparison

    FROM state_metrics
)

SELECT
    'state_delivery_orders_match'
        AS check_name,

    r.delivered_orders::NUMERIC
        AS expected_value,

    s.delivered_orders::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_orders
        - s.delivered_orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_orders
           = s.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'state_delivery_date_coverage_matches',

    r.orders_with_delivery_date::NUMERIC,

    s.orders_with_delivery_date::NUMERIC,

    ABS(
        r.orders_with_delivery_date
        - s.orders_with_delivery_date
    )::NUMERIC,

    CASE
        WHEN r.orders_with_delivery_date
           = s.orders_with_delivery_date
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'state_delivery_comparison_matches',

    r.orders_with_delivery_comparison::NUMERIC,

    s.orders_with_delivery_comparison::NUMERIC,

    ABS(
        r.orders_with_delivery_comparison
        - s.orders_with_delivery_comparison
    )::NUMERIC,

    CASE
        WHEN r.orders_with_delivery_comparison
           = s.orders_with_delivery_comparison
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s;


-- ------------------------------------------------------------
-- 8.6 Freight reconciliation
-- ------------------------------------------------------------

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.price,
        oi.freight_value

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS items_sold,

        SUM(price)
            AS product_gmv,

        SUM(freight_value)
            AS freight_value

    FROM delivered_items
),

order_freight AS (
    SELECT
        order_id,

        COUNT(*) AS items_count,

        SUM(price)
            AS product_value,

        SUM(freight_value)
            AS freight_value

    FROM delivered_items

    GROUP BY
        order_id
),

order_totals AS (
    SELECT
        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv,

        SUM(freight_value)
            AS freight_value

    FROM order_freight
)

SELECT
    'freight_items_match_overall'
        AS check_name,

    r.items_sold::NUMERIC
        AS expected_value,

    o.items_sold::NUMERIC
        AS actual_value,

    ABS(
        r.items_sold
        - o.items_sold
    )::NUMERIC AS difference,

    CASE
        WHEN r.items_sold = o.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN order_totals AS o

UNION ALL

SELECT
    'freight_product_gmv_matches_overall',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        o.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - o.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(o.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN order_totals AS o

UNION ALL

SELECT
    'freight_value_matches_overall',

    ROUND(
        r.freight_value,
        2
    ),

    ROUND(
        o.freight_value,
        2
    ),

    ROUND(
        ABS(
            r.freight_value
            - o.freight_value
        ),
        2
    ),

    CASE
        WHEN ROUND(r.freight_value, 2)
           = ROUND(o.freight_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN order_totals AS o;


-- ------------------------------------------------------------
-- 8.7 Freight by customer state reconciliation
-- ------------------------------------------------------------

WITH order_freight AS (
    SELECT
        oi.order_id,

        COUNT(*) AS items_count,

        SUM(oi.price)
            AS product_value,

        SUM(oi.freight_value)
            AS freight_value

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        oi.order_id
),

delivered_orders AS (
    SELECT
        o.order_id,

        c.customer_state,

        f.items_count,
        f.product_value,
        f.freight_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    JOIN order_freight AS f
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv,

        SUM(freight_value)
            AS freight_value

    FROM delivered_orders
),

state_metrics AS (
    SELECT
        customer_state,

        SUM(items_count)
            AS items_sold,

        SUM(product_value)
            AS product_gmv,

        SUM(freight_value)
            AS freight_value

    FROM delivered_orders

    GROUP BY
        customer_state
),

state_totals AS (
    SELECT
        SUM(items_sold)
            AS items_sold,

        SUM(product_gmv)
            AS product_gmv,

        SUM(freight_value)
            AS freight_value

    FROM state_metrics
)

SELECT
    'state_freight_items_match'
        AS check_name,

    r.items_sold::NUMERIC
        AS expected_value,

    s.items_sold::NUMERIC
        AS actual_value,

    ABS(
        r.items_sold
        - s.items_sold
    )::NUMERIC AS difference,

    CASE
        WHEN r.items_sold = s.items_sold
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'state_freight_gmv_matches',

    ROUND(
        r.product_gmv,
        2
    ),

    ROUND(
        s.product_gmv,
        2
    ),

    ROUND(
        ABS(
            r.product_gmv
            - s.product_gmv
        ),
        2
    ),

    CASE
        WHEN ROUND(r.product_gmv, 2)
           = ROUND(s.product_gmv, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s

UNION ALL

SELECT
    'state_freight_value_matches',

    ROUND(
        r.freight_value,
        2
    ),

    ROUND(
        s.freight_value,
        2
    ),

    ROUND(
        ABS(
            r.freight_value
            - s.freight_value
        ),
        2
    ),

    CASE
        WHEN ROUND(r.freight_value, 2)
           = ROUND(s.freight_value, 2)
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN state_totals AS s;

-- ------------------------------------------------------------
-- 9. Reviews analysis validation
-- ------------------------------------------------------------

-- Review analysis uses delivered orders only.
-- Reviews are stored at the order level.
--
-- If an order has multiple review rows, their scores are first
-- averaged into one order-level review score.


-- ------------------------------------------------------------
-- 9.1 Overall review consistency
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score,

        BOOL_OR(
            NULLIF(
                BTRIM(review_comment_message),
                ''
            ) IS NOT NULL
        ) AS has_comment

    FROM analytics.reviews

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,

        r.avg_order_review_score,

        COALESCE(
            r.has_comment,
            FALSE
        ) AS has_comment

    FROM analytics.orders AS o

    LEFT JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

review_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(avg_order_review_score)
            AS reviewed_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score >= 4
        ) AS positive_review_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score <= 2
        ) AS negative_review_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score > 2
              AND avg_order_review_score < 4
        ) AS neutral_review_orders,

        COUNT(*) FILTER (
            WHERE has_comment
        ) AS orders_with_comment

    FROM delivered_orders
)

SELECT
    'reviewed_orders_exceed_delivered_orders'
        AS check_name,

    CASE
        WHEN reviewed_orders <= delivered_orders
        THEN 0
        ELSE 1
    END AS violations,

    CASE
        WHEN reviewed_orders <= delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM review_metrics

UNION ALL

SELECT
    'review_satisfaction_groups_do_not_reconcile',

    ABS(
        reviewed_orders
        - positive_review_orders
        - neutral_review_orders
        - negative_review_orders
    ),

    CASE
        WHEN reviewed_orders
           =
           positive_review_orders
           + neutral_review_orders
           + negative_review_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM review_metrics

UNION ALL

SELECT
    'review_comments_exceed_reviewed_orders',

    CASE
        WHEN orders_with_comment <= reviewed_orders
        THEN 0
        ELSE 1
    END,

    CASE
        WHEN orders_with_comment <= reviewed_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM review_metrics;


-- ------------------------------------------------------------
-- 9.2 Review-score value checks
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
)

SELECT
    'order_review_score_below_one'
        AS check_name,

    COUNT(*) FILTER (
        WHERE avg_order_review_score < 1
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE avg_order_review_score < 1
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM order_reviews

UNION ALL

SELECT
    'order_review_score_above_five',

    COUNT(*) FILTER (
        WHERE avg_order_review_score > 5
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE avg_order_review_score > 5
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM order_reviews

UNION ALL

SELECT
    'null_order_review_score',

    COUNT(*) FILTER (
        WHERE avg_order_review_score IS NULL
    ),

    CASE
        WHEN COUNT(*) FILTER (
            WHERE avg_order_review_score IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM order_reviews;


-- ------------------------------------------------------------
-- 9.3 Satisfaction distribution reconciliation
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score,

        BOOL_OR(
            NULLIF(
                BTRIM(review_comment_message),
                ''
            ) IS NOT NULL
        ) AS has_comment

    FROM analytics.reviews

    GROUP BY
        order_id
),

reviewed_orders AS (
    SELECT
        o.order_id,
        r.avg_order_review_score,
        r.has_comment

    FROM analytics.orders AS o

    JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

satisfaction_groups AS (
    SELECT
        order_id,
        avg_order_review_score,
        has_comment,

        CASE
            WHEN avg_order_review_score >= 4
                THEN 'positive'

            WHEN avg_order_review_score <= 2
                THEN 'negative'

            ELSE 'neutral/mixed'
        END AS satisfaction_group

    FROM reviewed_orders
),

reference_metrics AS (
    SELECT
        COUNT(*) AS reviewed_orders,

        COUNT(*) FILTER (
            WHERE has_comment
        ) AS orders_with_comment

    FROM reviewed_orders
),

group_metrics AS (
    SELECT
        satisfaction_group,

        COUNT(*) AS reviewed_orders,

        COUNT(*) FILTER (
            WHERE has_comment
        ) AS orders_with_comment

    FROM satisfaction_groups

    GROUP BY
        satisfaction_group
),

group_totals AS (
    SELECT
        SUM(reviewed_orders)
            AS reviewed_orders,

        SUM(orders_with_comment)
            AS orders_with_comment

    FROM group_metrics
)

SELECT
    'satisfaction_group_orders_match'
        AS check_name,

    r.reviewed_orders::NUMERIC
        AS expected_value,

    g.reviewed_orders::NUMERIC
        AS actual_value,

    ABS(
        r.reviewed_orders
        - g.reviewed_orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.reviewed_orders
           = g.reviewed_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN group_totals AS g

UNION ALL

SELECT
    'satisfaction_group_comments_match',

    r.orders_with_comment::NUMERIC,

    g.orders_with_comment::NUMERIC,

    ABS(
        r.orders_with_comment
        - g.orders_with_comment
    )::NUMERIC,

    CASE
        WHEN r.orders_with_comment
           = g.orders_with_comment
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN group_totals AS g;


-- ------------------------------------------------------------
-- 9.4 Monthly review reconciliation
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

delivered_orders AS (
    SELECT
        o.order_id,

        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        r.avg_order_review_score

    FROM analytics.orders AS o

    LEFT JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'
),

reference_metrics AS (
    SELECT
        COUNT(*) AS delivered_orders,

        COUNT(avg_order_review_score)
            AS reviewed_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score >= 4
        ) AS positive_review_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score <= 2
        ) AS negative_review_orders

    FROM delivered_orders
),

monthly_metrics AS (
    SELECT
        month,

        COUNT(*) AS delivered_orders,

        COUNT(avg_order_review_score)
            AS reviewed_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score >= 4
        ) AS positive_review_orders,

        COUNT(*) FILTER (
            WHERE avg_order_review_score <= 2
        ) AS negative_review_orders

    FROM delivered_orders

    GROUP BY
        month
),

monthly_totals AS (
    SELECT
        SUM(delivered_orders)
            AS delivered_orders,

        SUM(reviewed_orders)
            AS reviewed_orders,

        SUM(positive_review_orders)
            AS positive_review_orders,

        SUM(negative_review_orders)
            AS negative_review_orders

    FROM monthly_metrics
)

SELECT
    'monthly_review_delivered_orders_match'
        AS check_name,

    r.delivered_orders::NUMERIC
        AS expected_value,

    m.delivered_orders::NUMERIC
        AS actual_value,

    ABS(
        r.delivered_orders
        - m.delivered_orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.delivered_orders
           = m.delivered_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_reviewed_orders_match',

    r.reviewed_orders::NUMERIC,

    m.reviewed_orders::NUMERIC,

    ABS(
        r.reviewed_orders
        - m.reviewed_orders
    )::NUMERIC,

    CASE
        WHEN r.reviewed_orders
           = m.reviewed_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m

UNION ALL

SELECT
    'monthly_positive_reviews_match',

    r.positive_review_orders::NUMERIC,

    m.positive_review_orders::NUMERIC,

    ABS(
        r.positive_review_orders
        - m.positive_review_orders
    )::NUMERIC,

    CASE
        WHEN r.positive_review_orders
           = m.positive_review_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m


UNION ALL


SELECT
    'monthly_negative_reviews_match',

    r.negative_review_orders::NUMERIC,

    m.negative_review_orders::NUMERIC,

    ABS(
        r.negative_review_orders
        - m.negative_review_orders
    )::NUMERIC,

    CASE
        WHEN r.negative_review_orders
           = m.negative_review_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END

FROM reference_metrics AS r

CROSS JOIN monthly_totals AS m;


-- ------------------------------------------------------------
-- 9.5 Review score by delivery timeliness validation
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

reviewed_delivery_orders AS (
    SELECT
        o.order_id,

        r.avg_order_review_score,

        o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date::date
            AS delivery_deviation_days

    FROM analytics.orders AS o

    JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
),

delivery_groups AS (
    SELECT
        order_id,
        avg_order_review_score,
        delivery_deviation_days,

        CASE
            WHEN delivery_deviation_days < 0
                THEN 'early'

            WHEN delivery_deviation_days = 0
                THEN 'on estimated date'

            WHEN delivery_deviation_days BETWEEN 1 AND 3
                THEN '1-3 days late'

            WHEN delivery_deviation_days BETWEEN 4 AND 7
                THEN '4-7 days late'

            ELSE '8+ days late'
        END AS delivery_group

    FROM reviewed_delivery_orders
),

group_totals AS (
    SELECT
        COUNT(*) AS reviewed_orders

    FROM delivery_groups
),

reference_metrics AS (
    SELECT
        COUNT(*) AS reviewed_orders

    FROM reviewed_delivery_orders
)

SELECT
    'delivery_review_groups_reconcile'
        AS check_name,

    r.reviewed_orders::NUMERIC
        AS expected_value,

    g.reviewed_orders::NUMERIC
        AS actual_value,

    ABS(
        r.reviewed_orders
        - g.reviewed_orders
    )::NUMERIC AS difference,

    CASE
        WHEN r.reviewed_orders
           = g.reviewed_orders
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM reference_metrics AS r

CROSS JOIN group_totals AS g;


-- ------------------------------------------------------------
-- 9.6 Delivery review group completeness
-- ------------------------------------------------------------

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

reviewed_delivery_orders AS (
    SELECT
        o.order_id,

        r.avg_order_review_score,

        o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date::date
            AS delivery_deviation_days

    FROM analytics.orders AS o

    JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
),

delivery_groups AS (
    SELECT
        order_id,

        CASE
            WHEN delivery_deviation_days < 0
                THEN 'early'

            WHEN delivery_deviation_days = 0
                THEN 'on estimated date'

            WHEN delivery_deviation_days BETWEEN 1 AND 3
                THEN '1-3 days late'

            WHEN delivery_deviation_days BETWEEN 4 AND 7
                THEN '4-7 days late'

            ELSE '8+ days late'
        END AS delivery_group

    FROM reviewed_delivery_orders
)

SELECT
    'null_delivery_review_group'
        AS check_name,

    COUNT(*) FILTER (
        WHERE delivery_group IS NULL
    ) AS violations,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE delivery_group IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM delivery_groups;