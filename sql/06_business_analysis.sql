-- ============================================================
-- BUSINESS ANALYSIS
-- ============================================================

-- ------------------------------------------------------------
-- 1. General business metrics
-- ------------------------------------------------------------

-- Order counts, total customer count and status rates use all orders.
-- Sales, item and repeat-customer metrics use delivered orders only.

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value
    FROM analytics.order_items
    GROUP BY order_id
),

payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM analytics.payments
    GROUP BY order_id
),

customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(*) AS orders_count
    FROM analytics.orders AS o
    JOIN analytics.customers AS c
        USING (customer_id)
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

delivered_customers AS (
    SELECT
        COUNT(*) AS customers
    FROM customer_orders
),

repeat_customers AS (
    SELECT
        COUNT(*) AS customers
    FROM customer_orders
    WHERE orders_count > 1
),

delivered_assortment AS (
    SELECT
        COUNT(DISTINCT oi.product_id) AS sku_count,
        COUNT(DISTINCT oi.seller_id) AS sellers,
        COUNT(DISTINCT p.product_category_name) AS known_categories
    FROM analytics.order_items AS oi
    JOIN analytics.orders AS o
        USING (order_id)
    JOIN analytics.products AS p
        USING (product_id)
    WHERE o.order_status = 'delivered'
)

SELECT
    -- Orders
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE o.order_status = 'delivered'
    ) AS delivered_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.order_status = 'delivered'
        )
        / COUNT(*),
        2
    ) AS delivered_rate,

    COUNT(*) FILTER (
        WHERE o.order_status = 'canceled'
    ) AS canceled_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE o.order_status = 'canceled'
        )
        / COUNT(*),
        2
    ) AS cancellation_rate,


    -- Customers
    COUNT(DISTINCT c.customer_unique_id)
        AS total_customers,

    (SELECT customers FROM delivered_customers)
        AS delivered_customers,

    (SELECT customers FROM repeat_customers)
        AS repeat_customers,

    ROUND(
        100.0
        * (SELECT customers FROM repeat_customers)
        / NULLIF(
            (SELECT customers FROM delivered_customers),
            0
        ),
        2
    ) AS repeat_customer_rate,

    ROUND(
        COUNT(*) FILTER (
            WHERE o.order_status = 'delivered'
        )::NUMERIC
        / NULLIF(
            (SELECT customers FROM delivered_customers),
            0
        ),
        2
    ) AS purchase_frequency,


    -- Items and assortment
    SUM(oi.items_count) FILTER (
        WHERE o.order_status = 'delivered'
    ) AS items_sold,

    ROUND(
        SUM(oi.items_count) FILTER (
            WHERE o.order_status = 'delivered'
        )::NUMERIC
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE o.order_status = 'delivered'
            ),
            0
        ),
        2
    ) AS avg_items_per_order,

    (SELECT sku_count FROM delivered_assortment)
        AS sold_sku_count,

    (SELECT sellers FROM delivered_assortment)
        AS active_sellers,

    (SELECT known_categories FROM delivered_assortment)
        AS known_active_categories,


    -- Financial metrics
    ROUND(
        SUM(oi.product_value) FILTER (
            WHERE o.order_status = 'delivered'
        ),
        2
    ) AS product_gmv,

    ROUND(
        SUM(p.payment_value) FILTER (
            WHERE o.order_status = 'delivered'
        ),
        2
    ) AS total_payment_value,

    ROUND(
        SUM(oi.product_value) FILTER (
            WHERE o.order_status = 'delivered'
        )
        /
        NULLIF(
            COUNT(*) FILTER (
                WHERE o.order_status = 'delivered'
            ),
            0
        ),
        2
    ) AS aov,


    -- Data period
    MIN(o.order_purchase_timestamp)::date
        AS first_order_date,

    MAX(o.order_purchase_timestamp)::date
        AS last_order_date

FROM analytics.orders AS o

JOIN analytics.customers AS c
    USING (customer_id)

LEFT JOIN order_items_agg AS oi
    USING (order_id)

LEFT JOIN payments_agg AS p
    USING (order_id);

-- ------------------------------------------------------------
-- 2. Monthly business dynamics
-- ------------------------------------------------------------

-- Order counts and status rates use all orders.
-- Buyer, sales and item metrics use delivered orders only.
-- A calendar is generated to ensure that MoM metrics compare
-- consecutive calendar months.
-- The first and last months may be incomplete and should be
-- interpreted with caution.

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value
    FROM analytics.order_items
    GROUP BY order_id
),

payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value
    FROM analytics.payments
    GROUP BY order_id
),

calendar AS (
    SELECT
        GENERATE_SERIES(
            (
                SELECT DATE_TRUNC(
                    'month',
                    MIN(order_purchase_timestamp)
                )
                FROM analytics.orders
            ),
            (
                SELECT DATE_TRUNC(
                    'month',
                    MAX(order_purchase_timestamp)
                )
                FROM analytics.orders
            ),
            INTERVAL '1 month'
        )::date AS month
),

monthly_metrics AS (
    SELECT
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        -- Orders
        COUNT(*) AS total_orders,

        COUNT(*) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE o.order_status = 'canceled'
        ) AS canceled_orders,


        -- Customers
        COUNT(
            DISTINCT c.customer_unique_id
        ) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS monthly_active_buyers,


        -- Items
        SUM(oi.items_count) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS items_sold,


        -- Financial metrics
        SUM(oi.product_value) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS product_gmv,

        SUM(p.payment_value) FILTER (
            WHERE o.order_status = 'delivered'
        ) AS total_payment_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)

    GROUP BY
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date
),

