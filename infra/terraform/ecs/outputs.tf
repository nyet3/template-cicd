output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID"
  value       = aws_lb.main.zone_id
}

output "ecr_backend_repository_url" {
  description = "ECR repository URL for backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "ECR repository URL for frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_service_name" {
  description = "Backend ECS service name"
  value       = aws_ecs_service.backend.name
}

output "frontend_service_name" {
  description = "Frontend ECS service name"
  value       = aws_ecs_service.frontend.name
}

output "keycloak_service_name" {
  description = "Keycloak ECS service name"
  value       = aws_ecs_service.keycloak.name
}

output "application_url" {
  description = "Application URL (ALB DNS)"
  value       = "https://${aws_lb.main.dns_name}"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "aurora_database_name" {
  description = "Aurora database name"
  value       = aws_rds_cluster.aurora.database_name
}

output "aurora_master_username" {
  description = "Aurora master username"
  value       = aws_rds_cluster.aurora.master_username
  sensitive   = true
}

output "aurora_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Aurora credentials"
  value       = aws_secretsmanager_secret.aurora_credentials.arn
}

output "database_url" {
  description = "Database connection URL"
  value       = "postgresql://${var.database_master_username}:${random_password.aurora_master_password.result}@${aws_rds_cluster.aurora.endpoint}:5432/${var.database_name}"
  sensitive   = true
}
