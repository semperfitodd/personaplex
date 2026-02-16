# PersonaPlex

EKS deployment of NVIDIA PersonaPlex with GPU support.

## Services

- **frontend**: Nginx reverse proxy to the PersonaPlex model server
- **personaplex**: PersonaPlex-7B model runtime (GPU)

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

## GPU Requirements

- **Minimum:** g5.xlarge (A10G, 24GB VRAM) with `CPU_OFFLOAD=true`
- **Recommended:** g5.2xlarge or larger

## Monitoring

```bash
kubectl logs -n personaplex -l app=personaplex -f
kubectl top pod -n personaplex
```
