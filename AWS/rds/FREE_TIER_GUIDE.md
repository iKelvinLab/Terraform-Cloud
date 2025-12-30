# AWS RDS Free Tier Configuration Guide

This guide provides detailed information about configuring AWS RDS within the Free Tier limits.

## Quick Fix for FreeTierRestrictionError

If you encounter the error:
```
Error: creating RDS DB Instance: operation error RDS: CreateDBInstance,
FreeTierRestrictionError: The specified backup retention period exceeds
the maximum available to free tier customers.
```

**Solution**: Ensure your `terraform.tfvars` contains:
```hcl
backup_retention_period = 0
```

## Free Tier Checklist

Use this checklist to ensure your RDS configuration stays within AWS Free Tier limits:

- [ ] Instance class is `db.t2.micro` or `db.t3.micro`
- [ ] Allocated storage is 20 GB or less
- [ ] Storage type is `gp2`
- [ ] Storage encryption is disabled (`storage_encrypted = false`)
- [ ] Storage autoscaling is disabled (`max_allocated_storage = 0`)
- [ ] Multi-AZ is disabled (`multi_az = false`)
- [ ] Backup retention period is 0 (`backup_retention_period = 0`)
- [ ] Enhanced Monitoring is disabled (`monitoring_interval = 0`)
- [ ] Performance Insights is disabled (`performance_insights_enabled = false`)
- [ ] Database engine is one of: MySQL, PostgreSQL, MariaDB (Oracle and SQL Server have different pricing)

## Complete Free Tier Configuration

Here's a complete `terraform.tfvars` configuration for AWS Free Tier:

```hcl
# General Configuration
aws_region   = "us-east-1"
environment  = "dev"
project_name = "myproject"

# Network Configuration
vpc_cidr               = "10.0.0.0/16"
database_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
allowed_cidr_blocks    = ["10.0.0.0/16"]

# RDS Instance Configuration - FREE TIER
db_engine          = "postgres"
db_engine_version  = "15.8"
db_instance_class  = "db.t3.micro"      # FREE TIER ELIGIBLE
db_name            = "mydb"
db_username        = "dbadmin"
db_port            = 5432

# Password Configuration
create_random_password = true

# Storage Configuration - FREE TIER
allocated_storage     = 20       # FREE TIER MAX
max_allocated_storage = 0        # AUTOSCALING DISABLED
storage_type          = "gp2"    # FREE TIER TYPE
storage_encrypted     = false    # NOT INCLUDED IN FREE TIER

# High Availability - FREE TIER
multi_az             = false     # NOT SUPPORTED IN FREE TIER
publicly_accessible  = false

# Backup Configuration - FREE TIER
backup_retention_period  = 0              # FREE TIER REQUIRES 0
backup_window           = "03:00-04:00"
maintenance_window      = "sun:04:00-sun:05:00"
skip_final_snapshot     = true
delete_automated_backups = true

# Monitoring Configuration - FREE TIER
monitoring_interval                   = 0      # ENHANCED MONITORING DISABLED
performance_insights_enabled          = false  # NOT INCLUDED IN FREE TIER
performance_insights_retention_period = 7
enabled_cloudwatch_logs_exports       = ["postgresql"]

# Parameter Group Configuration
create_db_parameter_group = true
db_parameter_group_family = "postgres15"
db_parameters = [
  {
    name  = "log_connections"
    value = "1"
  },
  {
    name  = "log_disconnections"
    value = "1"
  }
]

# Option Group Configuration
create_db_option_group = false

# Upgrade and Maintenance
auto_minor_version_upgrade  = true
allow_major_version_upgrade = false
apply_immediately           = false

# Security Configuration
deletion_protection = false  # EASIER MANAGEMENT FOR DEV

# Secrets Manager Configuration
store_credentials_in_secrets_manager = true
secret_recovery_window_days          = 7

# CloudWatch Alarms Configuration
create_cloudwatch_alarms        = true
cpu_utilization_threshold       = 80
free_storage_space_threshold    = 5368709120
freeable_memory_threshold       = 536870912
database_connections_threshold  = 100
```

## Free Tier Limitations and Restrictions

### 1. Backup Retention Period
**Limitation**: Must be set to `0` (no automated backups)
**Error if violated**:
```
FreeTierRestrictionError: The specified backup retention period exceeds
the maximum available to free tier customers.
```
**Impact**: No automatic point-in-time recovery available
**Workaround**: Create manual snapshots when needed

### 2. Storage Capacity
**Limitation**: Maximum 20 GB of storage
**Error if violated**: Charges applied for storage beyond 20 GB
**Impact**: Limited database size
**Workaround**: Monitor storage usage and clean up old data regularly

### 3. Instance Type
**Limitation**: Only `db.t2.micro` or `db.t3.micro` eligible
**Performance**: 1 vCPU, 1 GiB RAM (suitable for development/testing only)
**Impact**: Limited performance for production workloads
**Workaround**: Use for development/testing, upgrade for production

