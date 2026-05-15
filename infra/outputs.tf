output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_ca_data" {
  description = "EKS cluster CA certificate data"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "eks_node_group_name" {
  description = "Primary managed node group name"
  value       = aws_eks_node_group.main.node_group_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by gateway version"
  value       = { for k, v in aws_ecr_repository.gateway : k => v.repository_url }
}

output "processor_secret_arns" {
  description = "Secrets Manager ARNs by logical region"
  value       = { for k, v in aws_secretsmanager_secret.processor_credentials : k => v.arn }
}

output "gateway_irsa_role_arn" {
  description = "IRSA IAM role ARN for gateway workloads"
  value       = aws_iam_role.gateway_irsa.arn
}

output "gateway_service_account_name" {
  description = "Kubernetes service account name expected by gateway deployments"
  value       = var.gateway_service_account_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
