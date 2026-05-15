variable "project_name" {
  description = "Project prefix for all resources"
  type        = string
  default     = "sao-paulo-gateway-migration"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "sa-east-1"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for EKS control plane and node groups"
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24", "10.50.3.0/24"]
}

variable "simulated_regions" {
  description = "Logical regions for rollout simulation inside EKS namespaces"
  type        = list(string)
  default     = ["saopaulo", "rio", "brasilia"]
}

variable "gateway_service_account_name" {
  description = "Kubernetes service account name used by gateway workloads/secret stores for IRSA"
  type        = string
  default     = "gateway-workload"
}

variable "node_instance_types" {
  description = "EKS node group EC2 instance types"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum worker nodes"
  type        = number
  default     = 6
}

variable "endpoint_public_access" {
  description = "Expose EKS API endpoint publicly"
  type        = bool
  default     = true
}

variable "gateway_images" {
  description = "Container image URI hints by version (used by Kubernetes manifests/docs)"
  type        = map(string)
  default = {
    v1 = "123456789012.dkr.ecr.sa-east-1.amazonaws.com/sao-paulo-gateway-migration-v1:latest"
    v2 = "123456789012.dkr.ecr.sa-east-1.amazonaws.com/sao-paulo-gateway-migration-v2:latest"
  }
}

variable "v2_weights" {
  description = "Canary percentage hints by logical region (used by rollout docs/scripts)"
  type        = map(number)
  default = {
    saopaulo = 10
    rio      = 10
    brasilia = 10
  }

  validation {
    condition = alltrue([
      for _, value in var.v2_weights : value >= 0 && value <= 100
    ])
    error_message = "All v2_weights values must be between 0 and 100."
  }
}
