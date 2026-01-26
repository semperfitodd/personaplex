# Personaplex

EKS infrastructure with GitOps deployment via ArgoCD.

## Services

- **frontend**: React/TypeScript web interface
- **personaplex**: GPU-accelerated ML model runtime

## Setup

### Infrastructure

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform apply
```

### Secrets

```bash
# Set HF token
aws secretsmanager put-secret-value \
  --secret-id personaplex/hf-token \
  --secret-string '{"HF_TOKEN":"YOUR_TOKEN"}'

# Get IAM role ARN and update k8s/master/values.yaml
terraform output personaplex_irsa_role_arn
```

### Build and Deploy

```bash
cd services
cp .env.example .env
./build-and-push.sh
```

ArgoCD automatically syncs changes.

## Access

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get pods -A
```
