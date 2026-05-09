# Архитектура системы безопасности контейнеров МТС

## Обзор архитектуры

Система безопасности контейнеров для МТС представляет собой комплексное решение, интегрирующее несколько открытых инструментов для обеспечения безопасности контейнеризированных приложений в телеком-инфраструктуре.

## Компоненты системы

### 1. Trivy Scanner (Сканирование уязвимостей)
- **Функция**: Сканирование Docker образов на наличие уязвимостей (CVEs)
- **Интерфейс**: REST API / CLI
- **Выход**: JSON отчет с найденными уязвимостями и их severity

### 2. Cosign Signer (Подписи образов)
- **Функция**: Генерация и верификация цифровых подписей образов
- **Интерфейс**: CLI / REST API
- **Методы**: Keyless signing (OIDC) или с использованием ключей

### 3. OPA Policy Engine (Политики безопасности)
- **Функция**: Оценка политик безопасности на языке Rego
- **Интерфейс**: REST API для оценки политик
- **Политики**: Блокировка по CVSS score, требование подписей, compliance проверки

### 4. Kubernetes Admission Webhook
- **Функция**: Автоматическая блокировка развертывания уязвимых образов
- **Интерфейс**: Kubernetes ValidatingAdmissionWebhook
- **Логика**: Интеграция Trivy + Cosign + OPA для принятия решений allow/deny

## Поток данных

```
Docker Registry → CI/CD Pipeline → Trivy Scan → Cosign Verify → OPA Evaluate → Webhook Decision → K8s API Server
```

## Интерфейсы взаимодействия

### Trivy ↔ Webhook
- **Протокол**: HTTP REST API
- **Метод**: POST /scan
- **Вход**: {"image": "registry/image:tag"}
- **Выход**: {"vulnerabilities": [...], "severity": "HIGH|CRITICAL"}

### Cosign ↔ Webhook
- **Протокол**: HTTP REST API
- **Метод**: POST /verify
- **Вход**: {"image": "registry/image:tag", "key": "cosign.pub"}
- **Выход**: {"verified": true|false, "signature": "..."}

### OPA ↔ Webhook
- **Протокол**: HTTP REST API
- **Метод**: POST /evaluate
- **Вход**: {"scan_results": {...}, "signature_verified": true, "policies": [...]}
- **Выход**: {"allow": true|false, "reason": "..."}

### Webhook ↔ Kubernetes API Server
- **Протокол**: HTTPS (mutual TLS)
- **Формат**: AdmissionReview request/response
- **Решение**: allow/deny с причиной

## Дополнительные компоненты

### CI/CD Integration (GitHub Actions)
- **Функция**: Автоматизация сканирования и подписывания
- **Триггеры**: Push, PR, release
- **Шаги**: build → scan → sign → push

### Monitoring (Prometheus)
- **Метрики**:
  - container_security_scans_total
  - container_security_blocks_total
  - container_security_signatures_verified_total

### Notifications (Telegram/Slack)
- **События**: Блокировка развертывания, критические уязвимости
- **Формат**: JSON webhook с деталями инцидента

## Безопасность и compliance

### Для МТС (телеком):
- **Zero-trust**: Все образы проверяются перед развертыванием
- **Chain of custody**: Полная traceability от build до deploy
- **Compliance**: Поддержка российских стандартов безопасности
- **High availability**: Redundant компоненты для телеком SLA

### Регуляторные требования:
- **GDPR**: Защита данных в контейнерах
- **ФСТЭК**: Российские стандарты криптографической защиты
- **PCI DSS**: Для платежных сервисов МТС
