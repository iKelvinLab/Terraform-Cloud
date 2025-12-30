# Terraform Cloud 基础设施即代码 (IaC)

使用 Terraform 管理多云平台的基础设施资源，实现声明式配置、版本控制和自动化部署。

## 📋 项目概述

本项目提供了一套完整的 Terraform 配置，用于管理和部署云基础设施，支持多云平台和多环境部署策略。

### 核心特性

- ✅ **多云支持** - AWS、阿里云、腾讯云等主流云平台
- ✅ **蓝绿部署** - 零停机更新，支持灰度发布和快速回滚
- ✅ **模块化设计** - 可复用的 Terraform 模块，便于维护和扩展
- ✅ **安全最佳实践** - 敏感信息保护，状态文件加密，最小权限原则
- ✅ **完整文档** - 详细的部署指南、架构说明和故障排除手册

## 🗂️ 项目结构

```
Terraform-Cloud/
├── README.md                    # 项目总览（本文件）
├── .gitignore                   # Git 忽略规则（182 行，覆盖所有子目录）
├── .claude/                     # Claude Code 配置目录
│
├── AWS/                         # AWS 云平台配置 ⭐
│   ├── README.md                # AWS 项目文档
│   ├── main.tf                  # Provider 和 Terraform 配置
│   ├── variables.tf             # 变量定义
│   ├── outputs.tf               # 输出定义
│   ├── terraform.tfvars.example # 变量配置示例
│   │
│   ├── shared.tf                # 共享资源（VPC, ALB, TG, Listener）
│   ├── blue.tf                  # Blue 环境配置
│   ├── green.tf                 # Green 环境配置
│   │
│   ├── init-script.sh           # EC2 实例初始化脚本
│   │
│   ├── dependency-graph.dot          # 依赖关系图（销毁视角）
│   ├── creation-flowchart.dot        # 创建流程图（零中断设计）
│   │
│   ├── BLUE_GREEN_DEPLOYMENT_GUIDE.md    # 蓝绿部署完整指南
│   ├── ZERO_DOWNTIME_DEPLOYMENT.md       # 零中断创建详解
│   ├── IMPLEMENTATION_SUMMARY.md         # 实施总结
│   └── VERIFICATION_CHECKLIST.md         # 验证清单
│
└── (其他云平台目录，待添加)
    ├── AliCloud/                # 阿里云配置
    ├── TencentCloud/            # 腾讯云配置
    └── GCP/                     # Google Cloud 配置
```

## 🚀 快速开始

### 前置要求

1. **安装工具**
   ```bash
   # Terraform (>= 1.0)
   brew install terraform

   # AWS CLI (如果使用 AWS)
   brew install awscli

   # Graphviz (可选，用于生成依赖图)
   brew install graphviz
   ```

2. **配置凭证**
   ```bash
   # AWS 凭证配置
   aws configure
   # 输入 Access Key ID、Secret Access Key、Region
   ```

3. **克隆项目**
   ```bash
   git clone <repository-url>
   cd Terraform-Cloud
   ```

### 部署流程

#### AWS 蓝绿部署示例

```bash
# 1. 进入 AWS 目录
cd AWS/

# 2. 复制变量配置文件
cp terraform.tfvars.example terraform.tfvars

# 3. 编辑变量（根据实际需求）
vim terraform.tfvars

# 4. 初始化 Terraform
terraform init

# 5. 查看执行计划
terraform plan

# 6. 应用配置（创建基础设施）
terraform apply

# 7. 获取输出信息
terraform output

# 8. 访问应用
curl http://$(terraform output -raw alb_dns_name)

# 9. 销毁基础设施（测试完成后）
terraform destroy
```

完整部署指南请参阅：[AWS/README.md](AWS/README.md)

## 📚 文档导航

### 总体文档

