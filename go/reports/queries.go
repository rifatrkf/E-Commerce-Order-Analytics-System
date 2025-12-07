package reports

// Customer Cohort Analysis
const QueryCustomerCohortAnalysis = `
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
`

// Customer RFM
const QueryCustomerRFM = `
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
`
