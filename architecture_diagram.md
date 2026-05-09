# Схема архитектуры системы безопасности контейнеров МТС

## Высокоуровневая архитектура

```mermaid
graph TB
    subgraph "Входные данные"
        A[Docker Registry<br/>Образы для развертывания]
        B[CI/CD Pipeline<br/>GitLab CI]
    end

    subgraph "Компоненты сканирования"
        C[Trivy Scanner<br/>Сканирование уязвимостей<br/>CVEs, конфигурации]
        D[Cosign Signer<br/>Подписи образов<br/>Keyless/OIDC]
    end

    subgraph "Политики и решения"
        E[OPA Policy Engine<br/>Оценка политик<br/>Rego язык]
        F[Kubernetes<br/>Admission Webhook<br/>ValidatingAdmissionWebhook]
    end

    subgraph "Мониторинг и уведомления"
        G[Prometheus<br/>Метрики системы]
        H[Telegram/Slack<br/>Уведомления о блокировках]
    end

    subgraph "Выход"
        I[Kubernetes API Server<br/>Разрешение/Блокировка<br/>деплоймента]
        J[Отчеты Compliance<br/>Автоматизированные<br/>отчеты]
    end

    A --> B
    B --> C
    B --> D
    C --> E
    D --> E
    E --> F
    F --> I

    C --> G
    D --> G
    F --> G
    F --> H

    G --> J
    C --> J

    style A fill:#e1f5fe
    style I fill:#c8e6c9
    style F fill:#ffebee

    linkStyle 6 stroke:#ff6b6b,stroke-width:3px
    linkStyle 7 stroke:#4ecdc4,stroke-width:3px
```

## Диаграмма развертывания в Kubernetes

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "container-security Namespace"
            WH[Webhook Server<br/>Deployment<br/>Go + HTTP/HTTPS]
            TR[Trivy Scanner<br/>CronJob<br/>Vulnerability DB Update]
            OP[OPA Engine<br/>Deployment<br/>Policy Evaluation]
            PR[Prometheus<br/>StatefulSet<br/>Metrics Collection]
            GR[Grafana<br/>Deployment<br/>Dashboards]
        end

        subgraph "External Services"
            TG[Telegram Bot<br/>Notifications]
            REG[Docker Registry<br/>Image Storage]
        end

        subgraph "Kubernetes Core"
            API[K8s API Server<br/>Admission Control]
            ETCD[etcd<br/>Cluster State]
            CM[cert-manager<br/>TLS Certificates]
        end
    end

    WH -->|Admission Requests| API
    API -->|Validate| WH
    WH -->|Scan| TR
    WH -->|Verify| REG
    WH -->|Evaluate| OP
    WH -->|Metrics| PR
    PR -->|Dashboards| GR
    WH -->|Alerts| TG

    CM -->|TLS Certs| WH

    style WH fill:#ffebee
    style API fill:#e8f5e8
```

## Детальная диаграмма компонентов

```mermaid
graph LR
    subgraph "Admission Webhook Flow"
        K[AdmissionRequest<br/>от K8s API]
        L{Trivy Scan<br/>Образ на уязвимости}
        M{Cosign Verify<br/>Проверка подписи}
        N{OPA Evaluate<br/>Применение политик}
        O[AdmissionResponse<br/>Allow/Deny]
    end

    K --> L
    L --> M
    M --> N
    N --> O

    style O fill:#c8e6c9
```

## Диаграмма последовательности

```mermaid
sequenceDiagram
    participant Dev as Разработчик
    participant CI as CI/CD Pipeline
    participant Reg as Docker Registry
    participant Web as Admission Webhook
    participant Tri as Trivy
    participant Cos as Cosign
    participant OPA as OPA Engine
    participant K8s as Kubernetes API

    Dev->>CI: Push code
    CI->>CI: Build Docker image
    CI->>Tri: Scan image for vulnerabilities
    Tri-->>CI: Scan results (JSON)
    CI->>Cos: Sign image if scan passed
    Cos-->>CI: Signature created
    CI->>Reg: Push signed image

    Dev->>K8s: Deploy application (kubectl apply)
    K8s->>Web: AdmissionRequest with image
    Web->>Tri: Scan image vulnerabilities
    Tri-->>Web: Vulnerabilities report
    Web->>Cos: Verify image signature
    Cos-->>Web: Signature status
    Web->>OPA: Evaluate policies
    OPA-->>Web: Policy decision
    Web->>K8s: AdmissionResponse (allow/deny)

    alt Allow deployment
        K8s->>K8s: Create pods
    else Deny deployment
        K8s->>Dev: Error: blocked by security policy
    end

## Диаграмма CI/CD процесса

```mermaid
sequenceDiagram
    participant Dev as Разработчик
    participant Git as GitLab
    participant Build as Build Job
    participant Scan as Security Scan
    participant Sign as Image Signing
    participant Push as Registry Push
    participant Deploy as Deploy Job
    participant Web as Admission Webhook
    participant K8s as Kubernetes

    Dev->>Git: Push code
    Git->>Build: Trigger build
    Build->>Build: Docker build
    Build->>Scan: Run security scan
    Scan->>Scan: Trivy scan vulnerabilities
    Scan->>Build: Scan results
    alt Scan passed
        Build->>Sign: Sign image with Cosign
        Sign->>Push: Push signed image
        Push->>Deploy: Trigger deployment
        Deploy->>K8s: kubectl apply
        K8s->>Web: AdmissionRequest
        Web->>Web: Validate image security
        Web->>K8s: Allow deployment
        K8s->>K8s: Create resources
    else Scan failed
        Scan->>Git: Fail pipeline
        Git->>Dev: Security violation alert
    end
```
