This Go program connects to PostgreSQL and runs my SQL reports automatically.
I made it as a command-line tool with flags. You can choose which report to run and export the result as JSON.

Example:
```
go run main.go --report=rfm --output=reports/
```
The code uses standard database/sql with simple error handling.
I tried to keep the structure clean by separating files for DB connection, queries, and export.
It also logs the execution time and number of rows fetched.
