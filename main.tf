# Proveedor AWS
provider "aws" {
  region = var.aws_region
  profile = var.profile_name
}

# VPC y Networking
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  tags = { Name = "Main-VPC-ALB" }
}

# Subredes públicas para ALB
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(["${var.aws_region}a", "${var.aws_region}b"], count.index)
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-ALB-${count.index + 1}" }
}

# Subredes privadas para instancias
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(["${var.aws_region}a", "${var.aws_region}b"], count.index)
  tags = { Name = "Private-Subnet-ALB-${count.index + 1}" }
}


# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "IGW-ALB" }
}

# NAT Gateway 
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "EIP-NAT-ALB"}
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "NAT-Gateway-ALB" }
}

 # Tablas de Rutas
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public-RouteTable" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "Private-RouteTable" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group para App Instances
resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  vpc_id      = aws_vpc.main.id
  description = "Permitir acceso HTTP desde NGINX Core"
  tags = { Name = "APP-SG"
  component = "networking"
  }
}


# Security Group para ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Permitir HTTP a ALB"
  tags = { Name = "ALB-SG"
  component = "networking"
  }
}

# Security Group para NGINX Core (ASG)
resource "aws_security_group" "nginx_core_sg" {
  name        = "nginx-core-sg"
  vpc_id      = aws_vpc.main.id
  description = "Permitir acceso HTTP desde ALB y SSH desde mi IP"
  tags = { Name = "NGINX-Core-SG"
  component = "networking"
  }
}

## ALB
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.alb_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

## NGINX Core
resource "aws_security_group_rule" "nginx_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nginx_core_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "nginx_ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.nginx_core_sg.id
  cidr_blocks       = [var.my_ip]
}

resource "aws_security_group_rule" "nginx_egress_to_app" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nginx_core_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "nginx_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.nginx_core_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

## App Servers
resource "aws_security_group_rule" "app_ingress_from_nginx" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.nginx_core_sg.id
}

resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.app_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}


# ALB
resource "aws_lb" "nginx_alb" {
  name               = "nginx-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
    tags = {
    Name = "nginx-alb"
  }
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

    tags = {
    Name = "nginx-tg"
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

  user_data = base64encode(templatefile("${path.module}/nginx_userdata.tpl", {
    app1_ip = aws_instance.app_servers[0].private_ip
    app2_ip = aws_instance.app_servers[1].private_ip
    app3_ip = aws_instance.app_servers[2].private_ip
    }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "nginx-core"
    }
  }
  # El launch template no se creara hasta que las instancias tengan IP
  depends_on = [aws_instance.app_servers]
}

resource "aws_autoscaling_group" "nginx_core_asg" {
  name_prefix          = "nginx-core-asg-"
  vpc_zone_identifier  = aws_subnet.public[*].id
  min_size             = 1
  max_size             = 4
  desired_capacity     = 1
  target_group_arns    = [aws_lb_target_group.nginx_tg.arn]

  launch_template {
    id      = aws_launch_template.nginx_core.id
    version = "$Latest"
  }

    tag {
    key                 = "Name"
    value               = "nginx-core"
    propagate_at_launch = true
  }
}

# Instancias App
resource "aws_instance" "app_servers" {
  count         = length(var.app_instances)
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[count.index % length(var.public_subnets)].id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo amazon-linux-extras enable nginx1
    sudo yum install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
    sudo echo "<h1>${var.app_instances[count.index]}</h1>" > /usr/share/nginx/html/index.html
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