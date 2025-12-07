-- Query:1 Customer Cohort Analysis with Running Totals

WITH
customer_first_order AS (
  -- Get first customer order that first order in 2024
  -- I assume that if there is a customer actual first order before 2024 and he/she has bought 2024, assume first order in 2024
  -- as definition only says 'include data from 2024'
  SELECT
    customer_id,
    MIN(order_date) AS first_order_date,
    DATE_TRUNC('month', MIN(order_date))::date AS cohort_month
  FROM orders o 
  WHERE status = 'completed'
    AND order_date >= '2024-01-01' 
  GROUP BY customer_id
),
cohort_revenue AS (
  -- Get Revenue from cohort in theifirst month
  SELECT
    cfo.cohort_month,
    COUNT(DISTINCT cfo.customer_id) AS new_customers,
    SUM(o.total_amount) as first_month_revenue
  FROM customer_first_order cfo
  LEFT JOIN orders o
    ON o.customer_id = cfo.customer_id
    AND o.status = 'completed'
    AND DATE_TRUNCT('month', o.order_date) = cfo.cohort_month
  GROUP BY cfo.cohort_month
),
cohort_retention_next_month AS (
  -- Customers that re-ordered in the next month
  SELECT
    cfo.cohort_month,
    COUNT(DISTINCT cfo.customer_id) AS retention_next_month_customer,
  FROM customer_first_order cfo
  INNER JOIN orders o
    ON o.customer_id = cfo.customer_id
    AND o.status = 'completed'
    AND DATE_TRUNC('month', o.order_date) = (cfo.cohort_month + INTERVAL '1 month')
  GROUP BY cfo.cohort_month
),
cohort_combined AS (
  -- combine cohort revenue and retention
  SELECT
    cr.cohort_month,
    new_customers,
    first_month_revenue,
    COALESCE(crnm.retention_next_month_customer, 0) AS retention_next_month_customer
  FROM cohort_revenue cr
  LEFT JOIN cohort_retention_next_month crnm
    ON cr.cohort_month = crnm.cohort_month
)
SELECT
  cohort_month,
  new_customers,
  first_month_revenue,
  -- Running total of all customers acquired up to that month (Cummulative Sum)
  SUM(new_cutomers) OVER (ORDER BY cohort_month) AS running_total_customers,
  CASE
    WHEN new_customers = 0 THEN 0 -- prevent div by 0
    ELSE ROUND(
        retained_next_month_customers::numeric / new_customers::numeric * 100,
        2
    )
  END AS retention_rate_percent
FROM cohort_combined
ORDER BY cohort_month;


-- Query 2: Product Performance with Ranking and Comparison Create a comprehensive product performance report

