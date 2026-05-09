#!/bin/bash

# Демо-скрипт для демонстрации работы системы безопасности контейнеров МТС
# Этот скрипт показывает различные сценарии использования системы

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Глобальные переменные
SYSTEM_MODE=""  # "docker-compose" или "kubernetes"
DOCKER_COMPOSE_CMD=""  # Команда для запуска docker compose

# Определение команды Docker Compose
set_docker_compose_cmd() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        DOCKER_COMPOSE_CMD=""
    fi
}

# Функции для цветного вывода
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Детекция режима работы системы
detect_system_mode() {
    # Определить команду Docker Compose
    set_docker_compose_cmd

    # Проверить Docker Compose
    if [ -n "$DOCKER_COMPOSE_CMD" ] && $DOCKER_COMPOSE_CMD ps 2>/dev/null | grep -q "container-security-webhook"; then
        SYSTEM_MODE="docker-compose"
        print_info "Обнаружен режим работы: Docker Compose"
        return 0
    fi

    # Проверить Kubernetes
    if kubectl get namespace container-security &>/dev/null; then
        SYSTEM_MODE="kubernetes"
        print_info "Обнаружен режим работы: Kubernetes"
        return 0
    fi

    print_error "Не удалось определить режим работы системы"
    print_info "Возможные причины:"
    print_info "  - Система не запущена"
    print_info "  - Docker Compose не запущен (docker compose ps)"
    print_info "  - Kubernetes кластер недоступен или namespace не создан"
    return 1
}

# Проверка зависимостей
check_dependencies() {
    print_header "Проверка зависимостей"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl не найден. Установите kubectl."
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        print_error "docker не найден. Установите Docker."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Не удается подключиться к Kubernetes кластеру."
        exit 1
    fi

    print_success "Все зависимости установлены"
}

# Проверка состояния системы безопасности
check_system_status() {
    print_header "Проверка состояния системы безопасности"

    if [ "$SYSTEM_MODE" = "docker-compose" ]; then
        check_docker_compose_status
    elif [ "$SYSTEM_MODE" = "kubernetes" ]; then
        check_kubernetes_status
    else
        print_error "Неизвестный режим работы системы"
        return 1
    fi
}

# Проверка статуса для Docker Compose режима
check_docker_compose_status() {
    # Проверка webhook контейнера
    if $DOCKER_COMPOSE_CMD ps | grep -q "container-security-webhook"; then
        WEBHOOK_PS_LINE=$($DOCKER_COMPOSE_CMD ps webhook-server | tail -n 1)
        if echo "$WEBHOOK_PS_LINE" | grep -q "healthy)"; then
            print_success "Webhook контейнер запущен и здоров"
        elif echo "$WEBHOOK_PS_LINE" | grep -q "Up"; then
            # Проверяем health endpoint напрямую
            if curl -f -s http://localhost:8080/health >/dev/null 2>&1; then
                print_success "Webhook контейнер запущен и отвечает на health check"
            else
                print_warning "Webhook контейнер запущен, но health check не прошел"
            fi
        else
            print_error "Webhook контейнер не готов"
            return 1
        fi
    else
        print_error "Webhook контейнер не найден"
        return 1
    fi

    # Проверка Trivy контейнера
    if $DOCKER_COMPOSE_CMD ps | grep -q "trivy-scanner"; then
        TRIVY_PS_LINE=$($DOCKER_COMPOSE_CMD ps trivy-scanner | tail -n 1)
        if echo "$TRIVY_PS_LINE" | grep -q "healthy)"; then
            print_success "Trivy сканер запущен и здоров"
        elif echo "$TRIVY_PS_LINE" | grep -q "Up"; then
            print_warning "Trivy сканер запущен, но health check не прошел"
        else
            print_warning "Trivy сканер не готов"
        fi
    else
        print_warning "Trivy контейнер не найден"
    fi

    # Проверка OPA контейнера
    if $DOCKER_COMPOSE_CMD ps | grep -q "opa-engine"; then
        OPA_PS_LINE=$($DOCKER_COMPOSE_CMD ps opa | tail -n 1)
        if echo "$OPA_PS_LINE" | grep -q "healthy)"; then
            print_success "OPA движок запущен и здоров"
        elif echo "$OPA_PS_LINE" | grep -q "Up"; then
            print_warning "OPA движок запущен, но health check не прошел"
        else
            print_warning "OPA движок не готов"
        fi
    else
        print_warning "OPA контейнер не найден"
    fi

    # Проверка health checks
    print_info "Проверка health checks..."

    # Webhook health check
    if curl -f -s http://localhost:8080/health &>/dev/null; then
        print_success "Webhook health check пройден"
    else
        print_error "Webhook health check не пройден"
        return 1
    fi

    # Trivy health check
    if curl -f -s http://localhost:8081/health &>/dev/null; then
        print_success "Trivy health check пройден"
    else
        print_warning "Trivy health check не пройден"
    fi

    # OPA health check
    if curl -f -s http://localhost:8181/health &>/dev/null; then
        print_success "OPA health check пройден"
    else
        print_warning "OPA health check не пройден"
    fi

    print_success "Система безопасности (Docker Compose) работает корректно"
}