complete_monthly_metrics AS (
    SELECT
        cal.month,

        COALESCE(mm.total_orders, 0)
            AS total_orders,

        COALESCE(mm.delivered_orders, 0)
            AS delivered_orders,

        COALESCE(mm.canceled_orders, 0)
            AS canceled_orders,

        COALESCE(mm.monthly_active_buyers, 0)
            AS monthly_active_buyers,

        COALESCE(mm.items_sold, 0)
            AS items_sold,

        COALESCE(mm.product_gmv, 0)
            AS product_gmv,

        COALESCE(mm.total_payment_value, 0)
            AS total_payment_value

    FROM calendar AS cal

    LEFT JOIN monthly_metrics AS mm
        USING (month)
),

monthly_kpi AS (
    SELECT
        month,

        total_orders,
        delivered_orders,

        100.0 * delivered_orders
        / NULLIF(total_orders, 0)
            AS delivered_rate,

        canceled_orders,

        100.0 * canceled_orders
        / NULLIF(total_orders, 0)
            AS cancellation_rate,

        monthly_active_buyers,

        items_sold,

        items_sold::NUMERIC
        / NULLIF(delivered_orders, 0)
            AS avg_items_per_order,

        product_gmv,

        total_payment_value,

        product_gmv
        / NULLIF(delivered_orders, 0)
            AS aov

    FROM complete_monthly_metrics
),

monthly_with_lag AS (
    SELECT
        *,

        LAG(delivered_orders) OVER (
            ORDER BY month
        ) AS previous_delivered_orders,

        LAG(product_gmv) OVER (
            ORDER BY month
        ) AS previous_product_gmv,

        LAG(monthly_active_buyers) OVER (
            ORDER BY month
        ) AS previous_active_buyers

    FROM monthly_kpi
)

SELECT
    month,

    -- Orders
    total_orders,
    delivered_orders,

    ROUND(
        delivered_rate,
        2
    ) AS delivered_rate,

    canceled_orders,

    ROUND(
        cancellation_rate,
        2
    ) AS cancellation_rate,


    -- Customers
    monthly_active_buyers,


    -- Items
    items_sold,

    ROUND(
        avg_items_per_order,
        2
    ) AS avg_items_per_order,


    -- Financial metrics
    ROUND(
        product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        total_payment_value,
        2
    ) AS total_payment_value,

    ROUND(
        aov,
        2
    ) AS aov,


    -- Month-over-month growth in delivered orders
    ROUND(
        100.0
        * (
            delivered_orders
            - previous_delivered_orders
        )
        / NULLIF(
            previous_delivered_orders,
            0
        ),
        2
    ) AS delivered_orders_mom_growth,


    -- Month-over-month growth in GMV
    ROUND(
        100.0
        * (
            product_gmv
            - previous_product_gmv
        )
        / NULLIF(
            previous_product_gmv,
            0
        ),
        2
    ) AS gmv_mom_growth,


    -- Month-over-month growth in active buyers
    ROUND(
        100.0
        * (
            monthly_active_buyers
            - previous_active_buyers
        )
        / NULLIF(
            previous_active_buyers,
            0
        ),
        2
    ) AS buyers_mom_growth

FROM monthly_with_lag

ORDER BY month;

-- ------------------------------------------------------------
-- 3. Product and category analysis
-- ------------------------------------------------------------

-- Sales metrics use delivered orders only.
-- Categories without an English translation keep their original name.
-- Products without a category are grouped as 'unknown'.


-- ------------------------------------------------------------
-- 3.1 Category performance
-- ------------------------------------------------------------

-- Reviews are order-level, not product/category-level.
-- The order review is attributed to every category
-- represented in that order.
-- If an order has multiple reviews, their scores are averaged
-- into a single order-level review score.

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.product_id,
        oi.seller_id,
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

category_sales AS (
    SELECT
        category,

        COUNT(DISTINCT order_id)
            AS orders,

        COUNT(*)
            AS items_sold,

        COUNT(DISTINCT product_id)
            AS sku_count,

        COUNT(DISTINCT seller_id)
            AS active_sellers,

        SUM(price)
            AS product_gmv

    FROM delivered_items

    GROUP BY category
),

order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY order_id
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
            AS orders_with_review,

        AVG(avg_order_review_score)
            AS avg_order_review_score

    FROM category_order_reviews

    GROUP BY category
)

SELECT
    cs.category,

    cs.orders,
    cs.items_sold,
    cs.sku_count,
    cs.active_sellers,

    ROUND(
        cs.product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0
        * cs.product_gmv
        / SUM(cs.product_gmv) OVER (),
        2
    ) AS gmv_share,

    ROUND(
        cs.product_gmv
        / NULLIF(cs.items_sold, 0),
        2
    ) AS aiv,

    ROUND(
        cs.items_sold::NUMERIC
        / NULLIF(cs.orders, 0),
        2
    ) AS avg_category_items_per_order,

    cr.orders_with_review,

    ROUND(
        100.0 * cr.orders_with_review
        / NULLIF(cs.orders, 0),
        2
    ) AS order_review_coverage,

    ROUND(
        cr.avg_order_review_score,
        2
    ) AS avg_order_review_score,

    DENSE_RANK() OVER (
        ORDER BY cs.product_gmv DESC
    ) AS gmv_rank

FROM category_sales AS cs

LEFT JOIN category_reviews AS cr
    USING (category)

ORDER BY
    cs.product_gmv DESC;

-- ------------------------------------------------------------
-- 3.2 Top products
-- ------------------------------------------------------------

-- Reviews are order-level, not product-level.
-- The order review is attributed to every product
-- represented in that order.
-- If an order has multiple reviews, their scores are averaged
-- into a single order-level review score.

WITH delivered_items AS (
    SELECT
        oi.order_id,
        oi.product_id,
        oi.seller_id,
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

product_sales AS (
    SELECT
        product_id,
        category,

        COUNT(DISTINCT order_id)
            AS orders,

        COUNT(*)
            AS items_sold,

        COUNT(DISTINCT seller_id)
            AS active_sellers,

        SUM(price)
            AS product_gmv,

        AVG(price)
            AS aiv

    FROM delivered_items

    GROUP BY
        product_id,
        category
),

order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY order_id
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
            AS orders_with_review,

        AVG(avg_order_review_score)
            AS avg_order_review_score

    FROM product_order_reviews

    GROUP BY product_id
)

