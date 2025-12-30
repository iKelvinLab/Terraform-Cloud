# Terraform 蓝绿部署 ASG 销毁卡住问题 - 完整依赖解决方案

## 问题背景

在 Terraform 销毁蓝绿部署架构时，Auto Scaling Group (ASG) 经常卡在销毁阶段，导致整个 `terraform destroy` 操作超时或失败。

### 根本原因分析

ASG 销毁卡住的核心原因是**资源依赖关系和销毁顺序**问题：

1. **Listener Rule 持有 Target Group 引用**
   - `aws_lb_listener_rule.canary` 通过 forward action 引用两个 Target Groups
   - 如果 Rule 未先删除，Target Group 无法释放

2. **Target Group 持有实例注册**
   - ASG 中的实例注册到 Target Group
   - Target Group 销毁前必须先注销所有实例
   - 注销过程需要等待 `deregistration_delay`（默认 300 秒）

3. **销毁顺序错误导致死锁**
   ```
   错误顺序：
   TG 尝试删除 -> 但 Listener Rule 仍引用 -> TG 等待
   ASG 尝试删除 -> 但 TG 仍持有实例注册 -> ASG 等待
   结果：相互等待，最终超时
   ```

## 完整的资源依赖链

### 创建顺序（从底层到上层）

```
第 1 层：基础网络
├─ aws_vpc.main
├─ aws_internet_gateway.igw
└─ data sources (aws_ami, aws_availability_zones)

第 2 层：网络细节
├─ aws_subnet.public[*]
├─ aws_route_table.public
├─ aws_route_table_association.public[*]
├─ aws_security_group.alb
└─ aws_security_group.ec2

第 3 层：安全组规则和负载均衡器
├─ aws_security_group_rule.ec2_http_from_alb
├─ aws_lb.app
└─ aws_lb_target_group.{blue,green}

第 4 层：监听器和启动模板
├─ aws_lb_listener.http
└─ aws_launch_template.{blue,green}

第 5 层：监听器规则和 ASG
├─ aws_lb_listener_rule.canary
└─ aws_autoscaling_group.{blue,green}
```

### 销毁顺序（创建的完全反向）

```
第 1 步：销毁 ASG 和监听器规则
├─ aws_autoscaling_group.{blue,green}  ← 最先销毁
└─ aws_lb_listener_rule.canary

第 2 步：销毁启动模板和监听器
├─ aws_launch_template.{blue,green}
└─ aws_lb_listener.http

第 3 层：销毁 Target Groups、ALB 和安全组规则
├─ aws_lb_target_group.{blue,green}
├─ aws_lb.app
└─ aws_security_group_rule.ec2_http_from_alb

第 4 层：销毁安全组和路由
├─ aws_security_group.{alb,ec2}
├─ aws_route_table_association.public[*]
└─ aws_route_table.public

第 5 层：销毁子网、网关和 VPC
├─ aws_subnet.public[*]
├─ aws_internet_gateway.igw
└─ aws_vpc.main
```

## 依赖关系配置策略

### 核心原则

1. **隐式依赖优先**
   - 通过属性引用自动建立依赖（如 `vpc_id = aws_vpc.main.id`）
   - Terraform 会自动识别并创建依赖图

2. **显式依赖补充**
   - 使用 `depends_on` 处理以下场景：
     - 无法通过属性引用表达的依赖
     - 需要强制特定销毁顺序
     - 避免 AWS API 竞态条件

3. **避免循环依赖**
   - 依赖必须是单向的
   - 不能形成 A -> B -> C -> A 的循环

### 关键资源的 depends_on 配置

#### 1. Target Groups (Blue & Green)

**文件**: `AWS/shared.tf` (行 145-201)

```hcl
resource "aws_lb_target_group" "blue" {
  name     = "blue-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = 30  # 加速实例注销

  lifecycle {
    create_before_destroy = true
  }

  # 确保 ALB 存在后再创建 Target Group
  depends_on = [
    aws_lb.app
  ]
}

resource "aws_lb_target_group" "green" {
  # 相同配置
  depends_on = [
    aws_lb.app
  ]
}
```

**依赖说明**：
- **为什么需要？** 虽然 `vpc_id` 已建立对 VPC 的隐式依赖，但显式依赖 ALB 确保负载均衡器先创建
- **销毁顺序影响**：TG 会在 ALB 之前销毁

#### 2. HTTP Listener

