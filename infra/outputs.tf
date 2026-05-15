output "alb_dns_name" {
  description = "DNS name of the migration ALB"
  value       = aws_lb.gateway.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by gateway version"
  value       = { for k, v in aws_ecr_repository.gateway : k => v.repository_url }
}

output "target_groups" {
  description = "Target groups by logical region/version"
  value = {
    for k, v in aws_lb_target_group.gateway :
    k => v.arn
  }
}
