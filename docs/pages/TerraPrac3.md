# Desplegar Wordpress con ECS (Fargate), RDS y EFS
Esta práctica es igual a la que ya está documentada [aquí](desplegarWP.md) y [aquí](creacionRDS.md). Así que no voy a entrar en detalles más específicos, centrándome solo en Terraform y su código.

### VPC
Vamos a necesitar una VPC como ya sabemos. Está hecho con un módulo, donde tendremos tres zonas y redes privadas y públicas. Este es el código usado:

!!!note "Módulo de VPC"
    ```bash
    # VPC con módulo oficial
    module "vpc" {
    source  = "terraform-aws-modules/vpc/aws"
    version = "5.21.0"

    name = "Conv_VPC"

    # Network
    cidr            = "10.0.0.0/16"
    azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    }
    ```

### Security Groups
Necesitaremos varios Security Groups para asegurar las conexiones entre servicios y también para dar acceso general a la página de Wordpress.

#### Security Group de WordPress
Para el Wordpress, se permite HTTP para todas las conexiones, y de salida completa para todo internet.

!!!note "WordPress SG"
    ```bash
    resource "aws_security_group" "wordpress_sg" {
    name        = "wordpress-sg"
    description = "Allow HTTP"
    vpc_id      = module.vpc.vpc_id

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
    ```

#### Security Group del bastión EC2
El grupo de seguridad del bastión permite conexión por SSH para mi IP personal (Que no os voy a enseñar para que no me doxeeis) y salida a todo internet.

!!!note "EC2 SG"
    ```bash
    resource "aws_security_group" "ec2_sg" {
    name        = "ec2_sg"
    description = "Security group to allow HTTP and SSH access"
    vpc_id      = module.vpc.vpc_id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = var.ip_whitelist
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "ec2_sg"
    }
    }
    ```

#### Security Group de RDS
Para el de RDS, vamos a permitir la entrada por el puerto 3306 para el EC2 y también para Wordpress. De salida a todo internet. 

!!!note "RDS SG"
    ```bash
    resource "aws_security_group" "rds_sg" {
    name   = "rds_sg"
    vpc_id = module.vpc.vpc_id

    ingress {
        from_port       = 3306
        to_port         = 3306
        protocol        = "tcp"
        security_groups = [aws_security_group.ec2_sg.id]
        description     = "Allow MySQL access from EC2"
    }

    ingress {
        from_port       = 3306
        to_port         = 3306
        protocol        = "tcp"
        security_groups = [aws_security_group.wordpress_sg.id]
        description     = "Allow ECS WordPress access"
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    }
    ```

#### Security Group de EFS
Para el EFS, solo le vamos a dar una regla de entrada para Wordpress por el puerto 2049.

!!!note "EFS SG"
    ```bash
    resource "aws_security_group" "wordpress_efs_sg" {
    name   = "wordpress-efs-sg"
    vpc_id = module.vpc.vpc_id

    ingress {
        from_port       = 2049
        to_port         = 2049
        protocol        = "tcp"
        security_groups = [aws_security_group.wordpress_sg.id] # ECS tasks
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    }
    ```

### Par de llaves
Vamos a necesitar un par de keys para poder conectar a EC2 si lo necesitamos. Primero creamos las claves.

```bash
    resource "tls_private_key" "terrafrom_generated_private_key" {
    algorithm = "RSA"
    rsa_bits  = 4096
    }
```

Ahora le asignamos a la clave privada un nombre, para poder asignársela después a EC2.

```bash
    resource "aws_key_pair" "ssh-key" {
    key_name   = "server-key"
    public_key = tls_private_key.terrafrom_generated_private_key.public_key_openssh
    }
```

Y por último la clave pública la vamos a tener en local, aunque no es la mejor práctica, ya que lo mejor sería llevarla a Secrets Manager. Al tenerla en local será más fácil para trabajar en esta práctica.

```bash
    resource "local_file" "cloud_pem" { 
    filename = "${path.module}/ec2_private_key.pem"
    content = tls_private_key.terrafrom_generated_private_key.private_key_openssh
    file_permission = "0600"
    }
```

!!!warning "¡Cuidado!"
    Importante, al tenerlo en local, si lo subes a un repositorio de GitHub, recuerda añadir a tu .gitignore para que no se suba automáticamente. O bórralo antes. Si subes la llave pública, podrían entrar a tu EC2, ¡cuidao!

### EC2
Para el bastión EC2, vamos a usar prácticamente el mismo código que en la [primera práctica](TerraEC2.md), pero con unos cambios esenciales. Primero, el data para la ami.

