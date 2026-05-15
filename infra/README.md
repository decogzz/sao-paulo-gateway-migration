# AWS Terraform Starter Layer (`infra/`) - EKS Edition

This folder provides a **starter AWS IaC scaffold for EKS** (instead of ECS), aligned with the Kubernetes trade-off discussed in design decisions.

## What it includes

- VPC + internet gateway + public subnets
- EKS cluster + managed node group
- IAM roles/policies for EKS control plane and worker nodes
- ECR repositories for `gateway-v1` and `gateway-v2`
- Secrets Manager placeholders per logical region (`saopaulo`, `rio`, `brasilia`)
- CloudWatch log group for control-plane logs
- Kubernetes manifest starter under `infra/k8s/`

> Note: This is a **starter layer** for assessment purposes. It is intentionally not production-complete (no private subnets + NAT, no IRSA wiring for controllers, no WAF, no autoscaling policies tuning).

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
# edit terraform.tfvars with your account/region values

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Configure kubectl for the created cluster

```bash
aws eks update-kubeconfig --region sa-east-1 --name sao-paulo-gateway-migration-dev-cluster
kubectl get nodes
```

### Deploy Kubernetes starter manifests

```bash
kubectl apply -f infra/k8s/namespaces.yaml
kubectl apply -f infra/k8s/saopaulo.yaml
kubectl apply -f infra/k8s/rio.yaml
kubectl apply -f infra/k8s/brasilia.yaml
```

### Switch canary phase in-cluster (example)

```bash
# phase mapping: 1=10, 2=50, 3=90, 4=100
./infra/k8s/set-phase.sh saopaulo 2
./infra/k8s/set-phase.sh rio 3
```
