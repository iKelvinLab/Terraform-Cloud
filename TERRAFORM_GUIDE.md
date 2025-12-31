# Terraform 使用指南

本指南提供 Terraform 基础知识、本项目的最佳实践、常用命令和操作流程。

## 目录

- [Terraform 简介](#terraform-简介)
- [安装和配置](#安装和配置)
- [基本概念](#基本概念)
- [核心工作流程](#核心工作流程)
- [常用命令](#常用命令)
- [项目最佳实践](#项目最佳实践)
- [状态管理](#状态管理)
- [变量和输出](#变量和输出)
- [模块化开发](#模块化开发)
- [安全实践](#安全实践)
- [故障排除](#故障排除)
- [性能优化](#性能优化)

## Terraform 简介

### 什么是 Terraform？

Terraform 是 HashiCorp 开发的**基础设施即代码**（Infrastructure as Code, IaC）工具，允许你使用声明式配置文件定义和管理云基础设施。

### 核心优势

- **声明式语法**: 描述"想要什么"而不是"如何实现"
- **版本控制**: 基础设施配置可以像代码一样进行版本管理
- **多云支持**: 支持 AWS、Azure、GCP、阿里云等 200+ 云平台
- **依赖管理**: 自动处理资源间的依赖关系
- **执行计划**: 在应用更改前预览将要执行的操作
- **状态管理**: 追踪实际基础设施状态

### Terraform vs 其他工具

| 特性 | Terraform | CloudFormation | Ansible | Pulumi |
|------|-----------|----------------|---------|--------|
| 语言 | HCL | JSON/YAML | YAML | 编程语言 |
| 多云支持 | ✅ 优秀 | ❌ 仅 AWS | ✅ 良好 | ✅ 优秀 |
| 状态管理 | ✅ 内置 | ✅ AWS 管理 | ❌ 无 | ✅ 内置 |
| 学习曲线 | 中等 | 中等 | 简单 | 较难 |
| 社区生态 | 很好 | 良好 | 很好 | 新兴 |

## 安装和配置

### 安装 Terraform

#### macOS

```bash
# 使用 Homebrew
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 验证安装
terraform version
```

#### Linux (Ubuntu/Debian)

```bash
# 添加 HashiCorp GPG 密钥
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 添加仓库
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 安装
sudo apt update
sudo apt install terraform
```

#### Windows

```powershell
# 使用 Chocolatey
choco install terraform

# 或下载二进制文件
# https://www.terraform.io/downloads
```

### 配置云平台凭证

#### AWS

```bash
# 方式 1: 使用 AWS CLI 配置
aws configure
# 输入:
#   AWS Access Key ID: YOUR_ACCESS_KEY
#   AWS Secret Access Key: YOUR_SECRET_KEY
#   Default region name: us-west-2
#   Default output format: json

# 方式 2: 使用环境变量
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"

# 方式 3: 在 Terraform 配置中（不推荐）
provider "aws" {
  region     = "us-west-2"
  access_key = "YOUR_ACCESS_KEY"  # ❌ 不要这样做！
  secret_key = "YOUR_SECRET_KEY"  # ❌ 不要这样做！
}

# 验证配置
aws sts get-caller-identity
```

#### 阿里云

```bash
# 使用环境变量
export ALICLOUD_ACCESS_KEY="your-access-key"
export ALICLOUD_SECRET_KEY="your-secret-key"
export ALICLOUD_REGION="cn-hangzhou"
```

### 编辑器配置

推荐使用 VS Code 并安装以下插件：

1. **HashiCorp Terraform** - 官方插件，提供语法高亮和自动补全
2. **Terraform Doc Snippets** - 文档片段
3. **AWS Toolkit** - AWS 资源浏览

配置 VS Code 设置（`.vscode/settings.json`）：

```json
{
  "terraform.languageServer.enable": true,
  "terraform.validation.enableEnhancedValidation": true,
  "files.associations": {
    "*.tf": "terraform",
    "*.tfvars": "terraform"
  },
  "[terraform]": {
    "editor.formatOnSave": true
  }
}
```

## 基本概念

### HCL 语法

Terraform 使用 HashiCorp Configuration Language (HCL) 编写配置：

```hcl
# 资源定义
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name = "WebServer"
  }
}

# 变量定义
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

# 输出定义
output "instance_ip" {
  description = "Public IP of the instance"
  value       = aws_instance.web.public_ip
}
```

### 核心组件

```mermaid
graph TD
    A[Provider] --> B[Resource]
    A --> C[Data Source]
    D[Variable] --> B
    B --> E[Output]
    F[Module] --> B
    G[State] -.管理.-> B
```

#### 1. Provider（提供商）

Provider 是与云平台 API 交互的插件：

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

#### 2. Resource（资源）

Resource 是基础设施的基本组件：

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}
```

#### 3. Data Source（数据源）

Data Source 用于查询外部信息：

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
```

#### 4. Variable（变量）

Variable 用于参数化配置：

```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

#### 5. Output（输出）

Output 用于导出资源信息：

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}
```

#### 6. Module（模块）

Module 是可重用的 Terraform 配置：

```hcl
module "vpc" {
  source = "./modules/vpc"

  cidr_block  = "10.0.0.0/16"
  environment = "production"
}
```

## 核心工作流程

Terraform 的标准工作流程包括四个阶段：

```mermaid
graph LR
    A[1. Init<br/>初始化] --> B[2. Plan<br/>计划]
    B --> C[3. Apply<br/>应用]
    C --> D[4. Destroy<br/>销毁]
    D -.可选.-> A
```

### 1. terraform init（初始化）

初始化工作目录，下载 provider 插件和模块：

```bash
# 基本初始化
terraform init

# 升级 provider 到最新版本
terraform init -upgrade

# 从远程状态后端初始化
terraform init -backend-config="bucket=my-terraform-state"

# 禁用插件安装（仅验证）
terraform init -get-plugins=false
```

**执行内容**：
- 下载配置的 provider 插件
- 初始化 backend 状态存储
- 下载引用的模块
- 创建 `.terraform/` 目录

### 2. terraform plan（计划）

生成执行计划，预览将要执行的操作：

```bash
# 基本计划
terraform plan

# 保存计划到文件
terraform plan -out=tfplan

# 使用变量文件
terraform plan -var-file="production.tfvars"

# 指定变量
terraform plan -var="instance_type=t3.large"

# 针对特定资源
terraform plan -target=aws_instance.web
```

**输出符号**：
- `+` 创建资源
- `-` 删除资源
- `~` 更新资源（就地修改）
- `-/+` 替换资源（删除后重建）
- `<=` 读取数据源

### 3. terraform apply（应用）

应用计划的更改，创建或修改基础设施：

```bash
# 基本应用（会提示确认）
terraform apply

# 自动批准（跳过确认）
terraform apply -auto-approve

# 应用保存的计划文件
terraform apply tfplan

# 使用变量文件
terraform apply -var-file="production.tfvars"

# 并行执行（默认 10）
terraform apply -parallelism=20
```

### 4. terraform destroy（销毁）

销毁所有由 Terraform 管理的基础设施：

```bash
# 销毁所有资源（会提示确认）
terraform destroy

# 自动批准
terraform destroy -auto-approve

# 销毁特定资源
terraform destroy -target=aws_instance.web

# 使用变量文件
terraform destroy -var-file="production.tfvars"
```

## 常用命令

### 验证和格式化

```bash
# 格式化配置文件
terraform fmt

# 递归格式化所有子目录
terraform fmt -recursive

# 检查格式（不修改文件）
terraform fmt -check

# 验证配置语法
terraform validate

# 验证并显示详细错误
terraform validate -json
```

### 状态管理

```bash
# 查看当前状态
terraform show

# 以 JSON 格式显示
terraform show -json

# 列出所有资源
terraform state list

# 显示特定资源详情
terraform state show aws_instance.web

# 移动资源（重命名）
terraform state mv aws_instance.old aws_instance.new

# 从状态中移除资源（不删除实际资源）
terraform state rm aws_instance.web

# 导入现有资源
terraform import aws_instance.web i-1234567890abcdef0

# 刷新状态（同步实际状态）
terraform refresh
```

### 输出管理

```bash
# 查看所有输出
terraform output

# 查看特定输出
terraform output vpc_id

# 以 JSON 格式输出
terraform output -json

# 获取原始值（无引号）
terraform output -raw alb_dns_name
```

### 工作区管理

Terraform 工作区用于管理同一配置的多个环境：

```bash
# 列出所有工作区
terraform workspace list

# 创建新工作区
terraform workspace new development

# 切换工作区
terraform workspace select production

# 显示当前工作区
terraform workspace show

# 删除工作区
terraform workspace delete staging
```

使用工作区的配置示例：

```hcl
locals {
  environment = terraform.workspace

  instance_count = {
    default    = 1
    production = 3
    staging    = 2
  }
}

resource "aws_instance" "app" {
  count         = local.instance_count[terraform.workspace]
  instance_type = "t3.micro"
  # ...
}
```

### 图形可视化

```bash
# 生成依赖关系图（DOT 格式）
terraform graph

# 生成 PNG 图片（需要安装 Graphviz）
terraform graph | dot -Tpng > graph.png

# 生成 SVG 图片
terraform graph | dot -Tsvg > graph.svg

# 只显示资源（不含模块）
terraform graph -type=plan
```

### 高级命令

```bash
# 生成并保存执行计划
terraform plan -out=tfplan

# 查看计划文件内容
terraform show tfplan

# 应用计划文件
terraform apply tfplan

# 强制解锁状态（谨慎使用）
terraform force-unlock <lock-id>

# 替换资源（强制重建）
terraform apply -replace=aws_instance.web

# 获取 provider 文档
terraform providers

# 查看 provider schema
terraform providers schema -json
```

## 项目最佳实践

### 文件组织结构

推荐的 Terraform 项目结构：

```
terraform-project/
├── main.tf                    # 主配置文件（Provider、核心资源）
├── variables.tf               # 变量定义
├── outputs.tf                 # 输出定义
├── versions.tf                # Terraform 和 Provider 版本约束
├── terraform.tfvars.example   # 变量配置示例（提交到 Git）
├── terraform.tfvars           # 实际变量值（不提交到 Git）
│
├── modules/                   # 自定义模块
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── ec2/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/              # 多环境配置
│   ├── dev/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       └── terraform.tfvars
│
└── README.md                  # 项目文档
```

### 版本约束

在 `versions.tf` 中明确指定版本：

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # 允许 5.x 的任何版本
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"  # 至少 3.0
    }
  }
}
```

版本约束符号：
- `=` - 精确版本: `= 1.2.3`
- `!=` - 排除版本: `!= 1.2.3`
- `>`, `>=`, `<`, `<=` - 比较符号
- `~>` - 悲观约束: `~> 1.2` 允许 `>= 1.2, < 2.0`

### 命名规范

#### 资源命名

```hcl
# 格式: resource_type.descriptive_name
resource "aws_instance" "web_server" {  # ✅ 好
  # ...
}

resource "aws_instance" "instance1" {   # ❌ 差
  # ...
}
```

#### 变量命名

```hcl
variable "instance_type" {        # ✅ 使用 snake_case
  # ...
}

variable "InstanceType" {         # ❌ 避免 PascalCase
  # ...
}
```

#### 标签规范

```hcl
locals {
  common_tags = {
    Project     = "terraform-cloud"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "infrastructure-team"
    CostCenter  = "engineering"
  }
}

resource "aws_instance" "web" {
  # ...
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-web-${var.environment}"
      Role = "web-server"
    }
  )
}
```

### 代码注释

```hcl
# 创建 VPC 用于托管应用基础设施
# CIDR: 10.0.0.0/16 提供 65,536 个 IP 地址
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true  # 启用 DNS 主机名支持

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# TODO: 添加 VPC Flow Logs 用于网络监控
# FIXME: CIDR 可能与现有网络冲突
```

## 状态管理

### 本地状态

默认情况下，Terraform 将状态保存在本地 `terraform.tfstate` 文件中：

```bash
# 查看状态文件
cat terraform.tfstate

# 查看状态（格式化输出）
terraform show

# 列出资源
terraform state list
```

**注意**：
- ❌ 不要将 `terraform.tfstate` 提交到 Git
- ❌ 不要手动编辑状态文件
- ❌ 不要在团队中共享本地状态

### 远程状态

生产环境应使用远程状态后端：

#### AWS S3 + DynamoDB

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "aws/blue-green/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"

    # 可选: 启用版本控制
    # versioning = true
  }
}
```

创建 S3 和 DynamoDB 资源：

```bash
# 创建 S3 存储桶
aws s3api create-bucket \
  --bucket my-terraform-state \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# 启用版本控制
aws s3api put-bucket-versioning \
  --bucket my-terraform-state \
  --versioning-configuration Status=Enabled

# 启用加密
aws s3api put-bucket-encryption \
  --bucket my-terraform-state \
  --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# 创建 DynamoDB 锁表
aws dynamodb create-table \
  --table-name terraform-state-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

#### Terraform Cloud

```hcl
terraform {
  cloud {
    organization = "my-org"

    workspaces {
      name = "my-workspace"
    }
  }
}
```

### 状态锁定

状态锁定防止并发操作导致的状态损坏：

```bash
# 如果操作被中断，可能需要手动解锁
terraform force-unlock <lock-id>

# 查看锁定信息
aws dynamodb get-item \
  --table-name terraform-state-locks \
  --key '{"LockID": {"S": "my-terraform-state/aws/blue-green/terraform.tfstate"}}'
```

## 变量和输出

### 变量类型

#### 基本类型

```hcl
# String
variable "region" {
  type    = string
  default = "us-west-2"
}

# Number
variable "instance_count" {
  type    = number
  default = 2
}

# Bool
variable "enable_monitoring" {
  type    = bool
  default = true
}
```

#### 复杂类型

```hcl
# List
variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

# Map
variable "instance_types" {
  type = map(string)
  default = {
    dev  = "t3.micro"
    prod = "t3.large"
  }
}

# Object
variable "database_config" {
  type = object({
    engine         = string
    engine_version = string
    instance_class = string
    allocated_storage = number
  })
  default = {
    engine         = "postgres"
    engine_version = "15.8"
    instance_class = "db.t3.micro"
    allocated_storage = 20
  }
}

# Set
variable "allowed_cidr_blocks" {
  type    = set(string)
  default = ["10.0.0.0/8", "172.16.0.0/12"]
}

# Tuple
variable "network_config" {
  type    = tuple([string, number, bool])
  default = ["10.0.0.0/16", 2, true]
}
```

### 变量验证

```hcl
variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_count" {
  type        = number
  description = "Number of instances"

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}
```

### 变量赋值优先级

Terraform 按以下顺序读取变量（后面的覆盖前面的）：

1. 环境变量 `TF_VAR_<name>`
2. `terraform.tfvars` 文件
3. `terraform.tfvars.json` 文件
4. `*.auto.tfvars` 或 `*.auto.tfvars.json` 文件
5. `-var` 和 `-var-file` 命令行参数

```bash
# 方式 1: 环境变量
export TF_VAR_instance_type="t3.large"

# 方式 2: 默认变量文件
echo 'instance_type = "t3.large"' > terraform.tfvars

# 方式 3: 自定义变量文件
terraform apply -var-file="production.tfvars"

# 方式 4: 命令行参数
terraform apply -var="instance_type=t3.large"
```

### 敏感变量

```hcl
variable "database_password" {
  type      = string
  sensitive = true
  description = "Database master password"
}

output "password" {
  value     = var.database_password
  sensitive = true  # 不会在控制台显示
}
```

### 输出值

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "instance_ips" {
  description = "Public IPs of all instances"
  value       = aws_instance.web[*].public_ip
}

output "connection_string" {
  description = "Database connection string"
  value       = "postgresql://${aws_db_instance.main.username}@${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
  sensitive   = true
}
```

查看输出：

```bash
# 所有输出
terraform output

# 特定输出
terraform output vpc_id

# JSON 格式
terraform output -json

# 原始值（用于脚本）
ALB_DNS=$(terraform output -raw alb_dns_name)
```

## 模块化开发

### 创建模块

模块结构：

```
modules/vpc/
├── main.tf       # 主配置
├── variables.tf  # 输入变量
├── outputs.tf    # 输出值
└── README.md     # 模块文档
```

示例模块（`modules/vpc/main.tf`）：

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

resource "aws_internet_gateway" "this" {
  count  = var.create_igw ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-igw"
    }
  )
}
```

模块变量（`modules/vpc/variables.tf`）：

```hcl
variable "name" {
  description = "Name of the VPC"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "create_igw" {
  description = "Create an Internet Gateway"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

模块输出（`modules/vpc/outputs.tf`）：

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = try(aws_internet_gateway.this[0].id, "")
}
```

### 使用模块

```hcl
module "vpc" {
  source = "./modules/vpc"

  name                 = "production-vpc"
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  create_igw           = true

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

# 引用模块输出
resource "aws_subnet" "public" {
  vpc_id     = module.vpc.vpc_id
  cidr_block = "10.0.1.0/24"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

### 使用公共模块

```hcl
# 从 Terraform Registry
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# 从 Git 仓库
module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.0.0"
  # ...
}
```

## 安全实践

### 1. 凭证管理

```hcl
# ❌ 不要硬编码凭证
provider "aws" {
  access_key = "AKIAIOSFODNN7EXAMPLE"  # 危险！
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # 危险！
}

# ✅ 使用环境变量
provider "aws" {
  region = "us-west-2"
  # AWS SDK 自动从环境变量或 ~/.aws/credentials 读取
}

# ✅ 使用 IAM 角色（EC2/ECS）
provider "aws" {
  region = "us-west-2"
  # 自动使用实例的 IAM 角色
}
```

### 2. 敏感数据保护

```hcl
# 使用 AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "rds-password"
}

resource "aws_db_instance" "main" {
  # ...
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
}

# 使用 random provider 生成密码
resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "rds-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}
```

### 3. 状态文件安全

```hcl
# 启用 S3 加密
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true              # ✅ 启用加密
    kms_key_id     = "arn:aws:kms:..."  # 可选: 使用 KMS
    dynamodb_table = "terraform-locks"
  }
}
```

### 4. .gitignore 配置

```gitignore
# .gitignore
**/.terraform/*
*.tfstate
*.tfstate.*
terraform.tfvars
*.auto.tfvars
crash.log
crash.*.log
*.tfvars
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

### 5. 安全扫描

使用 tfsec 扫描安全问题：

```bash
# 安装 tfsec
brew install tfsec

# 扫描当前目录
tfsec .

# 输出 JSON 格式
tfsec . --format json

# 忽略特定规则
tfsec . --exclude-rule aws-s3-enable-versioning
```

## 故障排除

### 常见错误和解决方案

#### 1. Provider 插件下载失败

```bash
Error: Failed to download provider

# 解决方案 1: 清理并重新初始化
rm -rf .terraform .terraform.lock.hcl
terraform init

# 解决方案 2: 使用镜像源（中国大陆）
export TF_CLI_CONFIG_FILE=~/.terraformrc
cat > ~/.terraformrc <<EOF
provider_installation {
  network_mirror {
    url = "https://terraform-mirror.example.com/"
  }
}
EOF
terraform init
```

#### 2. 状态锁定

```bash
Error: Error acquiring the state lock

# 查看锁定信息
terraform force-unlock <lock-id>

# 注意: 只有在确认没有其他操作时才使用
```

#### 3. 资源已存在

```bash
Error: resource already exists

# 解决方案: 导入现有资源
terraform import aws_instance.web i-1234567890abcdef0

# 或删除状态中的资源（不删除实际资源）
terraform state rm aws_instance.web
```

#### 4. 依赖冲突

```bash
Error: Cycle: aws_security_group.alb, aws_security_group.ec2

# 解决方案: 使用 depends_on 明确依赖
resource "aws_security_group" "alb" {
  # ...
}

resource "aws_security_group" "ec2" {
  # ...
  depends_on = [aws_security_group.alb]
}
```

### 调试技巧

```bash
# 启用详细日志
export TF_LOG=DEBUG
terraform apply

# 只显示特定组件日志
export TF_LOG_PROVIDER=TRACE
export TF_LOG_CORE=DEBUG

# 将日志保存到文件
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
terraform apply

# 禁用日志
unset TF_LOG TF_LOG_PATH TF_LOG_PROVIDER TF_LOG_CORE
```

## 性能优化

### 并行执行

```bash
# 增加并行度（默认 10）
terraform apply -parallelism=20

# 减少并行度（降低 API 调用频率）
terraform apply -parallelism=5
```

### 目标资源操作

```bash
# 只应用特定资源
terraform apply -target=aws_instance.web

# 只销毁特定资源
terraform destroy -target=aws_instance.web

# 多个目标
terraform apply \
  -target=aws_instance.web \
  -target=aws_security_group.web
```

### 刷新优化

```bash
# 跳过刷新（如果状态已同步）
terraform plan -refresh=false

# 只刷新不应用
terraform refresh
```

### 使用 terraform.lock.hcl

锁定文件确保团队使用相同的 provider 版本：

```bash
# 生成锁定文件
terraform init

# 更新锁定文件
terraform init -upgrade

# 提交锁定文件到 Git
git add .terraform.lock.hcl
git commit -m "chore: update provider versions"
```

## 本项目特定配置

### 项目结构

```
Terraform-Cloud/
├── AWS/
│   ├── blue-green/          # 蓝绿部署模块
│   │   ├── terraform.tf     # Provider 和 backend 配置
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── shared.tf        # 共享资源
│   │   ├── blue.tf
│   │   └── green.tf
│   └── rds/                 # RDS 模块
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

### 使用示例

#### 部署蓝绿环境

```bash
cd AWS/blue-green/

# 初始化
terraform init

# 创建变量文件
cp terraform.tfvars.example terraform.tfvars

# 编辑变量
vim terraform.tfvars

# 部署
terraform apply

# 获取 ALB DNS
terraform output alb_dns_name

# 测试
curl http://$(terraform output -raw alb_dns_name)
```

#### 部署 RDS 数据库

```bash
cd AWS/rds/

# 初始化
terraform init

# 部署（免费套餐配置）
terraform apply

# 获取连接信息
terraform output rds_instance_endpoint

# 获取密码（从 Secrets Manager）
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw secrets_manager_secret_id) \
  --query SecretString --output text | jq .
```

## 进阶主题

### Dynamic Blocks

```hcl
variable "ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
}

resource "aws_security_group" "example" {
  name = "example"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

### Conditional Resources

```hcl
resource "aws_instance" "web" {
  count = var.create_instance ? 1 : 0

  ami           = var.ami_id
  instance_type = var.instance_type
}

resource "aws_eip" "web" {
  count    = var.create_instance ? 1 : 0
  instance = aws_instance.web[0].id
}
```

### For Expressions

```hcl
locals {
  instance_ips = [for i in aws_instance.web : i.private_ip]

  instance_map = {
    for i in aws_instance.web :
    i.id => i.private_ip
  }

  upper_names = [for name in var.names : upper(name)]
}
```

## 资源和参考

### 官方文档

- **Terraform 官网**: https://www.terraform.io/
- **Terraform 文档**: https://www.terraform.io/docs
- **Terraform Registry**: https://registry.terraform.io/
- **AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

### 学习资源

- **HashiCorp Learn**: https://learn.hashicorp.com/terraform
- **Terraform Best Practices**: https://www.terraform-best-practices.com/
- **Awesome Terraform**: https://github.com/shuaibiyy/awesome-terraform

### 工具

- **tfsec**: 安全扫描工具
- **terraform-docs**: 自动生成文档
- **terrascan**: 合规性检查
- **checkov**: 安全和合规扫描
- **infracost**: 成本估算

## 获取帮助

- 查看模块的 README 文档
- 在项目 Issues 中搜索问题
- 阅读 Terraform 官方文档
- 访问 Terraform 社区论坛

---

**最后更新**: 2025-12-31
**维护者**: iKelvinLab
**Terraform 版本**: >= 1.0
