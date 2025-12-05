resource "aws_vpc" "main" { # crea la vpc
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_subnet" "public" { # crea la subnet publica, donde va el ECR, fronend y backend
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_cidr_1
  map_public_ip_on_launch = true
  availability_zone       = var.public_subnet_az_1

  tags = {
    Name = "${var.app_name}-subnet-front"
  }
}

resource "aws_subnet" "private" { # crea la subnet privada, donde va la base de datos
  vpc_id     = aws_vpc.main.id
  cidr_block = var.subnet_private_cidr
  availability_zone = var.private_subnet_az_4

  tags = {
    Name = "${var.app_name}-subnet-db"
  }
}

resource "aws_subnet" "private_db" { # crea la segunda subnet privada, donde va la base de datos
  vpc_id     = aws_vpc.main.id
  cidr_block = var.subnet_private_cidr_2
  availability_zone = var.private_subnet_az_1

  tags = {
    Name = "${var.app_name}-subnet-db-2"
  }
}

resource "aws_internet_gateway" "main" { # crea la gateway para que la vpc tenga acceso a internet
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_ecr_repository" "main" { #crea el repositorio ECR para las imagenes docker
  name = var.ecr_repo_name
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "github_actions" { # crea el rol IAM para GitHub Actions
  name = "${var.app_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:RodrigoOrtega1/is2-back-blog:*",
              "repo:1rv1nn/Materias_front:*"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "github_actions" { # OIDC Provider for GitHub Actions, autenticar entre AWS y GitHub
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

resource "aws_iam_role_policy" "github_actions_ecr" { # política para que GitHub Actions pueda interactuar con ECR
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.main.arn
      }
    ]
  })
}

resource "aws_iam_role" "ec2_ecr_role" { # crea el rol IAM para la instancia EC2 que le permite extraer imágenes de ECR
  name = "${var.app_name}-ec2-ecr-pull-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"  # EC2 assumes this role, not GitHub
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_ecr_policy" { # política para que la instancia EC2 pueda extraer imágenes de ECR
  name = "${var.app_name}-ec2-ecr-pull-policy"
  role = aws_iam_role.ec2_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" { # wrapper para el rol IAM de la instancia EC2
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

resource "aws_db_instance" "main" { # crea la base de datos
  identifier             = "${var.app_name}-db"
  db_name                = var.db_name
  engine                 = "postgres"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  username               = var.db_user
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

resource "aws_instance" "front" { # crea la instancia EC2 para el frontend
  ami                    = data.aws_ssm_parameter.amazon_linux_2_ami.value
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.deployed.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = file("user_data.sh")

  tags = {
    Name = "${var.app_name}-instance-front"
  }
}

resource "aws_lb" "main" { # crea el Application Load Balancer
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_2.id]

  tags = {
    Name = "${var.app_name}-alb"
  }
}

resource "aws_lb_target_group" "main" { # crea el target group para el ALB
  name        = "${var.app_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "http" { # crea el listener para el ALB
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_subnet" "public_2" { # crea la segunda subnet publica, donde va el ECR, fronend y backend
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_cidr_2
  map_public_ip_on_launch = true
  availability_zone       = var.public_subnet_az_2

  tags = {
    Name = "${var.app_name}-subnet-front-2"
  }
}

resource "aws_route_table" "public" { # crea la tabla de rutas para la subnet publica
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.app_name}-route-table-publica"
  }
}

resource "aws_security_group" "alb" { # crea el security group para el ALB
  name        = "${var.app_name}-alb-sg"
  description = "Permite el acceso HTTP y HTTPS al ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "ec2" { # crea el security group para la instancia EC2
  name        = "${var.app_name}-ec2-sg"
  description = "Permite el acceso SSH, HTTP y HTTPS a EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr] 
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] 
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" { # crea el security group para la base de datos RDS
  name        = "${var.app_name}-rds-sg"
  description = "Permite el acceso desde la instancia EC2 a RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" { # crea el subnet group para la base de datos RDS
  name       = "${var.app_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_db.id]

  tags = {
    Name = "${var.app_name}-db-subnet-group"
  }
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployed" {
  key_name   = var.ec2_key_name
  public_key = tls_private_key.generated.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.generated.private_key_pem
  filename        = "${var.ec2_key_name}.pem"
  file_permission = "0400"
}

resource "aws_instance" "back" { # crea la instancia EC2 para el backend
  ami                    = data.aws_ssm_parameter.amazon_linux_2_ami.value
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.deployed.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = file("user_data.sh")

  tags = {
    Name = "${var.app_name}-instance-back"
  }
}

resource "aws_lb_target_group_attachment" "front" { # asocia la instancia EC2 del frontend al target group del ALB
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.front.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "back" { # asocia la instancia EC2 del backend al target group del ALB
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.back.id
  port             = 80
}

data "aws_ssm_parameter" "amazon_linux_2_ami" { # obtiene el ID de la AMI de Amazon Linux 2
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_eip" "back" { # crea una IP elástica para la instancia backend
  instance = aws_instance.back.id
  domain = "vpc"

  tags = {
    Name = "${var.app_name}-eip-back"
  }
}

resource "aws_eip" "front" { # crea una IP elástica para la instancia frontend
  instance = aws_instance.front.id
  domain = "vpc"

  tags = {
    Name = "${var.app_name}-eip-front"
  }
}

resource "aws_eip_association" "front" { # asocia la IP elástica a la instancia frontend
  instance_id   = aws_instance.front.id
  allocation_id = aws_eip.front.id
}

resource "aws_eip_association" "back" { # asocia la IP elástica a la instancia backend
  instance_id   = aws_instance.back.id
  allocation_id = aws_eip.back.id
}

resource "aws_route53_zone" "main" { # crea una zona hospedada en Route 53
  name = var.route53_zone_name
}

resource "aws_route53_record" "front" { # crea un registro A para el frontend en Route 53
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.route53_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "back" { # crea un registro A para el backend en Route 53
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.route53_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "root" { # crea un registro A para el dominio raíz
  zone_id = aws_route53_zone.main.zone_id
  name    = var.route53_zone_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

output "nameserver_addresses" {
  description = "Direcciones de los nameservers de la zona hospedada en Route 53"
  value       = aws_route53_zone.main.name_servers
}
