# E-Commerce Order Analytics System
- Name: Rifat Rachim Khatami Fasha
- Job Role Application: Data Automation & Retrieval Engineer

## Scenario Overview
We are working for an e-commerce company that needs help retrieving and automating order data analysis. The company has a PostgreSQL database containing orders, customers, and products. Business teams frequently request complex data extracts and analytical reports.

## Part 1 - Complex SQL Queries & Database Analysis
### 1.1 Schema Analysis
Given the following simplified e-commerce database schema:
```
-- Customers table
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    country VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INT DEFAULT 0
);

-- Orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50), -- 'pending', 'completed', 'cancelled'
    total_amount DECIMAL(10,2)
);

-- Order items table
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL
);
```


#### Performance Issues
if this database has millions data records (1M+ customers, 10M+ orders, and 50M+ order items),
the possibility issues maybe can happen:
1. **Slow Join between Tables**  
example for case when joining `orders` and `order_items`, it can be very slow if there is no index on the foreignkeu. Because it will scan the full table to get the match rows.
2. **Slow Query**  
for instance, analytical reports often depend on date range, so it will use filter such as `WHERE order_date BETWEEN ... AND ...` in table `orders`, if no a manual index created for order_date or partition, the queries read all rows for `orders` table.
3. **Foregin Key field not become index**  
need to index to make it join fasters to solve issue no. 1
4. **Aggregation scan all**  
analytical report also often using aggregation, like total sales per date range or based on custome etc,  and    it will become slower as tables getting bigger
5. **No partition**  
Partition is important, so it won't scan all rows, example partition by order_date, the table will scan only needed row in partition

#### Index Recommendations
5 indexes that would improve common query patterns

1.   ```
     CREATE INDEX idx_orders_customer_id
     ON orders(customer_id);
     ```
     **Reason**: when Join between `orders` and `customers` becomes faster, foq queries sales per customer, qty order per customer etc.

2.   ```
     CREATE INDEX idx_orders_order_date
     ON orders(order_date DESC);
     ```
     **Reason**: faster for date range based queries.

3.   ```
     CREATE INDEX idx_order_items_order_id
     ON order_items(order_id);
     ```
     **Reason**: when Join between `order_items` and `orders` becomes faster, for queries detailed orders, qty item per order etc.

4.   ```
     CREATE INDEX idx_order_items_product_id
     ON order_items(product_id);
     ```
     **Reason**: when Join between `order_items` and `products` becomes faster, for queries detailed orders with product information.

5.   ```
     CREATE INDEX idx_orders_status_order_date
     ON orders(status, order_date DESC);
     ```
     **Reason**: if the user often query by date range and breakdown by order status



#### Schema Improvements
1.  **Use ENUM for `status` in table orders**  
   for column that is use fix category values we can use enum to prevent invalid or inconsistent data, also can save storage
2. **Add partition to `order_date` column in table orders**   
when partition the table, query become faster for spesific date range, and easier to maintenance (example for drop and replacing same partition)
3. **Add materialized views for monthly reports**  
for repeating reports like trend sales per month, top customer or top products. we can use materialized view , it save the result of query, without run/scan query manually, so the reports can load directly and reduce CPU load for repeated process.



### 1.2 Write Complex SQL Queries

Query 1: Customer Cohort Analysis with Running Totals Write a query that shows monthly customer acquisition and retention metrics:
- Group customers by the month they first ordered (cohort month)
- For each cohort month, show:
    - Number of new customers acquired
    - Total revenue from that cohort in their first month
    - Running total of all customers acquired up to that month
    - Percentage of customers from that cohort who ordered again in the following month (retention rate)
- Only include data from 2024
- Sort by cohort month


Required elements: Window functions (SUM OVER, LAG/LEAD), CTEs, date functions


Query 2: Product Performance with Ranking and Comparison Create a comprehensive product performance report:
- For each product, show:
    - Product name, category
    - Total revenue and units sold (all time)
    - Revenue rank within its category (1 = highest revenue)
    - Percentage of category's total revenue this product represents
    - Month-over-month revenue change for the last completed month vs previous month
    - Flag products that are in top 20% of their category by revenue
- Only include products that had at least one sale
- Sort by category, then revenue rank


Required elements: Window functions (RANK, PERCENT_RANK, SUM OVER PARTITION), CTEs, complex calculations


Query 3: Customer Segmentation with RFM Analysis Implement RFM (Recency, Frequency, Monetary) analysis to segment customers:
- Calculate for each customer:
    - Recency: Days since last order
    - Frequency: Total number of completed orders
    - Monetary: Total lifetime revenue
    - RFM Score: Assign scores 1-5 for each dimension (5 = best)
        - Recency: 5 = ordered in last 30 days, 1 = >365 days
        - Frequency: 5 = 20+ orders, 1 = 1-2 orders
        - Monetary: 5 = top 20% revenue, 1 = bottom 20%
    - Segment label based on combined score:
        - "Champions" (RFM >= 12)
        - "Loyal" (RFM 9-11)
        - "At Risk" (RFM 6-8)
        - "Lost" (RFM < 6)
- Return: customer name, email, recency days, frequency count, monetary value, rfm_score, segment
- Sort by RFM score descending


Required elements: CASE statements, NTILE or complex scoring logic, CTEs for multi-step calculation


Query 4: Advanced Sales Trend Analysis Create a query that analyzes sales trends and anomalies:
- For each day in the last 90 days, calculate:
    - Total orders and revenue
    - 7-day moving average of revenue
    - 7-day moving average of order count
    - Percentage difference between today's revenue and the 7-day average
    - Day of week
    - Flag days where revenue is >30% above or below the moving average
- Only include completed orders
- Include days with zero orders (should show 0, not be omitted)


Required elements: Window functions (AVG OVER with ROWS BETWEEN), date series generation, complex calculations


Query 5: Inventory Turnover and Stock Analysis Write a complex inventory analysis query:
- For each product, calculate:
    - Current stock quantity
    - Total units sold in last 90 days
    - Average daily sales rate (units/day)
    - Estimated days until stock out (current stock / daily rate)
    - Last order date
    - Stock status:
        - "Critical" if days until stockout < 7
        - "Low" if days until stockout 7-30
        - "Adequate" if days until stockout 30-90
        - "Overstocked" if days until stockout > 90
        - "Dead Stock" if no sales in 90 days but stock > 0
    - Reorder recommendation (quantity needed to maintain 45 days of stock)
- Include products with stock > 0 OR products sold in last 90 days
- Sort by stock status priority, then by days until stockout


Required elements: Complex CASE logic, date calculations, mathematical calculations, CTEs


Query 6: Customer Purchase Pattern Analysis Analyze customer purchase patterns across time:
- For each customer who ordered in 2024:
    - Customer name and email
    - Total number of orders
    - Average days between orders
    - Standard deviation of days between orders (consistency metric)
    - Most frequently purchased product category
    - Average order value
    - Trend indicator: "Increasing" if last 3 orders' average > first 3 orders' average, else "Decreasing"
    - Customer lifetime (days from first to last order)
- Only include customers with at least 3 orders
- Sort by number of orders descending
Required elements: Self-joins or window functions with LAG, aggregations, complex date math, string aggregation

