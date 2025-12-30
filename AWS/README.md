# AWS 蓝绿部署 Terraform 项目

使用 Terraform 在 AWS 上实现零停机的蓝绿部署架构，支持灰度发布和快速回滚。

## 📋 项目概述

本项目提供了一套完整的 AWS 基础设施即代码（IaC）配置，实现了基于 Application Load Balancer 的蓝绿部署策略。

### 核心特性

- ✅ **零停机部署** - 实例就绪后再接入流量，避免 503 错误
- ✅ **灰度发布** - 支持流量权重调整（0-100%）
- ✅ **快速回滚** - 调整 Listener Rule 权重即可秒级回滚
- ✅ **高可用架构** - 跨可用区部署，自动故障转移
- ✅ **完整依赖管理** - 优化的创建和销毁顺序，2-3 分钟完成

### 部署架构

```
互联网用户
    ↓
Application Load Balancer (跨 2 个可用区)
    ↓
HTTP Listener (Port 80)
    ↓
Canary Listener Rule (加权转发)
    ↓                    ↓
Blue Target Group    Green Target Group
  (初始 100%)          (初始 0%)
    ↓                    ↓
Blue Auto Scaling Group  Green Auto Scaling Group
  (2 × t3.micro)         (0-2 × t3.micro)
    ↓                    ↓
跨 2 个可用区的 VPC Public Subnets
```

## 🚀 快速开始

### 前置要求

1. **工具安装**
   ```bash
   # Terraform >= 1.0
   terraform version

   # AWS CLI
   aws --version

   # 可选：Graphviz（生成依赖图）
   dot -V
   ```

2. **AWS 凭证配置**
   ```bash
   # 方式 1：使用 AWS CLI 配置
   aws configure
   # 输入：
   #   - AWS Access Key ID
   #   - AWS Secret Access Key
   #   - Default region name (us-west-2)
   #   - Default output format (json)

   # 方式 2：使用环境变量
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-west-2"

   # 验证配置
   aws sts get-caller-identity
   ```

3. **IAM 权限要求**

   确保您的 AWS 凭证具有以下权限：
   - EC2（VPC、Subnets、Security Groups、Instances）
   - ELB/ALB（Load Balancer、Target Groups、Listeners）
   - Auto Scaling
   - IAM（GetUser、GetRole）

### 部署步骤

#### 1. 初始化项目

```bash
# 进入 AWS 目录
cd /Users/jinxiaozhang/Project/Terraform-Cloud/AWS

# 初始化 Terraform（下载 AWS provider）
terraform init

# 预期输出：
# Initializing the backend...
# Initializing provider plugins...
# - Installing hashicorp/aws v6.27.0...
# Terraform has been successfully initialized!
```

#### 2. 配置变量（可选）

```bash
# 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 编辑配置文件
vim terraform.tfvars

# 可调整的主要变量：
# - aws_region: "us-west-2"
# - instance_type: "t3.micro"
# - blue_instance_count: 2
# - green_instance_count: 0
# - enable_green_env: false
```

**注意**：`terraform.tfvars` 会被 `.gitignore` 忽略，不会提交到 Git。

#### 3. 查看执行计划

```bash
# 生成并查看执行计划
terraform plan

# 预期输出：
# Plan: 20 to add, 0 to change, 0 to destroy.
#
# 将创建的资源：
#   - 1 VPC
#   - 2 Subnets (跨可用区)
#   - 1 Internet Gateway
#   - 1 Route Table
#   - 2 Security Groups
#   - 1 Application Load Balancer
#   - 2 Target Groups (Blue & Green)
#   - 1 HTTP Listener
#   - 2 Launch Templates
#   - 1 Blue Auto Scaling Group
#   - 相关资源关联
```

#### 4. 创建基础设施

```bash
# 应用配置（创建资源）
terraform apply

# 查看执行计划并确认
# 输入 "yes" 继续

# 预期耗时：约 3-4 分钟
#
# 创建流程：
# 1. VPC 和网络资源 (0-30s)
# 2. Security Groups (30-45s)
# 3. Application Load Balancer (45-90s，等待 active）
# 4. Target Groups (90-100s)
# 5. Launch Templates (100-110s)
# 6. Blue ASG + 等待实例健康 (110-180s) ⏳
# 7. HTTP Listener (180-185s，实例已就绪 ✅)
# 8. 验证完成 (185-200s)
```