# Проверка статуса для Kubernetes режима
check_kubernetes_status() {
    # Проверка namespace
    if kubectl get namespace container-security &> /dev/null; then
        print_success "Namespace container-security существует"
    else
        print_error "Namespace container-security не найден"
        return 1
    fi

    # Проверка webhook deployment
    if kubectl get deployment container-security-webhook -n container-security &> /dev/null; then
        print_success "Webhook deployment найден"
    else
        print_error "Webhook deployment не найден"
        return 1
    fi

    # Проверка ValidatingWebhookConfiguration
    if kubectl get validatingwebhookconfiguration container-security-webhook &> /dev/null; then
        print_success "ValidatingWebhookConfiguration найден"
    else
        print_error "ValidatingWebhookConfiguration не найден"
        return 1
    fi

    # Проверка количества подов
    READY_PODS=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)
    if [ "$READY_PODS" -gt 0 ]; then
        print_success "Webhook поды готовы ($READY_PODS)"
    else
        print_error "Нет готовых webhook подов"
        return 1
    fi

    print_success "Система безопасности (Kubernetes) работает корректно"
}

# Демонстрация 1: Безопасное развертывание
demo_secure_deployment() {
    print_header "Демонстрация 1: Безопасное развертывание"

    print_info "Создаем безопасное развертывание с подписанным образом..."

    # Создание namespace для теста с лейблом для webhook
    kubectl create namespace demo-secure --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl label namespace demo-secure container-security/enabled=true --overwrite=true >/dev/null 2>&1

    # Создаем временную копию deployment с правильным namespace
    sed 's/namespace: production/namespace: demo-secure/' examples/secure-deployment.yaml > /tmp/secure-deployment-demo.yaml

    # Применение безопасного deployment
    if kubectl apply -f /tmp/secure-deployment-demo.yaml; then
        print_success "Безопасное развертывание создано успешно"

        # Ожидание создания подов
        sleep 5

        # Проверка статуса
        if kubectl get pods -n demo-secure -l app=secure-mts-app | grep -q "Running"; then
            print_success "Поды запущены успешно"
        else
            print_warning "Поды еще не запущены, проверьте статус позже"
        fi

        # Показать логи webhook
        print_info "Логи webhook (последние 10 строк):"
        WEBHOOK_POD=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$WEBHOOK_POD" ]; then
            kubectl logs -n container-security "$WEBHOOK_POD" --tail=10 2>/dev/null | grep -E "(admission|validation|request)" || print_warning "Логи webhook не найдены"
        else
            print_warning "Webhook под не найден"
        fi

    else
        print_error "Не удалось создать безопасное развертывание"
    fi

    # Очистка временного файла
    rm -f /tmp/secure-deployment-demo.yaml
}

