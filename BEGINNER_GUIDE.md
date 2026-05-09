# 🚀 Руководство для Чайников: Запуск Системы Безопасности Контейнеров МТС

## 👋 Привет, Чайник!

Если ты новичок в контейнерной безопасности и хочешь быстро запустить систему, то это руководство именно для тебя! Мы разберем все по шагам: от установки зависимостей до проверки всех функций системы.

> **Время на прочтение**: 15 минут  
> **Время на установку**: 20-30 минут  
> **Сложность**: Начинающий

---

## 📋 Что такое эта система?

Это **система безопасности контейнеров для МТС**, которая:

- 🔍 **Сканирует** контейнеры на уязвимости (Trivy)
- ✍️ **Проверяет** цифровые подписи образов (Cosign)
- 📋 **Применяет** политики безопасности (OPA)
- 🚫 **Блокирует** опасные развертывания в Kubernetes
- 📊 **Мониторит** все операции с метриками

**Зачем это нужно?** Чтобы предотвратить запуск уязвимых приложений в production среде МТС.

---

## 🔧 Шаг 1: Что нужно установить перед запуском

### Обязательные компоненты:

#### 1. Docker (версия 20.10+)
```bash
# Проверить установлен ли Docker
docker --version

# Если нет - установить (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Добавить пользователя в группу docker
sudo usermod -aG docker $USER
# Выйти и зайти снова или перезагрузить систему
```

#### 2. kubectl (версия 1.28+)
```bash
# Скачать kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Установить
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Проверить
kubectl version --client
```

#### 3. Go (версия 1.21+) - если будешь разрабатывать
```bash
# Скачать и установить Go
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz

# Добавить в PATH
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

# Проверить
go version
```

#### 4. Git
```bash
# Установить git
sudo apt update && sudo apt install -y git

# Проверить
git --version
```

### Рекомендуемые компоненты:

#### Minikube или Kind (для локального тестирования)
```bash
# Minikube (рекомендуется)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Или Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/
```

---

## 🚀 Шаг 2: Запуск системы

### Вариант 1: Docker Compose (самый простой, рекомендуемый)

#### Шаг 2.1: Клонировать репозиторий
```bash
# Скачать проект
git clone https://github.com/mts/container-security-system.git
cd container-security-system
```

#### Шаг 2.2: Запустить все компоненты
```bash
# Запустить систему
docker-compose up -d

# Проверить статус
docker-compose ps
```

**Что запустится:**
- `trivy-scanner` - сканер уязвимостей (порт 8081)
- `opa` - движок политик (порт 8181)
- `webhook-server` - основной сервер безопасности (порты 8443, 8080)
- `prometheus` - сбор метрик (порт 9090)
- `grafana` - визуализация (порт 3000, логин: admin, пароль: admin)

#### Шаг 2.3: Проверить работу
```bash
# Дождаться готовности всех контейнеров
docker compose logs -f

# Проверить health checks
curl http://localhost:8080/health  # Webhook server (метрики и health)
curl http://localhost:8081/health  # Trivy scanner
curl http://localhost:8181/health  # OPA engine

# Проверить метрики
curl http://localhost:8080/metrics # Prometheus метрики
```

---

### Вариант 2: Kubernetes (для продакшена)

#### Шаг 2.1: Запустить кластер
```bash
# С Minikube
minikube start --driver=docker --kubernetes-version=v1.28.0

# Или с Kind
kind create cluster --config kind-config.yaml
```

#### Шаг 2.2: Установить cert-manager
```bash
# Cert-manager для TLS сертификатов webhook
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Дождаться готовности
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
```

#### Шаг 2.3: Развернуть систему безопасности
```bash
# Применить все компоненты
kubectl apply -f deploy/k8s/

# Проверить статус
kubectl get pods -n container-security
kubectl get validatingwebhookconfigurations
```

---

## 🧪 Шаг 3: Тестирование всех функций

### Тест 1: Проверка компонентов системы