### 4. Multi-AZ Deployment
**Limitation**: Not supported in free tier
**Impact**: No automatic failover capability
**Risk**: Single point of failure
**Workaround**: Accept the risk for dev environments

### 5. Storage Encryption
**Limitation**: Not included in free tier
**Security Impact**: Data stored unencrypted
**Workaround**: Use application-level encryption or upgrade to paid tier

### 6. Enhanced Monitoring
**Limitation**: Not included in free tier
**Impact**: Limited visibility into database performance
**Workaround**: Use basic CloudWatch metrics (included)

### 7. Performance Insights
**Limitation**: Not included in free tier
**Impact**: No advanced query performance analysis
**Workaround**: Use CloudWatch Logs and basic metrics

### 8. Storage Autoscaling
**Limitation**: Setting `max_allocated_storage > 0` may incur charges
**Impact**: Cannot automatically grow storage
**Workaround**: Monitor storage and manually increase if needed

## Monthly Free Tier Allowance

AWS RDS Free Tier provides:
- **750 hours** of db.t2.micro or db.t3.micro instance time per month
- **20 GB** of General Purpose (SSD) database storage
- **20 GB** of backup storage for automated database backups and manual snapshots

**Important**: If you run a single `db.t3.micro` instance continuously:
- 24 hours/day × 30 days = 720 hours/month
- You stay within the 750-hour limit

**If you exceed**: You will be charged standard RDS rates for the excess usage.

## Cost Monitoring

To avoid unexpected charges, monitor your usage:

1. **Set up AWS Budgets**:
   ```bash
   aws budgets create-budget \
     --account-id YOUR_ACCOUNT_ID \
     --budget file://budget.json
   ```

2. **Enable billing alerts** in AWS Console:
   - Go to Billing → Billing Preferences
   - Enable "Receive Free Tier Usage Alerts"
   - Set up CloudWatch billing alarms

3. **Check Free Tier usage** regularly:
   - AWS Console → Billing Dashboard → Free Tier
   - Review usage tracking for RDS

## Transitioning to Production

When moving from Free Tier to production, follow this upgrade path:

### Phase 1: Enable Backups
```hcl
backup_retention_period = 7
skip_final_snapshot = false
```

### Phase 2: Upgrade Instance
```hcl
db_instance_class = "db.t3.small"  # or larger
```

### Phase 3: Enable Monitoring
```hcl
monitoring_interval = 60
performance_insights_enabled = true
```

### Phase 4: Enable Encryption
```hcl
storage_encrypted = true
```
**Note**: Encryption cannot be enabled on existing instance; must create snapshot and restore

### Phase 5: Enable High Availability
```hcl
multi_az = true
```

### Phase 6: Increase Storage
```hcl
allocated_storage = 100
max_allocated_storage = 500
storage_type = "gp3"
```

## Testing Free Tier Configuration

After applying your configuration, verify it's within free tier:

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# Verify instance details
aws rds describe-db-instances \
  --db-instance-identifier myproject-dev-rds \
  --query 'DBInstances[0].[DBInstanceClass,AllocatedStorage,StorageType,MultiAZ,BackupRetentionPeriod]' \
  --output table
```

Expected output:
```
----------------------------------
|   DescribeDBInstances          |
+--------------------------------+
|  db.t3.micro                   |
|  20                            |
|  gp2                           |
|  False                         |
|  0                             |
+--------------------------------+
```

## Common Errors and Solutions

### Error 1: FreeTierRestrictionError
**Error**:
```
FreeTierRestrictionError: The specified backup retention period exceeds
the maximum available to free tier customers.
```
**Solution**: Set `backup_retention_period = 0`

### Error 2: Storage Encryption Not Supported
**Error**:
```
InvalidParameterCombination: Encryption is not available for db.t2.micro
```
**Solution**: Set `storage_encrypted = false`

### Error 3: Enhanced Monitoring Charges
**Warning**: Setting `monitoring_interval > 0` will incur charges
**Solution**: Set `monitoring_interval = 0`

### Error 4: Performance Insights Charges
**Warning**: Enabling Performance Insights incurs additional costs
**Solution**: Set `performance_insights_enabled = false`

## Additional Resources

- [AWS RDS Free Tier](https://aws.amazon.com/rds/free/)
- [AWS Free Tier FAQs](https://aws.amazon.com/free/free-tier-faqs/)
- [RDS Pricing Calculator](https://calculator.aws/#/addService/RDS)
- [RDS Instance Types](https://aws.amazon.com/rds/instance-types/)

## Support

For questions or issues:
1. Check AWS Free Tier usage dashboard
2. Review CloudWatch metrics and logs
3. Consult AWS documentation
4. Contact AWS Support (if applicable)
