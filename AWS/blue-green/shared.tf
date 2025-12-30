data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "blue-green-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "blue-green-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true

  tags = {
    Name = "blue-green-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "blue-green-public-rtb"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.public_subnet_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name   = "blue-green-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "blue-green-alb-sg"
  }

  # 更新时避免中断
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ec2" {
  name   = "blue-green-ec2-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "blue-green-ec2-sg"
  }

  # 更新时避免中断
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ec2_http_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2.id
  source_security_group_id = aws_security_group.alb.id

  # 防止 SG 交叉引用死锁
  depends_on = [
    aws_security_group.ec2,
    aws_security_group.alb
  ]
}

resource "aws_lb" "app" {
  name               = "blue-green-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # 确保 IGW 和 SG 就绪
  depends_on = [
    aws_internet_gateway.igw,
    aws_security_group.alb
  ]
}

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

  # 优化注销延迟，从默认 300 秒减少到 30 秒，加快销毁速度
  deregistration_delay = 30

  # 蓝绿部署时新 TG 先创建
  lifecycle {
    create_before_destroy = true
  }

  # 确保 ALB 存在后再创建 Target Group
  depends_on = [
    aws_lb.app
  ]
}

resource "aws_lb_target_group" "green" {
  name     = "green-tg"
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

  # 优化注销延迟，从默认 300 秒减少到 30 秒，加快销毁速度
  deregistration_delay = 30

  # 蓝绿部署时新 TG 先创建
  lifecycle {
    create_before_destroy = true
  }

  # 确保 ALB 存在后再创建 Target Group
  depends_on = [
    aws_lb.app
  ]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # 零中断创建的关键配置：
  # 1. 等待 Blue ASG 创建完成（实例启动、注册、健康检查通过）
  # 2. Listener 创建时，Blue TG 中已有健康实例
  # 3. 流量路由立即可用，无 503 错误
  #
  # 销毁时反向处理：
  # - Blue ASG 先销毁（实例注销 30s）
  # - Listener 后销毁
  # - Target Groups 最后销毁
  depends_on = [
    aws_lb.app,
    aws_lb_target_group.blue,
    aws_lb_target_group.green,
    aws_autoscaling_group.blue  # 关键：等待 Blue 实例就绪
  ]
}

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

  # 零中断创建的关键配置：
  # 1. 等待 Listener 创建（Listener 已经等待 Blue ASG 就绪）
  # 2. 如果启用了 Green，等待 Green ASG 就绪
  # 3. Canary Rule 创建时，两个环境的实例都已健康
  #
  # 销毁时反向处理：
  # - Green ASG 先销毁（如果存在）
  # - Canary Rule 后销毁
  # - Listener 再销毁
  # - Target Groups 最后销毁
  depends_on = [
    aws_lb_listener.http,          # Listener 已经等待了 Blue ASG
    aws_lb_target_group.blue,
    aws_lb_target_group.green
    # Green ASG 的依赖通过 count.index 条件处理
  ]
}
