# Crear un ECS y su configuración con Terraform
Antes de empezar, he reutilizado algunas cosas que usamos en el de EC2, así que si no lo has mirado te aconsejo [echarle un vistazo](TerraEC2.md). Reaprovechamos la VPC y el security group, además de que el archivo versions.tf será el mismo. Así que nos vamos a centrar en el main.tf, en el ECS directamente.

???note "Código completo"
    ```bash
    # VPC con módulo oficial
    module "vpc" {
    source  = "terraform-aws-modules/vpc/aws"
    version = "5.21.0"

    name = "Conv_VPC"

    # Network
    cidr            = "10.0.0.0/16"
    azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] # Frankfurt
    private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    }

    # Security Group para permitir tráfico HTTP
    resource "aws_security_group" "nginx_sg" {
    name        = "nginx-sg"
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

    # Creating an ECS cluster
    resource "aws_ecs_cluster" "cluster" {
    name = "ecs_convenio"

    setting {
        name  = "containerInsights"
        value = "enabled"
    }
    }

    # Creating an ECS task definition
    resource "aws_ecs_task_definition" "task" {
    family                   = "service"
    network_mode             = "awsvpc"
    requires_compatibilities = ["FARGATE"]
    cpu                      = 512
    memory                   = 1024

    container_definitions = jsonencode([
        {
        name: "nginx",
        image: "nginx:latest",
        cpu    = 256,
        memory = 512,
        essential: true,
        portMappings: [
            {
            containerPort: 80,
            hostPort: 80,
            },
        ],
        },
    ])
    }

    # Creating an ECS service
    resource "aws_ecs_service" "service" {
    name             = "service_conv"
    cluster          = aws_ecs_cluster.cluster.id
    task_definition  = aws_ecs_task_definition.task.arn
    desired_count    = 1
    launch_type      = "FARGATE"
    platform_version = "LATEST"

    network_configuration {
        assign_public_ip = true
        security_groups  = [aws_security_group.nginx_sg.id]
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

### Usando el resource de ECS
Esta vez no vamos a usar un módulo, ya que el módulo que encontramos en el registro de Terraform es un poco confuso y tiene demasiadas cosas, más para alguien que está aprendiendo. Así que usaremos un resource. Voy a explicarlo por bloques. Esto será todo lo que se necesita para desplegarlo.

???note "Creando el cluster"
    Lo primero es crear el cluster, aquí es donde indicamos que será un resource, concretamente "aws_ecs_cluster" y le ponemos el nombre que queramos. En settings, lo dejamos tal y como muestro. Esta parte es sencilla.

    ```bash
        # Creating an ECS cluster
    resource "aws_ecs_cluster" "cluster" {
    name = "ecs_convenio"

    setting {
        name  = "containerInsights"
        value = "enabled"
        }
    }
    ```

???note "Creando la tarea"
    Ahora nos encargaremos de la tarea, que como ya sabemos, aquí es donde le diremos qué contenedor usar. Yendo por partes, le indicaremos que será de la familia servicios para que se ejecute cuando un servicio se lo diga. El network mode, queremos que trabaje por VPC para aprovechar la que tenemos. Y le ponemos compatibilidad con Fargate, ya que es así como lo queremos hacer, sin EC2. Luego el uso de CPU y memoria.

    Después vendría el contenedor, el NGINX. Aquí vamos a poner que use la última versión, que sea esencial y también le mapeamos los puertos que queremos que use. Como trabajará por HTTP, le ponemos puerto 80.

    ```bash
    # Creating an ECS task definition
    resource "aws_ecs_task_definition" "task" {
    family                   = "service"
    network_mode             = "awsvpc"
    requires_compatibilities = ["FARGATE"]
    cpu                      = 512
    memory                   = 1024

    container_definitions = jsonencode([
        {
        name: "nginx",
        image: "nginx:latest",
        cpu    = 256,
        memory = 512,
        essential: true,
        portMappings: [
            {
            containerPort: 80,
            hostPort: 80,
            },
        ],
        },
    ])
    }
    ```

???note "Creando el servicio"
    Por último vamos a crear el servicio. Le ponemos prácticamente enlaces a todo lo que hemos estado haciendo... el nombre, el cluster, la tarea... le decimos que queremos una tarea con desired_count. Le decimos que se lance con Fargate directamente y que use la última versión de nuestra tarea. 

    En la network configuration, queremos que tenga una ip pública para poder entrar directamente por HTTP. Luego, reaprovechamos la VPC y el SG. Por último le decimos que en el ciclo de vida, ignore los cambios de la task. Con esto lo tenemos todo.

    ```bash
    # Creating an ECS service
    resource "aws_ecs_service" "service" {
    name             = "service_conv"
    cluster          = aws_ecs_cluster.cluster.id
    task_definition  = aws_ecs_task_definition.task.arn
    desired_count    = 1
    launch_type      = "FARGATE"
    platform_version = "LATEST"

    network_configuration {
        assign_public_ip = true
        security_groups  = [aws_security_group.nginx_sg.id]
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

Esto es todo lo que hace falta para nuestro ECS. Como ya he dicho antes, recuerda que se necesita la VPC y el SG para esto, que podrás encontrarlo en la parte de [EC2](TerraEC2.md).

!!!warning
    **¡Recuerda hacer terraform destroy al acabar!**