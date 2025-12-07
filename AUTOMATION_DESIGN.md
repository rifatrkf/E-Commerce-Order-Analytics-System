# Automation Design Document
## 3.1 Automation Opportunity Identification
1. **Approach**  

The business team still runs some reports manually every week, such as sales reports, stock alerts, and customer churn analysis.
My goal is to make these reports fully automated using a small, reliable system that can run on schedule without human work.

The main idea is to build an automated reporting service that runs my SQL scripts on a fixed schedule, exports the result into JSON or CSV, and notifies the business team when the report is ready.

Each report will have its own query file and schedule (daily, weekly, or monthly).
This way, it is easy to add or remove reports in the future.

2. **Architecture**  

The system will follow a simple and modular structure.
It uses a scheduler to trigger the reporting tool, which connects to the PostgreSQL database, runs the SQL, saves the data, and sends a notification.

How it works step by step:

  1. Scheduler  
  A scheduler such as a Linux cronjob or simple task runner (for example, Airflow later) will run the Go reporting program automatically.
  The schedule depends on the report type (daily, weekly, or monthly).
  For example, the low-stock alert runs every morning, while the monthly revenue report runs on the first day of each month.

  2. Go Report Tool    
  The Go tool handles the main logic.
  It connects to PostgreSQL using environment variables, executes the SQL query, and saves the output file in JSON or CSV format.
  The filename includes a timestamp to track history (for example: sales_2025-01-06_08-00.json).

  3. Storage Layer  
  The generated reports are stored in a specific folder on the server.
  Later, we can move this to cloud storage such as Amazon S3 or Google Cloud Storage if we need to share files or keep history longer.

  4. Notification System  
    After a report is finished, a simple email or Slack notification is sent to the business team.
    The message includes the report name, time, and link or path to the file.

  5. Logging and Monitoring  
  The program logs when the report starts, how long it takes, and if any error occurs.
  Logs are saved locally or printed to stdout so they can be viewed in server logs.

This approach keeps the system lightweight, low-cost, and easy to maintain.
It does not need complex infrastructure at the beginning, but can still grow later if the workload increases.


3. **Technology Choices**

- PostgreSQL
- Go CL
- Cron Job / Apache Airflow
- AWS S3 / GCS
- 
For the database, I will continue using **PostgreSQL**, because the system already uses it and it supports all the queries from Part 1.

The reporting process will use my **Go command-line tool** from Part 2, since it can connect to PostgreSQL and export reports in JSON.
For scheduling, I plan to start with a **cron job** on Linux. Cron is lightweight and reliable for time-based tasks.
If the company later needs more control or tracking, we can switch to **Apache Airflow or another workflow tool**.

Report files will be saved locally first, but for larger use, I would move them to **AWS S3** or **Goggle Cloud Storage** for better storage and sharing.
For team notifications, **Slack or simple email** alerts can be added easily using an API.
Finally, all logs can be printed to the console or written to a local log file for quick review.

4. **Prioritization**  
  If I need to choose which automation to build first, I will start with the **Low Stock Alert**.
  This one runs every day and has the biggest impact, because if stock runs out, the business can lose sales.
  Next, I will automate the **Weekly Sales Report**, since it is also repeated often but not as critical as stock.
  The **Monthly Revenue by Category** and **Customer Churn Report** can come next because they are less frequent.
  
  Priority order:
  
    1. Low stock alert (daily)
    2. Weekly sales report
    3. Monthly revenue by category
    4. Customer churn risk analysis

5. **Scalability**  
At first, this system can run on one small server using cron jobs.
If later the business needs to run so much reports (for example 15 or more), I can make the system more scalable.
Some ideas for scaling:
- Use database connection pooling to handle multiple queries safely.
- Add retries and error handling so failed reports can re-run automatically.
- Move from cron to a workflow manager like Airflow if the job list becomes large.

This approach can grow step by step. It starts simple, but can expand without changing the whole design.

## 3.2 Query Performance Debugging
1. Root Cause (Why the query is slow)  
The main reason this query is slow is because the database does not have any supporting indexes other than primary keys (like in part 1).

When we filter with `WHERE o.order_date >= '2024-01-01'`, PostgreSQL must scan all 15 million rows in the orders table to find matching records.

Also, the query uses a `LEFT JOIN` between a very large customers table (2 million rows) and orders.
This means the database has to check every possible match, which creates a lots of work.

Finally, the aggregation part `COUNT(o.id)` and `SUM(o.total_amount)` adds extra computation, and sorting by `total_revenue DESC` on millions of rows makes it even slower.
Because there is no index on order_date or customer_id, the system cannot jump directly to relevant rows — it has to read everything.

So the query is slow because:
- No index on orders.order_date or orders.customer_id
- Large number of rows being scanned
- Heavy aggregation and sorting on big tables


2. Quick Fixes
  1. Add index on order_date  
    This helps PostgreSQL find the orders for 2024 faster without scanning the whole table.
    ```
    CREATE INDEX idx_orders_order_date ON orders(order_date);
    ```

  2. Add index on customer_id in orders  
  This helps us to join between customers and orders.
  ```
  CREATE INDEX idx_orders_customer_id ON orders(customer_id);
  ```

  3. Change `LEFT JOIN` to `INNER JOIN`
  In this case, we only want customers who have more than 5 orders.
  A `LEFT JOIN` is not needed because customers with zero orders will be removed by the` HAVING` condition anyway.


3. Long-term Solutions
  1. Partition the orders table by year or month  
  For example, create partitions for each year (orders_2024, orders_2025, etc.).
  This allows PostgreSQL to only scan data for 2024 instead of the whole table.

  2. Create materialized views for frequent reports  
  If this query is used often (like in weekly reports), store the aggregated results in a materialized view and refresh it daily or weekly. This avoids repeating calculation.

  3. Maintain summary tables  
  Have a separate table that stores order_count and total_revenue per customer.
  Update this table whenever a new order is inserted.
  Then the report query only needs to read from this smaller summary table.

4. Updated Query

```
   -- Index first
  CREATE INDEX idx_orders_order_date ON orders(order_date);
  CREATE INDEX idx_orders_customer_id ON orders(customer_id);

  -- Optimized query
  SELECT
      c.name,
      c.email,
      COUNT(o.id) AS order_count,
      SUM(o.total_amount) AS total_revenue
  FROM customers c
  INNER JOIN orders o
      ON c.id = o.customer_id
  WHERE o.order_date >= '2024-01-01'
  GROUP BY c.id, c.name, c.email
  HAVING COUNT(o.id) > 5
  ORDER BY total_revenue DESC;
```
