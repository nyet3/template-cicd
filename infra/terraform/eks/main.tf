# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, k + 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
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
    }
  )
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # EKS Managed Node Group
  eks_managed_node_groups = {
    main = {
      name = "${var.cluster_name}-node-group"

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
      }

      tags = var.tags
    }
  }

  # Cluster access entry
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}

# ECR Repositories
resource "aws_ecr_repository" "backend" {
  name                 = "template-cicd/backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "template-cicd/frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = var.tags
}

resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-alb-sg"
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = var.tags
}

# IAM Role for ECS Task Execution (used if migrating to ECS later)
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.cluster_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# Aurora PostgreSQL Database
# =============================================================================

# DB Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.cluster_name}-aurora-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-aurora-subnet-group"
  })
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${var.cluster_name}-aurora-sg"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
    description     = "PostgreSQL from EKS cluster"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-aurora-sg"
  })
}

# Random password for Aurora
resource "random_password" "aurora_master_password" {
  length  = 16
  special = true
}

# Aurora Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.cluster_name}-aurora"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = var.aurora_engine_version
  database_name           = var.database_name
  master_username         = var.database_master_username
  master_password         = random_password.aurora_master_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  backup_retention_period = var.aurora_backup_retention_period
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.cluster_name}-aurora-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  serverlessv2_scaling_configuration {
    max_capacity = var.aurora_max_capacity
    min_capacity = var.aurora_min_capacity
  }

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}

# Aurora Cluster Instances
resource "aws_rds_cluster_instance" "aurora" {
  count              = var.aurora_instance_count
  identifier         = "${var.cluster_name}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = var.tags
}

# Store DB credentials in Secrets Manager
resource "aws_secretsmanager_secret" "aurora_credentials" {
  name                    = "${var.cluster_name}/aurora/credentials"
  description             = "Aurora PostgreSQL credentials"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = aws_secretsmanager_secret.aurora_credentials.id
  secret_string = jsonencode({
    username            = var.database_master_username
    password            = random_password.aurora_master_password.result
    engine              = "postgres"
    host                = aws_rds_cluster.aurora.endpoint
    port                = 5432
    dbname              = var.database_name
    dbClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
    DATABASE_URL        = "postgresql://${var.database_master_username}:${random_password.aurora_master_password.result}@${aws_rds_cluster.aurora.endpoint}:5432/${var.database_name}"
  })
}

# IAM Policy for Secrets Manager access
resource "aws_iam_policy" "secrets_manager_read" {
  name        = "${var.cluster_name}-secrets-manager-read"
  description = "Allow reading secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.aurora_credentials.arn
      }
    ]
  })

  tags = var.tags
}

# CloudWatch Log Group for Aurora
resource "aws_cloudwatch_log_group" "aurora" {
  name              = "/aws/rds/cluster/${var.cluster_name}-aurora/postgresql"
  retention_in_days = 7

  tags = var.tags
}
