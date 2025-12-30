resource "aws_launch_template" "blue" {
  name_prefix   = "blue-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/init-script.sh", {
    file_content = "blue version 1.0"
  }))

  # 确保 SG 存在后再创建
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_security_group.ec2
  ]
}

resource "aws_autoscaling_group" "blue" {
  name_prefix         = "blue-asg-"
  max_size            = var.blue_instance_count
  min_size            = var.blue_instance_count
  desired_capacity    = var.blue_instance_count
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.blue.arn]
  health_check_type   = "ELB"

  # 零中断创建的关键配置：
  # 等待至少 blue_instance_count 个实例在 TG 中状态为 healthy
  # Terraform 会轮询 TG 健康状态，确保实例完全就绪后才返回
  min_elb_capacity          = var.blue_instance_count
  wait_for_elb_capacity     = var.blue_instance_count
  wait_for_capacity_timeout = "10m"  # 给实例充足时间启动和健康检查

  # 强制删除 ASG，即使实例未完全终止（仅用于销毁）
  force_delete = true

  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "blue"
    propagate_at_launch = true
  }

  # 确保蓝绿部署零停机，ASG 在 TG 之前删除
  lifecycle {
    create_before_destroy = true
  }

  # 设置销毁超时为 15 分钟，避免无限等待
  timeouts {
    delete = "15m"
  }

  # 关键变更：移除对 Listener 的依赖，避免循环
  # Listener 会依赖 Blue ASG，确保实例就绪后才创建流量路由
  #
  # 销毁顺序（由 Listener depends_on Blue ASG 控制）：
  # 1. Blue ASG 先销毁（实例终止、注销 30s）
  # 2. Listener 后销毁
  # 3. Target Groups 最后销毁
  depends_on = [
    aws_lb_target_group.blue,
    aws_launch_template.blue
  ]
}
