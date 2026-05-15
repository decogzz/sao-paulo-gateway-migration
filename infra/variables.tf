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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (2-3 entries recommended)"
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24", "10.50.3.0/24"]
}

variable "simulated_regions" {
  description = "Logical regions for rollout simulation"
  type        = list(string)
  default     = ["saopaulo", "rio", "brasilia"]
}

variable "gateway_images" {
  description = "Container image URI for each gateway version"
  type        = map(string)
  default = {
    v1 = "public.ecr.aws/docker/library/node:20-alpine"
    v2 = "public.ecr.aws/docker/library/node:20-alpine"
  }
}

variable "desired_count_per_service" {
  description = "Desired tasks per region/version service"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory"
  type        = number
  default     = 512
}

variable "v2_weights" {
  description = "Traffic percentage to v2 by logical region (0-100)"
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
