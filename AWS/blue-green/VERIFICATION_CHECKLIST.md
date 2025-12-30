# 零中断创建验证清单

## 快速验证步骤

### 第 1 步：验证 Terraform 配置

```bash
cd AWS

# 验证语法
terraform validate

# 期望输出：
# ✅ Success! The configuration is valid.
```

### 第 2 步：检查关键配置

#### Blue ASG 配置检查

```bash
# 检查 Blue ASG 是否配置了等待实例健康
grep -A 3 "wait_for_elb_capacity" blue.tf

# 期望输出：
# min_elb_capacity          = var.blue_instance_count
# wait_for_elb_capacity     = var.blue_instance_count
# wait_for_capacity_timeout = "10m"
```

```bash
# 检查 Blue ASG 是否移除了对 Listener 的依赖
grep -A 5 "depends_on" blue.tf | grep -v "aws_lb_listener.http"

# 期望输出：应该没有 aws_lb_listener.http
```

#### Listener 配置检查

```bash
# 检查 Listener 是否添加了对 Blue ASG 的依赖
grep -A 5 "depends_on" shared.tf | grep "aws_autoscaling_group.blue"

# 期望输出：
# aws_autoscaling_group.blue  # 关键：等待 Blue 实例就绪
```

### 第 3 步：查看执行计划

```bash
# 查看 Terraform 执行计划
terraform plan

# 检查关键点：
# 1. Blue ASG 应该在 Listener 之前创建
# 2. 没有循环依赖错误
# 3. 资源创建顺序正确
```

### 第 4 步：创建基础设施（实际测试）

```bash
# 开始创建（首次部署）
time terraform apply -auto-approve

# 观察关键日志：
# 1. Blue ASG 创建时应该显示 "Still creating..." 约 2-3 分钟
# 2. Listener 应该在 ASG 之后创建（约 5 秒）
```

**关键观察点**：

```
# 期望看到的日志顺序：
aws_launch_template.blue: Creating...
aws_launch_template.blue: Creation complete after 1s

aws_autoscaling_group.blue: Creating...
aws_autoscaling_group.blue: Still creating... [10s elapsed]
aws_autoscaling_group.blue: Still creating... [20s elapsed]
...
aws_autoscaling_group.blue: Still creating... [2m0s elapsed]
aws_autoscaling_group.blue: Creation complete after 2m15s  ← Terraform 等待实例健康

aws_lb_listener.http: Creating...  ← 在 ASG 之后创建
aws_lb_listener.http: Creation complete after 3s
```

### 第 5 步：验证 Target Group 健康状态

```bash
# 获取 Blue Target Group ARN
BLUE_TG_ARN=$(terraform output -raw blue_tg_arn)

# 检查健康状态
aws elbv2 describe-target-health \
  --target-group-arn $BLUE_TG_ARN \
  --region us-west-2 \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# 期望输出：所有实例状态都是 "healthy"
# +-----------------------+---------+
# |DescribeTargetHealth   |         |
# +-----------------------+---------+
# |  i-0abc123def456789   |  healthy|
# |  i-0def456abc123789   |  healthy|
# +-----------------------+---------+
```

### 第 6 步：验证零中断（关键）

```bash
# 获取 ALB DNS 名称
ALB_DNS=$(terraform output -raw alb_dns_name)

# 立即测试 ALB（应该立即返回 200 OK）
curl -v http://$ALB_DNS

# 期望输出：
# < HTTP/1.1 200 OK  ← 立即返回 200，无 503 错误 ✅
# < Content-Type: text/html
# ...
# Welcome to Blue Environment!

# 测试多次，确保稳定
for i in {1..10}; do
  STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://$ALB_DNS)
  echo "请求 $i: HTTP $STATUS"
done

# 期望输出：所有请求都是 200 OK
# 请求 1: HTTP 200
# 请求 2: HTTP 200
# ...
# 请求 10: HTTP 200
```

### 第 7 步：验证销毁顺序

