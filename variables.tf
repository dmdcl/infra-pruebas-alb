variable "aws_region" {
    description = "Region de AWS donde se desplegaran los recursos"
    type = string
    default = "us-east-1"
}

variable "vpc_cidr" {
    description = "CIDR block para la VPC"
    type = string 
    default = "10.0.0.0/16"
}

variable "public_subnets" {
    description = "CIDR blocks para subredes publicas"
    type = list(string)
    default = ["10.0.1.0/24", "10.0.4.0/24"] 
}

variable "private_subnets" {
    description = "CIDR blocks para subredes privadas"
    type = list(string) 
    default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "azs" {
    description = "Zonas de disponibilidad"
    type = list(string)
    default = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
    description = "Tipo de instancia EC2"
    type = string
    default = "t3.micro"
}

variable "key_name" {
    description = "Nombre del key pair SSH"
    type = string
}

variable "my_ip" {
    description = "IP personal para acceso SSH (en formato CIDR)"
    type = string
    default = "0.0.0.0/0"
}

variable "app_instances" {
    description = "Nombres de las instancias de aplicacion"
    type = list(string)
    default = ["App1", "App2", "App3"]
}