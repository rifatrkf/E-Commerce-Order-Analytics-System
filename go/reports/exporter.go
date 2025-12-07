package reports

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func ExportJSON(filename string, data interface{}) error {
	// Make sure the folder exists
	if err := os.MkdirAll(filepath.Dir(filename), 0755); err != nil {
		return fmt.Errorf("failed to create folder: %v", err)
	}

	file, err := os.Create(filename)
	if err != nil {
		return fmt.Errorf("failed to create file: %v", err)
	}
	defer file.Close()

	enc := json.NewEncoder(file)
	enc.SetIndent("", "  ")
	if err := enc.Encode(data); err != nil {
		return fmt.Errorf("failed to write JSON: %v", err)
	}

	fmt.Println("✅ Exported to:", filename)
	return nil
}

func TimestampedFilename(baseDir, name string) string {
	t := time.Now().Format("20060102_150405")
	return filepath.Join(baseDir, fmt.Sprintf("%s_%s.json", name, t))
}
