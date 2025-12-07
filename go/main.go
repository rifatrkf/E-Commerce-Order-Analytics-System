package main

import (
	"database/sql"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"go-example/db"
	"go-example/reports"
	"go-example/utils"
)

func main() {
	// Command-line flags
	report := flag.String("report", "", "Report type (customer_cohort or rfm)")
	output := flag.String("output", "reports/", "Output folder path")
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

	var query string
	switch *report {
	case "customer_cohort":
		query = reports.QueryCustomerCohortAnalysis
	case "rfm":
		query = reports.QueryCustomerRFM
	default:
		log.Fatalf("Unknown report: %s", *report)
	}

	rows, err := conn.Query(query)
	if err != nil {
		log.Fatalf("Query execution failed: %v", err)
	}
	defer rows.Close()

	// Read result dynamically (works for any query)
	cols, _ := rows.Columns()
	count := 0
	results := []map[string]interface{}{}

	for rows.Next() {
		// Use sql.RawBytes for generic scanning
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

	// Log and export
	utils.Log(fmt.Sprintf("Rows fetched: %d", count))
	utils.Log(fmt.Sprintf("Execution time: %v", time.Since(startTime)))

	filename := reports.TimestampedFilename(*output, *report)
	if err := reports.ExportJSON(filename, results); err != nil {
		log.Fatalf("Export failed: %v", err)
	}

	utils.Log("Report completed successfully")
}
