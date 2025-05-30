# Página estática en S3, con CloudFront, ACM y Route 53
En esta práctica dejamos lista la infraestructura para poder tener una web estática en S3, con un CDN para añadir seguridad y cacheo, un DNS para la redirección, y con certificado para hacer que funcione por HTTPS. 

### Versions.tf
En esta práctica, tenemos que hacer algo que no hemos hecho en ninguna otra. Como vamos a usar servicios que están solo en algunas regiones concretas, tenemos que tener dos proveedores, uno en la zona que usamos siempre (en mi caso eu-central-1) y otro proveedor en la zona principal de AWS, que es us-east-1. 

```bash
    terraform {
    required_version = "~> 1.11.0"

    required_providers {
        aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
        }
    }
    backend "s3" {
        bucket       = "convenio-tfstate"
        key          = "terraform.tfstate"
        region       = "eu-central-1"
        use_lockfile = true
    }
    }

    provider "aws" {
    region = "eu-central-1"

    default_tags {
        tags = {
        Environment = "Prod"
        Owner       = "Álvaro García Ocaña"
        Project     = "Convenio Terraform"
        }
    }
    }

    provider "aws" {
    region = "us-east-1"
    alias  = "us-east-1"
    default_tags {
        tags = {
        Environment = "Prod"
        Owner       = "Álvaro García Ocaña"
        Project     = "Convenio Terraform"
        }
    }
    }
```

### Data.tf y Variables.tf
Para esto, vamos a usar un Route 53, que en este caso he usado el de <span style="color: #9839ff;">Basetis</span>. Como ya es un recurso que existe, le tenemos que decir a Terraform que pille la información de la cuenta de AWS directamente con un data, esto entonces se lo indicaremos de la siguiente manera.

!!!note "Data.tf"
    ```bash
        data "aws_route53_zone" "zone" {
        name         = var.route53_zone_name
        private_zone = false
        }
    ```

También, más por comodidad que otra cosa, vamos a crear una variable que indique el resto del FQDN del DNS de nuestro Route 53
!!!note "Variables.tf"
    ```bash
        variable "route53_zone_name" {
        description = "Route53 zone name"
        type        = string
        default     = "data.pre.basetis.com"
        }
    ```

### ACM
Usaremos un módulo para el certificado, donde le vamos a indicar el proveedor exacto que queremos, referenciándolo con el alias que le hemos puesto en el versions.tf. Luego, el nombre de dominio, el id de la zona (route 53) y el método de validación que usaremos, osea, DNS.

```bash
    module "acm_certificate_proyecto" {
    source  = "terraform-aws-modules/acm/aws"
    version = "5.1.1"

    providers = {
        aws = aws.us-east-1
    }

    domain_name       = "proyecto-docs.${var.route53_zone_name}"
    zone_id           = data.aws_route53_zone.zone.zone_id
    validation_method = "DNS"
    }
```

### S3
Crear el S3 es tan fácil como lo es en la consola de AWS. Lo primero, le ponemos el nombre.

```bash
    resource "aws_s3_bucket" "website_bucket" {
    bucket = "proyecto-docs"

    tags = {
        Name        = "proyecto-docs"
        Environment = "Prod"
    }
    }
```

Luego, hacemos que todo el contenido que entre en el bucket, sea propiedad del que lo creó.

```bash
    resource "aws_s3_bucket_ownership_controls" "website_bucket" {
    bucket = aws_s3_bucket.website_bucket.id
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
    }
```

Quitamos los bloqueos públicos que trae S3 por defecto, ya que queremos que la web sea visitable a través de internet.

```bash
    resource "aws_s3_bucket_public_access_block" "website_bucket" {
    bucket = aws_s3_bucket.website_bucket.id

    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
    }
```

Y por último, le ponemos una ACL en la que básicamente le decimos que será de lectura pública.

```bash
    resource "aws_s3_bucket_acl" "website_bucket" {
    depends_on = [
        aws_s3_bucket_ownership_controls.website_bucket,
        aws_s3_bucket_public_access_block.website_bucket,
    ]

    bucket = aws_s3_bucket.website_bucket.id
    acl    = "public-read"
    }
```