SELECT
    ps.product_id,
    ps.category,

    ps.orders,
    ps.items_sold,
    ps.active_sellers,

    ROUND(
        ps.product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0
        * ps.product_gmv
        / SUM(ps.product_gmv) OVER (),
        4
    ) AS gmv_share,

    ROUND(
        ps.aiv,
        2
    ) AS aiv,

    pr.orders_with_review,

    ROUND(
        100.0 * pr.orders_with_review
        / NULLIF(ps.orders, 0),
        2
    ) AS order_review_coverage,

    ROUND(
        pr.avg_order_review_score,
        2
    ) AS avg_order_review_score,

    DENSE_RANK() OVER (
        ORDER BY ps.product_gmv DESC
    ) AS gmv_rank

FROM product_sales AS ps

LEFT JOIN product_reviews AS pr
    USING (product_id)

ORDER BY
    ps.product_gmv DESC

LIMIT 20;

-- ------------------------------------------------------------
-- 4. Customer analysis
-- ------------------------------------------------------------

-- Customer behavior and value metrics use delivered orders only.


-- ------------------------------------------------------------
-- 4.1 Purchase frequency distribution
-- ------------------------------------------------------------

-- Purchase frequency is based on delivered orders only.

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

        CASE
            WHEN delivered_orders_count = 1 THEN 1
            WHEN delivered_orders_count = 2 THEN 2
            WHEN delivered_orders_count = 3 THEN 3
            ELSE 4
        END AS sort_order

    FROM customer_orders
)

SELECT
    order_frequency,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share

FROM frequency_distribution

GROUP BY
    order_frequency,
    sort_order

ORDER BY
    sort_order;

-- ------------------------------------------------------------
-- 4.2 Customer value
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value

    FROM analytics.order_items

    GROUP BY order_id
),

payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_value

    FROM analytics.payments

    GROUP BY order_id
),

customer_metrics AS (
    SELECT
        c.customer_unique_id,

        COUNT(*) AS delivered_orders_count,

        SUM(oi.items_count) AS items_bought,

        SUM(oi.product_value) AS customer_gmv,

        SUM(p.payment_value) AS customer_payment_value

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    LEFT JOIN payments_agg AS p
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        c.customer_unique_id
)

SELECT
    COUNT(*) AS customers,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY delivered_orders_count
            )::NUMERIC,
        2
    ) AS median_orders_per_customer,

    ROUND(
        AVG(items_bought),
        2
    ) AS avg_items_per_customer,

    ROUND(
        AVG(customer_gmv),
        2
    ) AS avg_customer_gmv,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY customer_gmv
            )::NUMERIC,
        2
    ) AS median_customer_gmv,

    ROUND(
        AVG(customer_payment_value),
        2
    ) AS avg_customer_payment_value

FROM customer_metrics;

-- ------------------------------------------------------------
-- 4.3 New vs returning buyers by month
-- ------------------------------------------------------------

-- Buyer activity is based on delivered orders only.
-- New buyers are defined by their first observed delivered order
-- within the dataset period.

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

        MIN(month) AS first_order_month

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
    month,

    monthly_active_buyers,

    new_buyers,

    returning_buyers,

    ROUND(
        100.0 * new_buyers
        / NULLIF(monthly_active_buyers, 0),
        2
    ) AS new_buyer_share,

    ROUND(
        100.0 * returning_buyers
        / NULLIF(monthly_active_buyers, 0),
        2
    ) AS returning_buyer_share

FROM monthly_customers

ORDER BY
    month;

-- ------------------------------------------------------------
-- 4.4 Cohort retention
-- ------------------------------------------------------------

-- Retention is based on delivered orders only.
-- Cohorts are defined by the month of the first observed
-- delivered order within the dataset period.
-- A customer is considered retained in month N if they made
-- at least one delivered order in that month.
-- Months that have not yet been observable for a cohort
-- are not included.

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

observation_period AS (
    SELECT
        MAX(activity_month)
            AS last_observed_month

    FROM customer_months
),

cohort_grid AS (
    SELECT
        cs.cohort_month,
        cs.cohort_size,
        month_number

    FROM cohort_sizes AS cs

    CROSS JOIN observation_period AS op

    CROSS JOIN LATERAL GENERATE_SERIES(
        0,
        (
            EXTRACT(
                YEAR FROM AGE(
                    op.last_observed_month,
                    cs.cohort_month
                )
            ) * 12
            +
            EXTRACT(
                MONTH FROM AGE(
                    op.last_observed_month,
                    cs.cohort_month
                )
            )
        )::INTEGER
    ) AS gs(month_number)
)

SELECT
    cg.cohort_month,
    cg.month_number,

    cg.cohort_size,

    COALESCE(
        ca.active_customers,
        0
    ) AS active_customers,

    ROUND(
        100.0
        * COALESCE(
            ca.active_customers,
            0
        )
        / NULLIF(cg.cohort_size, 0),
        2
    ) AS retention_rate

FROM cohort_grid AS cg

LEFT JOIN cohort_activity AS ca
    ON cg.cohort_month = ca.cohort_month
   AND cg.month_number = ca.month_number

ORDER BY
    cg.cohort_month,
    cg.month_number;

-- ------------------------------------------------------------
-- 4.5 RFM base metrics
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,
        SUM(price) AS product_value

    FROM analytics.order_items

    GROUP BY order_id
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
    customer_unique_id,

    recency_days,

    frequency,

    ROUND(
        monetary,
        2
    ) AS monetary

FROM rfm

ORDER BY
    monetary DESC,
    frequency DESC;

-- ------------------------------------------------------------
-- 5. Geographic analysis
-- ------------------------------------------------------------

-- Sales metrics use delivered orders only.
-- Customer geography represents the delivery location of the order.


-- ------------------------------------------------------------
-- 5.1 Customer geography by state
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value

    FROM analytics.order_items

    GROUP BY order_id
),