```bash
# Для Docker Compose режима:
docker compose ps                    # Проверить все контейнеры
curl http://localhost:8080/health   # Webhook health check
curl http://localhost:8081/health   # Trivy scanner health check
curl http://localhost:8181/health   # OPA engine health check
curl http://localhost:8080/metrics  # Метрики системы

# Для Kubernetes режима:
kubectl get pods -n container-security                    # Проверить все поды
kubectl get validatingwebhookconfigurations             # Проверить webhook конфигурацию
kubectl exec -n container-security deployment/container-security-webhook -- curl -s http://localhost:8080/metrics  # Метрики
```

### Тест 2: Безопасное развертывание (должно пройти)

```bash
# Создать тестовый namespace
kubectl create namespace test-secure

# Развернуть безопасное приложение
kubectl apply -f examples/secure-deployment.yaml -n test-secure

# Проверить статус
kubectl get pods -n test-secure
kubectl get events -n test-secure --sort-by=.metadata.creationTimestamp
```

### Тест 3: Блокировка уязвимого образа (должно заблокироваться)

```bash
# Создать namespace для теста
kubectl create namespace test-vulnerable

# Попытаться развернуть уязвимое приложение
kubectl apply -f examples/vulnerable-deployment.yaml -n test-vulnerable

# Посмотреть результат (должна быть ошибка)
kubectl get events -n test-vulnerable --sort-by=.metadata.creationTimestamp | tail -5
```

### Тест 4: Проверка политик безопасности

```bash
# Запустить тестирование политик
./scripts/test-opa-policies.sh

# Посмотреть результаты
cat test-opa-policies.log
```

### Тест 5: Ручное сканирование образа

```bash
# Протестировать Trivy сканер
docker run --rm container-security/trivy-scanner:latest image scan nginx:latest --format json

# Протестировать Cosign верификацию (если образ подписан)
docker run --rm container-security/cosign verify nginx:latest
```

### Тест 6: Полная демонстрация

```bash
# Запустить полный демо-скрипт (автоматически определяет режим работы)
./examples/demo-security-system.sh

# Или отдельные части:
./examples/demo-security-system.sh secure      # Только безопасное развертывание
./examples/demo-security-system.sh vulnerable  # Только блокировка уязвимого образа
./examples/demo-security-system.sh policies    # Только тестирование политик
./examples/demo-security-system.sh monitoring  # Только метрики и мониторинг

# Скрипт автоматически определяет режим работы:
# - Docker Compose: работает с контейнерами и API
# - Kubernetes: работает с pods и ValidatingWebhookConfiguration
```

---

## 📊 Шаг 4: Просмотр метрик и мониторинга

### Grafana дашборд
```bash
# Открыть в браузере
open http://localhost:3000

# Логин: admin
# Пароль: admin
```

### Prometheus метрики
```bash
# Открыть в браузере
open http://localhost:9090

# Основные метрики для проверки:
# - container_security_scans_total - количество сканирований
# - container_security_blocks_total - количество блокировок
# - container_security_policy_evaluations_total - оценок политик
```

### Метрики через API
```bash
# Для Docker Compose режима:
curl http://localhost:8080/metrics  # Прямой запрос к webhook

# Для Kubernetes режима:
kubectl exec -n container-security deployment/container-security-webhook -- curl -s http://localhost:8080/metrics

# Основные метрики для проверки:
# HELP container_security_scans_total Total number of container scans performed
# HELP container_security_admission_requests_allowed_total Total number of admission requests allowed
# HELP container_security_admission_requests_denied_total Total number of admission requests denied
# HELP container_security_policy_evaluations_total Total number of policy evaluations
```

### Логи системы
```bash
# Для Docker Compose режима:
docker compose logs -f webhook-server   # Логи webhook сервера
docker compose logs -f trivy-scanner    # Логи Trivy сканера
docker compose logs -f opa              # Логи OPA engine

# Для Kubernetes режима:
kubectl logs -n container-security -l app=container-security-webhook -f  # Логи webhook
kubectl logs -n container-security -l app=trivy-scanner -f              # Логи Trivy
kubectl logs -n container-security -l app=opa -f                        # Логи OPA
```

---

## 🔧 Шаг 5: Решение проблем

### Проблема: "Webhook блокирует все развертывания"

**Решение:**
```bash
# Проверить конфигурацию webhook
kubectl describe validatingwebhookconfiguration container-security-webhook

# Проверить namespace labels (нужен label для активации)
kubectl get namespaces --show-labels

# Добавить label активации
kubectl label namespace default container-security/enabled=true
```