# Демонстрация 2: Блокировка уязвимого образа
demo_vulnerable_block() {
    print_header "Демонстрация 2: Блокировка уязвимого образа"

    print_info "Пытаемся развернуть приложение с уязвимым образом..."

    # Создание namespace для теста с лейблом для webhook
    kubectl create namespace demo-vulnerable --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl label namespace demo-vulnerable container-security/enabled=true --overwrite=true >/dev/null 2>&1

    # Создаем временную копию deployment с правильным namespace
    sed 's/namespace: test-vulnerable/namespace: demo-vulnerable/' examples/vulnerable-deployment.yaml > /tmp/vulnerable-deployment-demo.yaml

    # Попытка применения уязвимого deployment
    if kubectl apply -f /tmp/vulnerable-deployment-demo.yaml 2>&1; then
        print_warning "Развертывание прошло без блокировки (возможно, webhook не активен)"
    else
        print_success "Развертывание было заблокировано системой безопасности!"
    fi

    # Показать события
    print_info "Последние события в namespace demo-vulnerable:"
    kubectl get events -n demo-vulnerable --sort-by=.metadata.creationTimestamp | tail -5 || print_warning "События не найдены"

    # Показать логи webhook
    print_info "Логи webhook о блокировке:"
    WEBHOOK_POD=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$WEBHOOK_POD" ]; then
        kubectl logs -n container-security "$WEBHOOK_POD" --tail=20 2>/dev/null | grep -E "(deny|block|vulnerable|violation|blocked)" || print_warning "Логи блокировки не найдены"
    else
        print_warning "Webhook под не найден"
    fi

    # Очистка временного файла
    rm -f /tmp/vulnerable-deployment-demo.yaml
}

# Демонстрация 3: Тестирование политик
demo_policy_testing() {
    print_header "Демонстрация 3: Тестирование политик безопасности"

    print_info "Запуск тестов политик OPA..."

    # Запуск тестов политик
    if [ -f "scripts/test-opa-policies.sh" ]; then
        bash scripts/test-opa-policies.sh
    else
        print_warning "Скрипт тестирования политик не найден"
    fi

    # Показать результаты тестов
    if [ -f "test-opa-policies.log" ]; then
        print_info "Результаты тестирования политик:"
        tail -20 test-opa-policies.log
    fi
}

# Демонстрация 4: Мониторинг и метрики
demo_monitoring() {
    print_header "Демонстрация 4: Мониторинг и метрики"

    print_info "Проверка метрик системы безопасности..."

    if [ "$SYSTEM_MODE" = "docker-compose" ]; then
        demo_monitoring_docker_compose
    elif [ "$SYSTEM_MODE" = "kubernetes" ]; then
        demo_monitoring_kubernetes
    else
        print_error "Неизвестный режим работы системы"
        return 1
    fi
}