#### 5. 验证部署

```bash
# 获取 ALB DNS 名称
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"

# 访问应用（应该立即返回 200 OK）
curl http://$ALB_DNS

# 预期输出：
# 显示蓝色主题的网页，包含：
#   - 环境：Blue
#   - 版本：1.0
#   - 实例 ID
#   - 可用区
#   - 私有 IP
```

#### 6. 查看所有输出

```bash
# 查看所有 Terraform 输出
terraform output

# 输出示例：
# alb_dns_name     = "app-alb-1234567890.us-west-2.elb.amazonaws.com"
# blue_asg_name    = "blue-asg-20241230..."
# vpc_id           = "vpc-0abc123..."
# public_subnet_ids = ["subnet-0def456...", "subnet-0ghi789..."]
```

### 蓝绿切换示例

#### 场景：从 Blue 切换到 Green

```bash
# 阶段 1：部署 Green 环境
terraform apply \
  -var="enable_green_env=true" \
  -var="green_instance_count=2"

# 等待 Green 实例就绪（约 2-3 分钟）

# 阶段 2：灰度测试（10% 流量到 Green）
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=90" \
  -var="green_target_weight=10"

# 观察监控指标...

# 阶段 3：增加 Green 流量（50%）
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=50" \
  -var="green_target_weight=50"

# 持续监控...

# 阶段 4：完全切换到 Green（100%）
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=0" \
  -var="green_target_weight=100"

# 验证 Green 稳定后，下线 Blue
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_instance_count=0" \
  -var="green_instance_count=2"
```

#### 快速回滚

```bash
# 如果 Green 出现问题，立即回滚到 Blue
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=100" \
  -var="green_target_weight=0"

# 流量立即切回 Blue（秒级回滚）
```

## 📁 文件说明

### Terraform 配置文件

```
AWS/
├── main.tf              # Provider 配置，Terraform 版本
├── variables.tf         # 变量定义（region, instance_type, 等）
├── outputs.tf           # 输出定义（ALB DNS, ASG 名称, 等）
├── terraform.tfvars.example  # 变量配置示例
│
├── shared.tf            # 共享资源
│   ├── VPC 和网络      # VPC, Subnets, IGW, Route Tables
│   ├── Security Groups  # ALB SG, EC2 SG
│   ├── Load Balancer    # Application Load Balancer
│   ├── Target Groups    # Blue & Green TG
│   └── Listeners        # HTTP Listener, Canary Rule
│
├── blue.tf              # Blue 环境
│   ├── Launch Template  # Blue 启动模板
│   └── Auto Scaling Group  # Blue ASG
│
├── green.tf             # Green 环境
│   ├── Launch Template  # Green 启动模板
│   └── Auto Scaling Group  # Green ASG
│
└── init-script.sh       # EC2 实例初始化脚本
    └── 安装 Nginx，配置网页
```

### 文档文件

```
├── README.md (本文件)    # 快速开始指南
│
├── BLUE_GREEN_DEPLOYMENT_GUIDE.md  # 完整部署指南（1000+ 行）
│   ├── 架构概述
│   ├── 创建流程详解（8 个阶段）
│   ├── 销毁流程详解（7 个阶段）
│   ├── 依赖关系说明
│   ├── 关键配置参数
│   ├── 故障排除指南
│   └── 最佳实践
│
├── ZERO_DOWNTIME_DEPLOYMENT.md  # 零中断创建详解
│   ├── 核心问题说明
│   ├── 配置参数详解
│   ├── 依赖关系图
│   ├── 创建流程对比
│   └── 验证步骤
│
├── IMPLEMENTATION_SUMMARY.md  # 实施总结
│   ├── 实施总结
│   ├── 修改详情
│   ├── 依赖关系变化
│   └── 测试验证指南
│
└── VERIFICATION_CHECKLIST.md  # 验证清单
    ├── 快速验证清单
    ├── 配置检查步骤
    └── 常见问题排查
```

### 可视化文件

