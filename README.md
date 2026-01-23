# Personaplex

EKS infrastructure with GitOps deployment via ArgoCD.

## Setup

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan -out=plan.out
terraform apply plan.out
```

## Access

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes
```
