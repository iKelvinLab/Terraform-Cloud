# RDS Instance Outputs
output "rds_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.rds.id
}

output "rds_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.rds.arn
}

output "rds_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.rds.endpoint
}

output "rds_instance_address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.rds.address
}

output "rds_instance_port" {
  description = "The port the RDS instance is listening on"
  value       = aws_db_instance.rds.port
}

output "rds_instance_status" {
  description = "The status of the RDS instance"
  value       = aws_db_instance.rds.status
}

output "rds_instance_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = aws_db_instance.rds.availability_zone
}

output "rds_instance_multi_az" {
  description = "Whether the RDS instance is multi-AZ"
  value       = aws_db_instance.rds.multi_az
}

output "rds_instance_resource_id" {
  description = "The RDS Resource ID"
  value       = aws_db_instance.rds.resource_id
}

# Database Configuration Outputs
output "database_name" {
  description = "The name of the database"
  value       = aws_db_instance.rds.db_name
}

output "database_username" {
  description = "The master username for the database"
  value       = aws_db_instance.rds.username
  sensitive   = true
}

output "database_engine" {
  description = "The database engine"
  value       = aws_db_instance.rds.engine
}

output "database_engine_version" {
  description = "The database engine version"
  value       = aws_db_instance.rds.engine_version
}

# Storage Outputs
output "storage_encrypted" {
  description = "Whether the RDS instance storage is encrypted"
  value       = aws_db_instance.rds.storage_encrypted
}

output "storage_type" {
  description = "The storage type of the RDS instance"
  value       = aws_db_instance.rds.storage_type
}

output "allocated_storage" {
  description = "The allocated storage size in GB"
  value       = aws_db_instance.rds.allocated_storage
}

# Network Outputs
output "vpc_id" {
  description = "The VPC ID where RDS is deployed"
  value       = aws_vpc.rds_vpc.id
}

output "subnet_ids" {
  description = "The subnet IDs used by the RDS instance"
  value       = var.create_db_subnet_group ? aws_subnet.rds_subnet[*].id : []
}

output "db_subnet_group_id" {
  description = "The DB subnet group ID"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.rds[0].id : null
}

output "db_subnet_group_arn" {
  description = "The ARN of the DB subnet group"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.rds[0].arn : null
}

output "security_group_id" {
  description = "The security group ID attached to the RDS instance"
  value       = aws_security_group.rds.id
}

output "security_group_arn" {
  description = "The ARN of the security group attached to the RDS instance"
  value       = aws_security_group.rds.arn
}

# Parameter and Option Group Outputs
output "db_parameter_group_id" {
  description = "The DB parameter group ID"
  value       = var.create_db_parameter_group ? aws_db_parameter_group.rds[0].id : null
}

output "db_parameter_group_arn" {
  description = "The ARN of the DB parameter group"
  value       = var.create_db_parameter_group ? aws_db_parameter_group.rds[0].arn : null
}

output "db_option_group_id" {
  description = "The DB option group ID"
  value       = var.create_db_option_group ? aws_db_option_group.rds[0].id : null
}

output "db_option_group_arn" {
  description = "The ARN of the DB option group"
  value       = var.create_db_option_group ? aws_db_option_group.rds[0].arn : null
}

# Monitoring Outputs
output "monitoring_role_arn" {
  description = "The ARN of the monitoring IAM role"
  value       = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
}

output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.rds.performance_insights_enabled
}

output "enhanced_monitoring_enabled" {
  description = "Whether Enhanced Monitoring is enabled"
  value       = var.monitoring_interval > 0
}

# Backup Outputs
output "backup_retention_period" {
  description = "The backup retention period"
  value       = aws_db_instance.rds.backup_retention_period
}

output "backup_window" {
  description = "The backup window"
  value       = aws_db_instance.rds.backup_window
}

output "maintenance_window" {
  description = "The maintenance window"
  value       = aws_db_instance.rds.maintenance_window
}

output "latest_restorable_time" {
  description = "The latest time to which the database can be restored with point-in-time restore"
  value       = aws_db_instance.rds.latest_restorable_time
}

# Secrets Manager Outputs
output "secrets_manager_secret_id" {
  description = "The ID of the Secrets Manager secret containing DB credentials"
  value       = var.store_credentials_in_secrets_manager ? aws_secretsmanager_secret.db_credentials[0].id : null
}

output "secrets_manager_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing DB credentials"
  value       = var.store_credentials_in_secrets_manager ? aws_secretsmanager_secret.db_credentials[0].arn : null
}

# CloudWatch Alarms Outputs
output "cloudwatch_alarm_cpu_id" {
  description = "The ID of the CPU utilization CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_cpu[0].id : null
}

output "cloudwatch_alarm_storage_id" {
  description = "The ID of the free storage space CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_storage[0].id : null
}

output "cloudwatch_alarm_memory_id" {
  description = "The ID of the freeable memory CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_memory[0].id : null
}

output "cloudwatch_alarm_connections_id" {
  description = "The ID of the database connections CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_connections[0].id : null
}

# Connection String Output
output "connection_string" {
  description = "Connection string for the database (without password)"
  value       = "${var.db_engine}://${aws_db_instance.rds.username}@${aws_db_instance.rds.endpoint}/${aws_db_instance.rds.db_name}"
  sensitive   = true
}

# Tags Output
output "rds_instance_tags" {
  description = "Tags applied to the RDS instance"
  value       = aws_db_instance.rds.tags_all
}