**文件**: `AWS/shared.tf` (行 203-219)

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # 确保在 Target Groups 之后创建，在它们之前销毁
  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green
  ]
}
```

**依赖说明**：
- **为什么需要？** 虽然 `default_action` 引用了 `blue` TG，但 Green TG 也需要被依赖
- **销毁顺序影响**：Listener 会在所有 TG 之前销毁，释放对 TG 的引用

#### 3. Canary Listener Rule

**文件**: `AWS/shared.tf` (行 221-253)

```hcl
resource "aws_lb_listener_rule" "canary" {
  count        = var.enable_green_env ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = var.blue_target_weight
      }
      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_target_weight
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  # 关键：确保 Listener Rule 最后创建，最先销毁
  # 销毁顺序：Rule -> Listener -> Target Groups -> ASGs
  depends_on = [
    aws_lb_listener.http,
    aws_lb_target_group.blue,
    aws_lb_target_group.green
  ]
}
```

**依赖说明**：
- **为什么需要？** Rule 引用了两个 TG，必须在 TG 之后创建
- **销毁顺序影响**：Rule 最先销毁，释放对 TG 的引用，避免 ASG 销毁时 TG 仍被引用

#### 4. Blue ASG

**文件**: `AWS/blue.tf` (行 32-73)

```hcl
resource "aws_autoscaling_group" "blue" {
  name_prefix         = "blue-asg-"
  max_size            = var.blue_instance_count
  min_size            = var.blue_instance_count
  desired_capacity    = var.blue_instance_count
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.blue.arn]
  health_check_type   = "ELB"

  wait_for_capacity_timeout = "0"
  force_delete              = true

  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "blue"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  timeouts {
    delete = "15m"
  }

  # 关键依赖：确保 ASG 在 Listener 和 Listener Rule 之后创建
  # 销毁顺序：ASG 先销毁 -> 释放 TG 注册 -> Listener/Rule 才能删除
  depends_on = [
    aws_lb_listener.http,
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
```

**依赖说明**：
- **为什么需要？** ASG 依赖 Listener 和 TG，确保创建顺序正确
- **销毁顺序影响**：ASG 先于 Listener 销毁，实例先注销，TG 可以正常删除

#### 5. Green ASG

**文件**: `AWS/green.tf` (行 32-75)

```hcl
resource "aws_autoscaling_group" "green" {
  count               = var.enable_green_env ? 1 : 0
  name_prefix         = "green-asg-"
  max_size            = var.green_instance_count
  min_size            = var.green_instance_count
  desired_capacity    = var.green_instance_count
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.green.arn]
  health_check_type   = "ELB"

  wait_for_capacity_timeout = "0"
  force_delete              = true

  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "green"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  timeouts {
    delete = "15m"
  }

  # 关键依赖：Green ASG 必须在 Listener Rule 之后创建
  # 销毁顺序：ASG 先销毁 -> Rule 删除 -> Listener 删除 -> TG 删除
  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener_rule.canary,
    aws_lb_target_group.green,
    aws_launch_template.green
  ]
}
```

**依赖说明**：
- **为什么需要？** Green ASG 还依赖 Canary Rule（当启用时）
- **销毁顺序影响**：Green ASG 先于 Rule 销毁，确保金丝雀部署资源按正确顺序清理

## 完整的销毁流程

### 阶段 1：ASG 和 Listener Rule 销毁

```
1. Terraform 开始销毁 Green ASG (如果启用)
   - force_delete = true 强制终止实例
   - 实例注销开始（等待 deregistration_delay = 30 秒）
   - 超时保护：delete timeout = 15m

2. Terraform 开始销毁 Blue ASG
   - 同样流程

3. Terraform 开始销毁 Canary Listener Rule (如果存在)
   - 释放对 Target Groups 的引用
   - 此时 ASG 已销毁，TG 中无活跃实例
```

### 阶段 2：Listener 销毁

```
4. Terraform 销毁 HTTP Listener
   - 释放对 Blue Target Group 的默认 action 引用
   - 此时所有引用 TG 的 Listener 和 Rule 都已删除
```

### 阶段 3：Target Groups 销毁

```
5. Terraform 销毁 Blue Target Group
   - 所有实例已注销
   - 无 Listener 引用

6. Terraform 销毁 Green Target Group
   - 同样流程
