provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC for RDS instance
resource "aws_vpc" "rds_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "rds_igw" {
  vpc_id = aws_vpc.rds_vpc.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-igw"
  }
}

# Database Subnet Group (minimum 2 subnets in different AZs)
resource "aws_subnet" "rds_subnet" {
  count                   = var.create_db_subnet_group ? length(var.database_subnet_cidrs) : 0
  vpc_id                  = aws_vpc.rds_vpc.id
  cidr_block              = var.database_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-subnet-${count.index + 1}"
    Type = "Database"
  }
}

resource "aws_db_subnet_group" "rds" {
  count       = var.create_db_subnet_group ? 1 : 0
  name        = "${var.project_name}-${var.environment}-rds-subnet-group"
  description = "Database subnet group for ${var.project_name} RDS instance"
  subnet_ids  = aws_subnet.rds_subnet[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS ${var.db_engine} instance"
  vpc_id      = aws_vpc.rds_vpc.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}

# Ingress rule for database access
resource "aws_security_group_rule" "rds_ingress" {
  type              = "ingress"
  from_port         = var.db_port
  to_port           = var.db_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.rds.id
  description       = "Allow database access from specified CIDR blocks"
}

# Egress rule - allow all outbound traffic
resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound traffic"
}

# DB Parameter Group
resource "aws_db_parameter_group" "rds" {
  count       = var.create_db_parameter_group ? 1 : 0
  name_prefix = "${var.project_name}-${var.environment}-rds-pg"
  family      = var.db_parameter_group_family
  description = "Database parameter group for ${var.project_name} ${var.db_engine}"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-parameter-group"
  }
}

# DB Option Group
resource "aws_db_option_group" "rds" {
  count                    = var.create_db_option_group ? 1 : 0
  name_prefix              = "${var.project_name}-${var.environment}-rds-og"
  option_group_description = "Option group for ${var.project_name} ${var.db_engine}"
  engine_name              = var.db_engine
  major_engine_version     = var.db_major_engine_version

  dynamic "option" {
    for_each = var.db_options
    content {
      option_name = option.value.option_name

      dynamic "option_settings" {
        for_each = lookup(option.value, "option_settings", [])
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-option-group"
  }
}

# Random password generation for DB master password
resource "random_password" "db_master_password" {
  count   = var.create_random_password ? 1 : 0
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# AWS Secrets Manager secret for storing DB credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  count                   = var.store_credentials_in_secrets_manager ? 1 : 0
  name_prefix             = "${var.project_name}-${var.environment}-rds-credentials"
  description             = "RDS database credentials for ${var.project_name}"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  count     = var.store_credentials_in_secrets_manager ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_credentials[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = var.create_random_password ? random_password.db_master_password[0].result : var.db_password
    engine   = var.db_engine
    host     = aws_db_instance.rds.address
    port     = aws_db_instance.rds.port
    dbname   = var.db_name
  })

  depends_on = [aws_db_instance.rds]
}

# RDS Instance
resource "aws_db_instance" "rds" {
  identifier     = "${var.project_name}-${var.environment}-rds"
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id
  iops                  = var.storage_type == "io1" || var.storage_type == "io2" ? var.iops : null

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.create_random_password ? random_password.db_master_password[0].result : var.db_password
  port     = var.db_port

  # Network configuration
  db_subnet_group_name   = var.create_db_subnet_group ? aws_db_subnet_group.rds[0].name : var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.publicly_accessible

  # Parameter and option groups
  parameter_group_name = var.create_db_parameter_group ? aws_db_parameter_group.rds[0].name : var.db_parameter_group_name
  option_group_name    = var.create_db_option_group ? aws_db_option_group.rds[0].name : var.db_option_group_name

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-rds-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  delete_automated_backups  = var.delete_automated_backups

  # Monitoring and logging
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled && var.performance_insights_kms_key_id != null ? var.performance_insights_kms_key_id : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  # High availability
  multi_az          = var.multi_az
  availability_zone = var.multi_az ? null : var.availability_zone

  # Upgrade and maintenance
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately

  # Deletion protection
  deletion_protection = var.deletion_protection

  # Additional configuration
  ca_cert_identifier = var.ca_cert_identifier

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      password,
    ]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-instance"
  }

  depends_on = [
    aws_db_subnet_group.rds,
    aws_db_parameter_group.rds,
    aws_db_option_group.rds,
    aws_iam_role.rds_monitoring
  ]
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  count              = var.monitoring_interval > 0 ? 1 : 0
  name_prefix        = "${var.project_name}-${var.environment}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role[0].json

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  }
}

data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms for RDS monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.free_storage_space_threshold
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-storage-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-rds-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.freeable_memory_threshold
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-memory-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-rds-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.database_connections_threshold
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-connections-alarm"
  }
}