WITH
detailed_item_orders AS (
  -- create detailed first
  SELECT
    oi.order_id,
    oi.product_id,
    oi.quantity,
    oi.unit_price,
    oi.quantity * oi.unit_price AS order_line_revenue,
    o.order_date
  FROM order_items oi
  LEFT JOIN orders o ON o.id = oi.order_id
  WHERE o.status = 'completed'
),
summary_by_product_id AS (
  SELECT
    product_id,
    SUM(order_line_revenue) AS total_revenue,
    SUM(quantity) AS total_quantity
  FROM detailed_item_orders
  GROUP BY product_id
),
summary_by_product_name AS (
  -- we Create new temp table and join productc table here to make it light scanning
  SELECT
    product_id,
    product_name,
    category,
    total_revenue,
    total_quantity
  FROM summary_by_product_id spi
  LEFT JOIN products p ON p.id = spi.product_id
),
summary_by_category AS (
    SELECT
        category,
        SUM(total_revenue) AS category_revenue
    FROM summary_by_product_name
    GROUP BY category
),
last_months AS (
  -- Get information about last_month and its previous month
  SELECT
    DATE_TRUNC('month', MAX(order_date))::date AS last_month,
    (DATE_TRUNC('month', MAX(order_date)) - INTERVAL '1 month')::date AS prev_month
  FROM detailed_item_orders
),
product_monthly_revenue AS (
  -- Revenue per product per monmth
  SELECT
    product_id,
    DATE_TRUNC('month', order_date)::date AS month,
    SUM(order_line_revenue) AS monthly_revenue
  FROM detailed_item_orders
  GROUP BY product_id, DATE_TRUNC('month', order_date)
),
mom_revenue AS (
  SELECT
    spi.product_id,
    COALESCE(SUM(CASE WHEN pmr.month = lm.last_month THEN pmr.monthly_revenue END), 0) AS last_month_revenue,
    COALESCE(SUM(CASE WHEN pmr.month = lm.prev_month THEN pmr.monthly_revenue END), 0) AS prev_month_revenue
  FROM summary_by_product_id spi
  CROSS JOIN last_months lm
  LEFT JOIN product_monthly_revenue pmr
    ON pmr.product_id = spi.product_id
    AND pmr.month IN (lm.last_month, lm.prev_month)
  GROUP BY spi.product_id, lm.last_month, lm.prev_month
),
product_ranked AS (
    -- Add ranking and % of category revenue
    SELECT
        spn.product_id,
        spn.product_name,
        spn.category,
        spn.total_revenue,
        spn.total_quantity,
        sc.category_revenue,
        RANK() OVER (PARTITION BY spn.category ORDER BY spn.total_revenue DESC) AS revenue_rank,
        -- Percentage of category revenue
        ROUND(
            spn.total_revenue::numeric
            / NULLIF(sc.category_revenue::numeric, 0) * 100,
            2
        ) AS pct_of_category_revenue,
        -- Percent rank to flag top 20%
        PERCENT_RANK() OVER (PARTITION BY spn.category ORDER BY spn.total_revenue DESC) AS revenue_percent_rank
    FROM summary_by_product_name spn
    LEFT JOIN summary_by_category sc ON sc.category = spn.category
)
SELECT
    pr.product_name,
    pr.category,
    pr.total_revenue,
    pr.total_quantity AS total_untis,
    pr.revenue_rank,
    pr.pct_of_category_revenue,
    mr.last_month_revenue,
    mr.prev_month_revenue,
    CASE
        WHEN mr.prev_month_revenue = 0 THEN NULL
        ELSE ROUND(
            (mr.last_month_revenue - mr.prev_month_revenue)
            / mr.prev_month_revenue::numeric * 100,
            2
        )
    END AS mom_revenue_change_pct,
    CASE
        -- PERCENT_RANK -> 0.0 is top, 1.0 is bottom, so top 20% is <= 0.2
        WHEN pr.revenue_percent_rank <= 0.2 THEN 'Top 20%'
        ELSE 'Normal'
    END AS top_20_flag
FROM product_ranked pr
LEFT JOIN mom_revenue mr ON mr.product_id = pr.product_id
-- Only include products that have at least one sale (already ensured by product_totals)
ORDER BY
    pr.category,
    pr.revenue_rank;



-- Query 3: Customer Segmentation with RFM Analysis