state_metrics AS (
    SELECT
        c.customer_state AS state,

        COUNT(*) AS orders,

        COUNT(DISTINCT c.customer_unique_id)
            AS customers,

        SUM(oi.items_count)
            AS items_sold,

        SUM(oi.product_value)
            AS product_gmv

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        c.customer_state
)

SELECT
    state,

    customers,
    orders,
    items_sold,

    ROUND(
        product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0 * product_gmv
        / SUM(product_gmv) OVER (),
        2
    ) AS gmv_share,

    ROUND(
        product_gmv
        / NULLIF(orders, 0),
        2
    ) AS aov,

    ROUND(
        orders::NUMERIC
        / NULLIF(customers, 0),
        2
    ) AS orders_per_customer,

    ROUND(
        items_sold::NUMERIC
        / NULLIF(orders, 0),
        2
    ) AS avg_items_per_order

FROM state_metrics

ORDER BY
    product_gmv DESC;

-- ------------------------------------------------------------
-- 5.2 Top customer cities
-- ------------------------------------------------------------

WITH order_items_agg AS (
    SELECT
        order_id,
        COUNT(*) AS items_count,
        SUM(price) AS product_value

    FROM analytics.order_items

    GROUP BY order_id
),

city_metrics AS (
    SELECT
        c.customer_state AS state,
        c.customer_city AS city,

        COUNT(*) AS orders,

        COUNT(DISTINCT c.customer_unique_id)
            AS customers,

        SUM(oi.items_count)
            AS items_sold,

        SUM(oi.product_value)
            AS product_gmv

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    LEFT JOIN order_items_agg AS oi
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        c.customer_state,
        c.customer_city
)

SELECT
    state,
    city,

    customers,
    orders,
    items_sold,

    ROUND(
        product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0 * product_gmv
        / SUM(product_gmv) OVER (),
        2
    ) AS gmv_share,

    ROUND(
        product_gmv
        / NULLIF(orders, 0),
        2
    ) AS aov

FROM city_metrics

ORDER BY
    product_gmv DESC

LIMIT 20;

-- ------------------------------------------------------------
-- 5.3 Seller geography by state
-- ------------------------------------------------------------

-- An order can contain sellers from multiple states,
-- so order counts are not additive across seller states.

WITH seller_state_metrics AS (
    SELECT
        s.seller_state AS state,

        COUNT(DISTINCT oi.seller_id)
            AS sellers,

        COUNT(DISTINCT oi.order_id)
            AS orders,

        COUNT(*)
            AS items_sold,

        COUNT(DISTINCT oi.product_id)
            AS sku_count,

        SUM(oi.price)
            AS product_gmv

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.sellers AS s
        USING (seller_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        s.seller_state
)

SELECT
    state,

    sellers,
    orders,
    items_sold,
    sku_count,

    ROUND(
        product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0 * product_gmv
        / SUM(product_gmv) OVER (),
        2
    ) AS gmv_share,

    ROUND(
        product_gmv
        / NULLIF(items_sold, 0),
        2
    ) AS aiv,

    ROUND(
        product_gmv
        / NULLIF(sellers, 0),
        2
    ) AS avg_gmv_per_seller

FROM seller_state_metrics

ORDER BY
    product_gmv DESC;

-- ------------------------------------------------------------
-- 5.4 Geolocation coverage
-- ------------------------------------------------------------

-- Geolocation coverage is calculated at the order-seller level.
-- Multiple items from the same seller within one order
-- represent a single customer-seller pair.

WITH order_seller_pairs AS (
    SELECT DISTINCT
        oi.order_id,
        oi.seller_id,
        o.customer_id

    FROM analytics.order_items AS oi

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
)

SELECT
    COUNT(*) AS delivered_order_seller_pairs,

    COUNT(*) FILTER (
        WHERE customer_geo.geolocation_zip_code_prefix IS NOT NULL
          AND seller_geo.geolocation_zip_code_prefix IS NOT NULL
    ) AS pairs_with_geolocation,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE customer_geo.geolocation_zip_code_prefix IS NOT NULL
              AND seller_geo.geolocation_zip_code_prefix IS NOT NULL
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS geolocation_coverage

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
       seller_geo.geolocation_zip_code_prefix;

-- ------------------------------------------------------------
-- 5.5 Customer-seller distance
-- ------------------------------------------------------------

-- The distance is an approximate great-circle distance
-- between aggregated customer and seller ZIP coordinates.

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
)

SELECT
    COUNT(distance_km) AS pairs_with_distance,

    ROUND(
        AVG(distance_km)::NUMERIC,
        2
    ) AS avg_distance_km,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY distance_km
            )::NUMERIC,
        2
    ) AS median_distance_km,

    ROUND(
        PERCENTILE_CONT(0.9)
            WITHIN GROUP (
                ORDER BY distance_km
            )::NUMERIC,
        2
    ) AS p90_distance_km,

    ROUND(
        MAX(distance_km)::NUMERIC,
        2
    ) AS max_distance_km

FROM distances;

-- ------------------------------------------------------------
-- 6. Seller analysis
-- ------------------------------------------------------------

-- Seller sales metrics use delivered orders only.
-- Reviews are order-level, not seller-level.
-- An order review is attributed to every seller represented
-- in that order.
-- If an order has multiple reviews, their scores are averaged
-- into a single order-level review score.


-- ------------------------------------------------------------
-- 6.1 Seller performance
-- ------------------------------------------------------------

-- An order can contain multiple sellers,
-- so seller order counts are not additive across sellers.

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
            AS orders_with_review,

        AVG(avg_order_review_score)
            AS avg_order_review_score

    FROM seller_order_reviews

    GROUP BY
        seller_id
)