- [项目概述](README.md) - 本文件
- [.gitignore 配置说明](#gitignore-配置)
- [贡献指南](#贡献指南)

### AWS 平台文档

进入 `AWS/` 目录查看详细文档：

1. **入门文档**
   - [AWS/README.md](AWS/README.md) - AWS 项目快速开始

2. **部署指南**
   - [蓝绿部署完整指南](AWS/BLUE_GREEN_DEPLOYMENT_GUIDE.md) - 1000+ 行详细说明
   - [零中断部署设计](AWS/ZERO_DOWNTIME_DEPLOYMENT.md) - 零停机创建方案

3. **实施文档**
   - [实施总结](AWS/IMPLEMENTATION_SUMMARY.md) - 配置变更和最佳实践
   - [验证清单](AWS/VERIFICATION_CHECKLIST.md) - 部署验证步骤

4. **可视化图表**
   - `dependency-graph.dot` - 资源依赖关系图
   - `creation-flowchart.dot` - 创建流程图

   生成图片：
   ```bash
   cd AWS/
   dot -Tpng dependency-graph.dot -o dependency-graph.png
   dot -Tpng creation-flowchart.dot -o creation-flowchart.png
   ```

## 🏗️ 架构设计

### AWS 蓝绿部署架构

```
                      互联网
                        ↓
              Application Load Balancer
                        ↓
                  HTTP Listener
                        ↓
              Listener Rule (Canary)
                ↓              ↓
    Blue Target Group    Green Target Group
         (100%)               (0%)
            ↓                    ↓
    Blue ASG (2 实例)    Green ASG (0-2 实例)
```

**核心特性**：
- ✅ 零停机部署（实例就绪后再接入流量）
- ✅ 灰度发布（流量权重可调：100/0 → 90/10 → 50/50 → 0/100）
- ✅ 快速回滚（调整权重即可）
- ✅ 2-3 分钟创建，2-3 分钟销毁

详细架构说明：[AWS/BLUE_GREEN_DEPLOYMENT_GUIDE.md](AWS/BLUE_GREEN_DEPLOYMENT_GUIDE.md)

## ⚙️ 配置管理

### .gitignore 配置

项目根目录的 `.gitignore` 包含 **182 行**规则，覆盖：

- **Terraform 文件** - `.terraform/`, `*.tfstate`, `*.tfvars`
- **敏感信息** - `*.pem`, `.env`, `credentials`
- **IDE 配置** - `.vscode/`, `.idea/`
- **系统文件** - `.DS_Store`, `Thumbs.db`
- **多语言** - Python, Node.js, Go 等

**关键特性**：
- 使用 `**/` 前缀，在所有子目录中生效
- 保护敏感信息不被提交
- 支持多云平台子目录

查看详细说明：
```bash
head -50 .gitignore  # 查看前 50 行和注释
```

### 变量配置

每个云平台目录包含：

- `variables.tf` - 变量定义和验证规则
- `terraform.tfvars.example` - 配置示例模板
- `terraform.tfvars` - 实际配置（本地使用，不提交）

**安全提示**：
- ❌ 绝不提交 `terraform.tfvars`（可能包含密码）
- ❌ 绝不提交 `*.tfstate`（包含所有资源信息）
- ✅ 使用远程状态后端（S3 + DynamoDB）

## 🔒 安全最佳实践

### 1. 凭证管理

```bash
# ✅ 推荐：使用环境变量
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# ✅ 推荐：使用 AWS CLI 配置
aws configure

# ❌ 避免：硬编码在 .tf 文件中
# provider "aws" {
#   access_key = "AKIAIOSFODNN7EXAMPLE"  # ❌ 危险！
# }
```

### 2. 状态文件管理

```hcl
# ✅ 推荐：使用远程后端
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "aws/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 3. 资源标签

```hcl
# ✅ 统一的资源标签
locals {
  common_tags = {
    Project     = "Terraform-Cloud"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "your-team"
  }
}
```

### 4. 最小权限原则

使用 IAM 策略限制 Terraform 的权限，只授予必要的操作权限。

## 🛠️ 常用命令

### Terraform 基础命令

```bash
# 初始化（下载 provider 插件）
terraform init

# 格式化代码
terraform fmt -recursive

# 验证配置
terraform validate

# 查看执行计划
terraform plan

# 应用变更
terraform apply

# 销毁资源
terraform destroy

# 查看状态
terraform show

# 列出资源
terraform state list

# 刷新状态
terraform refresh
```

### 高级操作

```bash
# 导入现有资源
terraform import aws_instance.example i-1234567890abcdef0

# 目标资源操作
terraform apply -target=aws_instance.example
terraform destroy -target=aws_instance.example

# 使用变量文件
terraform apply -var-file="prod.tfvars"

# 自动批准
terraform apply -auto-approve

# 生成依赖图
terraform graph | dot -Tpng > graph.png
```

### 故障排除

```bash
# 启用详细日志
export TF_LOG=DEBUG
terraform apply

# 查看 provider 调试信息
export TF_LOG_PROVIDER=TRACE
terraform plan

# 清理缓存重新初始化
rm -rf .terraform
terraform init
```

## 🧪 测试和验证

### 1. 配置验证

```bash
# 验证语法
terraform validate

# 检查格式
terraform fmt -check -recursive

# 安全扫描（使用 tfsec）
brew install tfsec
tfsec .

# 成本估算（使用 infracost）
brew install infracost
infracost breakdown --path .
```

### 2. 部署测试

```bash
# 开发环境测试
terraform workspace new dev
terraform apply -var-file="dev.tfvars"

# 验证资源创建
terraform show

# 销毁测试环境
terraform destroy -auto-approve
```

### 3. 持续集成

todo: 配置 Jenkins 持续集成 / 自动部署

## 📊 监控和日志

### AWS CloudWatch

- **日志** - EC2 实例日志自动收集到 CloudWatch Logs
- **指标** - ALB、ASG、EC2 的核心指标
- **告警** - 根据阈值配置告警规则

### Terraform 输出

```bash
# 获取所有输出
terraform output

# 获取特定输出
terraform output alb_dns_name

# JSON 格式输出
terraform output -json
```

## 🤝 贡献指南

### 提交规范

使用语义化提交消息：

```
feat: 添加新功能
fix: 修复 bug
docs: 文档更新
style: 代码格式调整
refactor: 代码重构
test: 测试相关
chore: 构建/工具链相关
```

示例：
```bash
git commit -m "feat(aws): add RDS database module"
git commit -m "fix(aws): resolve ASG destroy timeout issue"
git commit -m "docs: update AWS deployment guide"
```

### 开发流程

1. 创建功能分支
   ```bash
   git checkout -b feature/add-rds-module
   ```

2. 开发和测试
   ```bash
   terraform fmt
   terraform validate
   terraform plan
   ```

3. 提交变更
   ```bash
   git add .
   git commit -m "feat(aws): add RDS module with multi-AZ support"
   ```

4. 推送并创建 Pull Request
   ```bash
   git push origin feature/add-rds-module
   ```

### 代码审查清单

- [ ] 代码格式化（`terraform fmt`）
- [ ] 配置验证（`terraform validate`）
- [ ] 变量有默认值或验证规则
- [ ] 敏感信息未硬编码
- [ ] 添加了适当的注释
- [ ] 更新了相关文档
- [ ] 测试了创建和销毁流程

## 📞 支持和反馈

### 问题报告

在 GitHub Issues 中报告问题时，请包含：

- Terraform 版本（`terraform version`）
- Provider 版本
- 错误日志
- 最小复现步骤

### 获取帮助

- **文档** - 查看各子目录的 README 和指南
- **示例** - 参考 `terraform.tfvars.example`
- **社区** - Terraform 官方论坛和 Discord



## 🙏 致谢

- [Terraform](https://www.terraform.io/) - HashiCorp 提供的 IaC 工具
- [AWS](https://aws.amazon.com/) - 云服务平台

---

**最后更新**: 2024-12-30
**维护者**: iKelvinLab
**版本**: 1.0.0
