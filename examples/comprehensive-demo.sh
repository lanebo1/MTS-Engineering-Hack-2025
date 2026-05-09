#!/bin/bash

# Полная демонстрация системы безопасности контейнеров МТС
# Этот скрипт показывает весь функционал проекта

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции для цветного вывода
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_subheader() {
    echo -e "${CYAN}---------------------------------${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}---------------------------------${NC}"
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

print_feature() {
    echo -e "${PURPLE}🚀 $1${NC}"
}

# Проверка зависимостей
check_dependencies() {
    print_header "Проверка зависимостей системы"

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

# Детекция режима работы
detect_system_mode() {
    if kubectl get namespace container-security &>/dev/null; then
        print_info "Обнаружен режим работы: Kubernetes"
        SYSTEM_MODE="kubernetes"
        return 0
    fi

    print_error "Не удалось определить режим работы системы"
    return 1
}

# Проверка состояния системы
check_system_status() {
    print_header "Проверка состояния системы безопасности"

    # Проверка namespace
    if kubectl get namespace container-security &> /dev/null; then
        print_success "✅ Namespace container-security существует"
    else
        print_error "❌ Namespace container-security не найден"
        return 1
    fi

    # Проверка webhook deployment
    if kubectl get deployment container-security-webhook -n container-security &> /dev/null; then
        print_success "✅ Webhook deployment найден"
    else
        print_error "❌ Webhook deployment не найден"
        return 1
    fi

    # Проверка ValidatingWebhookConfiguration
    if kubectl get validatingwebhookconfiguration container-security-webhook &> /dev/null; then
        print_success "✅ ValidatingWebhookConfiguration найден"
    else
        print_error "❌ ValidatingWebhookConfiguration не найден"
        return 1
    fi

    # Проверка подов
    READY_PODS=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)
    if [ "$READY_PODS" -gt 0 ]; then
        print_success "✅ Webhook поды готовы ($READY_PODS)"
    else
        print_error "❌ Нет готовых webhook подов"
        return 1
    fi

    print_success "🎉 Система безопасности готова к демонстрации!"
}

# Демонстрация архитектуры
demo_architecture() {
    print_header "🏗️  АРХИТЕКТУРА СИСТЕМЫ БЕЗОПАСНОСТИ"

    print_info "Система безопасности контейнеров МТС включает следующие компоненты:"
    echo ""
    print_feature "1. Admission Controller (Webhook Server)"
    print_info "   - Go приложение на порту 8443 (HTTPS)"
    print_info "   - Обрабатывает admission requests от Kubernetes API"
    print_info "   - Интегрируется с Trivy, Cosign, OPA"
    echo ""

    print_feature "2. Vulnerability Scanner (Trivy)"
    print_info "   - Сканирование образов на уязвимости"
    print_info "   - Поддержка SBOM и compliance checks"
    print_info "   - Интеграция с различными registries"
    echo ""

    print_feature "3. Policy Engine (OPA - Open Policy Agent)"
    print_info "   - Declarative политики безопасности"
    print_info "   - Rego language для написания правил"
    print_info "   - JSON данные для контекста политик"
    echo ""

    print_feature "4. Signature Verifier (Cosign)"
    print_info "   - Проверка цифровых подписей образов"
    print_info "   - Интеграция с Sigstore"
    print_info "   - Attestations и SBOM"
    echo ""

    print_feature "5. Monitoring & Observability"
    print_info "   - Prometheus для сбора метрик"
    print_info "   - Grafana для визуализации"
    print_info "   - Логи и алерты"
    echo ""

    print_feature "6. Notifications System"
    print_info "   - Telegram боты для оповещений"
    print_info "   - Email и другие каналы"
    print_info "   - Configurable severity levels"
    echo ""

    print_info "Архитектура: Kubernetes API → Webhook → [Trivy|OPA|Cosign] → Decision"
}

# Демонстрация политик безопасности
demo_policies() {
    print_header "📋 ПОЛИТИКИ БЕЗОПАСНОСТИ"

    print_subheader "Доступные политики OPA:"

    if [ -d "policies" ]; then
        print_info "Файлы политик в директории policies/:"
        ls policies/*.rego | while read line; do
            policy_name=$(basename "$line" .rego)
            print_feature "• $policy_name"
        done
        echo ""

        print_info "Ключевые политики:"
        print_feature "• container_security.rego - основные правила безопасности"
        print_feature "• vulnerability_policy.rego - политика уязвимостей"
        print_feature "• signature_policy.rego - проверка подписей"
        print_feature "• base_image_policy.rego - политика базовых образов"
        print_feature "• compliance_policy.rego - compliance checks"

        if [ -f "policies/test_scenarios.json" ]; then
            print_success "✅ Тестовые сценарии настроены"
        fi

        if [ -f "policies/data.json" ]; then
            print_success "✅ Данные политик настроены"
        fi
    else
        print_warning "⚠️  Директория policies не найдена"
    fi

    print_subheader "Примеры политик:"

    print_info "1. Проверка privileged контейнеров:"
    print_info "   - Запрещает privileged: true"
    print_info "   - Разрешает только для системных компонентов"

    print_info "2. Проверка базовых образов:"
    print_info "   - Разрешает только approved образы"
    print_info "   - Проверяет registry whitelist"

    print_info "3. Проверка ресурсов:"
    print_info "   - Требует limits и requests"
    print_info "   - Проверяет resource quotas"
}

# Демонстрация интеграций
demo_integrations() {
    print_header "🔗 ИНТЕГРАЦИИ И ИНСТРУМЕНТЫ"

    print_subheader "Интегрированные инструменты безопасности:"

    print_feature "🔍 Trivy Scanner"
    print_info "   Статус: $(kubectl get pods -n container-security -l app=trivy-scanner 2>/dev/null | grep -c Running || echo 0) под(а) работают"
    print_info "   Функции: сканирование уязвимостей, SBOM, secrets detection"
    echo ""

    print_feature "🔐 Cosign Verifier"
    print_info "   Функции: проверка подписей, attestations, keyless signing"
    print_info "   Интеграция: Sigstore, Fulcio, Rekor"
    echo ""

    print_feature "⚖️  Open Policy Agent (OPA)"
    print_info "   Статус: $(kubectl get pods -n container-security -l app=opa 2>/dev/null | grep -c Running || echo 0) под(а) работают"
    print_info "   Функции: policy evaluation, data binding, REST API"
    echo ""

    print_feature "📊 Prometheus & Grafana"
    print_info "   Prometheus: $(kubectl get pods -n container-security -l app=prometheus 2>/dev/null | grep -c Running || echo 0) под(а) работают"
    print_info "   Grafana: $(kubectl get pods -n container-security -l app=grafana 2>/dev/null | grep -c Running || echo 0) под(а) работают"
    print_info "   Метрики: HTTP requests, validation time, block statistics"
    echo ""

    print_feature "📱 Notifications"
    print_info "   Каналы: Telegram, Email, Slack"
    print_info "   События: violations, alerts, compliance failures"
}

# Демонстрация deployment примеров
demo_examples() {
    print_header "📦 ПРИМЕРЫ РАЗВЕРТЫВАНИЙ"

    print_subheader "Примеры конфигураций:"

    if [ -d "examples" ]; then
        print_info "Доступные примеры в директории examples/:"
        ls examples/*.yaml | while read line; do
            example_name=$(basename "$line" .yaml)
            print_feature "• $example_name"
        done
        echo ""

        if [ -f "examples/secure-deployment.yaml" ]; then
            print_success "✅ Безопасное развертывание настроено"
            print_info "   Включает: resource limits, security context, annotations"
        fi

        if [ -f "examples/vulnerable-deployment.yaml" ]; then
            print_info "⚠️  Тестовое уязвимое развертывание (для демонстрации блокировки)"
            print_info "   Содержит: уязвимый образ, privileged режим"
        fi
    fi

    print_subheader "Рекомендации по безопасности:"

    print_info "1. Всегда устанавливайте resource limits"
    print_info "2. Используйте read-only root filesystem"
    print_info "3. Запускайте с non-root пользователем"
    print_info "4. Подписывайте образы перед развертыванием"
    print_info "5. Регулярно сканируйте на уязвимости"
}

# Демонстрация мониторинга
demo_monitoring() {
    print_header "📈 МОНИТОРИНГ И МЕТРИКИ"

    print_subheader "Система мониторинга:"

    WEBHOOK_POD=$(kubectl get pods -n container-security -l app=container-security-webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$WEBHOOK_POD" ]; then
        print_info "Webhook метрики (эндпоинт /metrics):"
        METRICS=$(kubectl exec -n container-security "$WEBHOOK_POD" -- curl -s http://localhost:8081/metrics 2>/dev/null | grep -E "(container_security|http_requests|go_)" | head -10 || echo "")
        if [ -n "$METRICS" ]; then
            echo "$METRICS"
        else
            print_warning "Метрики недоступны через exec"
        fi
        echo ""

        print_info "Статистика запросов:"
        REQUEST_COUNT=$(kubectl logs -n container-security "$WEBHOOK_POD" --tail=1000 2>/dev/null | grep -c "GET /" || echo "0")
        print_info "   HTTP запросов: $REQUEST_COUNT"

        ADMISSION_COUNT=$(kubectl logs -n container-security "$WEBHOOK_POD" --tail=1000 2>/dev/null | grep -c "admission\|validation" || echo "0")
        print_info "   Admission запросов: $ADMISSION_COUNT"
    fi

    print_subheader "Grafana дашборды:"

    if kubectl get pods -n container-security -l app=grafana 2>/dev/null | grep -q Running; then
        print_success "✅ Grafana доступен"
        print_info "   Доступ: kubectl port-forward svc/grafana 3000:3000 -n container-security"
        print_info "   Дашборды: Security Overview, Vulnerability Trends, Policy Violations"
    else
        print_warning "⚠️  Grafana не запущен"
    fi

    print_subheader "Prometheus метрики:"

    if kubectl get pods -n container-security -l app=prometheus 2>/dev/null | grep -q Running; then
        print_success "✅ Prometheus доступен"
        print_info "   Доступ: kubectl port-forward svc/prometheus 9090:9090 -n container-security"
        print_info "   Метрики: container_security_*, admission_duration, block_count"
    else
        print_warning "⚠️  Prometheus не запущен"
    fi
}

# Демонстрация deployment процесса
demo_deployment() {
    print_header "🚀 ПРОЦЕСС РАЗВЕРТЫВАНИЯ"

    print_subheader "Этапы развертывания системы:"

    print_info "1. Подготовка инфраструктуры:"
    print_info "   • Kubernetes кластер (v1.19+)"
    print_info "   • cert-manager для TLS сертификатов"
    print_info "   • RBAC права для webhook"
    echo ""

    print_info "2. Установка компонентов:"
    print_info "   • kubectl apply -f deploy/k8s/"
    print_info "   • Порядок: namespace → rbac → certificates → webhook → monitoring"
    echo ""

    print_info "3. Конфигурация политик:"
    print_info "   • Настройка OPA политик в policies/"
    print_info "   • Конфигурация данных в policies/data.json"
    print_info "   • Тестирование политик: ./scripts/test-opa-policies.sh"
    echo ""

    print_info "4. Настройка интеграций:"
    print_info "   • Trivy: конфигурация registry credentials"
    print_info "   • Cosign: настройка key management"
    print_info "   • Notifications: настройка Telegram бота"
    echo ""

    print_info "5. Валидация:"
    print_info "   • ./examples/demo-security-system.sh"
    print_info "   • Проверка логов и метрик"
    print_info "   • Тестирование сценариев безопасности"

    print_subheader "Скрипты развертывания:"
    if [ -d "scripts" ]; then
        ls scripts/*.sh | while read script; do
            script_name=$(basename "$script")
            print_feature "• $script_name"
        done
    fi
}

# Главная функция
main() {
    echo "🚀 ПОЛНАЯ ДЕМОНСТРАЦИЯ СИСТЕМЫ БЕЗОПАСНОСТИ КОНТЕЙНЕРОВ МТС"
    echo ""
    print_info "Этот скрипт демонстрирует весь функционал системы безопасности,"
    print_info "включая архитектуру, компоненты, политики и интеграции."
    echo ""

    # Проверка зависимостей
    check_dependencies

    # Детекция режима работы
    if ! detect_system_mode; then
        print_error "Не удалось определить режим работы системы"
        print_info "Запустите систему через Kubernetes:"
        print_info "  kubectl apply -f deploy/k8s/"
        exit 1
    fi

    # Проверка системы
    if ! check_system_status; then
        print_error "Система безопасности не готова."
        exit 1
    fi

    # Запуск демонстраций
    demo_architecture
    echo ""

    demo_policies
    echo ""

    demo_integrations
    echo ""

    demo_examples
    echo ""

    demo_monitoring
    echo ""

    demo_deployment
    echo ""

    print_header "🎉 ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА!"

    print_success "Система безопасности контейнеров МТС демонстрирует:"
    print_feature "• Полную защиту admission controller"
    print_feature "• Интеграцию с ведущими инструментами безопасности"
    print_feature "• Гибкую систему политик на базе OPA"
    print_feature "• Комплексный мониторинг и оповещения"
    print_feature "• Поддержку compliance и аудита"

    echo ""
    print_info "Для практического тестирования запустите:"
    print_info "  ./examples/demo-security-system.sh"
    echo ""
    print_info "Документация: README.md, docs/, INSTALL.md"
}

# Обработка аргументов
case "${1:-}" in
    "architecture")
        check_dependencies && detect_system_mode && demo_architecture
        ;;
    "policies")
        demo_policies
        ;;
    "integrations")
        check_dependencies && detect_system_mode && demo_integrations
        ;;
    "monitoring")
        check_dependencies && detect_system_mode && demo_monitoring
        ;;
    "examples")
        demo_examples
        ;;
    "deployment")
        demo_deployment
        ;;
    *)
        main
        ;;
esac