SELECT
    ss.seller_id,

    ss.orders,
    ss.items_sold,
    ss.sku_count,

    ROUND(
        ss.product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        100.0
        * ss.product_gmv
        / SUM(ss.product_gmv) OVER (),
        4
    ) AS gmv_share,

    ROUND(
        ss.product_gmv
        / NULLIF(ss.items_sold, 0),
        2
    ) AS aiv,

    ROUND(
        ss.product_gmv
        / NULLIF(ss.orders, 0),
        2
    ) AS avg_seller_gmv_per_order,

    sr.orders_with_review,

    ROUND(
        100.0 * sr.orders_with_review
        / NULLIF(ss.orders, 0),
        2
    ) AS order_review_coverage,

    ROUND(
        sr.avg_order_review_score,
        2
    ) AS avg_order_review_score,

    DENSE_RANK() OVER (
        ORDER BY ss.product_gmv DESC
    ) AS gmv_rank

FROM seller_sales AS ss

LEFT JOIN seller_reviews AS sr
    USING (seller_id)

ORDER BY
    ss.product_gmv DESC

LIMIT 20;

-- ------------------------------------------------------------
-- 6.2 Seller concentration
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
)

SELECT
    COUNT(*) AS active_sellers,

    ROUND(
        SUM(product_gmv),
        2
    ) AS total_product_gmv,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY product_gmv
            )::NUMERIC,
        2
    ) AS median_seller_gmv,

    ROUND(
        AVG(product_gmv),
        2
    ) AS avg_seller_gmv,

    ROUND(
        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 10
        )
        / NULLIF(MAX(total_gmv), 0),
        2
    ) AS top_10_sellers_gmv_share,

    ROUND(
        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 50
        )
        / NULLIF(MAX(total_gmv), 0),
        2
    ) AS top_50_sellers_gmv_share,

    ROUND(
        100.0
        * SUM(product_gmv) FILTER (
            WHERE seller_rank <= 100
        )
        / NULLIF(MAX(total_gmv), 0),
        2
    ) AS top_100_sellers_gmv_share

FROM seller_ranked;

-- ------------------------------------------------------------
-- 7. Payments analysis
-- ------------------------------------------------------------

-- Payment analysis uses delivered orders only.
-- One order can contain multiple payment records
-- and can use more than one payment method.


-- ------------------------------------------------------------
-- 7.1 Payment methods
-- ------------------------------------------------------------

-- One order can use multiple payment methods,
-- so order usage shares are not additive across payment types.
-- Order usage share is calculated among delivered orders
-- with at least one payment record.

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

payment_methods AS (
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

payment_summary AS (
    SELECT
        COUNT(DISTINCT order_id)
            AS orders_with_payment

    FROM delivered_payments
)

SELECT
    pm.payment_type,

    pm.orders_using_method,

    ROUND(
        100.0
        * pm.orders_using_method
        / NULLIF(ps.orders_with_payment, 0),
        2
    ) AS order_usage_share,

    ROUND(
        pm.payment_value,
        2
    ) AS payment_value,

    ROUND(
        100.0
        * pm.payment_value
        / NULLIF(
            SUM(pm.payment_value) OVER (),
            0
        ),
        2
    ) AS payment_value_share,

    ROUND(
        pm.payment_value
        / NULLIF(pm.orders_using_method, 0),
        2
    ) AS avg_method_value_per_order_using_method

FROM payment_methods AS pm

CROSS JOIN payment_summary AS ps

ORDER BY
    pm.payment_value DESC;


-- ------------------------------------------------------------
-- 7.2 Credit card installment distribution
-- ------------------------------------------------------------

-- Distribution is calculated at the credit-card payment-record level.
-- Zero installment values are excluded because they cannot be
-- meaningfully interpreted as an installment count.

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
      AND p.payment_installments > 0
)

SELECT
    payment_installments,

    COUNT(*) AS credit_card_payment_records,

    ROUND(
        100.0
        * COUNT(*)
        / NULLIF(
            SUM(COUNT(*)) OVER (),
            0
        ),
        2
    ) AS payment_record_share,

    ROUND(
        SUM(payment_value),
        2
    ) AS credit_card_payment_value,

    ROUND(
        AVG(payment_value),
        2
    ) AS avg_credit_card_payment_value

FROM credit_card_payments

GROUP BY
    payment_installments

ORDER BY
    payment_installments;


-- ------------------------------------------------------------
-- 7.3 Credit card installment usage
-- ------------------------------------------------------------

-- Installment usage is calculated at the order level.
-- An order is considered an installment order if at least one
-- credit-card payment record uses more than one installment.
-- Zero installment values are excluded from installment analysis.

