package utils

import (
	"fmt"
	"time"
)

func Log(message string) {
	fmt.Printf("[%s] %s\n", time.Now().Format("15:04:05"), message)
}
