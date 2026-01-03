# Multi-Region Disaster Recovery Infrastructure
# Primary: ap-northeast-1 (Tokyo)
# Secondary: us-west-2 (Oregon)

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Uncomment to use S3 backend for state management
  # backend "s3" {
  #   bucket         = "template-cicd-terraform-state"
  #   key            = "multi-region/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# Primary Region Provider (Tokyo)
provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

# Secondary Region Provider (Osaka)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Default Provider
provider "aws" {
  region = var.primary_region
}

# Data sources
data "aws_caller_identity" "current" {}

# Primary Region Infrastructure
module "primary_region" {
  source = "../modules/regional-infrastructure"

  providers = {
    aws = aws.primary
  }

  region             = var.primary_region
  region_short       = "apne1"
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.primary_vpc_cidr
  node_instance_types = var.node_instance_types
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
  is_primary_region  = true
  secondary_regions  = [var.secondary_region]

  tags = merge(
    var.tags,
    {
      Region = "primary"
      DR     = "enabled"
    }
  )
}

# Secondary Region Infrastructure
module "secondary_region" {
  source = "../modules/regional-infrastructure"

  providers = {
    aws = aws.secondary
  }

  region             = var.secondary_region
  region_short       = "oska"
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.secondary_vpc_cidr
  node_instance_types = var.node_instance_types
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
  is_primary_region  = false
  secondary_regions  = []

  tags = merge(
    var.tags,
    {
      Region = "secondary"
      DR     = "enabled"
    }
  )
}

# Aurora Global Database
resource "random_password" "aurora_master_password" {
  length  = 16
  special = true
}

# Primary Aurora Cluster (Global Database Primary)
resource "aws_rds_global_cluster" "aurora_global" {
  provider = aws.primary

  global_cluster_identifier = "${var.cluster_name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  database_name             = var.database_name
  storage_encrypted         = true
}

# Primary Region Aurora Cluster
resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = "${var.cluster_name}-aurora-primary"
  engine                    = aws_rds_global_cluster.aurora_global.engine
  engine_version            = aws_rds_global_cluster.aurora_global.engine_version
  database_name             = aws_rds_global_cluster.aurora_global.database_name
  master_username           = var.database_master_username
  master_password           = random_password.aurora_master_password.result
  global_cluster_identifier = aws_rds_global_cluster.aurora_global.id

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.aurora_primary.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.cluster_name}-aurora-primary-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-primary"
      Region = "primary"
      DR     = "enabled"
    }
  )

  depends_on = [aws_rds_global_cluster.aurora_global]
}

# Primary Aurora Instances
resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.aurora_instance_count

  identifier         = "${var.cluster_name}-aurora-primary-${count.index}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  publicly_accessible = false

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-primary-${count.index}"
      Region = "primary"
    }
  )
}

# DB Subnet Group - Primary
resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name       = "${var.cluster_name}-aurora-subnet-group-primary"
  subnet_ids = module.primary_region.private_subnets

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-subnet-group-primary"
      Region = "primary"
    }
  )
}

# Security Group for Aurora - Primary
resource "aws_security_group" "aurora_primary" {
  provider = aws.primary

  name        = "${var.cluster_name}-aurora-sg-primary"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = module.primary_region.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.primary_region.eks_cluster_security_group_id]
    description     = "Allow PostgreSQL access from EKS cluster"
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
      Name   = "${var.cluster_name}-aurora-sg-primary"
      Region = "primary"
    }
  )
}

# Secondary Region Aurora Cluster
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${var.cluster_name}-aurora-secondary"
  engine                    = aws_rds_global_cluster.aurora_global.engine
  engine_version            = aws_rds_global_cluster.aurora_global.engine_version
  global_cluster_identifier = aws_rds_global_cluster.aurora_global.id

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.aurora_secondary.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.cluster_name}-aurora-secondary-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-secondary"
      Region = "secondary"
      DR     = "enabled"
    }
  )

  depends_on = [aws_rds_cluster.primary]
}

# Secondary Aurora Instances
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.aurora_instance_count

  identifier         = "${var.cluster_name}-aurora-secondary-${count.index}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version

  publicly_accessible = false

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-secondary-${count.index}"
      Region = "secondary"
    }
  )
}

# DB Subnet Group - Secondary
resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = "${var.cluster_name}-aurora-subnet-group-secondary"
  subnet_ids = module.secondary_region.private_subnets

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-aurora-subnet-group-secondary"
      Region = "secondary"
    }
  )
}

