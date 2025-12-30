# Terraform-Cloud 技术文档

> 版本: 1.0.0
> 最后更新: 2025-12-30
> 维护者: iKelvinLab

## 1. 项目概述

### 1.1 项目简介

Terraform-Cloud 是一个基于 Terraform 的多云基础设施即代码(IaC)项目,用于自动化管理和部署云基础设施。当前版本实现了 AWS 平台的蓝绿部署架构,支持零停机更新和灰度发布。

### 1.2 核心功能

- **多云支持**: 设计支持 AWS、阿里云、腾讯云等主流云平台
- **蓝绿部署**: 实现零停机更新,支持流量权重调整和快速回滚
- **模块化设计**: 资源配置模块化,便于复用和维护
- **安全最佳实践**: 敏感信息保护、状态文件加密、最小权限原则

### 1.3 项目特点

- 声明式配置管理
- 版本控制和审计
- 自动化部署流程
- 详细的文档和可视化依赖图

## 2. 项目结构

### 2.1 目录结构

```
Terraform-Cloud/
├── README.md                          # 项目总览文档
├── TECHNICAL_DOCUMENTATION.md         # 技术文档(本文件)
├── .gitignore                         # Git 忽略规则(182行,覆盖所有子目录)
│
├── AWS/                               # AWS 平台配置
│   ├── terraform.tf                   # Terraform 和 Provider 配置
│   ├── variables.tf                   # 变量定义(105行)
│   ├── outputs.tf                     # 输出定义
│   ├── shared.tf                      # 共享资源(VPC, ALB, TG, Listener)
│   ├── blue.tf                        # Blue 环境配置
│   ├── green.tf                       # Green 环境配置
│   ├── init-script.sh                 # EC2 实例初始化脚本
│   │
│   ├── README.md                      # AWS 快速开始指南
│   ├── BLUE_GREEN_DEPLOYMENT_GUIDE.md # 蓝绿部署完整指南(1000+行)
│   ├── ZERO_DOWNTIME_DEPLOYMENT.md    # 零中断部署设计说明
│   ├── IMPLEMENTATION_SUMMARY.md      # 实施总结
│   ├── VERIFICATION_CHECKLIST.md      # 验证清单
│   ├── QUICK_REFERENCE.md             # 快速参考
│   ├── DEPENDENCY_SOLUTION.md         # 依赖关系解决方案
│   │
│   ├── dependency-graph.dot           # 资源依赖图(DOT格式)
│   └── creation-flowchart.dot         # 创建流程图(DOT格式)
│
└── (其他云平台目录,待扩展)
    ├── AliCloud/                      # 阿里云配置
    ├── TencentCloud/                  # 腾讯云配置
    └── GCP/                           # Google Cloud 配置
```

### 2.2 核心文件说明

| 文件路径 | 功能说明 |
|---------|---------|
| `AWS/terraform.tf` | Terraform 版本要求和 AWS Provider 配置 |
| `AWS/variables.tf` | 定义所有可配置变量(region, instance_type 等) |
| `AWS/outputs.tf` | 定义输出值(ALB DNS, ASG名称等) |
| `AWS/shared.tf` | 共享基础设施(VPC, Subnets, Security Groups, ALB, Target Groups) |
| `AWS/blue.tf` | Blue 环境资源(Launch Template, Auto Scaling Group) |
| `AWS/green.tf` | Green 环境资源(Launch Template, Auto Scaling Group) |
| `AWS/init-script.sh` | EC2 实例启动脚本(安装Nginx, 配置网页) |

### 2.3 文档文件说明

| 文档文件 | 内容概要 |
|---------|---------|
| `README.md` | 项目总览、快速开始、命令参考 |
| `AWS/README.md` | AWS 平台快速部署指南(835行) |
| `AWS/BLUE_GREEN_DEPLOYMENT_GUIDE.md` | 蓝绿部署详细说明(创建/销毁流程、依赖关系、故障排除) |
| `AWS/ZERO_DOWNTIME_DEPLOYMENT.md` | 零停机部署的实现原理和配置 |
| `AWS/VERIFICATION_CHECKLIST.md` | 部署验证步骤和问题排查 |

