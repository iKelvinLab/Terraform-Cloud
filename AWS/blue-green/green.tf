resource "aws_launch_template" "green" {
  name_prefix   = "green-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/init-script.sh", {
    file_content = "green version 1.0"
  }))

  # 确保 SG 存在后再创建
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_security_group.ec2
  ]
}

resource "aws_autoscaling_group" "green" {
  count               = var.enable_green_env ? 1 : 0
  name_prefix         = "green-asg-"
  max_size            = var.green_instance_count
  min_size            = var.green_instance_count
  desired_capacity    = var.green_instance_count
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.green.arn]
  health_check_type   = "ELB"

  # 零中断创建的关键配置：
  # 等待至少 green_instance_count 个实例在 TG 中状态为 healthy
  # 如果 green_instance_count = 0，则跳过等待（直接返回）
  min_elb_capacity          = var.green_instance_count
  wait_for_elb_capacity     = var.green_instance_count
  wait_for_capacity_timeout = "10m"  # 给实例充足时间启动和健康检查

  # 强制删除 ASG，即使实例未完全终止（仅用于销毁）
  force_delete = true

  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "green"
    propagate_at_launch = true
  }

  # Green ASG 还需依赖 canary rule
  lifecycle {
    create_before_destroy = true
  }

  # 设置销毁超时为 15 分钟，避免无限等待
  timeouts {
    delete = "15m"
  }

  # 关键变更：移除对 Listener 和 Rule 的依赖，避免循环
  # Canary Rule 会依赖 Green ASG（通过条件），确保实例就绪后才创建规则
  #
  # 销毁顺序（由 Canary Rule depends_on 控制）：
  # 1. Green ASG 先销毁（实例终止、注销 30s）
  # 2. Canary Rule 后销毁
  # 3. Listener 再销毁
  # 4. Target Groups 最后销毁
  depends_on = [
    aws_lb_target_group.green,
    aws_launch_template.green
  ]
}
