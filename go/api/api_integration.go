package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
)

// Structure for the API payload
type SalesSummary struct {
	ReportType  string    `json:"report_type"`
	Date        string    `json:"date"`
	Data        SalesData `json:"data"`
	GeneratedAt string    `json:"generated_at"`
}

type SalesData struct {
	TotalRevenue      float64 `json:"total_revenue"`
	TotalOrders       int     `json:"total_orders"`
	AverageOrderValue float64 `json:"average_order_value"`
	TopCategory       string  `json:"top_category"`
}

// GenerateDailySalesSummary collects summary from database for given date
func GenerateDailySalesSummary(db *sql.DB, date string) (*SalesSummary, error) {
	// Query total revenue, total orders, average order value
	query := `
		SELECT
			COALESCE(SUM(total_amount), 0) AS total_revenue,
			COUNT(id) AS total_orders,
			CASE WHEN COUNT(id) = 0 THEN 0 ELSE SUM(total_amount) / COUNT(id) END AS avg_order_value
		FROM orders
		WHERE status = 'completed'
		  AND DATE(order_date) = $1;
	`

	row := db.QueryRow(query, date)

	var totalRevenue float64
	var totalOrders int
	var avgOrderValue float64

	err := row.Scan(&totalRevenue, &totalOrders, &avgOrderValue)
	if err != nil {
		return nil, fmt.Errorf("failed to scan daily sales summary: %v", err)
	}

	// Query top category by revenue
	topCategoryQuery := `
		SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
		FROM order_items oi
		JOIN products p ON p.id = oi.product_id
		JOIN orders o ON o.id = oi.order_id
		WHERE o.status = 'completed'
		  AND DATE(o.order_date) = $1
		GROUP BY p.category
		ORDER BY revenue DESC
		LIMIT 1;
	`

	var topCategory string
	err = db.QueryRow(topCategoryQuery, date).Scan(&topCategory)
	if err == sql.ErrNoRows {
		topCategory = "N/A"
	} else if err != nil {
		return nil, fmt.Errorf("failed to scan top category: %v", err)
	}

	// Build summary struct
	summary := &SalesSummary{
		ReportType: "daily_sales",
		Date:       date,
		Data: SalesData{
			TotalRevenue:      totalRevenue,
			TotalOrders:       totalOrders,
			AverageOrderValue: avgOrderValue,
			TopCategory:       topCategory,
		},
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
	}

	return summary, nil
}

// SendReport sends JSON payload to the BI platform API
func SendReport(summary *SalesSummary) error {
	apiURL := "https://api.bi-platform.com/v1/reports"
	apiToken := os.Getenv("API_TOKEN")

	if apiToken == "" {
		return fmt.Errorf("missing API_TOKEN environment variable")
	}

	payload, err := json.Marshal(summary)
	if err != nil {
		return fmt.Errorf("failed to encode report payload: %v", err)
	}

	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(payload))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiToken)

	client := &http.Client{Timeout: 10 * time.Second}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("API returned an error: %s", resp.Status)
	}

	fmt.Println("Report successfully sent to BI platform")
	return nil
}

// RetrySendReport tries sending report up to 3 times if there’s an error
func RetrySendReport(summary *SalesSummary) error {
	var err error
	for i := 1; i <= 3; i++ {
		err = SendReport(summary)
		if err == nil {
			return nil
		}
		fmt.Printf("Retry %d failed: %v\n", i, err)
		time.Sleep(3 * time.Second)
	}
	return fmt.Errorf("failed to send report after retries: %v", err)
}