```bash
# 销毁基础设施
time terraform destroy -auto-approve

# 观察关键日志：
# 1. Listener 应该先销毁
# 2. Blue ASG 应该在 Listener 之后销毁
# 3. 销毁过程应该顺利完成（约 2-3 分钟）
```

**关键观察点**：

```
# 期望看到的日志顺序：
aws_lb_listener_rule.canary[0]: Destroying...
aws_lb_listener_rule.canary[0]: Destruction complete after 2s

aws_lb_listener.http: Destroying...  ← Listener 先销毁
aws_lb_listener.http: Destruction complete after 2s

aws_autoscaling_group.blue: Destroying...  ← ASG 后销毁
aws_autoscaling_group.blue: Still destroying... [10s elapsed]
aws_autoscaling_group.blue: Still destroying... [30s elapsed]  ← 等待实例注销
aws_autoscaling_group.blue: Destruction complete after 45s

aws_lb_target_group.blue: Destroying...  ← TG 最后销毁
aws_lb_target_group.blue: Destruction complete after 1s

# ✅ 销毁完成，无卡住现象
```

## 验证清单总结

### 配置验证 ✅

- [ ] `terraform validate` 通过
- [ ] Blue ASG 配置了 `wait_for_elb_capacity = var.blue_instance_count`
- [ ] Blue ASG 配置了 `wait_for_capacity_timeout = "10m"`
- [ ] Blue ASG 移除了对 `aws_lb_listener.http` 的依赖
- [ ] Listener 添加了对 `aws_autoscaling_group.blue` 的依赖
- [ ] Green ASG 同样配置（如果启用）
- [ ] `terraform plan` 无循环依赖错误

### 创建验证 ✅

- [ ] Blue ASG 创建时显示 "Still creating..." 约 2-3 分钟
- [ ] Listener 在 ASG 之后创建（日志顺序正确）
- [ ] Target Group 中所有实例状态为 "healthy"
- [ ] 访问 ALB DNS 立即返回 200 OK
- [ ] 多次请求都返回 200 OK（无 503 错误）
- [ ] 总创建时间约 3-4 分钟

### 销毁验证 ✅

- [ ] Listener 先销毁
- [ ] Blue ASG 后销毁（约 30-60 秒）
- [ ] Target Groups 最后销毁
- [ ] 销毁过程顺利完成（无卡住）
- [ ] 总销毁时间约 2-3 分钟

## 常见问题排查

### 问题 1：terraform validate 失败

**症状**：
```
Error: Invalid reference
```

**解决方案**：
```bash
# 检查语法错误
terraform fmt
terraform validate
```

### 问题 2：Blue ASG 创建超时

**症状**：
```
Error: timeout while waiting for capacity
```

**可能原因**：
1. 实例启动慢（User Data 脚本耗时）
2. 健康检查失败（nginx 未正常启动）
3. Security Group 阻止健康检查

**排查步骤**：
```bash
# 1. 检查实例状态
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=blue" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table

# 2. 检查实例日志
aws ec2 get-console-output --instance-id <instance-id>

# 3. 登录实例排查
ssh -i your-key.pem ubuntu@<instance-ip>
sudo systemctl status nginx
curl localhost
```

**解决方案**：
```hcl
# 增加 timeout
wait_for_capacity_timeout = "15m"

# 或者增加健康检查宽容度
health_check {
  interval            = 30  # 增加间隔
  unhealthy_threshold = 3   # 增加不健康阈值
}
```

### 问题 3：访问 ALB 返回 503

**症状**：
```bash
curl http://<alb-dns>
# 返回 503 Service Temporarily Unavailable
```

**可能原因**：
1. Target Group 中无健康实例
2. Security Group 配置错误
3. nginx 未正常启动

**排查步骤**：
```bash
# 1. 检查 Target Group 健康状态
aws elbv2 describe-target-health \
  --target-group-arn <blue-tg-arn>

# 2. 检查 Security Group 规则
aws ec2 describe-security-groups \
  --group-ids <ec2-sg-id> \
  --query 'SecurityGroups[*].IpPermissions'

# 3. 检查实例上的 nginx
ssh -i your-key.pem ubuntu@<instance-ip>
sudo systemctl status nginx
sudo netstat -tlnp | grep :80
```