WITH
customer_orders AS (
  SELECT
    customer_id,
    order_date,
    total_amount
  FROM orders
  WHERE status = 'completed'
),
customer_rfm_base AS (
  SELECT
    c.id AS customer_id
    c.name,
    c.email,
    --Recency: days since last order
    (CURRENT_DATE - MAX(co.order_date)::date) AS recency_days,
    -- Frequency: Total number of completed orders
    COUNT(*) AS frequency
    -- Monetary: Total lifetime revenue
    SUM(co.total_anount) AS monetary
  FROM customers c
  INNER JOIN customer_orders co ON co.customer_id = c.id 
  GROUP BY 1,2,3
),
monetary_quintiles AS (
  SELECT
    customer_id,
    name,
    email,
    recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY monetary) AS monetary_ntile
  FROM customer_rfm_base
),
rfm_score AS (
  SELECT
    customer_id,
    name,
    email,
    recency_days,
    frequency,
    monetary,
    -- Recency score
    CASE
        WHEN recency_days <= 30 THEN 5
        WHEN recency_days <= 90 THEN 4
        WHEN recency_days <= 180 THEN 3
        WHEN recency_days <= 365 THEN 2
        ELSE 1
    END AS recency_score,
    -- Frequency score
    CASE
        WHEN frequency >= 20 THEN 5
        WHEN frequency >= 11 THEN 4
        WHEN frequency >= 6  THEN 3
        WHEN frequency >= 3  THEN 2
        ELSE 1
    END AS frequency_score,
    -- Monetary score, convert NTILE first (1=lowest,5=highest) to score
    (6 - monetary_ntile) AS monetary_score
FROM monetary_quintiles
),
rfm_segment_based_score (
  SELECT
    customer_id,
    name,
    email,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    (recency_score + frequency_score + monetary_score) AS rfm_score
  FROM rfm_score
)
SELECT
    name AS customer_name,
    email,
    recency_days,
    frequency AS frequency_count,
    monetary AS monetary_value,
    rfm_score,
    CASE
        WHEN rfm_score >= 12 THEN 'Champions'
        WHEN rfm_score >= 9  THEN 'Loyal'
        WHEN rfm_score >= 6  THEN 'At Risk'
        ELSE 'Lost'
    END AS segment
FROM rfm_segmented
ORDER BY rfm_score DESC, monetary DESC;

