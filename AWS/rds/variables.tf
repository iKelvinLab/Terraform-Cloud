# General Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name to be used for resource naming"
  type        = string
  default     = "myproject"
}

# VPC and Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "database_subnet_cidrs" {
  description = "List of CIDR blocks for database subnets (minimum 2 required)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "create_db_subnet_group" {
  description = "Whether to create a new DB subnet group"
  type        = bool
  default     = true
}

variable "db_subnet_group_name" {
  description = "Name of existing DB subnet group to use (if create_db_subnet_group is false)"
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the RDS instance"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# RDS Instance Configuration
variable "db_engine" {
  description = "Database engine type (mysql, postgres, mariadb, oracle-ee, oracle-se2, sqlserver-ee, sqlserver-se, sqlserver-ex, sqlserver-web)"
  type        = string
  default     = "postgres"

  validation {
    condition = contains([
      "mysql", "postgres", "mariadb",
      "oracle-ee", "oracle-se2", "oracle-se", "oracle-ee-cdb", "oracle-se2-cdb",
      "sqlserver-ee", "sqlserver-se", "sqlserver-ex", "sqlserver-web"
    ], var.db_engine)
    error_message = "Database engine must be one of: mysql, postgres, mariadb, oracle-*, sqlserver-*"
  }
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "15.8"
}

variable "db_major_engine_version" {
  description = "Major version of the database engine (for option groups)"
  type        = string
  default     = "15"
}

variable "db_instance_class" {
  description = "RDS instance class (e.g., db.t3.micro, db.t3.small, db.r5.large)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "mydb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the database (only used if create_random_password is false)"
  type        = string
  default     = null
  sensitive   = true
}

variable "create_random_password" {
  description = "Whether to create a random password for the database"
  type        = bool
  default     = true
}

variable "db_port" {
  description = "Port on which the database accepts connections"
  type        = number
  default     = 5432
}

variable "publicly_accessible" {
  description = "Whether the RDS instance should be publicly accessible"
  type        = bool
  default     = false
}

# Storage Configuration
variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for storage autoscaling (0 to disable, free tier requires 0)"
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Storage type (gp2, gp3, io1, io2). Free tier supports gp2"
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp2, gp3, io1, io2"
  }
}

variable "storage_encrypted" {
  description = "Whether to encrypt the storage (free tier does not support encryption)"
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID for storage encryption (if not specified, uses default RDS KMS key)"
  type        = string
  default     = null
}

variable "iops" {
  description = "Provisioned IOPS for io1 or io2 storage type"
  type        = number
  default     = null
}

# Backup Configuration
variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0 to disable, free tier requires 0)"
  type        = number
  default     = 0

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days"
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot when destroying the instance"
  type        = bool
  default     = false
}

variable "delete_automated_backups" {
  description = "Whether to delete automated backups immediately after instance deletion"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60). Free tier requires 0"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60"
  }
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights (free tier does not support)"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7, 731)"
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 or 731 days"
  }
}

variable "performance_insights_kms_key_id" {
  description = "KMS key ID for Performance Insights encryption"
  type        = string
  default     = null
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch (varies by engine)"
  type        = list(string)
  default     = ["postgresql"]
}

# High Availability Configuration
variable "multi_az" {
  description = "Whether to enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability zone for single-AZ deployment (only used if multi_az is false)"
  type        = string
  default     = null
}

# Parameter and Option Groups
variable "create_db_parameter_group" {
  description = "Whether to create a custom DB parameter group"
  type        = bool
  default     = true
}

variable "db_parameter_group_name" {
  description = "Name of existing DB parameter group to use (if create_db_parameter_group is false)"
  type        = string
  default     = null
}

variable "db_parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "postgres15"
}

variable "db_parameters" {
  description = "List of DB parameters to apply"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = [
    {
      name  = "log_connections"
      value = "1"
    },
    {
      name  = "log_disconnections"
      value = "1"
    }
  ]
}

variable "create_db_option_group" {
  description = "Whether to create a custom DB option group"
  type        = bool
  default     = false
}

variable "db_option_group_name" {
  description = "Name of existing DB option group to use (if create_db_option_group is false)"
  type        = string
  default     = null
}

variable "db_options" {
  description = "List of DB options to apply"
  type = list(object({
    option_name = string
    option_settings = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
  default = []
}

# Upgrade and Maintenance
variable "auto_minor_version_upgrade" {
  description = "Whether to enable automatic minor version upgrades"
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "Whether to allow major version upgrades"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether to apply changes immediately or during maintenance window"
  type        = bool
  default     = false
}

# Security Configuration
variable "deletion_protection" {
  description = "Whether to enable deletion protection (recommended to disable for dev/free tier)"
  type        = bool
  default     = false
}

variable "ca_cert_identifier" {
  description = "Certificate authority (CA) certificate identifier"
  type        = string
  default     = null
}

# Secrets Manager Configuration
variable "store_credentials_in_secrets_manager" {
  description = "Whether to store database credentials in AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "secret_recovery_window_days" {
  description = "Number of days to retain secret after deletion (0 for immediate deletion)"
  type        = number
  default     = 7
}

# CloudWatch Alarms Configuration
variable "create_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for RDS monitoring"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers (e.g., SNS topic ARNs)"
  type        = list(string)
  default     = []
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold percentage for CloudWatch alarm"
  type        = number
  default     = 80
}

variable "free_storage_space_threshold" {
  description = "Free storage space threshold in bytes for CloudWatch alarm"
  type        = number
  default     = 5368709120 # 5 GB
}

variable "freeable_memory_threshold" {
  description = "Freeable memory threshold in bytes for CloudWatch alarm"
  type        = number
  default     = 536870912 # 512 MB
}

variable "database_connections_threshold" {
  description = "Database connections threshold for CloudWatch alarm"
  type        = number
  default     = 100
}
