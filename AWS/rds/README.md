# AWS RDS Terraform Configuration

This Terraform configuration creates a fully-configured Amazon RDS instance with best practices for security, monitoring, backup, and high availability.

## Features

### Core Functionality
- Automated RDS instance provisioning with configurable engine support (PostgreSQL, MySQL, MariaDB, Oracle, SQL Server)
- VPC and subnet configuration for network isolation
- Security group configuration with customizable access rules
- Automated password generation and secure storage in AWS Secrets Manager

### Security
- Storage encryption enabled by default
- Automated password generation using random provider
- Credentials stored in AWS Secrets Manager
- Deletion protection enabled by default
- Network isolation with private subnets
- Configurable security group rules

### High Availability
- Multi-AZ deployment support
- Automated backups with configurable retention
- Point-in-time recovery capability
- Automated failover for Multi-AZ deployments

### Monitoring and Alerting
- Enhanced Monitoring with configurable intervals
- Performance Insights enabled by default
- CloudWatch Logs export (query logs, error logs, etc.)
- Pre-configured CloudWatch Alarms:
  - CPU Utilization
  - Free Storage Space
  - Freeable Memory
  - Database Connections
- Custom IAM role for Enhanced Monitoring

### Backup and Recovery
- Automated daily backups
- Configurable backup retention period (7 days default)
- Final snapshot before deletion
- Point-in-time restore capability

### Customization
- Custom Parameter Groups for database tuning
- Custom Option Groups (for MySQL/Oracle)
- Configurable storage autoscaling
- Multiple storage types (gp2, gp3, io1, io2)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- AWS Provider >= 5.0

## Quick Start

### 1. Clone and Navigate
```bash
cd AWS/rds
```

### 2. Create Variables File
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. Customize Configuration
Edit `terraform.tfvars` with your desired settings:

```hcl
aws_region   = "us-east-1"
environment  = "production"
project_name = "myapp"

db_engine         = "postgres"
db_engine_version = "15.8"
db_instance_class = "db.r5.large"
db_username       = "dbadmin"
multi_az          = true

allocated_storage     = 100
max_allocated_storage = 500
storage_encrypted     = true

backup_retention_period = 30
```

### 4. Initialize Terraform
```bash
terraform init
```

### 5. Review Plan
```bash
terraform plan
```

### 6. Apply Configuration
```bash
terraform apply
```

### 7. Retrieve Database Credentials
After deployment, retrieve credentials from AWS Secrets Manager:

```bash
# Get secret ARN from Terraform output
terraform output secrets_manager_secret_arn

# Retrieve credentials using AWS CLI
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString \
  --output text | jq .
```

## AWS Free Tier Configuration

This configuration has been optimized to work with AWS RDS Free Tier by default. The free tier includes:

### Free Tier Specifications
- **Instance Type**: db.t2.micro or db.t3.micro (1 vCPU, 1 GiB RAM)
- **Storage**: Up to 20 GB of General Purpose (SSD) storage (gp2)
- **Backup**: 0 days retention (automated backups not included in free tier)
- **Multi-AZ**: Not supported in free tier
- **Monitoring**: Basic monitoring only (Enhanced Monitoring requires additional cost)
- **Performance Insights**: Not included in free tier
- **Encryption**: Not included in free tier (storage encryption requires additional cost)
- **Duration**: 750 hours per month for 12 months

### Default Free Tier Settings

The following default values are configured for AWS Free Tier compatibility:

```hcl
# Instance Configuration
db_instance_class = "db.t3.micro"        # Free tier eligible
allocated_storage = 20                    # Maximum for free tier
max_allocated_storage = 0                 # Autoscaling disabled
storage_type = "gp2"                      # Free tier storage type
storage_encrypted = false                 # Encryption not included

# High Availability
multi_az = false                          # Not supported in free tier

# Backup Configuration
backup_retention_period = 0               # Free tier requires 0
skip_final_snapshot = true                # Recommended for dev/free tier

# Monitoring
monitoring_interval = 0                   # Enhanced monitoring disabled
performance_insights_enabled = false      # Not included in free tier

# Security
deletion_protection = false               # Easier management for dev/free tier
```

### Upgrading from Free Tier to Production

When you're ready to move to production, update these settings in your `terraform.tfvars`:

```hcl
# Production Configuration
db_instance_class = "db.r5.large"         # Production instance
allocated_storage = 100                   # Larger storage
max_allocated_storage = 500               # Enable autoscaling
storage_type = "gp3"                      # Better performance
storage_encrypted = true                  # Enable encryption

# High Availability
multi_az = true                           # Enable Multi-AZ

# Backup Configuration
backup_retention_period = 30              # 30-day retention
skip_final_snapshot = false               # Protect data

# Monitoring
monitoring_interval = 60                  # Enable Enhanced Monitoring
performance_insights_enabled = true       # Enable Performance Insights

# Security
deletion_protection = true                # Prevent accidental deletion
```