### 问题 4：循环依赖错误

**症状**：
```
Error: Cycle: aws_lb_listener.http, aws_autoscaling_group.blue
```

**原因**：Blue ASG 依然依赖 Listener

**解决方案**：
```bash
# 检查 Blue ASG 的 depends_on
grep -A 5 "depends_on" blue.tf

# 确保移除了 aws_lb_listener.http
# 正确配置应该是：
depends_on = [
  aws_lb_target_group.blue,
  aws_launch_template.blue
]
```

### 问题 5：销毁卡住

**症状**：
```
aws_autoscaling_group.blue: Still destroying... [10m0s elapsed]
```

**可能原因**：
1. deregistration_delay 太长
2. 实例有保护（Protected from scale-in）

**排查步骤**：
```bash
# 1. 检查 ASG 状态
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <asg-name>

# 2. 手动缩容
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <asg-name> \
  --min-size 0 --max-size 0 --desired-capacity 0

# 3. 强制删除
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name <asg-name> \
  --force-delete
```

## 性能基准

### 创建时间基准（参考）

| 阶段 | 预期时间 | 实际时间（填写）|
|------|----------|----------------|
| VPC 和网络层 | 0-30s | |
| 安全组层 | 30-45s | |
| ALB 层 | 45-90s | |
| Target Groups | 90-100s | |
| Launch Templates | 100-110s | |
| Blue ASG（等待健康）| 110-180s | |
| Listener | 180-185s | |
| **总计** | **3-4 分钟** | |

### 销毁时间基准（参考）

| 阶段 | 预期时间 | 实际时间（填写）|
|------|----------|----------------|
| Listener/Rule | 0-5s | |
| Blue ASG（注销）| 5-60s | |
| Launch Templates | 60-65s | |
| Target Groups | 65-70s | |
| ALB | 70-75s | |
| 网络层 | 75-120s | |
| **总计** | **2-3 分钟** | |

## 成功标准

### 零中断标准 ✅

1. **创建时**：
   - [ ] Listener 在 Blue ASG 之后创建
   - [ ] 访问 ALB DNS 立即返回 200 OK
   - [ ] 无 503 Service Unavailable 错误
   - [ ] Target Group 中至少 2 个实例状态为 healthy

2. **销毁时**：
   - [ ] Listener 先销毁
   - [ ] Blue ASG 后销毁（约 30-60 秒）
   - [ ] 销毁过程顺利完成（无卡住）

3. **性能标准**：
   - [ ] 创建时间：3-4 分钟
   - [ ] 销毁时间：2-3 分钟
   - [ ] 业务中断时间：0 秒 ✅

## 下一步

### 如果验证通过 ✅

1. **提交代码**：
   ```bash
   git add .
   git commit -m "feat: implement zero-downtime creation strategy"
   git push
   ```

2. **更新文档**：
   - 阅读 `ZERO_DOWNTIME_DEPLOYMENT.md`
   - 阅读 `IMPLEMENTATION_SUMMARY.md`

3. **生产环境配置**（可选）：
   ```hcl
   # 调整生产环境参数
   force_delete = false
   wait_for_capacity_timeout = "15m"
   deregistration_delay = 60
   ```

### 如果验证失败 ❌

1. **查看日志**：
   ```bash
   terraform apply 2>&1 | tee terraform-apply.log
   ```

2. **排查问题**：
   - 参考上面的"常见问题排查"
   - 检查 CloudWatch Logs
   - 查看实例日志

3. **寻求帮助**：
   - 查看 `BLUE_GREEN_DEPLOYMENT_GUIDE.md` 的"故障排除指南"
   - 查看 Terraform 官方文档

---

**验证日期**: _________________
**验证人员**: _________________
**验证结果**: [ ] 通过 / [ ] 失败
**备注**: _________________________________