WITH order_items_agg AS (
    SELECT
        order_id,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

credit_card_orders AS (
    SELECT
        p.order_id,

        BOOL_OR(
            p.payment_installments > 1
        ) AS uses_installments

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'
      AND p.payment_type = 'credit_card'
      AND p.payment_installments > 0

    GROUP BY
        p.order_id
)

SELECT
    COUNT(*) AS credit_card_orders,

    COUNT(*) FILTER (
        WHERE uses_installments
    ) AS installment_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE uses_installments
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS installment_order_share,

    ROUND(
        AVG(oi.product_value) FILTER (
            WHERE NOT uses_installments
        ),
        2
    ) AS avg_product_value_non_installment_orders,

    ROUND(
        AVG(oi.product_value) FILTER (
            WHERE uses_installments
        ),
        2
    ) AS avg_product_value_installment_orders

FROM credit_card_orders AS cc

JOIN order_items_agg AS oi
    USING (order_id);


-- ------------------------------------------------------------
-- 7.4 Multiple payments per order
-- ------------------------------------------------------------

WITH order_payments AS (
    SELECT
        p.order_id,

        COUNT(*) AS payment_records_count,

        COUNT(DISTINCT p.payment_type)
            AS payment_methods_count

    FROM analytics.payments AS p

    JOIN analytics.orders AS o
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        p.order_id
)

SELECT
    COUNT(*) AS orders_with_payment,

    COUNT(*) FILTER (
        WHERE payment_records_count > 1
    ) AS orders_with_multiple_payment_records,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE payment_records_count > 1
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS multiple_payment_records_share,

    COUNT(*) FILTER (
        WHERE payment_methods_count > 1
    ) AS orders_with_multiple_payment_methods,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE payment_methods_count > 1
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS multiple_payment_methods_share,

    ROUND(
        AVG(payment_records_count),
        2
    ) AS avg_payment_records_per_order,

    MAX(payment_records_count)
        AS max_payment_records_per_order,

    MAX(payment_methods_count)
        AS max_payment_methods_per_order

FROM order_payments;


-- ------------------------------------------------------------
-- 7.5 Order value by primary payment method
-- ------------------------------------------------------------

-- For orders using multiple payment methods, the primary method
-- is defined as the method with the largest payment value.
-- If two methods have the same payment value, payment_type
-- is used as a deterministic tie-breaker.

WITH order_items_agg AS (
    SELECT
        order_id,

        SUM(price)
            AS product_value

    FROM analytics.order_items

    GROUP BY
        order_id
),

payment_method_values AS (
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

ranked_payment_methods AS (
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

    FROM payment_method_values
),

primary_payment_method AS (
    SELECT
        order_id,

        payment_type
            AS primary_payment_type

    FROM ranked_payment_methods

    WHERE payment_rank = 1
)

SELECT
    ppm.primary_payment_type,

    COUNT(*) AS orders,

    ROUND(
        SUM(oi.product_value),
        2
    ) AS product_gmv,

    ROUND(
        AVG(oi.product_value),
        2
    ) AS aov

FROM primary_payment_method AS ppm

JOIN order_items_agg AS oi
    USING (order_id)

GROUP BY
    ppm.primary_payment_type

ORDER BY
    product_gmv DESC;


-- ------------------------------------------------------------
-- 8. Delivery analysis
-- ------------------------------------------------------------

-- Delivery analysis uses delivered orders only.
-- Delivery time is measured from purchase to customer delivery.
-- Delivery deviation compares actual and estimated delivery dates:
-- positive values mean late delivery,
-- negative values mean early delivery.
-- Date-level comparison is used for estimated delivery because
-- the estimated delivery field represents a delivery date.


-- ------------------------------------------------------------
-- 8.1 Overall delivery performance
-- ------------------------------------------------------------

WITH delivery_orders AS (
    SELECT
        order_id,

        CASE
            WHEN order_delivered_customer_date IS NOT NULL
            THEN
                EXTRACT(
                    EPOCH FROM (
                        order_delivered_customer_date
                        - order_purchase_timestamp
                    )
                ) / 86400.0
        END AS delivery_time_days,

        CASE
            WHEN order_delivered_customer_date IS NOT NULL
             AND order_estimated_delivery_date IS NOT NULL
            THEN
                order_delivered_customer_date::date
                - order_estimated_delivery_date::date
        END AS delivery_deviation_days

    FROM analytics.orders

    WHERE order_status = 'delivered'
)

SELECT
    COUNT(*) AS delivered_orders,

    COUNT(delivery_time_days)
        AS orders_with_delivery_timestamp,

    ROUND(
        100.0
        * COUNT(delivery_time_days)
        / NULLIF(COUNT(*), 0),
        2
    ) AS delivery_timestamp_coverage,

    ROUND(
        AVG(delivery_time_days)::NUMERIC,
        2
    ) AS avg_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS median_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.9)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS p90_delivery_days,

    COUNT(delivery_deviation_days)
        AS orders_with_delivery_comparison,

    COUNT(*) FILTER (
        WHERE delivery_deviation_days > 0
    ) AS late_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_deviation_days > 0
        )
        / NULLIF(
            COUNT(delivery_deviation_days),
            0
        ),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(delivery_deviation_days)::NUMERIC,
        2
    ) AS avg_delivery_deviation_days,

    ROUND(
        AVG(delivery_deviation_days) FILTER (
            WHERE delivery_deviation_days > 0
        ),
        2
    ) AS avg_late_days

FROM delivery_orders;


-- ------------------------------------------------------------
-- 8.2 Fulfillment stage times
-- ------------------------------------------------------------

-- Stage metrics are calculated only when both timestamps
-- required for the corresponding interval are available
-- and their chronological order is valid.
-- Negative stage durations caused by source-data anomalies
-- are excluded from the corresponding metric.


WITH delivery_stages AS (
    SELECT
        order_id,

        CASE
            WHEN order_purchase_timestamp IS NOT NULL
             AND order_approved_at IS NOT NULL
             AND order_approved_at >= order_purchase_timestamp
            THEN
                EXTRACT(
                    EPOCH FROM (
                        order_approved_at
                        - order_purchase_timestamp
                    )
                ) / 3600.0
        END AS approval_time_hours,

        CASE
            WHEN order_approved_at IS NOT NULL
             AND order_delivered_carrier_date IS NOT NULL
             AND order_delivered_carrier_date >= order_approved_at
            THEN
                EXTRACT(
                    EPOCH FROM (
                        order_delivered_carrier_date
                        - order_approved_at
                    )
                ) / 86400.0
        END AS approved_to_carrier_days,

        CASE
            WHEN order_delivered_carrier_date IS NOT NULL
             AND order_delivered_customer_date IS NOT NULL
             AND order_delivered_customer_date >= order_delivered_carrier_date
            THEN
                EXTRACT(
                    EPOCH FROM (
                        order_delivered_customer_date
                        - order_delivered_carrier_date
                    )
                ) / 86400.0
        END AS carrier_to_customer_days

    FROM analytics.orders

    WHERE order_status = 'delivered'
)