# Security Group for Aurora - Secondary
resource "aws_security_group" "aurora_secondary" {
  provider = aws.secondary

  name        = "${var.cluster_name}-aurora-sg-secondary"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = module.secondary_region.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.secondary_region.eks_cluster_security_group_id]
    description     = "Allow PostgreSQL access from EKS cluster"
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
      Name   = "${var.cluster_name}-aurora-sg-secondary"
      Region = "secondary"
    }
  )
}

# Secrets Manager for Primary Aurora Credentials
resource "aws_secretsmanager_secret" "aurora_credentials_primary" {
  provider = aws.primary

  name        = "${var.cluster_name}-aurora-credentials-primary"
  description = "Aurora PostgreSQL credentials for primary region"

  tags = merge(
    var.tags,
    {
      Region = "primary"
    }
  )
}

resource "aws_secretsmanager_secret_version" "aurora_credentials_primary" {
  provider = aws.primary

  secret_id = aws_secretsmanager_secret.aurora_credentials_primary.id
  secret_string = jsonencode({
    username            = var.database_master_username
    password            = random_password.aurora_master_password.result
    engine              = "postgres"
    host                = aws_rds_cluster.primary.endpoint
    port                = 5432
    dbname              = var.database_name
    dbClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    DATABASE_URL        = "postgresql://${var.database_master_username}:${random_password.aurora_master_password.result}@${aws_rds_cluster.primary.endpoint}:5432/${var.database_name}"
  })
}

# Secrets Manager for Secondary Aurora Credentials
resource "aws_secretsmanager_secret" "aurora_credentials_secondary" {
  provider = aws.secondary

  name        = "${var.cluster_name}-aurora-credentials-secondary"
  description = "Aurora PostgreSQL credentials for secondary region"

  tags = merge(
    var.tags,
    {
      Region = "secondary"
    }
  )
}

resource "aws_secretsmanager_secret_version" "aurora_credentials_secondary" {
  provider = aws.secondary

  secret_id = aws_secretsmanager_secret.aurora_credentials_secondary.id
  secret_string = jsonencode({
    username            = var.database_master_username
    password            = random_password.aurora_master_password.result
    engine              = "postgres"
    host                = aws_rds_cluster.secondary.endpoint
    port                = 5432
    dbname              = var.database_name
    dbClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
    DATABASE_URL        = "postgresql://${var.database_master_username}:${random_password.aurora_master_password.result}@${aws_rds_cluster.secondary.endpoint}:5432/${var.database_name}"
  })
}

# CloudWatch Log Groups for Aurora
resource "aws_cloudwatch_log_group" "aurora_primary" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${aws_rds_cluster.primary.cluster_identifier}/postgresql"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Region = "primary"
    }
  )
}

resource "aws_cloudwatch_log_group" "aurora_secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${aws_rds_cluster.secondary.cluster_identifier}/postgresql"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Region = "secondary"
    }
  )
}

# Route 53 Health Checks and Failover
resource "aws_route53_health_check" "primary" {
  fqdn              = module.primary_region.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-primary-health-check"
      Region = "primary"
    }
  )
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = module.secondary_region.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-secondary-health-check"
      Region = "secondary"
    }
  )
}

# Route 53 Hosted Zone (create manually or import existing)
# Uncomment and configure if you want Terraform to manage your DNS
# resource "aws_route53_zone" "main" {
#   name = var.domain_name
#   tags = var.tags
# }

# Route 53 Records with Failover
# Uncomment and configure after setting up your hosted zone
# resource "aws_route53_record" "primary" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "A"
#
#   set_identifier = "primary"
#   failover_routing_policy {
#     type = "PRIMARY"
#   }
#
#   alias {
#     name                   = module.primary_region.alb_dns_name
#     zone_id                = module.primary_region.alb_zone_id
#     evaluate_target_health = true
#   }
#
#   health_check_id = aws_route53_health_check.primary.id
# }
#
# resource "aws_route53_record" "secondary" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "A"
#
#   set_identifier = "secondary"
#   failover_routing_policy {
#     type = "SECONDARY"
#   }
#
#   alias {
#     name                   = module.secondary_region.alb_dns_name
#     zone_id                = module.secondary_region.alb_zone_id
#     evaluate_target_health = true
#   }
#
#   health_check_id = aws_route53_health_check.secondary.id
# }
