package utils

import (
	"os"
	"strconv"
	"time"
)

// GetEnvString gets a string environment variable with a default value
func GetEnvString(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// GetEnvInt gets an integer environment variable with a default value
func GetEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

// GetEnvBool gets a boolean environment variable with a default value
func GetEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}

// GetEnvDuration gets a duration environment variable with a default value
func GetEnvDuration(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}

// ValidateConfig validates configuration values
func ValidateConfig() error {
	// Add configuration validation logic here
	return nil
}

// LoadConfigFromEnv loads configuration from environment variables
func LoadConfigFromEnv() map[string]interface{} {
	config := make(map[string]interface{})

	// Common environment variables
	config["log_level"] = GetEnvString("LOG_LEVEL", "info")
	config["port"] = GetEnvInt("PORT", 8080)
	config["host"] = GetEnvString("HOST", "0.0.0.0")

	// Trivy specific
	config["trivy_cache_dir"] = GetEnvString("TRIVY_CACHE_DIR", "/opt/trivy/cache")
	config["trivy_reports_dir"] = GetEnvString("TRIVY_REPORTS_DIR", "/opt/trivy/reports")
	config["trivy_timeout"] = GetEnvDuration("TRIVY_TIMEOUT", 5*time.Minute)
	config["trivy_skip_db_update"] = GetEnvBool("TRIVY_SKIP_DB_UPDATE", false)
	config["trivy_update_interval"] = GetEnvDuration("TRIVY_UPDATE_INTERVAL", 24*time.Hour)

	return config
}