### Проблема: "Сертификаты истекли"

**Решение:**
```bash
# Перегенерировать сертификаты
./scripts/generate-webhook-cert.sh

# Применить новый secret
kubectl apply -f certs/webhook-secret.yaml

# Перезапустить webhook
kubectl rollout restart deployment/container-security-webhook -n container-security
```

### Проблема: "Trivy не может просканировать образ"

**Решение:**
```bash
# Проверить логи Trivy
kubectl logs -n container-security -l app=trivy-scanner --tail=50

# Проверить доступ к Docker registry
docker login registry.mts.ru

# Тест сканирования вручную
kubectl exec -n container-security deployment/trivy-scanner -- trivy image nginx:latest
```

### Проблема: "Контейнеры не запускаются"

**Решение:**
```bash
# Для Docker Compose режима:
docker compose ps                          # Проверить статус контейнеров
docker compose logs webhook-server         # Посмотреть логи конкретного контейнера
docker compose logs -f                     # Посмотреть логи всех контейнеров
docker compose restart                     # Перезапустить все контейнеры
docker compose down && docker compose up -d  # Полная пересборка

# Для Kubernetes режима:
kubectl get pods -n container-security     # Проверить статус подов
kubectl describe pod -n container-security # Детали о проблемном поде
kubectl logs -n container-security -l app=container-security-webhook -f

# Проверить ресурсы системы
docker system df  # Для Docker
free -h          # Для памяти
df -h            # Для диска
```

### Проблема: "Не могу подключиться к Kubernetes"

**Решение:**
```bash
# Проверить подключение
kubectl cluster-info

# Проверить контекст
kubectl config current-context

# Если Minikube - проверить статус
minikube status

# Перезапустить кластер
minikube stop && minikube start
```

---

## 🎯 Шаг 6: Проверка всех функций (чек-лист)

- [ ] Docker Compose запущен и все контейнеры healthy
- [ ] Webhook сервер отвечает на health check
- [ ] Trivy сканер работает
- [ ] OPA политики загружены
- [ ] Prometheus собирает метрики
- [ ] Grafana доступна
- [ ] Безопасное развертывание прошло успешно
- [ ] Уязвимое развертывание заблокировано
- [ ] Политики работают корректно
- [ ] Метрики отображаются
- [ ] Логи доступны и читаемы

---

## 🧹 Шаг 7: Очистка после тестирования

```bash
# Остановить и удалить контейнеры
docker-compose down

# Очистить volumes
docker-compose down -v

# Очистить тестовые namespaces
kubectl delete namespace test-secure test-vulnerable --ignore-not-found=true

# Остановить Minikube кластер
minikube stop

# Очистить Docker ресурсы
docker system prune -f
```

---

## 📚 Дополнительные материалы

### Документация
- [Основная документация](README.md)
- [Подробная установка](INSTALL.md)
- [Архитектура системы](architecture.md)
- [Политики безопасности](policies/)

### Примеры и демо
- [Демо скрипт](examples/demo-security-system.sh)
- [Тестовые развертывания](examples/)
- [Примеры политик](policies/)

### Скрипты
- [Тестирование всего](scripts/test-e2e-security.sh)
- [Генерация отчетов](scripts/generate-security-report.sh)
- [Обновление политик](scripts/update-opa-policies.sh)

---

## 🆘 Помощь и поддержка

Если что-то не работает:

1. **Проверь логи**: `docker-compose logs` или `kubectl logs`
2. **Проверь статус**: `docker-compose ps` или `kubectl get pods`
3. **Перечитай ошибки**: Часто в логах есть подсказки
4. **Начни заново**: `docker-compose down && docker-compose up -d`

### Контакты
- **Документация**: https://docs.mts.ru/container-security
- **Slack**: #container-security
- **Email**: devsecops@mts.ru

---

**Поздравляем! 🎉** Ты успешно запустил систему безопасности контейнеров МТС. Теперь ты можешь сканировать, подписывать и блокировать опасные контейнеры в Kubernetes!

> **Pro tip**: Сохрани этот файл - он пригодится для следующих запусков системы.