```
├── dependency-graph.dot      # 依赖关系图（销毁视角）
└── creation-flowchart.dot    # 创建流程图（零中断设计）

生成图片：
$ dot -Tpng dependency-graph.dot -o dependency-graph.png
$ dot -Tpng creation-flowchart.dot -o creation-flowchart.png
```

## ⚙️ 配置说明

### 主要变量

在 `terraform.tfvars` 中配置：

```hcl
# AWS 区域
aws_region = "us-west-2"

# EC2 实例类型
instance_type = "t3.micro"  # 免费套餐可用

# Blue 环境配置
blue_instance_count = 2     # Blue ASG 实例数量

# Green 环境配置
enable_green_env     = false  # 是否启用 Green 环境
green_instance_count = 0      # Green ASG 实例数量（当 enable_green_env = true 时）

# 流量权重（仅当 enable_green_env = true 时生效）
blue_target_weight  = 100     # Blue 流量权重（0-100）
green_target_weight = 0       # Green 流量权重（0-100）
```

### 关键配置参数

#### 1. 零中断创建配置

```hcl
# 在 blue.tf 和 green.tf 中
resource "aws_autoscaling_group" "blue" {
  # 等待至少 blue_instance_count 个实例在 TG 中状态为 healthy
  min_elb_capacity          = var.blue_instance_count
  wait_for_elb_capacity     = var.blue_instance_count
  wait_for_capacity_timeout = "10m"  # 给实例充足时间启动

  # ... 其他配置
}
```

**作用**：
- Terraform 会轮询 Target Group 健康状态
- 确保所有实例状态为 "healthy" 后才返回成功
- HTTP Listener 在实例就绪后才创建，避免 503 错误

#### 2. 快速销毁配置

```hcl
# Target Group 注销延迟
resource "aws_lb_target_group" "blue" {
  deregistration_delay = 30  # 从默认 300s 减少到 30s
  # ... 其他配置
}

# ASG 强制删除和超时
resource "aws_autoscaling_group" "blue" {
  force_delete = true

  timeouts {
    delete = "15m"  # 销毁超时 15 分钟
  }
  # ... 其他配置
}
```

**作用**：
- 注销延迟从 5 分钟降到 30 秒
- 销毁时间从 5+ 分钟降到 2-3 分钟

#### 3. 依赖关系配置

```hcl
# HTTP Listener 等待 Blue ASG 就绪（关键！）
resource "aws_lb_listener" "http" {
  # ... 其他配置

  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green,
    aws_autoscaling_group.blue  # ← 零中断的关键
  ]
}
```

**作用**：
- 创建时：Listener 在实例健康后才创建
- 销毁时：ASG 先销毁，Listener 后销毁（正确顺序）

## 📊 资源列表

部署完成后将创建以下 AWS 资源：

| 资源类型 | 数量 | 名称/描述 |
|---------|------|-----------|
| **网络** | | |
| VPC | 1 | 10.0.0.0/16 |
| Subnet | 2 | 跨 2 个可用区的公有子网 |
| Internet Gateway | 1 | 提供公网访问 |
| Route Table | 1 | 默认路由到 IGW |
| Route Table Association | 2 | 关联到 2 个 Subnet |
| **安全** | | |
| Security Group | 2 | ALB SG, EC2 SG |
| SG Rule | 3 | HTTP 入站、出站规则 |
| **负载均衡** | | |
| Application Load Balancer | 1 | 跨 2 个可用区 |
| Target Group | 2 | Blue TG, Green TG |
| Listener | 1 | HTTP Port 80 |
| Listener Rule | 0-1 | Canary Rule（条件） |
| **计算** | | |
| Launch Template | 2 | Blue LT, Green LT |
| Auto Scaling Group | 1-2 | Blue ASG, Green ASG（条件） |
| EC2 Instance | 2-4 | t3.micro 实例 |

**预估成本**（us-west-2, 按需实例）：
- 2 × t3.micro: ~$0.0208/小时 = ~$15/月
- ALB: ~$0.0225/小时 + 数据传输 = ~$20/月
- **总计**: ~$35/月（测试环境，低流量）

## 🔧 常用命令

### Terraform 操作

