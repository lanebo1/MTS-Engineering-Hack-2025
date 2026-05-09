# Trivy Scanner Service

Trivy Scanner Service - это компонент системы безопасности контейнеров МТС, отвечающий за сканирование Docker образов на наличие уязвимостей безопасности.

## Обзор

Сервис предоставляет REST API для сканирования контейнерных образов с использованием Trivy - ведущего инструмента для сканирования уязвимостей. Сервис поддерживает:

- Сканирование образов на уязвимости (CVEs)
- Экспорт результатов в JSON формате
- Автоматическое обновление базы данных уязвимостей
- Интеграцию с Prometheus для мониторинга
- Масштабируемую архитектуру на базе Kubernetes

## API Endpoints

### POST /api/v1/scan

Запуск сканирования Docker образа на уязвимости.

**Запрос:**
```json
{
  "image": "nginx:1.21",
  "scan_types": ["os", "library"],
  "severity_levels": ["CRITICAL", "HIGH", "MEDIUM"],
  "format": "json",
  "skip_db_update": false
}
```

**Ответ:**
```json
{
  "success": true,
  "image": "nginx:1.21",
  "scan_time": "2024-01-01T12:00:00Z",
  "vulnerabilities": [
    {
      "id": "CVE-2023-12345",
      "severity": "CRITICAL",
      "cvss_score": 9.8,
      "package": "openssl",
      "version": "1.1.1",
      "fixed_version": "1.1.1u",
      "description": "Buffer overflow vulnerability"
    }
  ],
  "summary": {
    "total": 15,
    "critical": 2,
    "high": 5,
    "medium": 8
  }
}
```

### GET /health

Проверка здоровья сервиса.

**Ответ:**
```json
{
  "status": "healthy",
  "service": "trivy-scanner",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### GET /ready

Проверка готовности сервиса.

**Ответ:**
```json
{
  "status": "ready",
  "service": "trivy-scanner",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

## Конфигурация

### Переменные окружения

| Переменная | Описание | Значение по умолчанию |
|------------|----------|----------------------|
| `LOG_LEVEL` | Уровень логирования | `info` |
| `TRIVY_CACHE_DIR` | Директория для кэша Trivy | `/opt/trivy/cache` |
| `TRIVY_REPORTS_DIR` | Директория для отчетов | `/opt/trivy/reports` |
| `TRIVY_TIMEOUT` | Таймаут сканирования | `5m` |
| `TRIVY_SKIP_DB_UPDATE` | Пропустить обновление БД | `false` |
| `TRIVY_UPDATE_INTERVAL` | Интервал обновления БД | `24h` |

## Установка и запуск

### Локальный запуск

1. **Сборка Docker образа:**
```bash
docker build -f docker/trivy-scanner.Dockerfile -t trivy-scanner:latest .
```

2. **Запуск сервиса:**
```bash
docker run -p 8080:8080 \
  -e LOG_LEVEL=debug \
  -v $(pwd)/cache:/opt/trivy/cache \
  -v $(pwd)/reports:/opt/trivy/reports \
  trivy-scanner:latest
```

### Kubernetes развертывание

1. **Создание namespace:**
```bash
kubectl create namespace container-security
```

2. **Применение манифестов:**
```bash
kubectl apply -f deploy/k8s/trivy/
```

3. **Проверка развертывания:**
```bash
kubectl get pods -n container-security
kubectl logs -n container-security deployment/trivy-scanner
```

## Тестирование

### Запуск тестов

```bash
chmod +x scripts/test-trivy-scanner.sh
./scripts/test-trivy-scanner.sh
```

Тесты проверяют:
- Доступность endpoints
- Функциональность сканирования
- Обработку ошибок
- Формат ответов

### Ручное тестирование

```bash
# Проверка здоровья
curl http://localhost:8080/health

# Сканирование образа
curl -X POST http://localhost:8080/api/v1/scan \
  -H "Content-Type: application/json" \
  -d '{"image": "nginx:1.21"}'
```

## Мониторинг

### Prometheus метрики

Сервис экспортирует следующие метрики:

```
# HELP container_security_scans_total Total number of container scans performed
# TYPE container_security_scans_total counter
container_security_scans_total{result="success"} 150

# HELP container_security_scan_duration_seconds Time taken to perform container scans
# TYPE container_security_scan_duration_seconds histogram
container_security_scan_duration_seconds_bucket{le="1"} 0
```

### Логи

Логи структурированы в JSON формате и включают:
- Уровень логирования
- Временные метки
- Информацию о запросах
- Ошибки и предупреждения

## Автоматическое обновление базы данных

Сервис поддерживает два механизма обновления базы уязвимостей:

1. **Background процесс** - обновление каждые 24 часа
2. **CronJob** - ежедневное обновление в 2:00 ночи

Обновления происходят автоматически и не требуют перезапуска сервиса.

## Производительность

### Рекомендуемые ресурсы

- **CPU:** 100m - 500m
- **Memory:** 256Mi - 512Mi
- **Storage:** 5Gi для кэша, 10Gi для отчетов

### Оптимизация

- Использование persistent volumes для кэша
- Масштабирование до 2+ реплик
- Настройка resource limits

## Безопасность

### Best practices

- Запуск от непривилегированного пользователя
- Использование read-only файловой системы где возможно
- Ограничение сетевых доступов
- Регулярное обновление базовых образов

### RBAC

Сервис использует минимально необходимые права Kubernetes:
- Доступ к pods, services, endpoints в своем namespace
- Нет доступа к секретам или конфигмапам других сервисов

## Troubleshooting

### Распространенные проблемы

1. **Database update fails**
   ```
   Решение: Проверить сетевой доступ к GitHub/Trivy DB
   ```

2. **Scan timeout**
   ```
   Решение: Увеличить TRIVY_TIMEOUT или оптимизировать образ
   ```

3. **High memory usage**
   ```
   Решение: Настроить resource limits или увеличить память
   ```

### Debug режим

```bash
# Включение debug логов
export LOG_LEVEL=debug

# Проверка логов
kubectl logs -n container-security deployment/trivy-scanner -f
```

## Архитектура

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   HTTP Client   │───▶│  Trivy Scanner  │───▶│     Trivy CLI   │
│                 │    │    Service      │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  Vulnerability   │
                       │     Database     │
                       └──────────────────┘
```

## Интеграция

Сервис интегрируется с другими компонентами системы:

- **Admission Webhook**: Получает результаты сканирования
- **OPA Engine**: Предоставляет данные для политик
- **Notification Service**: Отправляет алерты
- **Monitoring**: Экспортирует метрики
