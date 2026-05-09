# Интерфейсы взаимодействия компонентов

## 1. Trivy Scanner API

### Эндпоинт: POST /api/v1/scan
**Описание**: Запуск сканирования Docker образа на уязвимости

**Входные данные**:
```json
{
  "image": "registry.example.com/app:tag",
  "scan_types": ["os", "library"],
  "severity_levels": ["CRITICAL", "HIGH", "MEDIUM"],
  "format": "json"
}
```

**Выходные данные**:
```json
{
  "success": true,
  "image": "registry.example.com/app:tag",
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

## 2. Cosign Signature API

### Эндпоинт: POST /api/v1/sign
**Описание**: Подписание Docker образа

**Входные данные**:
```json
{
  "image": "registry.example.com/app:tag",
  "key_type": "keyless",
  "oidc_provider": "github",
  "repository": "owner/repo"
}
```

**Выходные данные**:
```json
{
  "success": true,
  "image": "registry.example.com/app:tag",
  "signature": "MEUCIQC...",
  "certificate": "LS0tLS1CRUdJTi...",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Эндпоинт: POST /api/v1/verify
**Описание**: Верификация подписи образа

**Входные данные**:
```json
{
  "image": "registry.example.com/app:tag",
  "expected_key": "cosign.pub",
  "check_expiry": true
}
```

**Выходные данные**:
```json
{
  "verified": true,
  "image": "registry.example.com/app:tag",
  "signer": "CN=cosign,O=...",
  "timestamp": "2024-01-01T12:00:00Z",
  "expiry": "2025-01-01T12:00:00Z"
}
```

## 3. OPA Policy Engine API

### Эндпоинт: POST /v1/data/container_security
**Описание**: Оценка политик безопасности

**Входные данные**:
```json
{
  "input": {
    "image": "registry.example.com/app:tag",
    "scan_results": {
      "vulnerabilities": [...],
      "summary": {"critical": 2, "high": 5}
    },
    "signature_verified": true,
    "deployment_context": {
      "namespace": "production",
      "environment": "prod",
      "team": "backend"
    }
  }
}
```

**Выходные данные**:
```json
{
  "result": [
    {
      "expressions": [
        {
          "value": {
            "allow": false,
            "reason": "Image contains 2 critical vulnerabilities",
            "policy_id": "block_critical_vulns",
            "severity": "CRITICAL"
          }
        }
      ]
    }
  ]
}
```

## 4. Admission Webhook API

### Kubernetes AdmissionReview Request
**Входные данные от K8s API Server**:
```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "12345678-1234-1234-1234-123456789012",
    "kind": {"group": "apps", "version": "v1", "kind": "Deployment"},
    "resource": {"group": "apps", "version": "v1", "resource": "deployments"},
    "name": "my-app",
    "namespace": "default",
    "operation": "CREATE",
    "object": {
      "spec": {
        "template": {
          "spec": {
            "containers": [
              {
                "name": "app",
                "image": "registry.example.com/app:tag"
              }
            ]
          }
        }
      }
    }
  }
}
```

### AdmissionReview Response
**Выходные данные к K8s API Server**:
```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "12345678-1234-1234-1234-123456789012",
    "allowed": false,
    "status": {
      "code": 403,
      "message": "Image blocked: contains 2 critical vulnerabilities. Policy: block_critical_vulns"
    }
  }
}
```

## 5. Monitoring API (Prometheus Metrics)

### Метрики для экспорта:
```
# HELP container_security_scans_total Total number of container scans performed
# TYPE container_security_scans_total counter
container_security_scans_total{result="success"} 150
container_security_scans_total{result="failed"} 3

# HELP container_security_blocks_total Total number of deployments blocked
# TYPE container_security_blocks_total counter
container_security_blocks_total{reason="vulnerabilities"} 12
container_security_blocks_total{reason="signature"} 5

# HELP container_security_signatures_verified_total Total signatures verified
# TYPE container_security_signatures_verified_total counter
container_security_signatures_verified_total{result="valid"} 145
container_security_signatures_verified_total{result="invalid"} 5
```

## 6. Notification API (Telegram/Slack Webhook)

### Формат уведомления:
```json
{
  "event_type": "deployment_blocked",
  "timestamp": "2024-01-01T12:00:00Z",
  "details": {
    "image": "registry.example.com/app:tag",
    "namespace": "production",
    "reason": "Critical vulnerabilities found",
    "vulnerabilities_count": 2,
    "policy_violated": "block_critical_vulns"
  },
  "severity": "CRITICAL",
  "recommended_action": "Update base image or apply security patches"
}
```

## Протоколы коммуникации

- **Внутри кластера**: HTTP/REST API с mTLS
- **С внешними сервисами**: HTTPS с JWT аутентификацией
- **Мониторинг**: Prometheus pull model
- **Уведомления**: Webhook push model

## Обработка ошибок

Все API возвращают стандартный формат ошибок:
```json
{
  "error": {
    "code": "SCAN_FAILED",
    "message": "Failed to scan image: connection timeout",
    "details": {...},
    "timestamp": "2024-01-01T12:00:00Z"
  }
}
```
