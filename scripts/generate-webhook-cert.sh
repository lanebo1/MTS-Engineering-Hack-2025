#!/bin/bash

# Script to generate TLS certificates for Kubernetes Admission Webhook
# This creates self-signed certificates for development/testing environments

set -e

NAMESPACE="container-security"
SERVICE_NAME="container-security-webhook"
SECRET_NAME="container-security-webhook-tls"
CERT_DIR="./certs"
WEBHOOK_CONFIG="deploy/k8s/webhook/validating-webhook.yaml"

# Create certs directory
mkdir -p ${CERT_DIR}

# Generate private key
openssl genrsa -out ${CERT_DIR}/webhook.key 2048

# Generate certificate signing request
cat > ${CERT_DIR}/webhook.csr.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = MTS
OU = Container Security
CN = ${SERVICE_NAME}.${NAMESPACE}.svc

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVICE_NAME}
DNS.2 = ${SERVICE_NAME}.${NAMESPACE}
DNS.3 = ${SERVICE_NAME}.${NAMESPACE}.svc
DNS.4 = ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
EOF

# Generate CSR
openssl req -new -key ${CERT_DIR}/webhook.key -out ${CERT_DIR}/webhook.csr -config ${CERT_DIR}/webhook.csr.cnf

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -in ${CERT_DIR}/webhook.csr -signkey ${CERT_DIR}/webhook.key -out ${CERT_DIR}/webhook.crt -days 365 -extensions v3_req -extfile ${CERT_DIR}/webhook.csr.cnf

# Create Kubernetes secret
kubectl create secret tls ${SECRET_NAME} \
  --cert=${CERT_DIR}/webhook.crt \
  --key=${CERT_DIR}/webhook.key \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml > ${CERT_DIR}/webhook-secret.yaml

# Extract CA bundle for webhook configuration
CA_BUNDLE=$(cat ${CERT_DIR}/webhook.crt | base64 | tr -d '\n')

# Update webhook configuration with CA bundle
if [ -f "${WEBHOOK_CONFIG}" ]; then
  # Create a backup
  cp ${WEBHOOK_CONFIG} ${WEBHOOK_CONFIG}.backup

  # Update the caBundle field (assuming single webhook for simplicity)
  sed -i "s/caBundle: \"\"/caBundle: \"${CA_BUNDLE}\"/" ${WEBHOOK_CONFIG}

  echo "Updated webhook configuration with CA bundle"
else
  echo "Warning: Webhook config file not found at ${WEBHOOK_CONFIG}"
fi

echo "Certificate generation completed!"
echo "Certificate: ${CERT_DIR}/webhook.crt"
echo "Private Key: ${CERT_DIR}/webhook.key"
echo "CA Bundle: ${CA_BUNDLE}"
echo ""
echo "To apply the secret to Kubernetes:"
echo "kubectl apply -f ${CERT_DIR}/webhook-secret.yaml"
echo ""
echo "To update the webhook configuration:"
echo "kubectl apply -f ${WEBHOOK_CONFIG}"