## 3. 使用方法

### 3.1 前置要求

**工具安装**:
- Terraform >= 1.5.0
- AWS CLI (配置凭证)
- Graphviz (可选,用于生成依赖图)

**AWS 凭证配置**:
```bash
# 方式1: 使用 AWS CLI
aws configure

# 方式2: 使用环境变量
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

**IAM 权限要求**:
- EC2 (VPC, Subnets, Security Groups, Instances)
- ELB/ALB (Load Balancer, Target Groups, Listeners)
- Auto Scaling
- IAM (GetUser, GetRole)

### 3.2 快速部署

#### 步骤 1: 初始化项目

```bash
# 进入 AWS 目录
cd AWS/

# 初始化 Terraform
terraform init

# 验证配置
terraform validate
```

#### 步骤 2: 配置变量(可选)

```bash
# 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 编辑配置
vim terraform.tfvars

# 主要变量:
# - aws_region: "us-west-2"
# - instance_type: "t3.micro"
# - blue_instance_count: 2
# - enable_green_env: false
```

#### 步骤 3: 部署基础设施

```bash
# 查看执行计划
terraform plan

# 应用配置(创建资源)
terraform apply
# 输入 'yes' 确认

# 预计耗时: 3-4 分钟
```

#### 步骤 4: 验证部署

```bash
# 获取 ALB DNS 名称
terraform output alb_dns_name

# 访问应用
curl http://$(terraform output -raw alb_dns_name)

# 预期: 返回蓝色主题网页(Blue 环境)
```

### 3.3 蓝绿切换

#### 部署 Green 环境

```bash
# 启用 Green 环境并创建实例
terraform apply \
  -var="enable_green_env=true" \
  -var="green_instance_count=2"
```

#### 灰度发布(流量权重调整)

```bash
# 阶段 1: 10% 流量到 Green
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=90" \
  -var="green_target_weight=10"

# 阶段 2: 50% 流量到 Green
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=50" \
  -var="green_target_weight=50"

# 阶段 3: 100% 流量到 Green
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=0" \
  -var="green_target_weight=100"
```

#### 快速回滚

```bash
# 如果 Green 出现问题,立即切回 Blue
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=100" \
  -var="green_target_weight=0"
```

### 3.4 资源清理

```bash
# 销毁所有资源
terraform destroy
# 输入 'yes' 确认

# 预计耗时: 2-3 分钟
```

### 3.5 常用命令

```bash
# 格式化代码
terraform fmt -recursive

# 查看当前状态
terraform show

# 列出所有资源
terraform state list

# 查看特定输出
terraform output alb_dns_name

# 刷新状态
terraform refresh

# 生成依赖图
terraform graph | dot -Tpng > graph.png
```

## 4. 技术栈说明

### 4.1 核心技术

**基础设施即代码(IaC)**:
- Terraform >= 1.5.0
- HashiCorp Configuration Language (HCL)

**云服务提供商**:
- AWS Provider >= 5.0

**版本控制**:
- Git
- GitHub (代码托管)

### 4.2 AWS 服务架构

#### 网络层

| 服务 | 数量 | 说明 |
|-----|------|------|
| VPC | 1 | 10.0.0.0/16 CIDR |
| Subnet | 2 | 跨 2 个可用区的公有子网 |
| Internet Gateway | 1 | 提供公网访问 |
| Route Table | 1 | 默认路由到 IGW |
| Security Group | 2 | ALB SG, EC2 SG |

#### 负载均衡层

| 服务 | 数量 | 说明 |
|-----|------|------|
| Application Load Balancer | 1 | 跨 2 个可用区 |
| Target Group | 2 | Blue TG, Green TG |
| HTTP Listener | 1 | Port 80 |
| Listener Rule | 0-1 | 加权转发规则(Canary) |

#### 计算层

| 服务 | 数量 | 说明 |
|-----|------|------|
| Launch Template | 2 | Blue LT, Green LT |
| Auto Scaling Group | 1-2 | Blue ASG, Green ASG |
| EC2 Instance | 2-4 | t3.micro 实例 |

### 4.3 部署架构图

```
                    互联网用户
                       ↓
        Application Load Balancer
              (跨 2 个可用区)
                       ↓
              HTTP Listener (Port 80)
                       ↓
         Canary Listener Rule (加权转发)
                ↓              ↓
    Blue Target Group    Green Target Group
      (初始 100%)          (初始 0%)
            ↓                    ↓
    Blue ASG (2 实例)    Green ASG (0-2 实例)
            ↓                    ↓
            └────────────────────┘
                       ↓
        VPC Public Subnets (跨 2 个可用区)