SELECT
    ROUND(
        AVG(approval_time_hours)::NUMERIC,
        2
    ) AS avg_approval_time_hours,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY approval_time_hours
            )::NUMERIC,
        2
    ) AS median_approval_time_hours,

    ROUND(
        AVG(approved_to_carrier_days)::NUMERIC,
        2
    ) AS avg_approved_to_carrier_days,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY approved_to_carrier_days
            )::NUMERIC,
        2
    ) AS median_approved_to_carrier_days,

    ROUND(
        AVG(carrier_to_customer_days)::NUMERIC,
        2
    ) AS avg_carrier_to_customer_days,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY carrier_to_customer_days
            )::NUMERIC,
        2
    ) AS median_carrier_to_customer_days

FROM delivery_stages;

-- ------------------------------------------------------------
-- 8.3 Monthly delivery performance
-- ------------------------------------------------------------

-- Orders are grouped by purchase month.
-- The first and last months may be incomplete and should be
-- interpreted with caution.

WITH delivery_orders AS (
    SELECT
        DATE_TRUNC(
            'month',
            order_purchase_timestamp
        )::date AS month,

        CASE
            WHEN order_delivered_customer_date IS NOT NULL
            THEN
                EXTRACT(
                    EPOCH FROM (
                        order_delivered_customer_date
                        - order_purchase_timestamp
                    )
                ) / 86400.0
        END AS delivery_time_days,

        CASE
            WHEN order_delivered_customer_date IS NOT NULL
             AND order_estimated_delivery_date IS NOT NULL
            THEN
                order_delivered_customer_date::date
                - order_estimated_delivery_date::date
        END AS delivery_deviation_days

    FROM analytics.orders

    WHERE order_status = 'delivered'
)

SELECT
    month,

    COUNT(*) AS delivered_orders,

    ROUND(
        AVG(delivery_time_days)::NUMERIC,
        2
    ) AS avg_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS median_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.9)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS p90_delivery_days,

    COUNT(*) FILTER (
        WHERE delivery_deviation_days > 0
    ) AS late_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_deviation_days > 0
        )
        / NULLIF(
            COUNT(delivery_deviation_days),
            0
        ),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(delivery_deviation_days)::NUMERIC,
        2
    ) AS avg_delivery_deviation_days

FROM delivery_orders

GROUP BY
    month

ORDER BY
    month;


-- ------------------------------------------------------------
-- 8.4 Delivery performance by customer state
-- ------------------------------------------------------------

WITH delivery_orders AS (
    SELECT
        c.customer_state AS state,

        CASE
            WHEN o.order_delivered_customer_date IS NOT NULL
            THEN
                EXTRACT(
                    EPOCH FROM (
                        o.order_delivered_customer_date
                        - o.order_purchase_timestamp
                    )
                ) / 86400.0
        END AS delivery_time_days,

        CASE
            WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_estimated_delivery_date IS NOT NULL
            THEN
                o.order_delivered_customer_date::date
                - o.order_estimated_delivery_date::date
        END AS delivery_deviation_days

    FROM analytics.orders AS o

    JOIN analytics.customers AS c
        USING (customer_id)

    WHERE o.order_status = 'delivered'
)

SELECT
    state,

    COUNT(*) AS delivered_orders,

    ROUND(
        AVG(delivery_time_days)::NUMERIC,
        2
    ) AS avg_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS median_delivery_days,

    ROUND(
        PERCENTILE_CONT(0.9)
            WITHIN GROUP (
                ORDER BY delivery_time_days
            )::NUMERIC,
        2
    ) AS p90_delivery_days,

    COUNT(*) FILTER (
        WHERE delivery_deviation_days > 0
    ) AS late_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_deviation_days > 0
        )
        / NULLIF(
            COUNT(delivery_deviation_days),
            0
        ),
        2
    ) AS late_delivery_rate,

    ROUND(
        AVG(delivery_deviation_days)::NUMERIC,
        2
    ) AS avg_delivery_deviation_days

FROM delivery_orders

GROUP BY
    state

ORDER BY
    avg_delivery_days DESC;


-- ------------------------------------------------------------
-- 8.5 Freight metrics
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
)

SELECT
    COUNT(*) AS orders_with_items,

    SUM(items_count)
        AS items_sold,

    ROUND(
        SUM(product_value),
        2
    ) AS product_gmv,

    ROUND(
        SUM(freight_value),
        2
    ) AS total_freight_value,

    ROUND(
        AVG(freight_value),
        2
    ) AS avg_freight_value_per_order,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY freight_value
            )::NUMERIC,
        2
    ) AS median_freight_value_per_order,

    ROUND(
        SUM(freight_value)
        / NULLIF(SUM(items_count), 0),
        2
    ) AS avg_freight_value_per_item,

    ROUND(
        100.0
        * SUM(freight_value)
        / NULLIF(SUM(product_value), 0),
        2
    ) AS freight_to_product_gmv_pct

FROM order_freight;


-- ------------------------------------------------------------
-- 8.6 Freight metrics by customer state
-- ------------------------------------------------------------

WITH order_freight AS (
    SELECT
        oi.order_id,

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

state_freight AS (
    SELECT
        c.customer_state AS state,

        COUNT(*) AS orders,

        SUM(ofr.product_value)
            AS product_gmv,

        SUM(ofr.freight_value)
            AS freight_value,

        AVG(ofr.freight_value)
            AS avg_freight_value_per_order,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY ofr.freight_value
            ) AS median_freight_value_per_order

    FROM order_freight AS ofr

    JOIN analytics.orders AS o
        USING (order_id)

    JOIN analytics.customers AS c
        USING (customer_id)

    GROUP BY
        c.customer_state
)

SELECT
    state,

    orders,

    ROUND(
        product_gmv,
        2
    ) AS product_gmv,

    ROUND(
        freight_value,
        2
    ) AS total_freight_value,

    ROUND(
        avg_freight_value_per_order,
        2
    ) AS avg_freight_value_per_order,

    ROUND(
        median_freight_value_per_order::NUMERIC,
        2
    ) AS median_freight_value_per_order,

    ROUND(
        100.0
        * freight_value
        / NULLIF(product_gmv, 0),
        2
    ) AS freight_to_product_gmv_pct

FROM state_freight

ORDER BY
    avg_freight_value_per_order DESC;

