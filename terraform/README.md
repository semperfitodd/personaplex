# Terraform

EKS cluster with VPC, CPU/GPU node groups, and IAM roles for AWS integrations.

## Setup

```bash
terraform init -backend-config=backend.hcl
terraform plan -out=plan.out
terraform apply plan.out
```

## Architecture

- VPC with public/private subnets across 3 AZs
- EKS cluster with CPU (SPOT) and GPU (ON_DEMAND) node groups
- VPC endpoints for S3 and ECR
- IAM roles for EBS CSI, ALB controller, and External DNS
