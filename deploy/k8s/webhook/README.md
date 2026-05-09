# Container Security Admission Webhook - Kubernetes Resources

This directory contains all Kubernetes manifests required to deploy the Container Security Admission Webhook in a Kubernetes cluster.

## Components

### 1. Namespace (`namespace.yaml`)
Creates the `container-security` namespace with appropriate labels for admission control.

### 2. TLS Certificates
- **Self-signed certificates** (`../../scripts/generate-webhook-cert.sh`): Generates certificates for development/testing
- **Cert-manager integration** (`cert-manager-issuer.yaml`): Production-ready certificate management

### 3. RBAC Configuration (`rbac.yaml`)
- ServiceAccount for the webhook
- ClusterRole with necessary permissions for admission control
- ClusterRoleBinding to associate the role with the service account

### 4. Configuration (`configmap.yaml`)
Contains configuration for all integrated components:
- Trivy scanner settings
- OPA policy evaluator configuration
- Cosign verifier settings

### 5. Webhook Deployment (`deployment.yaml`)
- Deployment manifest for the webhook server
- Service for exposing the webhook endpoint
- Health checks and probes
- Security contexts and resource limits

### 6. ValidatingAdmissionWebhook (`validating-webhook.yaml`)
Kubernetes admission controller configuration that:
- Intercepts Pod creation/update operations
- Validates container images against security policies
- Blocks deployments with security violations

## Deployment

Use the deployment script for automated deployment:

```bash
# Deploy all components
./scripts/deploy-webhook.sh

# Check deployment status
./scripts/deploy-webhook.sh status

# Cleanup deployment
./scripts/deploy-webhook.sh cleanup
```

## Manual Deployment Steps

If you prefer manual deployment:

1. Create namespace:
   ```bash
   kubectl apply -f namespace.yaml
   ```

2. Setup certificates (choose one):
   ```bash
   # For development
   ./scripts/generate-webhook-cert.sh
   kubectl apply -f certs/webhook-secret.yaml

   # For production with cert-manager
   kubectl apply -f cert-manager-issuer.yaml
   ```

3. Deploy RBAC:
   ```bash
   kubectl apply -f rbac.yaml
   ```

4. Deploy configuration:
   ```bash
   kubectl apply -f configmap.yaml
   ```

5. Deploy webhook:
   ```bash
   kubectl apply -f deployment.yaml
   ```

6. Deploy admission webhook:
   ```bash
   kubectl apply -f validating-webhook.yaml
   ```

## Namespace Selection

The webhook only processes resources in namespaces labeled with `container-security/enabled=true`:

```bash
kubectl label namespace default container-security/enabled=true
```

## Security Considerations

- Webhook runs with minimal privileges (non-root, read-only filesystem)
- TLS encryption required for all communications
- RBAC permissions follow principle of least privilege
- Network policies should be applied to restrict traffic

## Monitoring

Monitor webhook operations:

```bash
# Check webhook logs
kubectl logs -n container-security -l app=container-security-webhook

# Check admission webhook status
kubectl get validatingadmissionwebhook container-security-webhook

# Check certificate status
kubectl get certificate -n container-security
```

## Troubleshooting

1. **Webhook not receiving requests**: Check namespace labels
2. **TLS errors**: Verify certificate validity and CA bundle injection
3. **RBAC errors**: Check service account and role bindings
4. **Pod security violations**: Review OPA policies and Trivy scan results