### Important Free Tier Limitations

1. **Backup Retention**: Setting `backup_retention_period > 0` will cause the error:
   ```
   FreeTierRestrictionError: The specified backup retention period exceeds
   the maximum available to free tier customers.
   ```

2. **Storage Autoscaling**: Setting `max_allocated_storage > 0` may incur charges once storage exceeds 20 GB.

3. **Enhanced Monitoring**: Setting `monitoring_interval > 0` will incur additional CloudWatch costs.

4. **Performance Insights**: Enabling this feature incurs additional costs beyond free tier.

5. **Encryption**: Enabling `storage_encrypted = true` requires KMS key which has associated costs.

6. **Multi-AZ**: This feature is not available in the free tier and will incur significant additional costs.

## Configuration Options

### Database Engine Support

The configuration supports the following database engines:

| Engine | Default Port | Parameter Group Family | Notes |
|--------|-------------|----------------------|-------|
| PostgreSQL | 5432 | postgres15 | Default engine |
| MySQL | 3306 | mysql8.0 | Requires option group |
| MariaDB | 3306 | mariadb10.6 | Similar to MySQL |
| Oracle | 1521 | oracle-ee-19 | Enterprise features |
| SQL Server | 1433 | sqlserver-ee-15.0 | Windows-based |

### Instance Classes

Choose appropriate instance class based on your workload:

**Development/Testing:**
- `db.t3.micro` - 2 vCPU, 1 GiB RAM
- `db.t3.small` - 2 vCPU, 2 GiB RAM
- `db.t3.medium` - 2 vCPU, 4 GiB RAM

**Production (Memory-Optimized):**
- `db.r5.large` - 2 vCPU, 16 GiB RAM
- `db.r5.xlarge` - 4 vCPU, 32 GiB RAM
- `db.r6g.2xlarge` - 8 vCPU, 64 GiB RAM (Graviton2)

**Production (Compute-Optimized):**
- `db.m5.large` - 2 vCPU, 8 GiB RAM
- `db.m5.xlarge` - 4 vCPU, 16 GiB RAM

### Storage Types

| Type | Use Case | IOPS | Throughput |
|------|----------|------|------------|
| gp2 | General purpose | 3 IOPS/GB (max 16,000) | Up to 250 MB/s |
| gp3 | General purpose (newer) | 3,000-16,000 baseline | 125-1,000 MB/s |
| io1 | High performance | Up to 64,000 | Up to 1,000 MB/s |
| io2 | Mission-critical | Up to 256,000 | Up to 4,000 MB/s |

### Environment-Specific Configurations

#### Development
```hcl
environment             = "dev"
db_instance_class       = "db.t3.micro"
multi_az                = false
backup_retention_period = 1
deletion_protection     = false
skip_final_snapshot     = true
```

#### Staging
```hcl
environment             = "staging"
db_instance_class       = "db.t3.medium"
multi_az                = false
backup_retention_period = 7
deletion_protection     = true
skip_final_snapshot     = false
```

#### Production
```hcl
environment             = "production"
db_instance_class       = "db.r5.large"
multi_az                = true
backup_retention_period = 30
deletion_protection     = true
skip_final_snapshot     = false
storage_encrypted       = true
```

## Outputs

The configuration provides comprehensive outputs:

### Connection Information
- `rds_instance_endpoint` - Full connection endpoint (hostname:port)
- `rds_instance_address` - Database hostname
- `rds_instance_port` - Database port
- `connection_string` - Ready-to-use connection string

### Resource Identifiers
- `rds_instance_id` - RDS instance identifier
- `rds_instance_arn` - RDS instance ARN
- `vpc_id` - VPC identifier
- `security_group_id` - Security group identifier

### Credentials and Secrets
- `secrets_manager_secret_arn` - ARN of Secrets Manager secret
- `database_username` - Master username (sensitive)

### Monitoring
- `monitoring_role_arn` - Enhanced Monitoring IAM role
- `cloudwatch_alarm_*_id` - CloudWatch alarm identifiers

## Best Practices

### Security
1. Never set `publicly_accessible = true` for production databases
2. Always enable `storage_encrypted = true`
3. Use Secrets Manager for credential management
4. Enable `deletion_protection = true` for production
5. Restrict `allowed_cidr_blocks` to minimum required ranges
6. Use VPN or bastion hosts for database access

### High Availability
1. Enable `multi_az = true` for production workloads
2. Set appropriate `backup_retention_period` (30 days for production)
3. Configure backup and maintenance windows during low-traffic periods
4. Test restore procedures regularly

### Performance
1. Choose appropriate instance class for your workload
2. Enable Performance Insights for query analysis
3. Configure parameter groups based on workload characteristics
4. Use gp3 storage for better price/performance ratio
5. Enable storage autoscaling with `max_allocated_storage`