```bash
# 初始化
terraform init

# 格式化代码
terraform fmt

# 验证配置
terraform validate

# 查看执行计划
terraform plan

# 应用配置（创建/更新）
terraform apply

# 查看特定资源的计划
terraform plan -target=aws_autoscaling_group.blue

# 销毁所有资源
terraform destroy

# 销毁特定资源
terraform destroy -target=aws_autoscaling_group.green

# 查看当前状态
terraform show

# 列出所有资源
terraform state list

# 查看特定资源详情
terraform state show aws_lb.app

# 刷新状态
terraform refresh

# 查看输出
terraform output
terraform output -json
terraform output alb_dns_name
```

### AWS CLI 操作

```bash
# 查看 ALB 状态
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `app-alb`)].{Name:LoadBalancerName,State:State.Code,DNS:DNSName}' \
  --output table

# 查看 Target Group 健康状态
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_tg_arn) \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table

# 查看 ASG 实例
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw blue_asg_name) \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}' \
  --output json

# 查看 EC2 实例
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=blue" \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,AZ:Placement.AvailabilityZone}' \
  --output table
```

## 🔍 监控和调试

### CloudWatch 日志

实例的 User Data 执行日志：
```bash
# SSH 到实例（需要配置密钥对）
ssh -i your-key.pem ubuntu@<instance-public-ip>

# 查看 User Data 执行日志
sudo cat /var/log/cloud-init-output.log

# 查看 Nginx 访问日志
sudo tail -f /var/log/nginx/access.log

# 查看 Nginx 错误日志
sudo tail -f /var/log/nginx/error.log
```

### 健康检查调试

```bash
# 查看 Target 健康状态详情
aws elbv2 describe-target-health \
  --target-group-arn <TG-ARN> \
  --output json | jq '.TargetHealthDescriptions[] | {Target: .Target.Id, State: .TargetHealth.State, Reason: .TargetHealth.Reason, Description: .TargetHealth.Description}'

# 如果状态为 unhealthy，可能原因：
# - initial: 正在进行初始健康检查
# - draining: 正在排空连接
# - unhealthy: 健康检查失败
#   - Reason: Target.FailedHealthChecks
#   - Reason: Target.Timeout
#   - Reason: Target.ResponseCodeMismatch
```

### Terraform 调试

```bash
# 启用详细日志
export TF_LOG=DEBUG
terraform plan

# 只显示 provider 日志
export TF_LOG_PROVIDER=TRACE
terraform apply

# 禁用日志
unset TF_LOG TF_LOG_PROVIDER

# 生成执行计划文件
terraform plan -out=tfplan

# 查看计划文件
terraform show tfplan

# 应用计划文件
terraform apply tfplan
```

## 🧪 测试和验证

### 功能测试

```bash
# 1. 测试 ALB 响应
curl -I http://$(terraform output -raw alb_dns_name)
# 预期: HTTP/1.1 200 OK

# 2. 测试负载均衡（多次请求查看不同实例）
for i in {1..10}; do
  curl -s http://$(terraform output -raw alb_dns_name) | grep "Instance ID"
done

# 3. 测试健康检查端点
curl http://$(terraform output -raw alb_dns_name)/

# 4. 测试 Blue 环境
curl http://$(terraform output -raw alb_dns_name)
# 应该返回蓝色主题页面

# 5. 部署 Green 后测试流量分配
# 多次请求，观察 Blue/Green 的比例是否符合权重设置
```

### 性能测试

```bash
# 使用 ab (Apache Bench)
ab -n 1000 -c 10 http://$(terraform output -raw alb_dns_name)/

# 使用 wrk
wrk -t4 -c100 -d30s http://$(terraform output -raw alb_dns_name)/

# 使用 hey
hey -n 1000 -c 50 http://$(terraform output -raw alb_dns_name)/
```

### 灾难恢复测试

```bash
# 1. 终止一个实例，观察 ASG 自动恢复
aws ec2 terminate-instances --instance-ids <instance-id>

# 2. 观察新实例启动（约 2-3 分钟）
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw blue_asg_name) \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]" \
  --output table'

# 3. 验证新实例健康后加入 Target Group
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_tg_arn)
```

## 🐛 故障排除

### 常见问题

#### 1. ASG 销毁卡住

**症状**：
```
aws_autoscaling_group.blue: Still destroying... [10m0s elapsed]
```

