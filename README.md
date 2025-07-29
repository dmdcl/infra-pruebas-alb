 Infraestructura AWS con NGINX Core, Auto Scaling, ALB y Apps

Este proyecto despliega una infraestructura en AWS usando Terraform para crear:

- Una **VPC** con subredes públicas y privadas.
- Un **Application Load Balancer (ALB)** público para enrutar tráfico HTTP.
- Un **Auto Scaling Group** con instancias EC2 corriendo **NGINX Core** en subred privada.
- Varias instancias EC2 de aplicaciones en subred privada.
- Seguridad con **Security Groups** para controlar el tráfico entre ALB, NGINX y apps.
- Configuración dinámica de NGINX Core para hacer reverse proxy a las apps.
- Uso de **NAT Gateway** para acceso a internet desde subredes privadas.

---

## Estructura general

- **VPC y Networking**: Define la VPC, subredes públicas y privadas, gateway, NAT Gateway, tablas de rutas y asociaciones.
- **Security Groups**: Controlan acceso HTTP y SSH entre ALB, NGINX Core y las apps.
- **ALB (Application Load Balancer)**: Distribuye el tráfico HTTP a las instancias NGINX Core.
- **Launch Template y Auto Scaling Group**: Para instancias NGINX Core, que reciben configuración con IPs privadas de apps.
- **Instancias app_servers**: Varias instancias EC2 en subred privada con NGINX simple sirviendo páginas básicas.
- **Configuración NGINX Core**: Reverse proxy para enrutar rutas `/app1`, `/app2`, `/app3` a las instancias app correspondientes.

---

## Detalles técnicos

- El ALB está configurado para escuchar en el puerto 80 y enrutar a NGINX Core.
- NGINX Core escucha peticiones y redirige a las apps por ruta, usando IPs privadas.
- Las apps sólo reciben tráfico HTTP desde NGINX Core (restricción en SG).
- Las subredes privadas usan NAT Gateway para salir a internet (updates, etc).
- SSH solo está permitido al NGINX Core desde la IP del usuario (variable `var.my_ip`).
- Las imágenes usadas son Amazon Linux 2 con NGINX instalado y configurado mediante `user_data`.
- El código Terraform usa `depends_on` para controlar el orden de creación y evitar errores.

---

## Requisitos

- AWS CLI configurado con el perfil y región adecuados.
- Terraform instalado (versión compatible con AWS provider).
- Variables definidas para rangos CIDR, claves SSH, tipo de instancia, IP del usuario, etc.

---

## Cómo usar

1. Configura las variables en `terraform.tfvars` o usando variables de entorno.
2. Ejecuta `terraform init` para inicializar el proyecto.
3. Ejecuta `terraform plan` para revisar los cambios.
4. Ejecuta `terraform apply` para desplegar toda la infraestructura.
5. Accede al DNS público del ALB para ver la página principal con enlaces a apps.
6. El ALB balanceará y enrutarán tráfico a las instancias NGINX Core y estas a las apps.

---

## Limpieza

Para destruir la infraestructura:

```bash
terraform destroy
```


