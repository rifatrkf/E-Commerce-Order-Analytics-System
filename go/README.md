This Go program connects to PostgreSQL and runs my SQL reports automatically.
I made it as a command-line tool with flags. You can choose which report to run and export the result as JSON.

Example:
```
go run main.go --report=rfm --output=reports/
```
The code uses standard database/sql with simple error handling.
I tried to keep the structure clean by separating files for DB connection, queries, and export.
It also logs the execution time and number of rows fetched.


# Go Automation Tool

A simple Go program that connects to PostgreSQL, runs SQL reports, exports results to JSON, and sends a daily sales summary to a REST API.  
Built for learning and automating data reporting tasks in a clean and easy way.


## Features
- Run SQL reports (RFM, Cohort)
- Export results as JSON with timestamp
- Send daily sales summary to BI API
- Retry API calls up to 3 times
- Clear logging and simple error handling


## How to Run

Run SQL reports:
```
go run main.go --report=rfm --output=reports/
```

## Cron Scheduling Example 
Automate daily report at 8 AM:

```
0 8 * * * API_TOKEN="your_token" go run main.go --report=daily_sales_api --date=$(date +\%F)
```

## Package Structure
```
go/
├── main.go
├── db/connection.go
├── reports/queries.go
├── reports/exporter.go
├── api/api_integration.go
├── utils/logger.go
```

## Error Handling
- Shows clear messages for database, query, or API errors
- Skips problematic rows instead of stopping
- Retries API requests 3 times if failed
