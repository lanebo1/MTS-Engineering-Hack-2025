package notifications

import "time"

// NotificationType represents the type of notification
type NotificationType string

const (
	NotificationTypeSecurityAlert   NotificationType = "security_alert"
	NotificationTypeScanComplete    NotificationType = "scan_complete"
	NotificationTypePolicyViolation NotificationType = "policy_violation"
)

// Notification represents a notification to be sent
type Notification struct {
	Type      NotificationType       `json:"type"`
	Title     string                 `json:"title"`
	Message   string                 `json:"message"`
	Severity  string                 `json:"severity"`
	Timestamp time.Time              `json:"timestamp"`
	Details   map[string]interface{} `json:"details,omitempty"`
}

// Config represents the configuration for Telegram notifications
type Config struct {
	Enabled bool `yaml:"enabled" json:"enabled"`

	// Telegram configuration
	BotToken string `yaml:"botToken" json:"bot_token"`
	ChatID   string `yaml:"chatId" json:"chat_id"`

	// Notification filters
	MinSeverity  string             `yaml:"minSeverity" json:"min_severity"` // "low", "medium", "high", "critical"
	EnabledTypes []NotificationType `yaml:"enabledTypes" json:"enabled_types"`
}

// Notifier interface for sending notifications
type Notifier interface {
	Send(notification *Notification) error
	Enabled() bool
}

// TelegramNotifier sends notifications to Telegram
type TelegramNotifier struct {
	config *Config
}
