variable "aws_region" {
  description = "Region de AWS donde se desplegara la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "profile_name" {
  description = "Nombre del perfil de AWS"
  type = string
  sensitive = "true"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "CIDR de las subredes publicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR de las subredes privadas"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "app_instances" {
  description = "Nombre de las instancias"
  type        = list(string)
  default     = ["App1", "App2", "App3"]
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nombre del KeyPair para acceso SSH"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Tu IP publica para conectarte a SSH"
  type = string
  sensitive = true 
}