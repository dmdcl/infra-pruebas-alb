# Proveedor AWS
provider "aws" {
  region = var.aws_region
  profile = "diegopocgob"
}

# VPC y Networking
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  tags = { Name = "Main-VPC" }
}

# Subredes públicas para ALB
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(["${var.aws_region}a", "${var.aws_region}b"], count.index)
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-${count.index + 1}" }
}

# Subredes privadas para instancias
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(["${var.aws_region}a", "${var.aws_region}b"], count.index)
  tags = { Name = "Private-Subnet-${count.index + 1}" }
}

# Security Group para ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP to ALB"

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
}

# Security Group para NGINX Core (ASG)
resource "aws_security_group" "nginx_core_sg" {
  name        = "nginx-core-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP from ALB and SSH from my IP"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Nueva regla: NGINX Core puede acceder a las Apps
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
}

# Security Group para App Instances
resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP from NGINX Core"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx_core_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB
resource "aws_lb" "nginx_alb" {
  name               = "nginx-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# Target Group para NGINX Core
resource "aws_lb_target_group" "nginx_tg" {
  name     = "nginx-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

# Listener ALB
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.nginx_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_tg.arn
  }
}

# Auto Scaling Group para NGINX Core
resource "aws_launch_template" "nginx_core" {
  name_prefix   = "nginx-core-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.nginx_core_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>NGINX Core $(hostname)</h1>
    <p><a href='/app1'>App1</a> | <a href='/app2'>App2</a> | <a href='/app3'>App3</a></p>" > /usr/share/nginx/html/index.html

    # Configuración proxy para las apps
    cat > /etc/nginx/conf.d/apps.conf <<'CONF'
    location /app1 {
      proxy_pass http://${aws_instance.app_servers[0].private_ip};
    }
    location /app2 {
      proxy_pass http://${aws_instance.app_servers[1].private_ip};
    }
    location /app3 {
      proxy_pass http://${aws_instance.app_servers[2].private_ip};
    }
    CONF
    systemctl restart nginx
  EOF
  )
}

resource "aws_autoscaling_group" "nginx_core_asg" {
  name_prefix          = "nginx-core-asg-"
  vpc_zone_identifier  = aws_subnet.private[*].id
  min_size             = 2
  max_size             = 4
  desired_capacity     = 2
  target_group_arns    = [aws_lb_target_group.nginx_tg.arn]

  launch_template {
    id      = aws_launch_template.nginx_core.id
    version = "$Latest"
  }
}

# Instancias App
resource "aws_instance" "app_servers" {
  count         = length(var.app_instances)
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private[count.index % length(var.private_subnets)].id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx
    systemctl start nginx
    echo "<h1>${var.app_instances[count.index]}</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = var.app_instances[count.index]
  }
}

# Data source para AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}