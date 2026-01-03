# Primary Region Outputs
output "primary_vpc_id" {
  description = "Primary region VPC ID"
  value       = module.primary_region.vpc_id
}

output "primary_eks_cluster_name" {
  description = "Primary region EKS cluster name"
  value       = module.primary_region.eks_cluster_name
}

output "primary_eks_cluster_endpoint" {
  description = "Primary region EKS cluster endpoint"
  value       = module.primary_region.eks_cluster_endpoint
}

output "primary_alb_dns_name" {
  description = "Primary region ALB DNS name"
  value       = module.primary_region.alb_dns_name
}

output "primary_aurora_endpoint" {
  description = "Primary Aurora cluster endpoint"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_aurora_reader_endpoint" {
  description = "Primary Aurora cluster reader endpoint"
  value       = aws_rds_cluster.primary.reader_endpoint
}

# Secondary Region Outputs
output "secondary_vpc_id" {
  description = "Secondary region VPC ID"
  value       = module.secondary_region.vpc_id
}

output "secondary_eks_cluster_name" {
  description = "Secondary region EKS cluster name"
  value       = module.secondary_region.eks_cluster_name
}

output "secondary_eks_cluster_endpoint" {
  description = "Secondary region EKS cluster endpoint"
  value       = module.secondary_region.eks_cluster_endpoint
}

output "secondary_alb_dns_name" {
  description = "Secondary region ALB DNS name"
  value       = module.secondary_region.alb_dns_name
}

output "secondary_aurora_endpoint" {
  description = "Secondary Aurora cluster endpoint"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_aurora_reader_endpoint" {
  description = "Secondary Aurora cluster reader endpoint"
  value       = aws_rds_cluster.secondary.reader_endpoint
}

# ECR Outputs
output "ecr_repository_backend_url" {
  description = "URL of the backend ECR repository"
  value       = module.primary_region.ecr_repository_backend_url
}

output "ecr_repository_frontend_url" {
  description = "URL of the frontend ECR repository"
  value       = module.primary_region.ecr_repository_frontend_url
}

# Database Outputs
output "aurora_global_cluster_id" {
  description = "Aurora Global Database cluster ID"
  value       = aws_rds_global_cluster.aurora_global.id
}

output "primary_database_url" {
  description = "Primary region database connection URL"
  value       = "postgresql://${var.database_master_username}:${nonsensitive(random_password.aurora_master_password.result)}@${aws_rds_cluster.primary.endpoint}:5432/${var.database_name}"
  sensitive   = true
}

output "secondary_database_url" {
  description = "Secondary region database connection URL (read-only)"
  value       = "postgresql://${var.database_master_username}:${nonsensitive(random_password.aurora_master_password.result)}@${aws_rds_cluster.secondary.endpoint}:5432/${var.database_name}"
  sensitive   = true
}

output "primary_secrets_manager_arn" {
  description = "Primary region Secrets Manager ARN"
  value       = aws_secretsmanager_secret.aurora_credentials_primary.arn
}

output "secondary_secrets_manager_arn" {
  description = "Secondary region Secrets Manager ARN"
  value       = aws_secretsmanager_secret.aurora_credentials_secondary.arn
}

# Health Check Outputs
output "primary_health_check_id" {
  description = "Primary region health check ID"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "Secondary region health check ID"
  value       = aws_route53_health_check.secondary.id
}

# Deployment Info
output "deployment_regions" {
  description = "Regions where infrastructure is deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }
}
