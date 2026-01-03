# Region Configuration
variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery"
  type        = string
  default     = "ap-northeast-3"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for primary region VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for secondary region VPC"
  type        = string
  default     = "10.1.0.0/16"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "template-cicd-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "project_name" {
  description = "Project name for ECR repositories"
  type        = string
  default     = "template-cicd"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# Node Configuration
variable "node_instance_types" {
  description = "Instance types for EKS nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of nodes per region"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes per region"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes per region"
  type        = number
  default     = 2
}

# Database Configuration
variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "templatecicd"
}

variable "database_master_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 2
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances per cluster"
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

# DNS Configuration
# variable "domain_name" {
#   description = "Domain name for the application"
#   type        = string
#   default     = "example.com"
# }

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "template-cicd"
    ManagedBy   = "terraform"
    Environment = "production"
    DR          = "enabled"
  }
}