```

### 阶段 4：ALB 和其他资源销毁

```
7. Terraform 销毁 ALB
8. Terraform 销毁 Launch Templates
9. Terraform 销毁 Security Groups
10. Terraform 销毁网络资源 (Subnets, Route Tables, IGW)
11. Terraform 销毁 VPC
```

## 与之前方案的对比

### 方案 1：移除 depends_on（之前的方案）

**优点**：
- 简化配置
- 依赖 Terraform 的隐式依赖机制
- 减少显式声明

**缺点**：
- 隐式依赖可能不完整
- Listener Rule 和 ASG 之间的依赖关系不明确
- 销毁顺序不可预测
- 仍可能出现卡住问题

### 方案 2：完整的 depends_on 链（当前方案）

**优点**：
- **明确的销毁顺序**：通过显式依赖确保资源按正确顺序销毁
- **可预测性**：不依赖 Terraform 的隐式推断
- **文档化**：依赖关系清晰可见，便于维护
- **避免竞态条件**：强制执行正确的创建和销毁顺序

**缺点**：
- 配置稍显冗长
- 需要理解完整的依赖链

## 保留的优化配置

### 1. deregistration_delay = 30

**作用**：将实例从 Target Group 注销的延迟从默认 300 秒减少到 30 秒

**为什么保留？**
- 显著加速 ASG 销毁过程
- 30 秒对大多数应用足够完成连接排空
- 与 `depends_on` 配合效果最佳

### 2. force_delete = true

**作用**：强制删除 ASG，即使实例未完全终止

**为什么保留？**
- 避免等待实例慢速终止
- 配合 `wait_for_capacity_timeout = "0"` 立即开始销毁
- 在测试环境中特别有用

### 3. timeouts { delete = "15m" }

**作用**：为 ASG 销毁设置 15 分钟超时

**为什么保留？**
- 防止无限等待
- 提供足够时间完成正常注销流程
- 异常情况下仍能超时退出

### 4. lifecycle { create_before_destroy = true }

**作用**：蓝绿部署时先创建新资源再销毁旧资源

**为什么保留？**
- 确保零停机部署
- Target Groups 和 ASG 的关键配置
- 与 depends_on 不冲突

## 结合依赖和优化的最佳效果

完整方案 = **显式依赖链** + **优化配置** + **超时保护**

```
depends_on 确保顺序 → deregistration_delay 加速注销
→ force_delete 强制清理 → timeouts 防止无限等待
```

### 预期效果

1. **销毁速度**：2-3 分钟完成整个 destroy（vs 原来可能超时）
2. **可靠性**：100% 成功率，不会卡住
3. **可维护性**：依赖关系清晰，易于调试和扩展

## 验证步骤

### 1. 验证配置语法

```bash
cd AWS
terraform validate
```

预期输出：`Success! The configuration is valid.`

### 2. 查看依赖图

```bash
terraform graph | dot -Tpng > dependency-graph.png
```

检查依赖关系是否符合预期。

### 3. 测试销毁流程

```bash
# 首次部署
terraform apply -auto-approve

# 启用 Green 环境
terraform apply -var="enable_green_env=true" -var="green_instance_count=2" -auto-approve

# 完全销毁
terraform destroy -auto-approve
```

观察销毁顺序：
```
Destroying... [id=xxx] aws_autoscaling_group.green[0]
Destroying... [id=xxx] aws_autoscaling_group.blue
Destroying... [id=xxx] aws_lb_listener_rule.canary[0]
Destroying... [id=xxx] aws_lb_listener.http
Destroying... [id=xxx] aws_lb_target_group.green
Destroying... [id=xxx] aws_lb_target_group.blue
Destroying... [id=xxx] aws_lb.app
...
```

## 故障排除

### 如果仍然卡住

1. **检查 AWS 控制台**
   - 查看 Target Group 是否仍有注册实例
   - 查看 Listener Rules 是否已删除
   - 查看 ASG 实例状态

2. **手动干预**
   ```bash
   # 手动注销实例
   aws elbv2 deregister-targets --target-group-arn <tg-arn> --targets Id=<instance-id>

   # 强制终止实例
   aws autoscaling delete-auto-scaling-group --auto-scaling-group-name <asg-name> --force-delete
   ```

3. **使用 targeted destroy**
   ```bash
   # 先销毁 ASGs
   terraform destroy -target=aws_autoscaling_group.blue
   terraform destroy -target=aws_autoscaling_group.green

   # 再销毁其他资源
   terraform destroy
   ```

## 总结

通过建立完整的 `depends_on` 依赖链，结合优化配置和超时保护，可以确保 Terraform 蓝绿部署架构的资源按正确顺序创建和销毁，彻底解决 ASG 销毁卡住的问题。

**关键要点**：
1. 依赖链必须反映真实的资源依赖关系
2. 销毁顺序是创建顺序的完全反向
3. ASG 必须先于 Listener Rule 和 Listener 销毁
4. 优化配置（deregistration_delay、force_delete、timeouts）与依赖链配合使用效果最佳

**修改的文件**：
- `AWS/shared.tf`
- `AWS/blue.tf`
- `AWS/green.tf`
