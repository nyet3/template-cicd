variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "template-cicd-cluster"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "backend_cpu" {
  description = "Backend Fargate CPU units"
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Backend Fargate memory (MB)"
  type        = number
  default     = 512
}

variable "frontend_cpu" {
  description = "Frontend Fargate CPU units"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Frontend Fargate memory (MB)"
  type        = number
  default     = 512
}

variable "keycloak_cpu" {
  description = "Keycloak Fargate CPU units"
  type        = number
  default     = 512
}

variable "keycloak_memory" {
  description = "Keycloak Fargate memory (MB)"
  type        = number
  default     = 1024
}

variable "backend_desired_count" {
  description = "Desired number of backend tasks"
  type        = number
  default     = 2
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks"
  type        = number
  default     = 2
}

variable "keycloak_desired_count" {
  description = "Desired number of keycloak tasks"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Project   = "template-cicd"
    ManagedBy = "Terraform"
  }
}