```bash
    data "aws_ami" "latest_amazon_linux_image" {
    most_recent = true
    owners      = ["amazon"]
    filter {
        name   = "name"
        values = ["amzn2-ami-kernel-*-hvm-*-x86_64-gp2"]
    }
    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
    }
```

Para empezar, las configuraciones básicas de la EC2. La instancia, el par de claves que hicimos antes, el grupo de seguridad, la subnet de la VPC. También clave pública, pero no creo que sea necesario para este proyecto.

```bash
    resource "aws_instance" "Conv_EC2" {
    ami = data.aws_ami.latest_amazon_linux_image.id

    instance_type               = "t2.micro"
    key_name                    = aws_key_pair.ssh-key.key_name
    vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
    subnet_id                   = module.vpc.public_subnets[0]
    associate_public_ip_address = true
```

Ahora el user data, esencial para el funcionamiento del proyecto. Vamos a necesitar crear la base de datos que usará Wordpress, además del usuario. Para ello, instalamos mysql, hacemos un sleep para que le de tiempo a RDS a estar listo, y luego lo que he comentado de MYSQL.

```bash
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y mysql

                # Esperar a que el clúster RDS esté disponible
                sleep 320

                # Crear usuario en la base de datos
                mysql -h ${module.cluster.cluster_endpoint} -u admin -ppassword -e "CREATE DATABASE IF NOT EXISTS wordpress;"
                mysql -h ${module.cluster.cluster_endpoint} -u admin -ppassword -e "CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY 'password';"
                mysql -h ${module.cluster.cluster_endpoint} -u admin -ppassword -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'admin'@'%' WITH GRANT OPTION;"
                mysql -h ${module.cluster.cluster_endpoint} -u admin -ppassword -e "FLUSH PRIVILEGES;"
                
                EOF
    }
```

### RDS
El cluster de RDS también será un módulo. La versión del engine, y la instancia lo he encontrado en documentaciones externas, pero es perfecto para esta en concreto. Además, la instancia está bien para ello, ya que es la más barata.

