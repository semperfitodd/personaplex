# PersonaPlex

EKS deployment of NVIDIA PersonaPlex with GPU support.

## Services

- **frontend**: React/TypeScript web interface
- **personaplex**: PersonaPlex-7B model runtime

## Setup

### Infrastructure

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform apply

aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### Secrets

```bash
aws secretsmanager put-secret-value \
  --secret-id <env>/hf-token \
  --secret-string '{"HF_TOKEN":"<token>"}'
```

### Deploy

```bash
cd k8s/devops
helm install devops . -n argocd --create-namespace

cd ../../services
cp .env.example .env
./build-and-push.sh

cd ../k8s/microservices
helm install microservices . -n argocd \
  --set awsAccountNumber=<account> \
  --set awsRegion=<region> \
  --set environment=<env>
```

## Configuration

### GPU Requirements

- **Minimum:** g5.xlarge (A10G, 24GB VRAM) with CPU_OFFLOAD enabled
- **Recommended:** g5.2xlarge (A10G, 24GB VRAM) or larger
- **Not supported:** T4 (15GB VRAM insufficient)

Resources in `k8s/microservices/values.yaml`:

```yaml
env:
  CPU_OFFLOAD: "true"
resources:
  requests:
    nvidia.com/gpu: 1
    cpu: 8000m
    memory: 24Gi
  limits:
    nvidia.com/gpu: 1
    cpu: 12000m
    memory: 32Gi
```

## Monitoring

```bash
kubectl logs -n personaplex -l app=personaplex -f
kubectl top pod -n personaplex
kubectl get events -n personaplex --sort-by='.lastTimestamp'
```
