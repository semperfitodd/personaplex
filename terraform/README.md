# Personaplex Terraform

EKS cluster with VPC for Personaplex.

## Prerequisites

- Terraform >= 1.14.3
- AWS CLI with profile configured

## Setup

```bash
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# Edit both files with your values

AWS_PROFILE=bscsandbox terraform init
AWS_PROFILE=bscsandbox terraform plan -out=plan.out
AWS_PROFILE=bscsandbox terraform apply plan.out
```

## Architecture

- VPC with public/private subnets across 3 AZs
- EKS cluster with CPU (SPOT) and GPU (ON_DEMAND) node groups
- VPC endpoints for S3 and ECR
- EBS CSI driver and ALB controller IAM roles

## Access Cluster

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region> --profile bscsandbox
kubectl get nodes
```

## Cleanup

```bash
AWS_PROFILE=bscsandbox terraform destroy
```
