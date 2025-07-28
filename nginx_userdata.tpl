#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras enable nginx1
sudo yum install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Escribimos index.html
sudo echo "<h1>NGINX Core $(hostname)</h1>
<p><a href='/app1'>App1</a> | <a href='/app2'>App2</a> | <a href='/app3'>App3</a></p>" | sudo tee /usr/share/nginx/html/index.html

# Configuración del reverse proxy
sudo tee /etc/nginx/conf.d/apps.conf > /dev/null <<EOF
server {
  listen 80;

  location /app1/ {
    proxy_pass http://${app1_ip}/;
  }

  location /app2/ {
    proxy_pass http://${app2_ip}/;
  }

  location /app3/ {
    proxy_pass http://${app3_ip}/;
  }
}
EOF

# Reiniciar nginx con nueva config
sudo nginx -t && sudo systemctl restart nginx