### CloudFront
Este bloque iremos por partes. Primero, con un recurso, creamos la distribución de CloudFront, dándole el origen que tendrá para los archivos, nuestro S3. Entre otras cosas, le indicamos también el archivo raíz que usará para mostrarselo a los usuarios principalmente.

```bash
    resource "aws_cloudfront_distribution" "website_distribution" {
    origin {
        domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
        origin_id   = aws_s3_bucket.website_bucket.bucket

        s3_origin_config {
        origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
        }
    }

    enabled             = true
    is_ipv6_enabled     = true
    default_root_object = "index.html"
    aliases             = module.acm_certificate_proyecto.distinct_domain_names
```

!!!warning "Importante"
    Como puedes ver, el alias referencia directamente al certificado. Es esencial que tenga el mismo nombre del certificado aquí y más adelante en el registro de DNS, si no, no podrá trabajar con ACM de ninguna manera.

Lo siguiente sería algunas configuraciones para el caché. También le indicamos que queremos que se redirija siempre hacia HTTPS.

```bash
    default_cache_behavior {
        allowed_methods  = ["GET", "HEAD", "OPTIONS"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = aws_s3_bucket.website_bucket.bucket

        forwarded_values {
        query_string = false

        cookies {
            forward = "none"
        }
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl                = 0
        default_ttl            = 3600
        max_ttl                = 86400
  }
```
Por último, no le ponemos restricciones de geolocalización para que sea visitable desde cualquier lado. Y también el certificado, lo señalamos hacia el módulo ACM, le indicamos el método ssl soportado y también la versión mínima del protocolo TLS que usará.

```bash
    restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }

    viewer_certificate {
        acm_certificate_arn      = module.acm_certificate_proyecto.acm_certificate_arn
        ssl_support_method       = "sni-only"
        minimum_protocol_version = "TLSv1.2_2021"
    }
    }
```

### Política para S3
Por defecto, S3 no permite el acceso a los servicios de AWS aunque estén en la misma cuenta, así que tenemos que crear una política para ello. Lo primero es crear una "llave de acceso" que permite a CloudFront acceder a S3. Luego en la propia política, le damos el acceso con esa llave, para que pueda descargar objetos del S3 desde la raíz.

```bash
    resource "aws_s3_bucket_policy" "website_bucket_policy" {
    bucket = aws_s3_bucket.website_bucket.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
        {
            Sid    = "AllowCloudFrontAccess"
            Effect = "Allow"
            Principal = {
            AWS = aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn
            }
            Action   = "s3:GetObject"
            Resource = "${aws_s3_bucket.website_bucket.arn}/*"
        }
        ]
    })
    }
```

### Registro DNS
Por último, como ya usamos el Route 53 que tenemos creado en la cuenta, vamos a crear solamente el registro DNS que apuntará a CloudFront, y que así los usuarios puedan usar un nombre de dominio en vez de una IP o el nombre de dominio por defecto del CloudFront. Le decimos la zona, el nombre que tendrá, el tipo de registro (A) y luego lo referenciamos con el alias hacia CloudFront.

```bash
    resource "aws_route53_record" "cloudfront_alias" {
    zone_id = data.aws_route53_zone.zone.zone_id
    name    = "proyecto-docs.${var.route53_zone_name}"
    type    = "A"

    alias {
        name                   = aws_cloudfront_distribution.website_distribution.domain_name
        zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
        evaluate_target_health = false
    }
    }
```

Con esto lo tenemos todo listo y podríamos hacer la página web estática, solo quedaría subir los archivos de la web a mano al S3. Sin embargo, recomiendo echarle un ojo a [esto de aquí](GitHubActions.md) para automatizar la subida de estos.
### Repositorio
Podéis encontrar la práctica completa en mi [GitHub](https://github.com/AlvaroGarOca/ClassRoom-Terraform/tree/main/practica-4)