```

### 4.4 关键技术特性

#### 零停机部署

通过以下配置实现:
```hcl
resource "aws_autoscaling_group" "blue" {
  min_elb_capacity          = var.blue_instance_count
  wait_for_elb_capacity     = var.blue_instance_count
  wait_for_capacity_timeout = "10m"
}
```

**工作原理**:
1. Terraform 等待实例在 Target Group 中状态为 "healthy"
2. HTTP Listener 在实例就绪后才创建
3. 避免 503 错误和流量丢失

#### 快速销毁

通过以下配置优化:
```hcl
# Target Group 注销延迟
deregistration_delay = 30  # 从 300s 降到 30s

# ASG 强制删除
force_delete = true

# 销毁超时
timeouts {
  delete = "15m"
}
```

**效果**: 销毁时间从 5+ 分钟降到 2-3 分钟

#### 依赖关系管理

```hcl
resource "aws_lb_listener" "http" {
  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green,
    aws_autoscaling_group.blue  # 关键: 等待实例就绪
  ]
}
```

**作用**:
- 创建时: Listener 在实例健康后才创建
- 销毁时: ASG 先销毁, Listener 后销毁

### 4.5 配置变量

#### 核心变量

| 变量名 | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `region` | string | "us-west-2" | AWS 区域 |
| `instance_type` | string | "t3.micro" | EC2 实例类型 |
| `vpc_cidr_block` | string | "10.0.0.0/16" | VPC CIDR |
| `public_subnet_count` | number | 2 | 公有子网数量 |

#### Blue/Green 变量

| 变量名 | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `enable_blue_env` | bool | true | 启用 Blue 环境 |
| `blue_instance_count` | number | 2 | Blue 实例数量 |
| `enable_green_env` | bool | false | 启用 Green 环境 |
| `green_instance_count` | number | 0 | Green 实例数量 |
| `blue_target_weight` | number | 100 | Blue 流量权重 (0-100) |
| `green_target_weight` | number | 0 | Green 流量权重 (0-100) |

### 4.6 安全配置

#### Security Group 规则

**ALB Security Group**:
- 入站: 允许来自互联网的 HTTP (Port 80)
- 出站: 允许到 EC2 Security Group 的 HTTP

**EC2 Security Group**:
- 入站: 仅允许来自 ALB Security Group 的 HTTP
- 出站: 允许所有流量(安装软件包)

#### 状态文件管理

**当前**: 本地状态文件(`.gitignore` 已排除)

**生产建议**: 使用远程后端
```hcl
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

### 4.7 成本估算

**基础配置** (us-west-2 区域):
- 2 × t3.micro EC2: ~$0.0208/小时 = ~$15/月
- 1 × Application Load Balancer: ~$0.0225/小时 = ~$20/月
- 数据传输: 按实际流量计费

**总计**: ~$35/月 (测试环境, 低流量)

**注意**:
- 使用 AWS 免费套餐可减少成本
- 不使用时建议 `terraform destroy` 销毁资源

## 5. 最佳实践

### 5.1 安全建议

1. **凭证管理**
   - 使用环境变量或 AWS CLI 配置
   - 禁止硬编码密钥在代码中
   - 为 Terraform 创建专用 IAM 用户(最小权限)

2. **状态文件保护**
   - 使用远程后端(S3 + DynamoDB)
   - 启用状态文件加密
   - 绝不提交 `*.tfstate` 到 Git

3. **网络安全**
   - Security Group 遵循最小权限原则
   - 生产环境启用 HTTPS (配置 ACM 证书)
   - 考虑添加 WAF 防护

