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
