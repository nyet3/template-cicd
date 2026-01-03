# Regional Infrastructure Module
# This module deploys infrastructure to a single region

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc-${var.region}"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, k + 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "production" ? false : true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "Region"                                     = var.region
    }
  )
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${var.cluster_name}-${var.region_short}"
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    main = {
      name = "${var.cluster_name}-node-group-${var.region_short}"

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      update_config = {
        max_unavailable_percentage = 33
      }

      labels = {
        Environment = var.environment
        Region      = var.region
      }

      tags = var.tags
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = merge(
    var.tags,
    {
      Region = var.region
    }
  )
}

# ECR Repositories (only in primary region)
resource "aws_ecr_repository" "backend" {
  count = var.is_primary_region ? 1 : 0
  name  = "${var.project_name}/backend"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = var.tags
}

resource "aws_ecr_repository" "frontend" {
  count = var.is_primary_region ? 1 : 0
  name  = "${var.project_name}/frontend"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = var.tags
}

# ECR Replication Configuration (only in primary region)
resource "aws_ecr_replication_configuration" "main" {
  count = var.is_primary_region && length(var.secondary_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.secondary_regions
        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }
    }
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.cluster_name}-alb-${var.region_short}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "production" ? true : false

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-alb-${var.region_short}"
      Region = var.region
    }
  )
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg-${var.region_short}"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-alb-sg-${var.region_short}"
      Region = var.region
    }
  )
}

# ALB Target Group (example for backend)
resource "aws_lb_target_group" "backend" {
  name        = "${var.cluster_name}-backend-${var.region_short}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-backend-tg-${var.region_short}"
      Region = var.region
    }
  )
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}-${var.region_short}/cluster"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Region = var.region
    }
  )
}
