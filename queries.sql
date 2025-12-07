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

