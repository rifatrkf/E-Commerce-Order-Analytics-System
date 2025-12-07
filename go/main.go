package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"go-example/api"     // new package for REST API integration
	"go-example/db"
	"go-example/reports"
	"go-example/utils"
)

func main() {
	// Command-line flags
	report := flag.String("report", "", "Report type (customer_cohort, rfm, or daily_sales_api)")
	output := flag.String("output", "reports/", "Output folder path")
	date := flag.String("date", time.Now().Format("2006-01-02"), "Report date (YYYY-MM-DD)") // new for API feature
	flag.Parse()

	if *report == "" {
		fmt.Println("Usage: go run main.go --report=rfm")
		os.Exit(1)
	}

	startTime := time.Now()
	utils.Log(fmt.Sprintf("Starting report: %s", *report))

	conn, err := db.Connect()
	if err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}
	defer conn.Close()

	switch *report {
	case "customer_cohort":
		runSQLReport(conn, reports.QueryCustomerCohortAnalysis, *output, *report, startTime)

	case "rfm":
		runSQLReport(conn, reports.QueryCustomerRFM, *output, *report, startTime)

	case "daily_sales_api":
		runDailySalesAPI(conn, *date)

	default:
		log.Fatalf("Unknown report: %s", *report)
	}
}

// runSQLReport handles normal query reports
func runSQLReport(conn *sql.DB, query, output, report string, startTime time.Time) {
	rows, err := conn.Query(query)
	if err != nil {
		log.Fatalf("Query execution failed: %v", err)
	}
	defer rows.Close()

	cols, _ := rows.Columns()
	count := 0
	results := []map[string]interface{}{}

	for rows.Next() {
		colsData := make([]interface{}, len(cols))
		colsPointers := make([]interface{}, len(cols))
		for i := range colsData {
			colsPointers[i] = &colsData[i]
		}

		if err := rows.Scan(colsPointers...); err != nil {
			log.Println("Scan error:", err)
			continue
		}

		rowMap := make(map[string]interface{})
		for i, colName := range cols {
			val := colsData[i]
			switch v := val.(type) {
			case []byte:
				rowMap[colName] = string(v)
			default:
				rowMap[colName] = v
			}
		}
		results = append(results, rowMap)
		count++
	}

	utils.Log(fmt.Sprintf("Rows fetched: %d", count))
	utils.Log(fmt.Sprintf("Execution time: %v", time.Since(startTime)))

	filename := reports.TimestampedFilename(output, report)
	if err := reports.ExportJSON(filename, results); err != nil {
		log.Fatalf("Export failed: %v", err)
	}

	utils.Log("Report completed successfully")
}

// runDailySalesAPI handles the daily sales summary API integration
func runDailySalesAPI(conn *sql.DB, date string) {
	utils.Log(fmt.Sprintf("Generating daily sales summary for %s", date))

	summary, err := api.GenerateDailySalesSummary(conn, date)
	if err != nil {
		log.Fatalf("Failed to generate sales summary: %v", err)
	}

	utils.Log("Sending report to BI platform API...")
	if err := api.RetrySendReport(summary); err != nil {
		log.Fatalf("Failed to send report: %v", err)
	}

	utils.Log("Daily sales report successfully sent")
}
