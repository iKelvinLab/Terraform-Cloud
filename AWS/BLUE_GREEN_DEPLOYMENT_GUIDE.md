# Terraform 蓝绿部署完整指南

## 📋 目录

1. [架构概述](#架构概述)
2. [零中断创建设计](#零中断创建设计) ⭐ 新增
3. [创建流程详解](#创建流程详解)
4. [销毁流程详解](#销毁流程详解)
5. [依赖关系说明](#依赖关系说明)
6. [关键配置参数](#关键配置参数)
7. [故障排除指南](#故障排除指南)
8. [最佳实践](#最佳实践)

---

## 🏗️ 架构概述

### 整体架构

这是一个基于 AWS 的蓝绿部署（Blue-Green Deployment）架构，支持零停机更新和流量灰度切换。

```
互联网 (Internet)
    ↓
Application Load Balancer (ALB)
    ↓
HTTP Listener (Port 80)
    ↓
Listener Rule (Canary - 可选)
    ↓ (加权分发)
    ├─→ Blue Target Group (100%) → Blue ASG (2 实例)
    └─→ Green Target Group (0%)  → Green ASG (0-2 实例)
```

### 资源层级结构

```
第 1 层：VPC 和网络基础设施
  ├─ VPC (10.0.0.0/16)
  ├─ Public Subnets × 2 (跨可用区)
  ├─ Internet Gateway
  └─ Route Tables

第 2 层：安全组
  ├─ ALB Security Group (允许 0.0.0.0/0:80)
  └─ EC2 Security Group (允许 ALB:80)

第 3 层：负载均衡器
  └─ Application Load Balancer

第 4 层：目标组
  ├─ Blue Target Group (deregistration_delay: 30s)
  └─ Green Target Group (deregistration_delay: 30s)

第 5 层：流量路由
  ├─ HTTP Listener (默认转发到 Blue)
  └─ Canary Listener Rule (加权转发，可选)

第 6 层：启动模板
  ├─ Blue Launch Template (Ubuntu 22.04, t3.micro)
  └─ Green Launch Template (Ubuntu 22.04, t3.micro)

第 7 层：计算资源
  ├─ Blue Auto Scaling Group (2 实例)
  └─ Green Auto Scaling Group (0-2 实例，可选)
```

---

## ⭐ 零中断创建设计

### 问题背景

在最初的设计中，创建流程存在一个严重的业务中断问题：

**旧流程（有问题）**：
```
第 4 阶段：创建 Target Groups ✓
第 5 阶段：创建 HTTP Listener (指向 Blue TG) ← 流量开始路由
第 6 阶段：创建 Launch Templates ✓
第 7 阶段：创建 ASG 和实例 ← 实例还在启动中
```

**问题分析**：
1. Listener 创建后立即开始接收流量
2. 但此时 Blue Target Group 中还没有健康实例
3. 所有请求都会失败（**503 Service Unavailable**）
4. 造成 **1-2 分钟的业务中断**

### 解决方案

通过调整资源创建顺序和依赖关系，实现零中断创建：

**新流程（零中断）**：
```
第 4 阶段：创建 Target Groups ✓
第 5 阶段：创建 Launch Templates ✓        ← 提前
第 6 阶段：创建 ASG 和实例                ← 提前
   ├─ 启动实例
   ├─ 执行 User Data
   ├─ 注册到 Target Group
   ├─ 健康检查通过 ✓
   └─ Terraform 等待确认所有实例健康 ⏳
第 7 阶段：创建 HTTP Listener             ← 延后，实例已就绪
第 8 阶段：创建 Canary Rule（可选）       ← 延后
```

**核心改进**：
1. **Listener 依赖 Blue ASG**：确保实例健康后才创建流量路由
2. **ASG 移除对 Listener 的依赖**：避免循环依赖
3. **使用 wait_for_elb_capacity**：Terraform 主动等待实例健康

### 关键配置对比

#### Blue ASG 配置变更

**旧配置**（会导致中断）：
```hcl
resource "aws_autoscaling_group" "blue" {
  # ...

  wait_for_capacity_timeout = "0"  # ❌ 不等待实例健康

  depends_on = [
    aws_lb_listener.http,          # ❌ 依赖 Listener（错误）
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
```

**新配置**（零中断）：
```hcl
resource "aws_autoscaling_group" "blue" {
  # ...

  # ✅ 关键：等待实例在 TG 中健康
  min_elb_capacity          = var.blue_instance_count
  wait_for_elb_capacity     = var.blue_instance_count
  wait_for_capacity_timeout = "10m"

  # ✅ 移除对 Listener 的依赖
  depends_on = [
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
```

#### Listener 配置变更

**旧配置**（会导致中断）：
```hcl
resource "aws_lb_listener" "http" {
  # ...

  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green    # ❌ 不等待实例健康
  ]
}
```

**新配置**（零中断）：
```hcl
resource "aws_lb_listener" "http" {
  # ...

  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green,
    aws_autoscaling_group.blue   # ✅ 等待 Blue 实例健康
  ]
}
```

### 依赖关系图

**旧的依赖关系**（错误）：
```
Target Groups → Listener → ASG
                    ↑        ↓
                    └────────┘  ← 循环依赖（需要手动 depends_on 打破）
```

**新的依赖关系**（正确）：
```
Target Groups → ASG（等待实例健康）→ Listener → Canary Rule
                      ↑
                  Terraform 轮询
                 TG 健康状态 ⏳
```

### 零中断验证流程

创建完成后，验证是否真正零中断：

```bash
# 1. 检查 Blue ASG 创建日志
# Terraform 应该显示：
aws_autoscaling_group.blue: Still creating... [1m30s elapsed]
aws_autoscaling_group.blue: Still creating... [2m0s elapsed]
aws_autoscaling_group.blue: Creation complete after 2m15s

# 2. 检查 Listener 创建日志
# Listener 应该在 ASG 之后创建：
aws_lb_listener.http: Creating...
aws_lb_listener.http: Creation complete after 3s

# 3. 验证 Target Group 健康状态
aws elbv2 describe-target-health \
  --target-group-arn <blue-tg-arn> \
  --region us-west-2

# 输出应该显示所有实例都是 healthy：
{
  "TargetHealthDescriptions": [
    {
      "Target": { "Id": "i-xxx", "Port": 80 },
      "HealthCheckPort": "80",
      "TargetHealth": { "State": "healthy" }
    },
    {
      "Target": { "Id": "i-yyy", "Port": 80 },
      "HealthCheckPort": "80",
      "TargetHealth": { "State": "healthy" }
    }
  ]
}

# 4. 测试 ALB 访问
curl http://<alb-dns-name>
# 应该立即返回 200 OK（无 503 错误）
```

### 销毁顺序说明

零中断创建的依赖设计同时确保了正确的销毁顺序：

```
销毁时（反向处理 depends_on）：
  1. Canary Rule 先销毁
  2. Listener 销毁
  3. Blue ASG 销毁（实例注销 30s）
  4. Target Groups 销毁
  5. Launch Templates 销毁

✅ ASG 在 Listener 之前销毁，避免卡住
```

### 性能影响分析

**旧流程耗时**：
- 创建 ASG：约 2 分钟（Terraform 不等待）
- **业务中断**：1-2 分钟（Listener 创建到实例健康）
- 总耗时：约 3-4 分钟（但有中断）

**新流程耗时**：
- 创建 ASG + 等待健康：约 2-3 分钟
- 创建 Listener：约 5 秒
- **业务中断**：0 秒 ✅
- 总耗时：约 3-4 分钟（无中断）

**结论**：总耗时相同，但完全消除了业务中断！

---

## 🚀 创建流程详解

### 阶段概览（零中断版本）⭐

| 阶段 | 描述 | 耗时 | 关键资源 | 零中断设计 |
|------|------|------|----------|------------|
| 1 | 基础网络层 | 0-30s | VPC, Subnets, IGW | - |
| 2 | 安全层 | 30-45s | Security Groups | - |
| 3 | 负载均衡器层 | 45-90s | ALB (等待 active) | - |
| 4 | 目标组层 | 90-100s | Target Groups | - |
| 5 | 启动模板层 | 100-110s | Launch Templates | 提前创建 ⭐ |
| 6 | 计算资源层 | 110-180s | ASG, 实例启动 + **等待健康** | 提前创建 + 等待 ⭐ |
| 7 | 流量路由层 | 180-190s | Listener, Rules | 延后创建 ⭐ |
| 8 | 验证和完成 | 190-200s | 健康检查 | - |

**关键变化**：
- 阶段 5-6 **提前**：Launch Templates 和 ASG 在 Listener 之前创建
- 阶段 6 **等待**：Terraform 主动等待实例健康（Listener 延后）
- 阶段 7 **延后**：Listener 在实例就绪后创建，无 503 错误

**总耗时**：
- 仅 Blue 环境：约 **3-4 分钟**（与旧版相同）
- Blue + Green 环境：约 **5-6 分钟**（与旧版相同）
- **业务中断**：**0 秒** ✅（旧版 1-2 分钟）

### 详细步骤

#### 第 1 阶段：基础网络层 (0-30 秒)

```bash
terraform apply
```

**步骤 1: 创建 VPC**
```hcl
aws_vpc.main
  CIDR: 10.0.0.0/16
  启用 DNS 主机名和解析
```

**步骤 2: 创建 Internet Gateway**
```hcl
aws_internet_gateway.igw
  连接到 VPC
  提供公网访问
```

**步骤 3: 创建 Public Subnets**
```hcl
aws_subnet.public[0] - 可用区 A (10.0.1.0/24)
aws_subnet.public[1] - 可用区 B (10.0.2.0/24)
  自动分配公网 IP
  跨可用区高可用
```

**步骤 4: 创建路由表**
```hcl
aws_route_table.public
  默认路由: 0.0.0.0/0 → Internet Gateway
  关联到所有 Public Subnets
```

#### 第 2 阶段：安全层 (30-45 秒)

**步骤 5: 创建 ALB Security Group**
```hcl
aws_security_group.alb
  入站规则:
    - 0.0.0.0/0:80 (HTTP from Internet)
  出站规则:
    - 0.0.0.0/0:* (All traffic)
```

**步骤 6: 创建 EC2 Security Group**
```hcl
aws_security_group.ec2
  入站规则:
    - ALB Security Group:80 (HTTP from ALB only)
  出站规则:
    - 0.0.0.0/0:* (All traffic)
```

#### 第 3 阶段：负载均衡器层 (45-90 秒)

**步骤 7: 创建 Application Load Balancer**
```hcl
aws_lb.app
  类型: application
  网络: internet-facing
  Subnets: [subnet-a, subnet-b]
  Security Groups: [alb-sg]

  ⏳ 等待时间: 约 60-90 秒
  AWS 会预配置 ALB 节点到每个可用区
  状态: provisioning → active
```

**依赖关系**：
```
VPC → Subnets → ALB
VPC → ALB Security Group → ALB
```

#### 第 4 阶段：目标组层 (90-100 秒)

**步骤 8 & 9: 并行创建 Target Groups**

```hcl
# Blue Target Group
aws_lb_target_group.blue
  Port: 80
  Protocol: HTTP
  VPC: aws_vpc.main

  健康检查:
    路径: /
    间隔: 15 秒
    超时: 5 秒
    健康阈值: 2 次
    不健康阈值: 2 次

  ⚡ 关键配置:
    deregistration_delay: 30 秒 (默认 300 秒)

  lifecycle:
    create_before_destroy: true

  depends_on: [aws_lb.app]
```

```hcl
# Green Target Group
aws_lb_target_group.green
  (配置与 Blue 相同)
```

**并行创建优势**：
- Blue 和 Green TG 同时创建，节省时间
- 两者互不依赖

#### 第 5 阶段：启动模板层 (100-110 秒) - 提前创建 ⭐

**步骤 10 & 11: 并行创建 Launch Templates**

```hcl
# Blue Launch Template
aws_launch_template.blue
  AMI: Ubuntu 22.04 LTS (最新)
  Instance Type: t3.micro
  Security Groups: [ec2-sg]

  User Data:
    #!/bin/bash
    apt update && apt install -y nginx
    # 配置蓝色主题网页
    # 显示环境信息

  depends_on: [aws_security_group.ec2]
```

```hcl
# Green Launch Template
aws_launch_template.green
  (配置与 Blue 类似，但使用绿色主题)
```

#### 第 6 阶段：计算资源层 (110-180 秒) - 提前创建 + 等待健康 ⭐

**步骤 12: 创建 Blue ASG**

```hcl
aws_autoscaling_group.blue
  Min/Max/Desired: 2
  VPC Zones: [subnet-a, subnet-b]

  ⚡ 零中断关键配置:
    target_group_arns: [blue-tg-arn]
    health_check_type: "ELB"

    # 新增：等待实例健康 ⭐
    min_elb_capacity: 2
    wait_for_elb_capacity: 2
    wait_for_capacity_timeout: "10m"

    force_delete: true

  Launch Template: aws_launch_template.blue

  Lifecycle:
    create_before_destroy: true

  Timeouts:
    delete: "15m"

  🔑 关键变更:
    depends_on: [
      # ⚠️ 移除了 aws_lb_listener.http 依赖
      aws_lb_target_group.blue,
      aws_launch_template.blue
    ]
```

**实例启动和健康等待流程** (约 70-90 秒):
```
1. ASG 请求启动 2 个 EC2 实例          (~5s)
2. EC2 实例预配置和启动                (~30s)
3. User Data 脚本执行                 (~20s)
   - apt update
   - 安装 nginx
   - 配置蓝色主题网页
   - 启动 nginx 服务
4. 实例注册到 Blue Target Group       (~5s)
5. 第一次健康检查 (GET /)              (~15s)
6. 第二次健康检查 (达到健康阈值)       (~15s)
7. 实例状态变为 "healthy" ✓

⏳ Terraform 轮询等待:
   - 每 10 秒检查 TG 健康状态
   - 确认 2 个实例都是 healthy
   - ASG 创建完成（约 2-3 分钟）

✅ 此时 Blue TG 中已有健康实例！
```

**步骤 13: 创建 Green ASG (条件)**

```hcl
aws_autoscaling_group.green
  count: var.enable_green_env ? 1 : 0
  Min/Max/Desired: var.green_instance_count

  ⚡ 零中断关键配置:
    # 新增：等待实例健康 ⭐
    min_elb_capacity: var.green_instance_count
    wait_for_elb_capacity: var.green_instance_count
    wait_for_capacity_timeout: "10m"

    force_delete: true

  🔑 关键变更:
    depends_on: [
      # ⚠️ 移除了 aws_lb_listener 和 canary rule 依赖
      aws_lb_target_group.green,
      aws_launch_template.green
    ]
```

**Green 实例启动流程**：
- 与 Blue 相同的启动和健康检查流程
- Terraform 同样等待所有实例健康
- 如果 green_instance_count = 0，立即返回

#### 第 7 阶段：流量路由层 (180-190 秒) - 延后创建，实例已就绪 ⭐

**步骤 14: 创建 HTTP Listener**

```hcl
aws_lb_listener.http
  ALB: aws_lb.app
  Port: 80
  Protocol: HTTP

  默认动作:
    Type: forward
    Target Group: aws_lb_target_group.blue

  🎯 零中断关键配置:
    depends_on: [
      aws_lb.app,
      aws_lb_target_group.blue,
      aws_lb_target_group.green,
      aws_autoscaling_group.blue  # ⭐ 新增：等待 Blue 实例健康
    ]
```

**关键优势**：
- ✅ 创建 Listener 时，Blue TG 中已有 2 个健康实例
- ✅ 流量路由立即可用，无 503 错误
- ✅ 用户访问 ALB DNS 立即返回 200 OK

**销毁顺序**：
- Listener 在 Blue ASG 之后销毁（反向处理 depends_on）
- 确保 ASG 先注销实例（30 秒）
- 然后才删除 Listener

**步骤 15: 创建 Canary Listener Rule (条件)**

```hcl
aws_lb_listener_rule.canary
  count: var.enable_green_env ? 1 : 0

  优先级: 1 (高于默认动作)

  动作:
    Type: forward
    加权转发:
      - Blue TG: var.blue_target_weight (默认 100)
      - Green TG: var.green_target_weight (默认 0)

  条件:
    路径模式: /*

  depends_on: [
    aws_lb_listener.http,          # Listener 已等待 Blue ASG
    aws_lb_target_group.blue,
    aws_lb_target_group.green
    # Green ASG 通过条件判断处理
  ]
```

**流量控制**：
```
初始状态: Blue 100%, Green 0%
灰度测试: Blue 90%, Green 10%
继续切换: Blue 50%, Green 50%
接近完成: Blue 10%, Green 90%
完全切换: Blue 0%, Green 100%
```

**关键优势**：
- ✅ 如果启用了 Green，此时 Green TG 也已有健康实例
- ✅ 加权转发立即生效，无错误
- ✅ 可以安全进行灰度发布

#### 第 8 阶段：验证和完成 (190-200 秒)

**步骤 16: 验证健康检查**
```
检查所有 Target 状态:
  Blue TG:
    ✓ Target 1: healthy
    ✓ Target 2: healthy

  Green TG (如果启用):
    ✓ Target 1: healthy
    ✓ Target 2: healthy

ALB 开始接收和分发流量
```

**步骤 17: 输出资源信息**
```hcl
Outputs:
  alb_dns_name      = "app-alb-1234567890.us-west-2.elb.amazonaws.com"
  blue_asg_name     = "blue-asg-20231230..."
  green_asg_name    = "green-asg-20231230..." (如果启用)
  vpc_id            = "vpc-..."
  subnet_ids        = ["subnet-...", "subnet-..."]
```

**创建完成！** ✅

---

## 🔥 销毁流程详解

### 为什么销毁顺序很重要？

**问题场景**（没有正确依赖时）：
```
Terraform 尝试销毁 ASG
  ↓
ASG 开始终止实例
  ↓
实例需要从 Target Group 注销
  ⚠️ 但 Listener 仍在使用 Target Group
  ⚠️ Target Group 无法立即注销实例
  ↓
等待 deregistration_delay (默认 300 秒)
  ↓
如果有活跃连接或健康检查失败
  ↓
❌ 销毁卡住！
```

**解决方案**（使用 depends_on）：
```
ASG 的 depends_on 包含 Listener
  ↓
销毁时，Terraform 反向处理依赖
  ↓
ASG 先于 Listener 销毁 ✅
  ↓
1. ASG 开始销毁
2. 实例终止
3. 实例从 TG 注销 (30 秒)
4. ASG 删除完成
5. 然后 Listener Rule 删除
6. 然后 Listener 删除
7. 最后 Target Group 删除
  ↓
✅ 顺利完成！
```

### 销毁阶段概览

| 阶段 | 描述 | 耗时 | 关键资源 |
|------|------|------|----------|
| 1 | Auto Scaling 层 | 0-60s | ASG, 实例终止 |
| 2 | 流量路由层 | 60-65s | Listener Rule, Listener |
| 3 | 目标组层 | 65-70s | Target Groups |
| 4 | 负载均衡器层 | 70-75s | ALB |
| 5 | 启动模板层 | 75-80s | Launch Templates |
| 6 | 安全层 | 80-85s | Security Groups |
| 7 | 基础网络层 | 85-120s | VPC, Subnets, IGW |

**总耗时**：约 **2-3 分钟**

### 详细步骤

#### 第 1 阶段：Auto Scaling 层 (0-60 秒) - 🎯 关键！

**步骤 1-2: 销毁 ASG**

```bash
terraform destroy

# Terraform 分析依赖关系
# 确定销毁顺序: ASG → Rule → Listener → TG → ALB → ...

🔍 关键：ASG depends_on Listener
   → 销毁时 ASG 必须在 Listener 之前销毁
```

**Green ASG 销毁** (如果存在):
```
aws_autoscaling_group.green[0]: Destroying...
  1. 设置 Desired Capacity = 0
  2. ASG 开始终止实例
  3. 实例从 Green Target Group 注销
     ⏱ 等待 deregistration_delay: 30 秒
  4. 连接排空完成
  5. 实例终止
  6. ASG 资源删除

aws_autoscaling_group.green[0]: Destruction complete after 45s
```

**Blue ASG 销毁**:
```
aws_autoscaling_group.blue: Destroying...
  (相同的销毁流程)

aws_autoscaling_group.blue: Destruction complete after 52s
```

**为什么不会卡住？**
- ✅ deregistration_delay = 30s (不是 300s)
- ✅ force_delete = true (强制删除)
- ✅ timeout = 15m (超时保护)
- ✅ Listener 仍然存在，不阻塞注销

#### 第 2 阶段：流量路由层 (60-65 秒)

**步骤 3: 销毁 Canary Listener Rule**

```
aws_lb_listener_rule.canary[0]: Destroying...
  1. 从 Listener 移除规则
  2. 释放对 Target Groups 的引用

aws_lb_listener_rule.canary[0]: Destruction complete after 3s
```

**步骤 4: 销毁 HTTP Listener**

```
aws_lb_listener.http: Destroying...
  1. 停止接收新连接
  2. 从 ALB 移除 Listener
  3. 释放对 Target Groups 的引用

aws_lb_listener.http: Destruction complete after 2s
```

**现在 Target Groups 没有任何引用了！** ✅

#### 第 3 阶段：目标组层 (65-70 秒)

**步骤 5-6: 并行销毁 Target Groups**

```
aws_lb_target_group.green: Destroying...
aws_lb_target_group.blue: Destroying...
  1. 确认没有注册的实例 (已在阶段 1 注销)
  2. 确认没有 Listener 引用 (已在阶段 2 删除)
  3. 删除健康检查配置
  4. 删除 Target Group

aws_lb_target_group.green: Destruction complete after 1s
aws_lb_target_group.blue: Destruction complete after 1s
```

**快速销毁原因**：
- ✅ 所有实例已注销
- ✅ 没有 Listener 引用
- ✅ 没有活跃连接

#### 第 4 阶段：负载均衡器层 (70-75 秒)

**步骤 7: 销毁 ALB**

```
aws_lb.app: Destroying...
  1. 停止接收流量
  2. 释放所有 ENI (Elastic Network Interfaces)
  3. 从每个 Subnet 移除 ALB 节点
  4. 删除 ALB 资源

aws_lb.app: Destruction complete after 3s
```

#### 第 5 阶段：启动模板层 (75-80 秒)

**步骤 8-9: 并行销毁 Launch Templates**

```
aws_launch_template.blue: Destroying...
aws_launch_template.green: Destroying...
  1. 删除模板版本
  2. 删除模板配置

aws_launch_template.blue: Destruction complete after 1s
aws_launch_template.green: Destruction complete after 1s
```

#### 第 6 阶段：安全层 (80-85 秒)

**步骤 10-11: 销毁 Security Groups**

```
aws_security_group_rule.ec2_http_from_alb: Destroying...
aws_security_group_rule.ec2_http_from_alb: Destruction complete after 1s

aws_security_group.ec2: Destroying...
aws_security_group.alb: Destroying...
  1. 移除所有规则
  2. 检查没有 ENI 使用
  3. 删除 Security Group

aws_security_group.ec2: Destruction complete after 2s
aws_security_group.alb: Destruction complete after 2s
```

#### 第 7 阶段：基础网络层 (85-120 秒)

**步骤 12-15: 销毁网络资源**

```
aws_route_table_association.public: Destroying...
aws_route_table_association.public: Destruction complete after 1s

aws_route_table.public: Destroying...
aws_route_table.public: Destruction complete after 2s

aws_subnet.public[0]: Destroying...
aws_subnet.public[1]: Destroying...
aws_subnet.public[0]: Destruction complete after 2s
aws_subnet.public[1]: Destruction complete after 2s

aws_internet_gateway.igw: Destroying...
  ⏱ 等待 IGW 完全分离: ~5-10 秒
aws_internet_gateway.igw: Destruction complete after 8s

aws_vpc.main: Destroying...
  1. 检查所有依赖资源已删除
  2. 删除 VPC
aws_vpc.main: Destruction complete after 2s
```

**销毁完成！** ✅

```
Destroy complete! Resources: 20 destroyed.
```

---

## 🔗 依赖关系说明

### 显式依赖 vs 隐式依赖

#### 隐式依赖（Implicit Dependencies）

通过资源属性引用自动建立：

```hcl
# 示例 1: VPC ID 引用
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id  # ← 隐式依赖
  # Terraform 自动知道：先创建 VPC，再创建 Subnet
}

# 示例 2: Target Group ARN 引用
resource "aws_autoscaling_group" "blue" {
  target_group_arns = [
    aws_lb_target_group.blue.arn  # ← 隐式依赖
  ]
  # Terraform 自动知道：先创建 TG，再创建 ASG
}
```

**优点**：
- ✅ 简洁明了
- ✅ 自动推断
- ✅ 不易出错

**缺点**：
- ❌ 某些依赖无法表达（如销毁顺序）
- ❌ 可能导致循环依赖

#### 显式依赖（Explicit Dependencies）

通过 `depends_on` 明确声明：

```hcl
# 示例：ASG 必须在 Listener 之后创建
resource "aws_autoscaling_group" "blue" {
  # ... 其他配置 ...

  depends_on = [
    aws_lb_listener.http,       # ← 显式依赖
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
```

**优点**：
- ✅ 明确控制创建和销毁顺序
- ✅ 可表达复杂依赖关系
- ✅ 文档化清晰

**缺点**：
- ❌ 需要手动维护
- ❌ 过度使用可能降低性能（减少并行）

### 本项目的依赖策略

#### 1. Target Groups 依赖 ALB

```hcl
resource "aws_lb_target_group" "blue" {
  vpc_id = aws_vpc.main.id  # 隐式

  depends_on = [
    aws_lb.app  # 显式：确保 ALB 先创建
  ]
}
```

**原因**：
- 创建时：TG 需要 ALB 存在
- 销毁时：TG 在 ALB 之前销毁 ✅

#### 2. Listener 依赖 ALB 和 TGs

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn  # 隐式

  default_action {
    target_group_arn = aws_lb_target_group.blue.arn  # 隐式
  }

  depends_on = [
    aws_lb.app,                  # 显式
    aws_lb_target_group.blue,    # 显式
    aws_lb_target_group.green    # 显式
  ]
}
```

**原因**：
- 创建时：Listener 需要 ALB 和 TG 都存在
- 销毁时：Listener 在 TG 之前销毁 ✅

#### 3. Listener Rule 依赖 Listener 和 TGs

```hcl
resource "aws_lb_listener_rule" "canary" {
  listener_arn = aws_lb_listener.http.arn  # 隐式

  depends_on = [
    aws_lb_listener.http,        # 显式
    aws_lb_target_group.blue,    # 显式
    aws_lb_target_group.green    # 显式
  ]
}
```

**原因**：
- 创建时：Rule 需要 Listener 和 TG 存在
- 销毁时：Rule 在 Listener 和 TG 之前销毁 ✅

#### 4. ASG 依赖 Listener、TG 和 LT - 🔑 关键！

```hcl
resource "aws_autoscaling_group" "blue" {
  target_group_arns = [
    aws_lb_target_group.blue.arn  # 隐式
  ]

  launch_template {
    id = aws_launch_template.blue.id  # 隐式
  }

  depends_on = [
    aws_lb_listener.http,        # 🔑 KEY! 显式依赖
    aws_lb_target_group.blue,    # 显式
    aws_launch_template.blue     # 显式
  ]
}
```

**这是解决销毁卡住问题的核心！**

**原因**：
- 创建时：ASG 需要 Listener 就绪后才创建（确保路由配置完成）
- **销毁时：ASG 在 Listener 之前销毁** ✅
  - ASG 终止实例
  - 实例从 TG 注销（30 秒）
  - 然后才删除 Listener
  - 最后删除 TG

**如果没有这个 depends_on 会怎样？**

```
❌ 错误场景：

Terraform 可能按以下顺序销毁：
  1. Listener 删除
  2. ASG 尝试销毁
  3. 实例需要从 TG 注销
  4. 但 TG 可能正在被删除
  5. 注销操作卡住
  6. 等待 deregistration_delay 超时 (300s)
  7. 或者永久卡住 ❌
```

### 完整依赖链

```
创建顺序 (从下到上)：
  VPC
    → Subnets, Security Groups
      → ALB
        → Target Groups
          → Listener
            → Listener Rule
              → Launch Templates, ASG

销毁顺序 (从上到下，完全反向)：
  ASG                           ← 第 1 步
    → Listener Rule             ← 第 2 步
      → Listener                ← 第 3 步
        → Target Groups         ← 第 4 步
          → ALB                 ← 第 5 步
            → Launch Templates  ← 第 6 步
              → Security Groups ← 第 7 步
                → Subnets, VPC  ← 第 8 步
```

---

## ⚙️ 关键配置参数

### 1. deregistration_delay

**位置**：Target Group 配置

```hcl
resource "aws_lb_target_group" "blue" {
  # ...
  deregistration_delay = 30
}
```

**默认值**：300 秒 (5 分钟)
**优化值**：30 秒

**作用**：
- 当实例从 Target Group 注销时，AWS 会等待这个时间
- 允许现有连接完成
- 新连接不再路由到该实例

**影响**：
- ✅ 减少销毁等待时间（从 5 分钟降到 30 秒）
- ✅ 加快蓝绿切换速度
- ⚠️ 如果应用有长连接（如 WebSocket），可能需要增加到 60-120 秒

**适用场景**：
- ✅ 测试/开发环境：30 秒
- ✅ 短连接应用：30-60 秒
- ⚠️ 长连接应用：120-300 秒
- ⚠️ 需要严格零数据丢失：保持 300 秒

### 2. force_delete

**位置**：Auto Scaling Group 配置

```hcl
resource "aws_autoscaling_group" "blue" {
  # ...
  force_delete = true
}
```

**默认值**：false
**优化值**：true

**作用**：
- 允许强制删除 ASG，即使实例未完全终止
- 跳过某些等待和验证步骤

**影响**：
- ✅ 加快 ASG 销毁速度
- ✅ 避免因单个实例卡住导致整个销毁失败
- ⚠️ 可能在实例完全终止前删除 ASG

**适用场景**：
- ✅ 测试/开发环境
- ✅ 临时环境
- ⚠️ 生产环境：谨慎使用，确保有监控

### 3. wait_for_capacity_timeout

**位置**：Auto Scaling Group 配置

```hcl
resource "aws_autoscaling_group" "blue" {
  # ...
  wait_for_capacity_timeout = "0"
}
```

**默认值**：10m
**优化值**：0 (不等待)

**作用**：
- 创建 ASG 时，Terraform 等待指定数量的实例健康
- 设为 "0" 表示不等待

**影响**：
- ✅ Terraform apply 更快完成（不等待实例健康）
- ⚠️ 需要手动验证实例是否健康
- ✅ 销毁时不影响

**适用场景**：
- ✅ 如果你有外部健康检查监控
- ✅ 如果你接受 Terraform 快速完成，然后手动验证
- ❌ 如果你需要 Terraform 确保实例健康后才继续

**推荐**：
- 开发环境：`"0"`
- 生产环境：`"10m"` 或 `"15m"`

### 4. timeouts

**位置**：Auto Scaling Group 配置

```hcl
resource "aws_autoscaling_group" "blue" {
  # ...
  timeouts {
    delete = "15m"
  }
}
```

**默认值**：无限期等待
**优化值**：15m (15 分钟)

**作用**：
- 设置 ASG 删除操作的最大等待时间
- 超时后 Terraform 会报错退出

**影响**：
- ✅ 防止无限期等待
- ✅ 15 分钟足够大多数正常销毁
- ✅ 异常情况下及时报错

**适用场景**：
- ✅ 所有环境都推荐设置
- 根据实例数量和注销时间调整：
  - 2-5 实例：15m
  - 5-10 实例：20m
  - 10+ 实例：30m

### 5. create_before_destroy

**位置**：Lifecycle 配置

```hcl
resource "aws_autoscaling_group" "blue" {
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

**默认值**：false
**优化值**：true

**作用**：
- 更新资源时，先创建新资源，再删除旧资源
- 确保零停机

**影响**：
- ✅ 蓝绿部署的核心配置
- ✅ 更新时不会中断服务
- ⚠️ 临时会有双倍资源（新旧同时存在）

**适用场景**：
- ✅ 所有需要高可用的资源
- ✅ ASG, Target Group, Launch Template
- ❌ 不适用于必须唯一的资源（如 Elastic IP）

### 6. health_check_type

**位置**：Auto Scaling Group 配置

```hcl
resource "aws_autoscaling_group" "blue" {
  # ...
  health_check_type = "ELB"
}
```

**可选值**：
- `EC2`：仅检查 EC2 实例状态
- `ELB`：检查 ELB/ALB Target Group 健康状态

**推荐值**：`"ELB"`

**作用**：
- 决定 ASG 如何判断实例是否健康
- ELB 模式会检查应用层健康（HTTP 200）

**影响**：
- ✅ 更准确的健康检查（应用级别）
- ✅ 自动替换不健康实例
- ⚠️ 如果健康检查路径返回非 200，实例会被终止

### 配置组合推荐

#### 开发/测试环境

```hcl
deregistration_delay      = 30          # 快速注销
force_delete              = true         # 强制删除
wait_for_capacity_timeout = "0"          # 不等待
health_check_type         = "ELB"        # 应用级检查
create_before_destroy     = true         # 零停机

timeouts {
  delete = "15m"
}
```

#### 生产环境

```hcl
deregistration_delay      = 60          # 平衡速度和安全
force_delete              = false        # 安全删除
wait_for_capacity_timeout = "10m"        # 确保实例健康
health_check_type         = "ELB"        # 应用级检查
create_before_destroy     = true         # 零停机

timeouts {
  delete = "20m"
}
```

---

## 🔧 故障排除指南

### 问题 1: ASG 销毁卡住

**症状**：
```
aws_autoscaling_group.blue: Still destroying... [10m0s elapsed]
aws_autoscaling_group.blue: Still destroying... [15m0s elapsed]
aws_autoscaling_group.blue: Still destroying... [20m0s elapsed]
```

**可能原因**：
1. ❌ ASG 没有 `depends_on` Listener
2. ❌ `deregistration_delay` 太长 (300s)
3. ❌ 实例有保护（Protected from scale-in）
4. ❌ 实例终止失败

**解决方案**：

**方案 1: 检查依赖配置**
```bash
# 确认 ASG 有正确的 depends_on
grep -A 5 "depends_on" blue.tf

# 应该看到：
depends_on = [
  aws_lb_listener.http,
  aws_lb_target_group.blue,
  aws_launch_template.blue
]
```

**方案 2: 手动清理（紧急）**
```bash
# 1. 取消当前操作
Ctrl+C

# 2. 手动缩容 ASG
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name blue-asg-XXXXXX \
  --min-size 0 --max-size 0 --desired-capacity 0 \
  --region us-west-2

# 3. 等待实例终止 (2-3 分钟)
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names blue-asg-XXXXXX \
  --region us-west-2 \
  --query "AutoScalingGroups[0].Instances[]"'

# 4. 强制删除 ASG
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name blue-asg-XXXXXX \
  --force-delete \
  --region us-west-2

# 5. 刷新 Terraform 状态
terraform refresh

# 6. 继续销毁
terraform destroy
```

**方案 3: 使用 Targeted Destroy**
```bash
# 分步销毁
terraform destroy -target=aws_autoscaling_group.blue
terraform destroy -target=aws_lb_listener_rule.canary
terraform destroy -target=aws_lb_listener.http
terraform destroy -target=aws_lb_target_group.blue
terraform destroy
```

### 问题 2: Target Group 销毁失败

**症状**：
```
Error: Error deleting Target Group: TargetGroupInUse:
Target group is currently in use by a listener or a rule
```

**原因**：
- Listener 或 Rule 仍在引用 Target Group

**解决方案**：
```bash
# 1. 检查哪些 Listener 在使用 TG
aws elbv2 describe-listeners \
  --load-balancer-arn <ALB-ARN> \
  --region us-west-2

# 2. 检查 Listener Rules
aws elbv2 describe-rules \
  --listener-arn <LISTENER-ARN> \
  --region us-west-2

# 3. 手动删除 Listener Rule
aws elbv2 delete-rule \
  --rule-arn <RULE-ARN> \
  --region us-west-2

# 4. 手动删除 Listener
aws elbv2 delete-listener \
  --listener-arn <LISTENER-ARN> \
  --region us-west-2

# 5. 继续 Terraform 销毁
terraform refresh
terraform destroy
```

### 问题 3: 实例健康检查一直失败

**症状**：
```
Target health checks are failing
Target state: unhealthy
Reason: Health checks failed
```

**可能原因**：
1. 应用未正确启动
2. Security Group 阻止健康检查
3. 健康检查路径错误

**排查步骤**：

**步骤 1: 检查 Security Group**
```bash
# 确认 EC2 SG 允许来自 ALB 的流量
aws ec2 describe-security-groups \
  --group-ids <EC2-SG-ID> \
  --region us-west-2

# 应该有规则：
# Port 80 from ALB Security Group
```

**步骤 2: 检查实例**
```bash
# 登录实例
ssh -i your-key.pem ubuntu@<INSTANCE-IP>

# 检查 nginx 状态
sudo systemctl status nginx

# 检查端口监听
sudo netstat -tlnp | grep :80

# 测试本地访问
curl http://localhost/
```

**步骤 3: 检查健康检查配置**
```bash
# 查看 Target Group 健康检查设置
aws elbv2 describe-target-health \
  --target-group-arn <TG-ARN> \
  --region us-west-2

# 查看详细健康检查配置
aws elbv2 describe-target-groups \
  --target-group-arns <TG-ARN> \
  --region us-west-2 \
  --query 'TargetGroups[0].HealthCheckPath'
```

**解决方案**：
```hcl
# 调整健康检查参数
resource "aws_lb_target_group" "blue" {
  health_check {
    path                = "/"
    matcher             = "200-399"  # 接受更多状态码
    interval            = 30         # 增加间隔
    timeout             = 10         # 增加超时
    healthy_threshold   = 2
    unhealthy_threshold = 3          # 增加不健康阈值
  }
}
```

### 问题 4: Terraform 状态不同步

**症状**：
```
Error: Error refreshing state:
ResourceNotFoundException: Target group 'blue-tg' not found
```

**原因**：
- 手动删除了资源但 Terraform 状态未更新

**解决方案**：
```bash
# 方案 1: 刷新状态
terraform refresh

# 方案 2: 移除特定资源
terraform state rm aws_lb_target_group.blue

# 方案 3: 重新导入资源
terraform import aws_lb_target_group.blue <TG-ARN>

# 方案 4: 完全重建状态（谨慎！）
rm terraform.tfstate
terraform import ...
```

### 问题 5: 依赖循环

**症状**：
```
Error: Cycle: aws_lb_listener.http, aws_autoscaling_group.blue
```

**原因**：
- 两个资源互相依赖，形成循环

**解决方案**：
```hcl
# ❌ 错误：循环依赖
resource "aws_lb_listener" "http" {
  depends_on = [aws_autoscaling_group.blue]
}

resource "aws_autoscaling_group" "blue" {
  depends_on = [aws_lb_listener.http]
}

# ✅ 正确：单向依赖
resource "aws_lb_listener" "http" {
  # 不依赖 ASG
}

resource "aws_autoscaling_group" "blue" {
  depends_on = [aws_lb_listener.http]
}
```

---

## 💡 最佳实践

### 1. 依赖管理

**✅ DO：使用显式依赖控制销毁顺序**
```hcl
resource "aws_autoscaling_group" "blue" {
  depends_on = [
    aws_lb_listener.http,        # 关键！
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
```

**❌ DON'T：过度使用 depends_on**
```hcl
# 不需要，vpc_id 已经建立隐式依赖
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id

  depends_on = [aws_vpc.main]  # ❌ 多余
}
```

### 2. 资源命名

**✅ DO：使用描述性前缀**
```hcl
resource "aws_lb_target_group" "blue" {
  name = "blue-tg"  # 清晰明了
}

resource "aws_autoscaling_group" "blue" {
  name_prefix = "blue-asg-"  # 自动添加唯一后缀
}
```

**❌ DON'T：使用泛型名称**
```hcl
resource "aws_lb_target_group" "main" {
  name = "tg"  # ❌ 不清楚用途
}
```

### 3. 变量设计

**✅ DO：提供合理的默认值**
```hcl
variable "blue_instance_count" {
  description = "Number of instances in Blue environment"
  type        = number
  default     = 2

  validation {
    condition     = var.blue_instance_count >= 0 && var.blue_instance_count <= 10
    error_message = "Instance count must be between 0 and 10"
  }
}
```

**❌ DON'T：硬编码值**
```hcl
resource "aws_autoscaling_group" "blue" {
  min_size = 2  # ❌ 应该使用变量
}
```

### 4. 蓝绿切换流程

**推荐的切换步骤**：

```bash
# 阶段 1: 部署 Green 环境
terraform apply -var="enable_green_env=true" -var="green_instance_count=2"

# 阶段 2: 灰度测试 (10% 流量到 Green)
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=90" \
  -var="green_target_weight=10"

# 监控 Green 环境指标...

# 阶段 3: 增加 Green 流量 (50%)
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=50" \
  -var="green_target_weight=50"

# 阶段 4: 完全切换到 Green (100%)
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_target_weight=0" \
  -var="green_target_weight=100"

# 阶段 5: 验证后下线 Blue
terraform apply \
  -var="enable_green_env=true" \
  -var="blue_instance_count=0"
```

### 5. 监控和日志

**推荐的监控点**：

```bash
# 1. Target Group 健康状态
aws elbv2 describe-target-health \
  --target-group-arn <TG-ARN>

# 2. ALB 请求数
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/app-alb/... \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum

# 3. Target 响应时间
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --statistics Average
```

### 6. 备份和恢复

**✅ DO：定期备份 Terraform 状态**
```bash
# 备份状态文件
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d)

# 使用远程状态（推荐）
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "blue-green/terraform.tfstate"
    region = "us-west-2"

    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### 7. 代码组织

**推荐的文件结构**：
```
terraform/
├── main.tf                 # Provider 配置
├── variables.tf            # 变量定义
├── outputs.tf              # 输出定义
├── shared.tf               # 共享资源（VPC, ALB, TG, Listener）
├── blue.tf                 # Blue 环境资源
├── green.tf                # Green 环境资源
├── terraform.tfvars        # 变量值（不提交到 Git）
├── terraform.tfvars.example # 变量示例
└── README.md               # 文档
```

---

## 📚 参考资料

### 官方文档

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html)
- [AWS Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)
- [Terraform depends_on](https://www.terraform.io/language/meta-arguments/depends_on)

### 相关文件

本项目包含以下辅助文件：

- `dependency-graph.dot` - 依赖关系图（销毁视角）
- `creation-flowchart.dot` - 创建流程图
- `BLUE_GREEN_DEPLOYMENT_GUIDE.md` - 本文档

### 可视化依赖图

```bash
# 安装 Graphviz
brew install graphviz

# 生成依赖关系图
dot -Tpng dependency-graph.dot -o dependency-graph.png

# 生成创建流程图
dot -Tpng creation-flowchart.dot -o creation-flowchart.png

# 打开图片
open dependency-graph.png
open creation-flowchart.png
```

---

## 🎯 总结

### 核心要点

1. **依赖关系是关键**
   - 使用 `depends_on` 明确控制创建和销毁顺序
   - ASG depends_on Listener 是解决销毁卡住的核心

2. **优化配置加速流程**
   - `deregistration_delay = 30` - 从 5 分钟降到 30 秒
   - `force_delete = true` - 强制删除保护
   - `timeout = 15m` - 超时保护

3. **创建流程约 3-4 分钟**
   - 7 个阶段，步骤清晰
   - 并行创建节省时间

4. **销毁流程约 2-3 分钟**
   - 严格按依赖顺序销毁
   - ASG → Rule → Listener → TG → ALB → VPC

5. **蓝绿部署灵活可靠**
   - 零停机更新
   - 灰度流量切换
   - 快速回滚

### 下一步

1. **测试创建流程**
   ```bash
   terraform plan
   terraform apply
   ```

2. **验证健康检查**
   ```bash
   curl http://<ALB-DNS>
   ```

3. **测试销毁流程**
   ```bash
   terraform destroy
   ```

4. **实施蓝绿切换**
   - 按照最佳实践逐步切换流量
   - 监控关键指标

5. **生产环境调优**
   - 根据实际负载调整参数
   - 配置告警和监控

---

**文档版本**: 1.0
**最后更新**: 2024-12-30