´´´bash
    module "cluster" {
    source = "terraform-aws-modules/rds-aurora/aws"

    name           = "test-aurora-mysql"
    engine         = "aurora-mysql"
    engine_version = "8.0.mysql_aurora.3.09.0"
    instance_class = "db.t4g.medium"
    instances = {
        one = {}
    }
´´´

Lo siguiente es algo que me ha **amargado la existencia** durante dos días. Para RDS, le asignamos un usuario y contraseña. Si solo pones *master_username* y *master_password*, Terraform por defecto va a ignorar la contraseña que le pongas y creará un Secret en AWS para usarlo automáticamente, para ello, hay que definir explícitamente que **NO** queremos que se haga de esa manera. Es contradictorio, ya que *manage_master_user_password* nos dice que al poner una contraseña, no se puede usar secrets, cosa que no es cierta.

```bash
  manage_master_user_password = false
  master_username = "admin"
  master_password = "password"
```

Por último, el resto de configuraciones básicas. El VPC, la subnet, y configuraciones varias que son a gusto y comodidad.

```bash
    vpc_id                 = module.vpc.vpc_id
    db_subnet_group_name   = "aurora-subnet-group"
    create_db_subnet_group = true
    subnets                = module.vpc.private_subnets
    vpc_security_group_ids = [aws_security_group.rds_sg.id]

    storage_encrypted               = true
    apply_immediately               = true
    skip_final_snapshot             = true
    enabled_cloudwatch_logs_exports = []

    tags = {
        Environment = "dev"
        Terraform   = "true"
    }
    }
```

### Secrets Manager
Vamos a crear un secrets manager para poder tener las credenciales de Wordpress, además del nombre de la base de datos, etc. Además le vamos a crear una política para que ECS pueda acceder a Secrets Manager y pueda coger toda la información necesaria.

```bash
    module "secrets_manager_wordpress" {
    source  = "terraform-aws-modules/secrets-manager/aws"
    version = "1.3.1"

    name                    = "wordpress-credentials-v5"
    description             = "Credenciales para WordPress ECS"
    recovery_window_in_days = 0

    # Permite acceso al secreto desde ECS
    create_policy       = true
    block_public_policy = true
    policy_statements = {
        ecs_read_access = {
        sid = "AllowEcsExecutionRoleToReadSecrets"
        principals = [{
            type        = "AWS"
            identifiers = ["arn:aws:iam::414131675413:role/ecsTaskExecutionRole"]
        }]
        actions   = ["secretsmanager:GetSecretValue"]
        resources = ["*"]
        }
    }

    secret_string = jsonencode({
        WORDPRESS_DB_HOST     = module.cluster.cluster_endpoint
        WORDPRESS_DB_NAME     = "wordpress"
        WORDPRESS_DB_USER     = "admin"
        WORDPRESS_DB_PASSWORD = "password"
    })

    tags = {
        Environment = "dev"
        Terraform   = "true"
    }
    }
```

### EFS
Necesitaremos el EFS para poder tener permanencia de archivos en WordPress. 

```bash
    resource "aws_efs_file_system" "wordpress" {
    creation_token = "wordpress-efs"
    encrypted      = true
    tags = {
        Name = "wordpress-efs"
    }
    }
```

Vamos a crear un "grupo de variables", un locals. Para poder darle directamente a EFS las zonas disponibles en las que trabajará.

```bash
    locals {
    private_subnet_map = {
        "az1" = module.vpc.private_subnets[0]
        "az2" = module.vpc.private_subnets[1]
        "az3" = module.vpc.private_subnets[2]
    }
    }
```

Y creamos el punto de montaje de EFS, que usará el locals que hemos creado ahora mismo, el EFS como tal, y el grupo de seguridad que le hicimos antes.

```bash
    resource "aws_efs_mount_target" "wordpress" {
    for_each = local.private_subnet_map

    file_system_id  = aws_efs_file_system.wordpress.id
    subnet_id       = each.value
    security_groups = [aws_security_group.wordpress_efs_sg.id]
    }
```

### ECS
Ahora el cluster de ECS, le ponemos el nombre deseado. También le tenemos activado Container Insights, una herramienta de monitoreo.

```bash
    resource "aws_ecs_cluster" "cluster" {
    name = "ecs_terraform_convenio"

    setting {
        name  = "containerInsights"
        value = "enabled"
    }
    }
```

#### Task Definition
Las configuraciones básicas, servicio con su rol de ejecución, el tipo de network y usando Fargate.

```bash
    resource "aws_ecs_task_definition" "task" {
    family                   = "service"
    execution_role_arn       = "arn:aws:iam::414131675413:role/ecsTaskExecutionRole"
    network_mode             = "awsvpc"
    requires_compatibilities = ["FARGATE"]
    cpu                      = 512
    memory                   = 1024
```

La definición del contenedor es directamente el JSON que usamos en [esta parte](desplegarWP.md). Lo hacemos así:

```bash
  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "wordpress:6.8.0-apache"
      cpu       = 0
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
          name          = "wordpress-80-tcp"
          appProtocol   = "http"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "Wordpress-convenio"
          containerPath = "/var/www/html"
          readOnly      = false
        }
      ]

      secrets = [
        {
          name      = "WORDPRESS_DB_HOST"
          valueFrom = "${module.secrets_manager_wordpress.secret_arn}:WORDPRESS_DB_HOST::"
        },
        {
          name      = "WORDPRESS_DB_NAME"
          valueFrom = "${module.secrets_manager_wordpress.secret_arn}:WORDPRESS_DB_NAME::"
        },
        {
          name      = "WORDPRESS_DB_USER"
          valueFrom = "${module.secrets_manager_wordpress.secret_arn}:WORDPRESS_DB_USER::"
        },
        {
          name      = "WORDPRESS_DB_PASSWORD"
          valueFrom = "${module.secrets_manager_wordpress.secret_arn}:WORDPRESS_DB_PASSWORD::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/wordpress-convenio"
          awslogs-region        = "eu-central-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
```

Por último el volumen que usará el ECS, básicamente le decimos que use EFS.

```bash
    volume {
        name = "Wordpress-convenio"

        efs_volume_configuration {
        file_system_id = aws_efs_file_system.wordpress.id
        root_directory = "/"

        transit_encryption = "ENABLED"

        authorization_config {
            access_point_id = null
            iam             = "DISABLED"
        }
        }
    }
    }
```

#### Service
Para acabar, tanto con el ECS como con toda la configuración, el service. Será un servicio sencillo, le decimos que use siempre la última versión de la task, que solo tenga una, que use FARGATe, y todas las configuraciones básicas de red, cluster, etc.

```bash
    resource "aws_ecs_service" "service" {
    name             = "service_conv"
    cluster          = aws_ecs_cluster.cluster.id
    task_definition  = aws_ecs_task_definition.task.arn
    desired_count    = 1
    launch_type      = "FARGATE"
    platform_version = "LATEST"

    network_configuration {
        assign_public_ip = true
        security_groups  = [aws_security_group.wordpress_sg.id]
        subnets          = module.vpc.public_subnets
    }

    lifecycle {
        ignore_changes = [task_definition]
    }

    tags = {
        serviceName = "service_conv"
    }
    }
```

### Repositorio
Podéis encontrar el proyecto completo y listo para usar en mi [GitHub](https://github.com/AlvaroGarOca/ClassRoom-Terraform/tree/main/practica-3)