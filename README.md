# Personaplex

EKS-based infrastructure for Personaplex.

## Structure

```
.
├── terraform/          # EKS cluster and VPC infrastructure
└── README.md
```

## Quick Start

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# Edit both files with your values

AWS_PROFILE=bscsandbox terraform init
AWS_PROFILE=bscsandbox terraform plan -out=plan.out
AWS_PROFILE=bscsandbox terraform apply plan.out
```

See `terraform/README.md` for details.
