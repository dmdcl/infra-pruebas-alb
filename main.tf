# Proveedor AWS
provider "aws"{
region = var.aws_region
profile = "diegopocgob"
}

#1. VPC
resource "aws_vpc" "main" {
    cidr_block = var.vpc_cidr
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = {
        Name = "Main-VPC"
    }
}

#2. Subredes Publicas
resource "aws_subnet" "public" {
    count = length(var.public_subnets)
    vpc_id = aws_vpc.main.id
    cidr_block = var.public_subnets[count.index]
    availability_zone = var.azs[count.index]
    map_public_ip_on_launch = true
    tags = {
        Name = "Subred Publica-${count.index + 1}"
    }
}

#3. Subredes Privadas
resource "aws_subnet" "private" {
    count = length (var.private_subnets)
    vpc_id = aws_vpc.main.id 
    cidr_block = var.private_subnets[count.index]
    availability_zone = var.azs[count.index]
    tags = {
        Name = "Subred Privada-${count.index + 1}"
    }
}

#4. Internet Gateway
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "Main-IGW"
    }
}

#5. NAT Gateway
resource "aws_eip" "nat" {
    domain = "vpc"
}

resource "aws_nat_gateway" "main" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public[0].id 
    tags = {
        Name = "Main NAT"
    }
}

#6. Tabla de rutas
## Publica
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "Public-RouteTable"
    }
}

## Privada
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat.id 
    }
    tags = {
        Name = "Private-RouteTable"
    }
}

## Asociaciones 
resource "aws_route_table_association" "public" {
    count = length(aws_subnet.public)
    subnet_id = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
    count = lenght(var.private_subnets)
    subnet_id = aws_subnet.private[count.index].id
    route_table_id = aws_route_table.private.id
}

#7 Security Groups 
## ALB
resource "aws_security_group" "alb_sg" {
    name = "alb-sg"
    description = "Security Group for ALB"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name ="ALB-SG"
    }
}

## NGINX Core
resource "aws_security_group" "nginx_core_sg" {
    name = "nginx-core-sg"
    description = "Grupo de seguridad para NGINX Core"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [aws_security_group.alb.sg.id]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.my_ip]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "NGINX-Core-SG"
    }
}

## App Instances
resource "aws_security_group" "app_sg" {
    name = "app-sg"
    description = "Grupo de seguridad para instancias de aplicacion"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [aws_security_group.nginx_core_sg.id]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "App-SG"
    }
}

#8. ELB y Target Group
resource "aws_lb" "nginx_alb" {
    name = "nginx-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = aws_subnet.public[*].id

    enable_deletion_protection = false

    tags = {
        Environment = "production"
    }
}

resource "aws_lb_target_group" "nginx_tg" {
    name = "nginx-tg"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.main.id

    health_check {
        path = "/"
        interval = 30
        timeout = 5
        healthy_threshold = 3
        unhealthy_threshold = 3
    }

    tags = {
        Name = "NGINX-TG"
    }
}

resource "aws_lb_listener" "front_end" {
    load_balancer_arn = aws_lb.nginx_alb.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.nginx_tg.arn
    }
}

#9. Auto Scaling Group para NGINX Core
resource "aws_launch_template" "nginx_core" {
    image_id = data.aws.ami.amazon_linux.id
    instance_type = var.instance_type
    key_name = var.key_name
    vpc_security_group_ids = [aws_security_group.nginx_core_sg.id]

    user_data = base64encode(<<-EOF
        #!/bin/bash
        yum update -y
        yum install -y nginx
        systemctl start nginx
        systemctl enable nginx
        echo " <h1>NGINX Core $(hostname)<h1> > /usr/share/nginx/html/index.html
    EOF
    )
}

resource "aws_autoscaling_group" "nginx_core_asg" {
    name_prefix = "nginx-core-asg-"
    vpc_zone_identifier = aws_subnet.private[*].id 
    min_size = 2
    max_size = 4
    desired_capacity = 2
    health_check_type = "ELB"
    target_group_arns = [aws_lb_target_group.nginx_tg.arn]
    
    launch_template {
        id = aws_launch_template.nginx_core.id
        version = "$Latest"
    }
    
    tag {
        key = "Name"
        value = "NGINX-Core"
        propagate_at_launch = true
    }
}

#10. Instancias EC2 para Apps
data "aws_ami" "amazon_linux" {
    most_recent = true
    owners = ["amazon"]

    filter {
        name = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

resource "aws_instance" "app_servers" {
    count = lenght(var.app_instances)
    ami = data.aws_ami.amazon_linux.id
    instance_type = var.instance_type
    key_name = var.key_name
    subnet_id = aws_subnet.private[count.index % length(var.private_subnets)].id
    vpc_security_group_ids = [aws_security_group.app_sg.id]

    user_data = base64encode(<<-EOF
        #!/bin/bash
        yum update -y
        yum install -y nginx
        systemctl start nginx
        systemctl enable nginx
        echo "<h1>App Instance ${var.app_instances[count.index]} $(hostname)</h1>" > /usr/share/nginx/html/index.html
    EOF
    )
    tags = {
        Name = var.app_instances[count.index]   
    }
}

    