### Monitoring
1. Configure CloudWatch alarms with appropriate thresholds
2. Enable Enhanced Monitoring (60-second interval recommended)
3. Export logs to CloudWatch for analysis
4. Set up SNS topics for alarm notifications

### Cost Optimization
1. Use Reserved Instances for production workloads (up to 69% savings)
2. Right-size instance classes based on actual usage
3. Use gp3 instead of gp2 for better cost efficiency
4. Configure appropriate backup retention periods
5. Enable storage autoscaling to avoid over-provisioning

## Connecting to RDS

### Using Connection String from Terraform Output
```bash
# Get connection details
ENDPOINT=$(terraform output -raw rds_instance_endpoint)
DB_NAME=$(terraform output -raw database_name)
USERNAME=$(terraform output -raw database_username)

# For PostgreSQL
psql "postgresql://$USERNAME@$ENDPOINT/$DB_NAME"

# For MySQL
mysql -h ${ENDPOINT%%:*} -P ${ENDPOINT##*:} -u $USERNAME -p $DB_NAME
```

### Using Credentials from Secrets Manager
```bash
# Retrieve credentials
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString --output text)

# Parse and connect (PostgreSQL example)
HOST=$(echo $SECRET | jq -r .host)
PORT=$(echo $SECRET | jq -r .port)
DBNAME=$(echo $SECRET | jq -r .dbname)
USER=$(echo $SECRET | jq -r .username)
PASSWORD=$(echo $SECRET | jq -r .password)

PGPASSWORD=$PASSWORD psql -h $HOST -p $PORT -U $USER -d $DBNAME
```

## Maintenance

### Upgrading Database Version
1. Review AWS RDS documentation for upgrade paths
2. Test upgrade in non-production environment first
3. Update `db_engine_version` in terraform.tfvars
4. Set `allow_major_version_upgrade = true` for major version upgrades
5. Run `terraform plan` to review changes
6. Apply during maintenance window

### Modifying Instance Class
1. Update `db_instance_class` in terraform.tfvars
2. Consider setting `apply_immediately = true` for urgent changes
3. Run `terraform apply`
4. Monitor performance after change

### Scaling Storage
Storage can only be scaled up, not down:
1. Update `allocated_storage` or `max_allocated_storage`
2. Run `terraform apply`
3. Note: Storage modifications may take several hours

## Troubleshooting

### Common Issues

**Connection Timeout**
- Verify security group rules allow traffic from your IP
- Check VPC routing and internet gateway configuration
- Ensure RDS is in correct subnet group

**Authentication Failure**
- Retrieve latest credentials from Secrets Manager
- Verify username and password are correct
- Check if password contains special characters that need escaping

**Insufficient Storage**
- Monitor `FreeStorageSpace` CloudWatch metric
- Increase `allocated_storage` or enable autoscaling
- Consider upgrading to larger instance class

**High CPU Usage**
- Review slow query logs in CloudWatch
- Analyze queries using Performance Insights
- Consider upgrading instance class or optimizing queries

## Disaster Recovery

### Backup Strategy
1. Automated daily backups (configurable retention)
2. Manual snapshots before major changes
3. Point-in-time recovery within retention period
4. Cross-region snapshot copying for DR

### Restore Procedures

**Point-in-Time Restore:**
```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier mydb \
  --target-db-instance-identifier mydb-restored \
  --restore-time 2025-01-15T10:00:00Z
```

**Snapshot Restore:**
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier mydb-restored \
  --db-snapshot-identifier mydb-snapshot
```

## Cleanup

To destroy all resources:

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy resources
terraform destroy

# Note: Final snapshot will be created unless skip_final_snapshot = true
```

## Advanced Configuration

### Custom Parameter Groups for MySQL
```hcl
db_parameter_group_family = "mysql8.0"
db_parameters = [
  {
    name  = "max_connections"
    value = "200"
  },
  {
    name  = "slow_query_log"
    value = "1"
  },
  {
    name  = "long_query_time"
    value = "2"
  }
]
```

### Custom Option Groups for Oracle
```hcl
create_db_option_group = true
db_major_engine_version = "19"
db_options = [
  {
    option_name = "OEM"
    option_settings = [
      {
        name  = "OMS_PORT"
        value = "5500"
      }
    ]
  }
]
```

### Multi-Region Deployment
For cross-region disaster recovery, create read replicas:

```hcl
resource "aws_db_instance" "replica" {
  replicate_source_db = aws_db_instance.rds.arn
  instance_class      = var.db_instance_class

  provider = aws.us-west-2  # Different region
}
```

## Support and Resources

- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [RDS Pricing Calculator](https://calculator.aws/)

## License

This configuration is provided as-is for use in your projects.