### 5.2 运维建议

1. **变更管理**
   - 始终先执行 `terraform plan` 检查变更
   - 在非生产环境测试后再应用到生产
   - 使用 Git 分支管理不同环境配置

2. **监控和告警**
   - 配置 CloudWatch 告警(实例健康、ALB 4xx/5xx 错误)
   - 定期检查 Target Group 健康状态
   - 记录所有部署操作

3. **备份和恢复**
   - 定期备份 Terraform 状态文件
   - 保存重要配置的版本历史
   - 测试灾难恢复流程

### 5.3 开发建议

1. **代码规范**
   - 使用 `terraform fmt` 格式化代码
   - 使用 `terraform validate` 验证配置
   - 为变量添加描述和验证规则

2. **文档维护**
   - 更新代码时同步更新文档
   - 记录重要的架构决策
   - 提供完整的使用示例

3. **测试策略**
   - 在开发环境测试完整的创建/销毁流程
   - 测试蓝绿切换和回滚场景
   - 验证安全组规则和网络连接

## 6. 故障排除

### 6.1 常见问题

#### 问题 1: ASG 销毁卡住

**症状**:
```
aws_autoscaling_group.blue: Still destroying... [10m0s elapsed]
```

**原因**: 实例注销延迟时间过长

**解决方案**:
```bash
# 手动缩容 ASG
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <ASG-NAME> \
  --min-size 0 --max-size 0 --desired-capacity 0

# 等待实例终止后重试
terraform destroy
```

#### 问题 2: 实例健康检查失败

**症状**: Target Group 中实例状态为 "unhealthy"

**排查步骤**:
1. 检查 Security Group 规则
2. 登录实例检查 Nginx 状态: `systemctl status nginx`
3. 查看健康检查路径配置

**解决方案**: 确保 EC2 Security Group 允许来自 ALB 的流量

#### 问题 3: Provider 下载失败

**症状**:
```
Error: Failed to download provider
```

**解决方案**:
```bash
# 清理缓存
rm -rf .terraform .terraform.lock.hcl

# 重新初始化
terraform init
```

### 6.2 调试技巧

**启用详细日志**:
```bash
export TF_LOG=DEBUG
terraform plan
```

**查看 AWS 资源状态**:
```bash
# 查看 ALB 状态
aws elbv2 describe-load-balancers

# 查看 Target Group 健康
aws elbv2 describe-target-health \
  --target-group-arn <TG-ARN>

# 查看 ASG 实例
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <ASG-NAME>
```

## 7. 相关资源

### 7.1 项目文档

- [项目概述 README](../README.md)
- [AWS 快速开始指南](AWS/README.md)
- [蓝绿部署完整指南](AWS/BLUE_GREEN_DEPLOYMENT_GUIDE.md)
- [零中断部署设计](AWS/ZERO_DOWNTIME_DEPLOYMENT.md)
- [验证清单](AWS/VERIFICATION_CHECKLIST.md)

### 7.2 官方文档

- [Terraform 官方文档](https://www.terraform.io/docs)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [AWS Auto Scaling](https://docs.aws.amazon.com/autoscaling/)
- [蓝绿部署策略白皮书](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/)

### 7.3 工具和插件

- [tfsec](https://github.com/aquasecurity/tfsec) - Terraform 安全扫描
- [infracost](https://www.infracost.io/) - 成本估算工具
- [terraform-docs](https://terraform-docs.io/) - 自动生成文档
- [Graphviz](https://graphviz.org/) - 依赖图可视化

## 8. 更新日志

### v1.0.0 (2025-12-30)

**初始版本特性**:
- AWS 蓝绿部署架构实现
- 零停机部署配置
- 灰度发布和快速回滚
- 完整的文档体系
- 依赖关系图和流程图

**AWS 资源配置**:
- VPC 和网络基础设施
- Application Load Balancer
- Auto Scaling Groups (Blue/Green)
- Target Groups 和 Listener 规则

**文档系统**:
- 5 个详细的 Markdown 文档
- 2 个可视化流程图 (DOT 格式)
- 182 行 .gitignore 规则

---

**维护者**: iKelvinLab