-- Query 4: Advanced Sales Trend Analysis Create a query that analyzes sales trends and anomalies
WITH 
date_series AS (
    -- Query that generate one row per day for last 90 days (including today)
    -- Create Start date and end_date first
    SELECT
        (CURRENT_DATE - INTERVAL '89 days')::date AS start_date,
        CURRENT_DATE::date AS end_date
),
all_days AS(
    -- generate one row per day
    -- why make this series? in order to make sure there is no miss day in tracking
    SELECT
        generate_series(
            (SELECT start_date FROM date_series),
            (SELECT end_date FROM date_series),
            INTERVAL '1 day'
        )::date AS dt
),
daily_sales AS(
  SELECT
    DATE(order_date) AS order_date,
    COUNT(*) as total_orders,
    COALESCE(SUM(total_amount),0) AS total_revenue
  FROM orders
  WHERE status = 'completed'
    AND order_date BETWEEN (SELECT start_date FROM date_series) AND (SELECT end_date FROM date_series)
  GROUP BY 1
),
daily_with_complete_date AS (
    SELECT
        d.dt AS sales_date,
        COALESCE(ds.total_orders, 0)   AS total_orders,
        COALESCE(ds.total_revenue, 0)  AS total_revenue
    FROM all_days d
    LEFT JOIN daily_sales ds ON ds.order_day = d.dt
),
daily_with_7_days_moving_average AS)
  SELECT
    sales_date,
    total_orders,
    total_revenue,
    AVG(total_revenue) OVER (ORDER BY sales_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as avg_7_days_revenue,
    AVG(total_orders) OVER (ORDER BY sales_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as avg_7_days_orders,
  FROM daily_with_complete_date
)
SELECT
    sales_date,
    total_orders,
    total_revenue,
    avg_7_days_revenues,
    avg_7_days_orders,
    CASE
        -- Make sure no div by 0
        WHEN avg_7_days_revenue = 0 THEN NULL
        ELSE ROUND((total_revenue - avg_7_days_revenue)/avg_7_days_revenue * 100,2)
    END AS current_date_revenue_vs_7_days_avg_pct,
    TO_CHAR(sales_date, 'Dy') AS day_of_week,
    CASE
        WHEN avg_7_days_revenue = 0 THEN 'Normal'
        WHEN ABS((total_revenue - avg_7_days_revenue)/ avg_7_days_revenue * 100) > 30 THEN 'Need to be Check'
        ELSE 'Normal'
    END AS flag
FROM daily_with_7_days_moving_average
ORDER BY sales_date;

-- Query 5: Inventory Turnover and Stock Analysis

WITH 
date_range AS (
    SELECT
        (CURRENT_DATE - INTERVAL '90 days')::date AS start_date,
        CURRENT_DATE::date AS end_date
),
product_sales_last_90_days AS 
    SELECT
        oi.product_id,
        SUM(oi.quantity) AS units_sold_90,
        MAX(o.order_date) AS last_order_date
    FROM order_items oi ON oi.product_id = p.id
    LEFT JOIN orders o
      ON o.id = oi.order_id
     AND o.status = 'completed'
     AND o.order_date BETWEEN (SELECT start_date FROM date_range) AND ((SELECT end_date FROM date_range)
    GROUP BY 1
),
product_with_base AS (
    -- Then Combine stock and last 90 sold
    -- Use product as base table because usually we track by all product or SKU, so if null product sold can be detected
    SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.category,
        p.stock_quantity,
        ps.last_order_date,
        CASE
            WHEN ps.units_sold_90 IS NULL THEN 0
            ELSE ps.units_sold_90
        END AS units_sold_90
    FROM products p
    LEFT JOIN product_sales_90 ps ON ps.product_id = p.id
),
product_daily_sales_rates AS(
  SELECT
    product_id,
    product_name,
    category,
    stock_quantity,
    units_sold_90,
    last_order_date,
    (units_sold_90/90) AS daily_sales_rate,
    CASE
      WHEN units_sold_90 = 0 OR stock_quantity = 0 THEN NULL
      ELSE stock_quantity / (units_sold_90/90)
    END AS days_until_stockout
  FROM product_with_base
),
product_stock_status AS (
  SELECT
        product_id,
        product_name,
        category,
        stock_quantity,
        units_sold_90_clean AS units_sold_90,
        daily_sales_rate,
        last_order_date,
        days_until_stockout,
        CASE
            WHEN stock_quantity > 0
                 AND (units_sold_90_clean = 0 OR last_order_date IS NULL) THEN 'Dead Stock'
            WHEN days_until_stockout IS NULL THEN 'Overstocked'
            WHEN days_until_stockout < 7  THEN 'Critical'
            WHEN days_until_stockout < 30 THEN 'Low'
            WHEN days_until_stockout < 90 THEN 'Adequate'
            ELSE 'Overstocked'
        END AS stock_status,
        -- Recomendation: 45 days of stock based on current daily rate
        CASE
            WHEN daily_sales_rate <= 0 THEN 0
            ELSE GREATEST(
                CEIL(daily_sales_rate * 45) - stock_quantity,
                0
            )
        END AS reorder_quantity_recommendation
    FROM product_rates
)
SELECT
    product_name,
    category,
    stock_quantity,
    units_sold_90,
    daily_sales_rate,
    days_until_stockout,
    last_order_date,
    stock_status,
    reorder_quantity
FROM product_final
WHERE
    -- Include products with stock > 0 OR sold in last 90 days
    stock_quantity > 0
    OR units_sold_90 > 0
ORDER BY
    -- Priority by stock_status
    CASE stock_status
        WHEN 'Critical'    THEN 1
        WHEN 'Low'         THEN 2
        WHEN 'Adequate'    THEN 3
        WHEN 'Dead Stock'  THEN 4
        WHEN 'Overstocked' THEN 5
        ELSE 6
    END,
    days_until_stockout NULLS FIRST


-- Query 6: Customer Purchase Pattern Analysis Analyze customer purchase patterns across time
WITH 
base_orders AS (
  -- completed orders only
  SELECT
      o.id AS order_id,
      o.customer_id,
      o.order_date,
      o.total_amount
  FROM orders o
  WHERE o.status = 'completed'
),
orders_2024_customers AS (
    -- Customers who at least have one order in 2024
    SELECT DISTINCT customer_id
    FROM base_orders
    WHERE order_date >= DATE '2024-01-01'
      AND order_date <  DATE '2025-01-01'
),
orders_with_lag AS (
    -- Ussing lag to compute days between orders
    SELECT
        *,
        LAG(bo.order_date) OVER (PARTITION BY bo.customer_idORDER BY bo.order_date) AS prev_order_date
    FROM base_orders
),
order_intervals AS (
    -- Calculate interval between orders
    SELECT
        customer_id,
        order_id,
        order_date,
        total_amount,
        CASE
            WHEN prev_order_date IS NULL THEN NULL
            ELSE (order_date::date - prev_order_date::date)
        END AS days_interval_since_prev_order
    FROM orders_with_lag
),
customer_order_summary AS (
    -- Total number of orders, average and stddev of days between orders, avegage order value, lifetime
    SELECT
        c.id AS customer_id,
        c.name,
        c.email,
        COUNT(oi.order_id) AS total_orders,
        AVG(oi.days_since_prev) AS avg_days_between_orders,
        STDDEV_POP(oi.days_since_prev) AS stddev_days_between_orders,
        AVG(oi.total_amount) AS avg_order_value,
        (MAX(oi.order_date)::date - MIN(oi.order_date)::date) AS customer_lifetime_days
    FROM customers c
    INNER JOIN order_intervals oi ON oi.customer_id = c.id
    GROUP BY 1, 2, 3
),
customer_category_pref AS (
    -- Most frequently purchased category per customer by quantity
    SELECT
        o.customer_id,
        p.category,
        SUM(oi.quantity) AS total_units,
        RANK() OVER (
            PARTITION BY o.customer_id
            ORDER BY SUM(oi.quantity) DESC
        ) AS category_rank
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.id
    INNER JOIN products p ON p.id = oi.product_id
    WHERE o.status = 'completed'
    GROUP BY 1, 2
),
top_category_per_customer AS (
    SELECT
        customer_id,
        category AS most_frequent_category
    FROM customer_category_pref
    WHERE category_rank = 1
),
order_ranked AS (
    -- Rank orders per customer to get first 3 and last 3
    SELECT
        order_id
        customer_id,
        order_date,
        total_amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY customer_idORDER BY order_date DESC) AS rn_desc
    FROM base_orders
),
order_trend AS (
    -- get average of first 3 and last 3 orders for each customer
    SELECT
        customer_id,
        AVG(CASE WHEN rn_asc  <= 3 THEN total_amount END) AS first3_avg,
        AVG(CASE WHEN rn_desc <= 3 THEN total_amount END) AS last3_avg
    FROM order_ranked
    GROUP BY customer_id
),
final_customers_result AS (
    -- Combine the result
    SELECT
        cos.customer_id,
        cos.name,
        cos.email,
        cos.total_orders,
        cos.avg_days_between_orders,
        cos.stddev_days_between_orders,
        cos.avg_order_value,
        cos.customer_lifetime_days,
        ctc.most_frequent_category,
        ot.first3_avg,
        ot.last3_avg,
        CASE
            WHEN ot.last3_avg > ot.first3_avg THEN 'Increasing'
            ELSE 'Decreasing'
        END AS trend_indicator
    FROM customer_order_summary cos
    INNER JOIN order_trend ot ON ot.customer_id = cos.customer_id
    LEFT JOIN customer_top_category ctc ON ctc.customer_id = cos.customer_id
)
SELECT
    name AS customer_name,
    email,
    total_orders,
    avg_days_between_orders,
    stddev_days_between_orders,
    most_frequent_category,
    avg_order_value,
    trend_indicator,
    customer_lifetime_days
FROM final_customers_result
WHERE
    -- Only include customers with at least 3 orders
    total_orders >= 3
    -- And has at least one order in 2024
    AND customer_id IN (SELECT customer_id FROM orders_2024_customers)
ORDER BY total_orders DESC, avg_order_value DESC;
