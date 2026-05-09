package notifications

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"

	"container-security-mts/pkg/utils"

	"gopkg.in/yaml.v2"
)

// NewNotifier creates a new Telegram notifier based on configuration
func NewNotifier(config *Config, logger *utils.Logger) Notifier {
	if !config.Enabled || config.BotToken == "" || config.ChatID == "" {
		logger.Info("Telegram notifications disabled or not configured")
		return &TelegramNotifier{config: config}
	}

	logger.Info("Telegram notifications enabled")
	return &TelegramNotifier{config: config}
}

// NewTelegramNotifier creates a new Telegram notifier
func NewTelegramNotifier(config *Config) *TelegramNotifier {
	return &TelegramNotifier{config: config}
}

// Send sends a notification via Telegram
func (t *TelegramNotifier) Send(notification *Notification) error {
	if !t.Enabled() {
		return nil
	}

	// Check if notification should be sent based on filters
	if !t.shouldSendNotification(notification) {
		return nil
	}

	message := t.formatTelegramMessage(notification)

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", t.config.BotToken)

	payload := map[string]interface{}{
		"chat_id":    t.config.ChatID,
		"text":       message,
		"parse_mode": "HTML",
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal Telegram payload: %w", err)
	}

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonPayload))
	if err != nil {
		return fmt.Errorf("failed to send Telegram notification: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Telegram notification failed with status: %d", resp.StatusCode)
	}

	return nil
}

// Enabled returns true if Telegram notifications are enabled
func (t *TelegramNotifier) Enabled() bool {
	return t.config.Enabled && t.config.BotToken != "" && t.config.ChatID != ""
}

// shouldSendNotification checks if a notification should be sent based on configuration
func (t *TelegramNotifier) shouldSendNotification(notification *Notification) bool {
	// Check if notification type is enabled
	if len(t.config.EnabledTypes) > 0 {
		typeEnabled := false
		for _, enabledType := range t.config.EnabledTypes {
			if enabledType == notification.Type {
				typeEnabled = true
				break
			}
		}
		if !typeEnabled {
			return false
		}
	}

	// Check severity threshold
	minSeverity := t.config.MinSeverity
	if minSeverity != "" && !t.isSeverityAboveThreshold(notification.Severity, minSeverity) {
		return false
	}

	return true
}

// formatTelegramMessage formats a notification for Telegram
func (t *TelegramNotifier) formatTelegramMessage(notification *Notification) string {
	var emoji string
	switch strings.ToLower(notification.Severity) {
	case "critical":
		emoji = "🚨"
	case "high":
		emoji = "⚠️"
	case "medium":
		emoji = "⚡"
	case "low":
		emoji = "ℹ️"
	default:
		emoji = "📢"
	}

	message := fmt.Sprintf("%s <b>%s</b>\n\n%s\n\n🔴 <b>Severity:</b> %s\n🕐 <b>Time:</b> %s",
		emoji,
		notification.Title,
		notification.Message,
		strings.Title(notification.Severity),
		notification.Timestamp.Format("2006-01-02 15:04:05 UTC"),
	)

	if len(notification.Details) > 0 {
		message += "\n\n📋 <b>Details:</b>\n"
		for key, value := range notification.Details {
			message += fmt.Sprintf("• <b>%s:</b> %v\n", key, value)
		}
	}

	return message
}

// isSeverityAboveThreshold checks if severity level meets the minimum threshold
func (t *TelegramNotifier) isSeverityAboveThreshold(severity, threshold string) bool {
	severityLevels := map[string]int{
		"low":      1,
		"medium":   2,
		"high":     3,
		"critical": 4,
	}

	currentLevel, exists := severityLevels[strings.ToLower(severity)]
	if !exists {
		return false
	}

	thresholdLevel, exists := severityLevels[strings.ToLower(threshold)]
	if !exists {
		return false
	}

	return currentLevel >= thresholdLevel
}

// LoadConfig loads configuration from a YAML file
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	return &config, nil
}

// DefaultConfig returns default notification configuration
func DefaultConfig() *Config {
	return &Config{
		Enabled:     false,
		BotToken:    "",
		ChatID:      "",
		MinSeverity: "medium",
		EnabledTypes: []NotificationType{
			NotificationTypeSecurityAlert,
		},
	}
}
