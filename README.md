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
