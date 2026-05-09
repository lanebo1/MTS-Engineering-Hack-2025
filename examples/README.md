# Примеры использования системы безопасности контейнеров МТС

Этот каталог содержит практические примеры использования системы безопасности контейнеров для различных сценариев.

## 📁 Структура примеров

### `secure-deployment.yaml`
Пример безопасного развертывания приложения МТС, которое пройдет все проверки системы безопасности:
- Подписанный образ из доверенного registry
- Корректные security contexts
- Resource limits и requests
- Health checks
- Service account с минимальными правами

### `vulnerable-deployment.yaml`
Примеры развертываний, которые будут заблокированы системой безопасности:
- Образ с известными уязвимостями (nginx:1.21)
- Неподписанный образ из публичного registry
- Отсутствие security contexts

### `demo-security-system.sh`
Интерактивный демо-скрипт для демонстрации работы системы:
```bash
# Полная демонстрация
./examples/demo-security-system.sh

# Отдельные сценарии
./examples/demo-security-system.sh secure      # Безопасное развертывание
./examples/demo-security-system.sh vulnerable  # Блокировка уязвимого
./examples/demo-security-system.sh policies    # Тестирование политик
./examples/demo-security-system.sh monitoring  # Метрики и мониторинг
./examples/demo-security-system.sh cleanup     # Очистка ресурсов
```

### `.gitlab-ci.yml`
Полный пример GitLab CI/CD pipeline с интеграцией системы безопасности:
- Многоуровневое сканирование (SAST, DAST, container scanning)
- Подписание образов Cosign
- Автоматическое тестирование политик
- Canary deployments
- Compliance отчеты

## 🚀 Быстрый старт с примерами

### 1. Запуск демо-системы
```bash
# Убедитесь, что система безопасности установлена
./scripts/deploy-webhook.sh status

# Запустите полную демонстрацию
cd examples
./demo-security-system.sh
```

### 2. Тестирование отдельных сценариев
```bash
# Тест безопасного развертывания
kubectl apply -f examples/secure-deployment.yaml -n test-namespace

# Тест блокировки (должен быть отклонен)
kubectl apply -f examples/vulnerable-deployment.yaml -n test-namespace
```

### 3. Анализ результатов
```bash
# Просмотр событий блокировки
kubectl get events --sort-by=.metadata.creationTimestamp

# Логи webhook
kubectl logs -n container-security -l app=container-security-webhook

# Метрики безопасности
kubectl exec -n container-security deployment/container-security-webhook -- curl http://localhost:8080/metrics
```

## 🔧 Кастомизация примеров

### Адаптация для вашего проекта

1. **Образы**: Замените `registry.mts.ru` на ваш registry
2. **Namespaces**: Измените namespaces согласно вашей структуре
3. **Политики**: Настройте аннотации под ваши требования compliance
4. **Resources**: Установите подходящие limits и requests

### Добавление новых примеров

```bash
# Структура для нового примера
examples/
├── my-custom-scenario.yaml
├── my-custom-scenario-test.sh
└── README-my-scenario.md
```

## 📊 Ожидаемые результаты

### Успешные развертывания
- ✅ Образ проходит все проверки безопасности
- ✅ Поды создаются и переходят в Running статус
- ✅ Метрики показывают успешные сканирования

### Заблокированные развертывания
- ❌ Admission webhook отклоняет запрос
- ❌ События содержат причину блокировки
- ❌ Логи webhook показывают детали нарушения
- ❌ Метрики фиксируют блокировки

## 🔍 Диагностика

### Проверка webhook логов
```bash
# Детальные логи обработки admission
kubectl logs -n container-security -l app=container-security-webhook --tail=50

# Поиск ошибок
kubectl logs -n container-security -l app=container-security-webhook | grep -i error
```

### Тестирование API webhook
```bash
# Прямой тест webhook endpoint
kubectl exec -n container-security deployment/container-security-webhook -- curl \
  -X POST \
  -H "Content-Type: application/json" \
  http://localhost:8080/admission \
  -d @test-admission-request.json
```

### Мониторинг метрик
```bash
# Текущие метрики
kubectl exec -n container-security deployment/container-security-webhook -- curl http://localhost:8080/metrics

# Prometheus запросы
kubectl port-forward svc/prometheus -n monitoring 9090:9090
# Откройте http://localhost:9090
```

## 🆘 Troubleshooting

### Webhook не блокирует развертывания
```bash
# Проверить конфигурацию webhook
kubectl describe validatingwebhookconfiguration container-security-webhook

# Проверить namespace labels
kubectl get namespaces --show-labels | grep container-security

# Добавить label активации
kubectl label namespace your-namespace container-security/enabled=true
```

### Ошибки TLS сертификатов
```bash
# Перегенерировать сертификаты
./scripts/generate-webhook-cert.sh

# Обновить secret
kubectl apply -f certs/webhook-secret.yaml

# Перезапустить webhook
kubectl rollout restart deployment/container-security-webhook -n container-security
```

### Проблемы с политиками OPA
```bash
# Проверить загруженные политики
kubectl get configmaps -n container-security

# Тест оценки политик
kubectl exec -n container-security deployment/container-security-webhook -- opa eval \
  -d /opt/opa/policies \
  -i /tmp/input.json \
  data.policies
```

## 📈 Расширение примеров

### Добавление новых тестовых сценариев
1. Создайте YAML манифест с вашим сценарием
2. Добавьте ожидаемый результат в описание
3. Обновите демо-скрипт для поддержки нового сценария
4. Протестируйте и задокументируйте результаты

### Интеграция с CI/CD
- Скопируйте `.gitlab-ci.yml` в ваш проект
- Настройте переменные под ваш registry
- Добавьте специфичные для проекта шаги безопасности
- Настройте approvals для production деплоев

## 📝 Полезные ссылки

- [Основная документация](../README.md)
- [Инструкции по установке](../INSTALL.md)
- [Архитектура системы](../architecture.md)
- [Политики безопасности](../policies/)
- [Скрипты автоматизации](../scripts/)