-- ------------------------------------------------------------
-- 9. Reviews analysis
-- ------------------------------------------------------------

-- Review analysis uses delivered orders only.
-- Reviews are order-level.
-- If an order has multiple reviews, their scores are averaged
-- into a single order-level review score.
--
-- Satisfaction groups used in this section:
-- positive      = average order review score >= 4
-- neutral/mixed = average order review score > 2 and < 4
-- negative      = average order review score <= 2
--
-- These groups are analytical categories and should not
-- be interpreted as NPS.


-- ------------------------------------------------------------
-- 9.1 Overall review metrics
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
)

SELECT
    COUNT(*) AS delivered_orders,

    COUNT(avg_order_review_score)
        AS reviewed_orders,

    ROUND(
        100.0
        * COUNT(avg_order_review_score)
        / NULLIF(COUNT(*), 0),
        2
    ) AS order_review_coverage,

    ROUND(
        AVG(avg_order_review_score),
        2
    ) AS avg_order_review_score,

    ROUND(
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY avg_order_review_score
            )::NUMERIC,
        2
    ) AS median_order_review_score,

    COUNT(*) FILTER (
        WHERE avg_order_review_score >= 4
    ) AS positive_review_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE avg_order_review_score >= 4
        )
        / NULLIF(
            COUNT(avg_order_review_score),
            0
        ),
        2
    ) AS positive_review_rate,

    COUNT(*) FILTER (
        WHERE avg_order_review_score <= 2
    ) AS negative_review_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE avg_order_review_score <= 2
        )
        / NULLIF(
            COUNT(avg_order_review_score),
            0
        ),
        2
    ) AS negative_review_rate,

    COUNT(*) FILTER (
        WHERE has_comment
    ) AS orders_with_comment,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE has_comment
        )
        / NULLIF(
            COUNT(avg_order_review_score),
            0
        ),
        2
    ) AS review_comment_rate

FROM delivered_orders;


-- ------------------------------------------------------------
-- 9.2 Satisfaction distribution
-- ------------------------------------------------------------

-- Satisfaction groups are based on the average order-level
-- review score.
-- For orders with multiple reviews, fractional average scores
-- can therefore occur.

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
        END AS satisfaction_group,

        CASE
            WHEN avg_order_review_score >= 4 THEN 3
            WHEN avg_order_review_score <= 2 THEN 1
            ELSE 2
        END AS sort_order

    FROM reviewed_orders
)

SELECT
    satisfaction_group,

    COUNT(*) AS reviewed_orders,

    ROUND(
        100.0
        * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS reviewed_order_share,

    ROUND(
        AVG(avg_order_review_score),
        2
    ) AS avg_order_review_score,

    COUNT(*) FILTER (
        WHERE has_comment
    ) AS orders_with_comment,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE has_comment
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS review_comment_rate

FROM satisfaction_groups

GROUP BY
    satisfaction_group,
    sort_order

ORDER BY
    sort_order;


-- ------------------------------------------------------------
-- 9.3 Monthly review dynamics
-- ------------------------------------------------------------

-- Reviews are grouped by order purchase month.
-- The first and last months may be incomplete and should be
-- interpreted with caution.

WITH order_reviews AS (
    SELECT
        order_id,

        AVG(review_score::NUMERIC)
            AS avg_order_review_score

    FROM analytics.reviews

    GROUP BY
        order_id
),

monthly_reviews AS (
    SELECT
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date AS month,

        COUNT(*) AS delivered_orders,

        COUNT(r.avg_order_review_score)
            AS reviewed_orders,

        AVG(r.avg_order_review_score)
            AS avg_order_review_score,

        COUNT(*) FILTER (
            WHERE r.avg_order_review_score >= 4
        ) AS positive_review_orders,

        COUNT(*) FILTER (
            WHERE r.avg_order_review_score <= 2
        ) AS negative_review_orders

    FROM analytics.orders AS o

    LEFT JOIN order_reviews AS r
        USING (order_id)

    WHERE o.order_status = 'delivered'

    GROUP BY
        DATE_TRUNC(
            'month',
            o.order_purchase_timestamp
        )::date
)

SELECT
    month,

    delivered_orders,

    reviewed_orders,

    ROUND(
        100.0
        * reviewed_orders
        / NULLIF(delivered_orders, 0),
        2
    ) AS order_review_coverage,

    ROUND(
        avg_order_review_score,
        2
    ) AS avg_order_review_score,

    ROUND(
        100.0
        * positive_review_orders
        / NULLIF(reviewed_orders, 0),
        2
    ) AS positive_review_rate,

    ROUND(
        100.0
        * negative_review_orders
        / NULLIF(reviewed_orders, 0),
        2
    ) AS negative_review_rate

FROM monthly_reviews

ORDER BY
    month;


-- ------------------------------------------------------------
-- 9.4 Review score by delivery timeliness
-- ------------------------------------------------------------

-- Delivery timeliness compares actual and estimated delivery dates.
-- Orders delivered on the estimated calendar date are considered
-- on time regardless of delivery time during that day.

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
        END AS delivery_group,

        CASE
            WHEN delivery_deviation_days < 0 THEN 1
            WHEN delivery_deviation_days = 0 THEN 2
            WHEN delivery_deviation_days BETWEEN 1 AND 3 THEN 3
            WHEN delivery_deviation_days BETWEEN 4 AND 7 THEN 4
            ELSE 5
        END AS sort_order

    FROM reviewed_delivery_orders
)

SELECT
    delivery_group,

    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(delivery_deviation_days)::NUMERIC,
        2
    ) AS avg_delivery_deviation_days,

    ROUND(
        AVG(avg_order_review_score),
        2
    ) AS avg_order_review_score,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE avg_order_review_score >= 4
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS positive_review_rate,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE avg_order_review_score <= 2
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS negative_review_rate

FROM delivery_groups

GROUP BY
    delivery_group,
    sort_order

ORDER BY
    sort_order;