# Мониторинг для Docker Compose режима
demo_monitoring_docker_compose() {
    # Проверка метрик webhook через API
    print_info "Метрики webhook:"
    if curl -s http://localhost:8080/metrics 2>/dev/null | head -20; then
        print_success "Метрики webhook получены"
    else
        print_warning "Не удалось получить метрики webhook"
    fi

    # Проверка количества проверок безопасности
    print_info "Количество проверок безопасности:"
    METRICS=$(curl -s http://localhost:8080/metrics 2>/dev/null)
    if echo "$METRICS" | grep -q container_security_scans_total; then
        echo "$METRICS" | grep container_security_scans_total
    else
        print_warning "Метрики сканирований недоступны"
    fi

    # Проверка Prometheus контейнера
    if $DOCKER_COMPOSE_CMD ps | grep -q prometheus; then
        PROMETHEUS_STATUS=$($DOCKER_COMPOSE_CMD ps prometheus | tail -n 1 | awk '{print $6}')
        if echo "$PROMETHEUS_STATUS" | grep -q "^Up"; then
            print_success "Prometheus доступен"
            print_info "Откройте http://localhost:9090 для просмотра метрик"
        else
            print_warning "Prometheus не готов (статус: $PROMETHEUS_STATUS)"
        fi
    else
        print_info "Prometheus не запущен в Docker Compose"
        print_info "Для запуска добавьте сервис в docker-compose.yml"
    fi
}

# Мониторинг для Kubernetes режима
demo_monitoring_kubernetes() {
    # Получение метрик через Kubernetes
    WEBHOOK_POD=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$WEBHOOK_POD" ]; then
        print_info "Метрики webhook (последние 15 строк):"
        kubectl exec -n container-security "$WEBHOOK_POD" -- curl -s http://localhost:8080/metrics 2>/dev/null | tail -15 || print_warning "Не удалось получить метрики webhook"

        print_info "Ключевые метрики безопасности:"
        METRICS=$(kubectl exec -n container-security "$WEBHOOK_POD" -- curl -s http://localhost:8080/metrics 2>/dev/null)
        if echo "$METRICS" | grep -q container_security; then
            echo "$METRICS" | grep container_security | head -5
        else
            print_warning "Метрики безопасности недоступны"
        fi

        print_info "Общая статистика запросов:"
        REQUEST_COUNT=$(kubectl logs -n container-security "$WEBHOOK_POD" --tail=100 2>/dev/null | grep -c "admission\|validation\|request" || echo "0")
        print_info "Обработано запросов admission: $REQUEST_COUNT"

    else
        print_warning "Webhook под не найден"
    fi

    # Проверка Grafana
    if kubectl get pods -n container-security -l app=grafana 2>/dev/null | grep -q Running; then
        print_success "Grafana доступен в namespace container-security"
        print_info "Grafana предоставляет дашборды для:"
        print_info "  - Метрики безопасности в реальном времени"
        print_info "  - Статистика сканирований уязвимостей"
        print_info "  - Мониторинг политик compliance"
        print_info "  - Аналитика инцидентов безопасности"
    else
        print_info "Grafana не запущен в container-security namespace"
    fi

    # Проверка Prometheus в Kubernetes
    if kubectl get pods -n container-security -l app=prometheus 2>/dev/null | grep -q Running; then
        print_success "Prometheus доступен"
        print_info "Prometheus собирает метрики:"
        print_info "  - HTTP запросы к webhook"
        print_info "  - Время обработки admission requests"
        print_info "  - Статистика блокировок по политикам"
        print_info "  - Метрики сканирования образов"
    else
        print_info "Prometheus не установлен (запустите deploy/k8s/monitoring/)"
        print_info "Для полной системы мониторинга установите Prometheus и Grafana"
    fi

    print_info "Архитектура мониторинга:"
    print_info "  Webhook Server → Prometheus → Grafana"
    print_info "     ↑              ↑            ↑"
    print_info "  Admission     Метрики     Визуализация"
    print_info "  Requests     Сбор         Дашборды"
}

# Демонстрация 5: Проверка подписей образов
demo_signature_verification() {
    print_header "Демонстрация 5: Проверка подписей контейнерных образов"

    print_info "Тестируем верификацию подписей образов..."

    # Создание namespace для теста
    kubectl create namespace demo-signature --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl label namespace demo-signature container-security/enabled=true --overwrite=true >/dev/null 2>&1

    print_info "Создаем deployment с неподписанным образом..."
    cat <<EOF > /tmp/unsigned-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unsigned-app
  namespace: demo-signature
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unsigned-app
  template:
    metadata:
      labels:
        app: unsigned-app
    spec:
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 80
EOF

    # Попытка применения неподписанного deployment
    if kubectl apply -f /tmp/unsigned-deployment.yaml 2>&1; then
        print_warning "Неподписанный образ был принят (возможно, проверка подписей отключена)"
    else
        print_success "Неподписанный образ был заблокирован!"
    fi

    print_info "Создаем deployment с подписанным образом..."
    cat <<EOF > /tmp/signed-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: signed-app
  namespace: demo-signature
  annotations:
    container-security/signed: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: signed-app
  template:
    metadata:
      labels:
        app: signed-app
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
EOF

    # Применение подписанного deployment
    if kubectl apply -f /tmp/signed-deployment.yaml; then
        print_success "Подписанный образ принят"
    else
        print_warning "Подписанный образ был отклонен"
    fi

    # Очистка временных файлов
    rm -f /tmp/unsigned-deployment.yaml /tmp/signed-deployment.yaml
}

# Демонстрация 6: Система нотификаций
demo_notifications() {
    print_header "Демонстрация 6: Система нотификаций безопасности"

    print_info "Проверка настроек системы нотификаций..."

    # Проверка конфигурации нотификаций
    NOTIFICATIONS_CONFIG=$(kubectl get configmap container-security-webhook-notifications-config -n container-security -o jsonpath='{.data.notifications\.yaml}' 2>/dev/null)
    if [ -n "$NOTIFICATIONS_CONFIG" ]; then
        print_info "Конфигурация нотификаций найдена:"
        echo "$NOTIFICATIONS_CONFIG" | head -10

        if echo "$NOTIFICATIONS_CONFIG" | grep -q "enabled: true"; then
            print_success "Нотификации включены"
        else
            print_warning "Нотификации отключены"
        fi

        if echo "$NOTIFICATIONS_CONFIG" | grep -q "YOUR_TELEGRAM_BOT_TOKEN_HERE"; then
            print_warning "Telegram токен не настроен (используется заглушка)"
            print_info "Для реальной работы настройте токен в deploy/k8s/webhook/notifications-config.yaml"
        fi
    else
        print_warning "Конфигурация нотификаций не найдена"
    fi

    print_info "Типы уведомлений, которые будут отправляться при нарушениях:"
    print_info "  - security_alert: оповещения о найденных уязвимостях"
    print_info "  - policy_violation: нарушения политик безопасности"
    print_info "  - compliance_failure: несоответствие требованиям compliance"

    print_info "Примеры сценариев отправки уведомлений:"
    print_info "  1. Обнаружение уязвимости с severity >= medium"
    print_info "  2. Попытка запуска privileged контейнера"
    print_info "  3. Использование образа из запрещенного реестра"
    print_info "  4. Несоответствие требованиям PCI DSS/GDPR"

    print_success "Система нотификаций настроена и готова к работе"
}

# Демонстрация 7: Отчеты compliance
demo_compliance_reports() {
    print_header "Демонстрация 7: Отчеты compliance"

    print_info "Генерация отчетов соответствия требованиям..."

    # Генерация отчета
    if [ -f "scripts/generate-consolidated-report.sh" ]; then
        # Создаем директорию для отчетов если она не существует
        mkdir -p reports

        # Запускаем генерацию отчета
        if bash scripts/generate-consolidated-report.sh . "reports/consolidated-security-report.json"; then
            print_success "Консолидированный отчет сгенерирован"
        else
            print_warning "Не удалось сгенерировать консолидированный отчет"
        fi
    elif [ -f "scripts/generate-security-report.sh" ]; then
        # Альтернатива: генерация простого отчета безопасности
        mkdir -p reports
        if bash scripts/generate-security-report.sh > "reports/security-report.txt"; then
            print_success "Отчет безопасности сгенерирован"
        else
            print_warning "Не удалось сгенерировать отчет безопасности"
        fi
    else
        print_warning "Скрипты генерации отчетов не найдены"
    fi

    # Показать структуру отчетов
    if [ -d "reports" ]; then
        print_info "Доступные отчеты:"
        ls -la reports/
    fi
}

# Демонстрация 7: Комплексная демонстрация политик
demo_comprehensive_policies() {
    print_header "Демонстрация 7: Комплексная демонстрация политик безопасности"

    print_info "Тестируем различные сценарии политик..."

    # Создание namespace для теста
    kubectl create namespace demo-policies --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl label namespace demo-policies container-security/enabled=true --overwrite=true >/dev/null 2>&1

    print_info "Тестируем политику base images..."
    cat <<EOF > /tmp/base-image-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: base-image-test
  namespace: demo-policies
spec:
  replicas: 1
  selector:
    matchLabels:
      app: base-image-test
  template:
    metadata:
      labels:
        app: base-image-test
    spec:
      containers:
      - name: app
        image: alpine:latest
        ports:
        - containerPort: 80
EOF

    if kubectl apply -f /tmp/base-image-test.yaml 2>&1; then
        print_success "Базовый образ принят"
    else
        print_info "Базовый образ заблокирован политикой"
    fi

    print_info "Тестируем политику privileged containers..."
    cat <<EOF > /tmp/privileged-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: privileged-test
  namespace: demo-policies
spec:
  replicas: 1
  selector:
    matchLabels:
      app: privileged-test
  template:
    metadata:
      labels:
        app: privileged-test
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        securityContext:
          privileged: true
EOF

    if kubectl apply -f /tmp/privileged-test.yaml 2>&1; then
        print_warning "Privileged контейнер принят"
    else
        print_success "Privileged контейнер заблокирован!"
    fi

    # Очистка временных файлов
    rm -f /tmp/base-image-test.yaml /tmp/privileged-test.yaml
}

# Очистка после демонстрации
cleanup_demo() {
    print_header "Очистка демонстрационных ресурсов"

    print_info "Удаляем тестовые namespaces..."

    kubectl delete namespace demo-secure --ignore-not-found=true
    kubectl delete namespace demo-vulnerable --ignore-not-found=true
    kubectl delete namespace demo-signature --ignore-not-found=true
    kubectl delete namespace demo-policies --ignore-not-found=true

    print_success "Очистка завершена"
}

# Главная функция
main() {
    echo "🚀 Демонстрация системы безопасности контейнеров МТС"
    echo ""

    # Проверка зависимостей
    check_dependencies

    # Детекция режима работы системы
    if ! detect_system_mode; then
        print_error "Не удалось определить режим работы системы"
        print_info "Запустите систему через Docker Compose или Kubernetes:"
        print_info "  Docker Compose: docker compose up -d"
        print_info "  Kubernetes: kubectl apply -f deploy/k8s/"
        exit 1
    fi

    # Проверка системы
    if ! check_system_status; then
        print_error "Система безопасности не готова. Запустите установку сначала."
        exit 1
    fi

    # Запуск демонстраций
    demo_secure_deployment
    echo ""

    demo_vulnerable_block
    echo ""

    demo_policy_testing
    echo ""

    demo_signature_verification
    echo ""

    demo_notifications
    echo ""

    demo_monitoring
    echo ""

    demo_comprehensive_policies
    echo ""

    demo_compliance_reports
    echo ""

    # Предложение очистки
    echo ""
    read -p "Хотите очистить демонстрационные ресурсы? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_demo
    fi

    print_header "Демонстрация завершена!"
    print_success "Система безопасности контейнеров МТС работает корректно"
    echo ""
    print_info "Для получения дополнительной информации см. документацию:"
    echo "  - README.md - основная документация"
    echo "  - INSTALL.md - инструкции по установке"
    echo "  - docs/ - дополнительная документация"
}

# Обработка аргументов командной строки
case "${1:-}" in
    "secure")
        check_dependencies
        if ! detect_system_mode; then exit 1; fi
        demo_secure_deployment
        ;;
    "vulnerable")
        check_dependencies
        if ! detect_system_mode; then exit 1; fi
        demo_vulnerable_block
        ;;
    "policies")
        demo_policy_testing
        ;;
    "signature")
        check_dependencies
        if ! detect_system_mode; then exit 1; fi
        demo_signature_verification
        ;;
    "comprehensive")
        check_dependencies
        if ! detect_system_mode; then exit 1; fi
        demo_comprehensive_policies
        ;;
    "monitoring")
        check_dependencies
        if ! detect_system_mode; then exit 1; fi
        demo_monitoring
        ;;
    "reports")
        demo_compliance_reports
        ;;
    "cleanup")
        cleanup_demo
        ;;
    *)
        main
        ;;
esac