**解决方案**：
查看 [BLUE_GREEN_DEPLOYMENT_GUIDE.md](BLUE_GREEN_DEPLOYMENT_GUIDE.md#问题-1-asg-销毁卡住)

**快速修复**：
```bash
# 取消当前操作
Ctrl+C

# 手动缩容
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <ASG-NAME> \
  --min-size 0 --max-size 0 --desired-capacity 0

# 等待实例终止后重试
terraform destroy
```

#### 2. 实例健康检查失败

**症状**：
```
Target health checks are failing
Target state: unhealthy
```

**排查步骤**：
```bash
# 1. 检查 Security Group
aws ec2 describe-security-groups --group-ids <EC2-SG-ID>

# 2. 登录实例检查
ssh ubuntu@<instance-ip>
sudo systemctl status nginx
curl localhost

# 3. 查看健康检查配置
aws elbv2 describe-target-groups \
  --target-group-arns <TG-ARN> \
  --query 'TargetGroups[0].HealthCheckPath'
```

**解决方案**：
确保 EC2 Security Group 允许来自 ALB Security Group 的 80 端口流量。

#### 3. Provider 插件下载失败

**症状**：
```
Error: Failed to download provider
```

**解决方案**：
```bash
# 清理缓存
rm -rf .terraform .terraform.lock.hcl

# 使用镜像源（中国大陆）
cat > ~/.terraformrc <<EOF
provider_installation {
  network_mirror {
    url = "https://terraform-mirror.example.com/"
  }
}
EOF

# 重新初始化
terraform init
```

#### 4. 资源配额限制

**症状**：
```
Error: Error launching instance: VcpuLimitExceeded
```

**解决方案**：
- 检查 AWS Service Quotas
- 请求增加配额或使用较小的实例类型

### 调试清单

完整的验证清单请参阅：[VERIFICATION_CHECKLIST.md](VERIFICATION_CHECKLIST.md)

## 📚 延伸阅读

### 项目文档

1. **[蓝绿部署完整指南](BLUE_GREEN_DEPLOYMENT_GUIDE.md)** (必读)
   - 1000+ 行详细说明
   - 创建和销毁流程详解
   - 依赖关系深度分析
   - 故障排除指南

2. **[零中断部署设计](ZERO_DOWNTIME_DEPLOYMENT.md)**
   - 零停机创建原理
   - 配置参数详解
   - 创建流程对比

3. **[实施总结](IMPLEMENTATION_SUMMARY.md)**
   - 配置变更详情
   - 最佳实践建议

4. **[验证清单](VERIFICATION_CHECKLIST.md)**
   - 快速验证步骤
   - 常见问题排查

### 外部资源

- [Terraform AWS Provider 文档](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ALB 最佳实践](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
- [蓝绿部署策略](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html)
- [Auto Scaling 最佳实践](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-best-practices.html)

## 🔐 安全建议

### 1. 最小权限原则

为 Terraform 创建专用 IAM 用户：

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "iam:GetUser",
      "iam:GetRole"
    ],
    "Resource": "*"
  }]
}
```

### 2. 使用远程状态

```hcl
# 在 main.tf 中配置
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "aws/blue-green/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

### 3. 启用 HTTPS

生产环境建议：
- 配置 ACM 证书
- Listener 使用 443 端口
- 强制 HTTPS 重定向

### 4. 限制 Security Group

```hcl
# 生产环境：限制来源 IP
ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["your-office-ip/32"]  # 仅允许特定 IP
}
```

## 🎯 下一步

### 功能增强

- [ ] 添加 HTTPS 支持（ACM 证书）
- [ ] 配置 CloudWatch 告警
- [ ] 添加 WAF 防护
- [ ] 实现多环境部署（dev/staging/prod）
- [ ] 集成 CI/CD 流水线
- [ ] 添加 RDS 数据库层
- [ ] 实现 ECS/EKS 容器化部署

### 学习资源

- 阅读完整部署指南
- 生成并查看依赖关系图
- 实验不同的蓝绿切换策略
- 测试故障恢复场景

---

**项目维护**: iKelvinLab
**最后更新**: 2024-12-30
**Terraform 版本**: >= 1.0
**AWS Provider 版本**: ~> 6.0
