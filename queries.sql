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


-- 
