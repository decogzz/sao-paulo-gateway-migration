# AWS Terraform Starter Layer (`infra/`)

This folder provides a **starter AWS IaC scaffold** for running the migration in cloud-native components.

## What it includes

- VPC + public subnets + internet gateway
- Application Load Balancer
- Weighted forwarding by logical region (`X-Region` header) to model rollout phases
- ECS Fargate cluster and services for:
  - `saopaulo-v1`, `saopaulo-v2`
  - `rio-v1`, `rio-v2`
  - `brasilia-v1`, `brasilia-v2`
- ECR repositories for v1 and v2 images
- CloudWatch log groups
- IAM execution role scaffold
- SSM/Secrets injection placeholder in task definitions

> Note: This is a **starter layer** for assessment purposes. It is intentionally not production-complete (no NAT/private subnet pattern, no WAF, no full secret policy wiring).

## Local commands

### Validate only (no cloud deployment)

```bash
cd infra
terraform init -backend=false
terraform fmt -recursive
terraform validate
```

### Plan/apply (requires AWS credentials)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with real values

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Change rollout traffic weights

Edit `v2_weights` in `terraform.tfvars`, then:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Example:

- phase 1: `{saopaulo=10, rio=10, brasilia=10}`
- phase 2: `{saopaulo=50, rio=50, brasilia=50}`
- phase 3: `{saopaulo=90, rio=90, brasilia=90}`
- phase 4: `{saopaulo=100, rio=100, brasilia=100}`
