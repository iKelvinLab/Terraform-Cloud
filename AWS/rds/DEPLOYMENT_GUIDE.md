# RDS Deployment Guide

This guide provides step-by-step instructions for deploying AWS RDS instances using this Terraform configuration.

## Table of Contents
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment Verification](#post-deployment-verification)
- [Environment-Specific Deployments](#environment-specific-deployments)
- [Troubleshooting](#troubleshooting)

## Pre-Deployment Checklist

### 1. AWS Account Setup
- [ ] AWS account created and active
- [ ] IAM user created with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] AWS credentials configured (`aws configure`)

### 2. Required IAM Permissions

The IAM user/role requires the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "ec2:CreateVpc",
        "ec2:CreateSubnet",
        "ec2:CreateSecurityGroup",
        "ec2:CreateInternetGateway",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeAvailabilityZones",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:GetSecretValue",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DescribeAlarms",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PassRole",
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. Tools Installation

```bash
# Terraform installation
brew install terraform  # macOS
# or
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installation
terraform version

# AWS CLI installation (if not already installed)
brew install awscli  # macOS
# or
pip install awscli

# Verify AWS CLI
aws --version
```

### 4. Cost Estimation

Before deployment, estimate your monthly costs:

**Development Environment (db.t3.micro, 20GB storage):**
- Instance: ~$15/month
- Storage: ~$2.30/month
- Backup: ~$2/month (if 20GB retained)
- **Total: ~$20/month**

**Production Environment (db.r5.large, 100GB storage, Multi-AZ):**
- Instance: ~$290/month (Multi-AZ doubles the cost)
- Storage: ~$11.50/month
- Backup: ~$10/month (if 100GB retained)
- Enhanced Monitoring: ~$7/month
- **Total: ~$320/month**

Use the [AWS Pricing Calculator](https://calculator.aws/) for accurate estimates.

## Deployment Steps

### Step 1: Clone Configuration

```bash
cd /Users/jinxiaozhang/Project/Terraform-Cloud/AWS/rds
```

### Step 2: Create Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
```

### Step 3: Configure Variables

Edit `terraform.tfvars` with your desired configuration:

```hcl
# Minimum required configuration
aws_region   = "us-east-1"
environment  = "dev"
project_name = "myapp"

# Database configuration
db_engine         = "postgres"
db_engine_version = "15.8"
db_instance_class = "db.t3.micro"
db_name           = "myappdb"
db_username       = "dbadmin"

# Network configuration
allowed_cidr_blocks = ["10.0.0.0/16"]  # Update with your IP/CIDR

# Security
create_random_password = true
storage_encrypted      = true
deletion_protection    = true
```

### Step 4: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/random versions matching "~> 3.5"...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

### Step 5: Validate Configuration

```bash
terraform validate
```

Expected output:
```
Success! The configuration is valid.
```

### Step 6: Format Code

```bash
terraform fmt -recursive
```

### Step 7: Review Deployment Plan

```bash
terraform plan -out=tfplan
```

Review the output carefully:
- Check resource counts (should create ~15-20 resources)
- Verify configuration values
- Confirm no unexpected changes

### Step 8: Apply Configuration

```bash
terraform apply tfplan
```

Or apply directly with approval:
```bash
terraform apply
```

Type `yes` when prompted.

**Deployment Time:**
- Initial deployment: 5-10 minutes
- Multi-AZ deployment: 10-15 minutes

### Step 9: Save Outputs

```bash
# Save all outputs to a file
terraform output > outputs.txt

# Get specific outputs
terraform output rds_instance_endpoint
terraform output secrets_manager_secret_arn
```

## Post-Deployment Verification

### 1. Verify RDS Instance

```bash
# Check instance status
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
```

Expected output: `available`

### 2. Retrieve Credentials

```bash
# Get credentials from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString \
  --output text | jq .
```

### 3. Test Database Connection

#### PostgreSQL
```bash
# Get connection details
ENDPOINT=$(terraform output -raw rds_instance_endpoint)
DB_NAME=$(terraform output -raw database_name)

# Get password from Secrets Manager
PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString --output text | jq -r .password)

# Connect to database
PGPASSWORD=$PASSWORD psql -h ${ENDPOINT%%:*} -p ${ENDPOINT##*:} -U dbadmin -d $DB_NAME -c "SELECT version();"
```

#### MySQL
```bash
ENDPOINT=$(terraform output -raw rds_instance_endpoint)
PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString --output text | jq -r .password)

mysql -h ${ENDPOINT%%:*} -P ${ENDPOINT##*:} -u dbadmin -p$PASSWORD -e "SELECT VERSION();"
```

### 4. Verify CloudWatch Alarms

```bash
# List created alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "myapp-dev-rds" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

### 5. Verify Enhanced Monitoring

```bash
# Check monitoring logs
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/rds/instance/$(terraform output -raw rds_instance_id)" \
  --query 'logGroups[*].logGroupName'
```

### 6. Verify Backup Configuration

```bash
# Check automated backup settings
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].[BackupRetentionPeriod,PreferredBackupWindow]' \
  --output table
```

## Environment-Specific Deployments

### Development Environment

**terraform.tfvars:**
```hcl
aws_region   = "us-east-1"
environment  = "dev"
project_name = "myapp"

db_instance_class       = "db.t3.micro"
multi_az                = false
backup_retention_period = 1
deletion_protection     = false
skip_final_snapshot     = true

allocated_storage     = 20
max_allocated_storage = 50

create_cloudwatch_alarms = false
monitoring_interval      = 0
```

**Deployment:**
```bash
terraform apply -auto-approve
```

### Staging Environment

**terraform.tfvars:**
```hcl
aws_region   = "us-east-1"
environment  = "staging"
project_name = "myapp"

db_instance_class       = "db.t3.medium"
multi_az                = false
backup_retention_period = 7
deletion_protection     = true
skip_final_snapshot     = false

allocated_storage     = 50
max_allocated_storage = 100

create_cloudwatch_alarms = true
monitoring_interval      = 60
```

**Deployment:**
```bash
terraform plan -out=staging.tfplan
terraform apply staging.tfplan
```

### Production Environment

**terraform.tfvars:**
```hcl
aws_region   = "us-east-1"
environment  = "production"
project_name = "myapp"

db_instance_class       = "db.r5.large"
multi_az                = true
backup_retention_period = 30
deletion_protection     = true
skip_final_snapshot     = false

allocated_storage     = 100
max_allocated_storage = 500
storage_type          = "gp3"

create_cloudwatch_alarms              = true
monitoring_interval                   = 60
performance_insights_enabled          = true
performance_insights_retention_period = 731

# SNS topic for alarms
alarm_actions = ["arn:aws:sns:us-east-1:123456789012:production-alerts"]
```

**Deployment:**
```bash
# Extra review for production
terraform plan -out=production.tfplan
# Have a colleague review the plan
terraform apply production.tfplan
```

## Troubleshooting

### Common Issues

#### Issue 1: Insufficient Permissions

**Error:**
```
Error: creating RDS DB Instance: AccessDenied: User is not authorized to perform: rds:CreateDBInstance
```

**Solution:**
Ensure your IAM user/role has the required permissions listed in the Pre-Deployment Checklist.

#### Issue 2: Subnet Group Creation Failed

**Error:**
```
Error: creating DB Subnet Group: DBSubnetGroupDoesNotCoverEnoughAZs
```

**Solution:**
Ensure you have at least 2 subnets in different availability zones:
```hcl
database_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
```

#### Issue 3: Invalid Parameter Group Family

**Error:**
```
Error: InvalidParameterValue: Invalid DB parameter group family
```

**Solution:**
Match the parameter group family with your engine version:
```hcl
db_engine = "postgres"
db_engine_version = "15.8"
db_parameter_group_family = "postgres15"  # Must match major version
```

#### Issue 4: Connection Timeout

**Error:**
```
psql: error: connection to server at "xxx.rds.amazonaws.com" timed out
```

**Solution:**
1. Check security group allows your IP:
```hcl
allowed_cidr_blocks = ["YOUR.PUBLIC.IP.ADDRESS/32"]
```

2. Verify VPC and subnet configuration
3. Ensure your machine has internet connectivity
4. Check if RDS is publicly accessible (if connecting from outside VPC)

#### Issue 5: Storage Size Too Small

**Error:**
```
Error: Allocated storage must be at least 100GB for db.r5.large instance class
```

**Solution:**
Increase storage allocation for larger instance classes:
```hcl
allocated_storage = 100
```

### Debugging Commands

```bash
# Check Terraform state
terraform show

# List all resources
terraform state list

# Inspect specific resource
terraform state show aws_db_instance.rds

# Enable detailed logging
export TF_LOG=DEBUG
terraform apply

# Refresh state
terraform refresh

# Import existing resource (if needed)
terraform import aws_db_instance.rds myapp-dev-rds
```

### Rollback Procedure

If deployment fails or you need to rollback:

```bash
# Destroy specific resource
terraform destroy -target=aws_db_instance.rds

# Destroy all resources
terraform destroy

# Restore from snapshot (if available)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-dev-rds \
  --db-snapshot-identifier myapp-dev-rds-snapshot-backup
```

## Maintenance Operations

### Upgrade Database Version

```bash
# Update variables
# terraform.tfvars:
# db_engine_version = "15.8"
# allow_major_version_upgrade = false  # or true for major upgrades

terraform plan
terraform apply
```

### Scale Instance

```bash
# Update variables
# terraform.tfvars:
# db_instance_class = "db.r5.xlarge"

terraform plan
terraform apply
```

### Modify Storage

```bash
# Update variables (can only increase)
# terraform.tfvars:
# allocated_storage = 200

terraform plan
terraform apply
```

## Best Practices for Production Deployment

1. **Use Remote State Backend:**
```hcl
# versions.tf
terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state"
    key            = "rds/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

2. **Use Terraform Workspaces:**
```bash
terraform workspace new production
terraform workspace select production
terraform apply
```

3. **Enable State Locking:**
```bash
# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

4. **Create Snapshots Before Major Changes:**
```bash
aws rds create-db-snapshot \
  --db-instance-identifier myapp-prod-rds \
  --db-snapshot-identifier myapp-prod-pre-upgrade-$(date +%Y%m%d)
```

5. **Test in Non-Production First:**
Always test changes in dev/staging before applying to production.

6. **Use CI/CD Pipeline:**
Integrate with GitHub Actions, GitLab CI, or Jenkins for automated deployments.

## Support

For issues or questions:
- Review AWS RDS documentation
- Check Terraform AWS provider documentation
- Review CloudWatch logs for RDS events
- Contact AWS Support for RDS-specific issues

## Next Steps

After successful deployment:
1. Configure database schema and users
2. Set up monitoring dashboards
3. Configure backup verification
4. Document connection procedures
5. Set up alerting and on-call procedures
6. Perform load testing
7. Create disaster recovery runbook
