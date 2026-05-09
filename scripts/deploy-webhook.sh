#!/bin/bash

# Deployment script for Container Security Admission Webhook
# This script deploys all necessary Kubernetes resources in the correct order

set -e

NAMESPACE="container-security"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEBHOOK_DIR="${PROJECT_ROOT}/deploy/k8s/webhook"

echo "🚀 Starting Container Security Webhook Deployment"
echo "================================================="

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl not found. Please install kubectl first."
        exit 1
    fi
}

# Function to check if we're connected to a Kubernetes cluster
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ Not connected to a Kubernetes cluster. Please configure kubectl."
        exit 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    echo "📁 Creating namespace: ${NAMESPACE}"
    kubectl apply -f "${WEBHOOK_DIR}/namespace.yaml"
}

# Function to generate and apply certificates
setup_certificates() {
    echo "🔐 Setting up TLS certificates"

    if command -v openssl &> /dev/null; then
        # Generate self-signed certificates
        echo "Generating self-signed certificates..."
        bash "${SCRIPT_DIR}/generate-webhook-cert.sh"

        # Apply the generated secret
        if [ -f "./certs/webhook-secret.yaml" ]; then
            kubectl apply -f "./certs/webhook-secret.yaml"
            echo "✅ Applied TLS secret"
        else
            echo "❌ Certificate generation failed"
            exit 1
        fi
    else
        echo "⚠️  OpenSSL not found. Using cert-manager for certificate management."
        echo "Please ensure cert-manager is installed in the cluster."
        kubectl apply -f "${WEBHOOK_DIR}/cert-manager-issuer.yaml"
    fi
}

# Function to deploy RBAC
deploy_rbac() {
    echo "🔒 Deploying RBAC permissions"
    kubectl apply -f "${WEBHOOK_DIR}/rbac.yaml"
}

# Function to deploy ConfigMaps
deploy_config() {
    echo "⚙️  Deploying configuration"
    kubectl apply -f "${WEBHOOK_DIR}/configmap.yaml"
    kubectl apply -f "${WEBHOOK_DIR}/opa-policies-configmap.yaml"
}

# Function to deploy webhook components
deploy_webhook() {
    echo "🌐 Deploying webhook server"
    kubectl apply -f "${WEBHOOK_DIR}/deployment.yaml"
}

# Function to deploy ValidatingAdmissionWebhook
deploy_admission_webhook() {
    echo "🎛️  Deploying ValidatingAdmissionWebhook configuration"

    # Wait for webhook service to be ready
    echo "Waiting for webhook service to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/container-security-webhook -n ${NAMESPACE}

    # Apply the webhook configuration
    kubectl apply -f "${WEBHOOK_DIR}/validating-webhook.yaml"
}

# Function to verify deployment
verify_deployment() {
    echo "🔍 Verifying deployment"

    # Check namespace
    if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
        echo "❌ Namespace ${NAMESPACE} not found"
        return 1
    fi

    # Check webhook deployment
    if ! kubectl get deployment container-security-webhook -n ${NAMESPACE} &> /dev/null; then
        echo "❌ Webhook deployment not found"
        return 1
    fi

    # Check webhook pods are running
    READY_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=container-security-webhook -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l)
    if [ "$READY_PODS" -lt 1 ]; then
        echo "❌ No webhook pods are ready"
        return 1
    fi

    # Check ValidatingAdmissionWebhook
    if ! kubectl get validatingadmissionwebhook container-security-webhook &> /dev/null; then
        echo "❌ ValidatingAdmissionWebhook not found"
        return 1
    fi

    echo "✅ Deployment verification passed"
    return 0
}

# Function to show deployment status
show_status() {
    echo ""
    echo "📊 Deployment Status"
    echo "==================="

    echo "Namespace: ${NAMESPACE}"
    echo "Pods:"
    kubectl get pods -n ${NAMESPACE} -l app=container-security-webhook

    echo ""
    echo "Services:"
    kubectl get svc -n ${NAMESPACE} -l app=container-security-webhook

    echo ""
    echo "ValidatingAdmissionWebhooks:"
    kubectl get validatingadmissionwebhook container-security-webhook

    echo ""
    echo "Webhook endpoint: https://container-security-webhook.${NAMESPACE}.svc:443/admission"
    echo "Health check: https://container-security-webhook.${NAMESPACE}.svc/health"
}

# Main deployment flow
main() {
    check_kubectl
    check_cluster

    create_namespace
    setup_certificates
    deploy_rbac
    deploy_config
    deploy_webhook
    deploy_admission_webhook

    if verify_deployment; then
        echo ""
        echo "🎉 Container Security Webhook deployed successfully!"
        show_status

        echo ""
        echo "📝 Next steps:"
        echo "1. Label namespaces where you want admission control: kubectl label namespace <namespace> container-security/enabled=true"
        echo "2. Test the webhook by deploying a pod with a vulnerable image"
        echo "3. Monitor webhook logs: kubectl logs -n ${NAMESPACE} -l app=container-security-webhook"
    else
        echo ""
        echo "❌ Deployment verification failed. Please check the logs above."
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    "cleanup")
        echo "🧹 Cleaning up webhook deployment"
        kubectl delete -f "${WEBHOOK_DIR}/" --ignore-not-found=true
        kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
        echo "✅ Cleanup completed"
        ;;
    "status")
        show_status
        ;;
    *)
        main
        ;;
esac
