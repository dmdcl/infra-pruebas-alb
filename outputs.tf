output "alb_dns_name" {
  description = "DNS del ALB"
  value       = aws_lb.nginx_alb.dns_name
}

output "app_private_ips" {
  description = "IPs privadas de las instancias App"
  value       = aws_instance.app_servers[*].private_ip
}