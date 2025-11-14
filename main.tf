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
  cidr_block = var.subnet_private_cidr
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

  user_data = file("docker_install.sh")

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

resource "tls_private_key" "generated" { # genera la clave privada para el key pair de EC2
  algorithm  = "ECDSA"
}

resource "aws_key_pair" "deployed" { # crea el key pair para acceder a la instancia EC2
  key_name   = var.ec2_key_name
  public_key = tls_private_key.generated.public_key_openssh
}

resource "local_file" "private_key_pem" { # guarda la clave privada en un archivo local
  content  = tls_private_key.generated.private_key_pem
  filename = "${var.ec2_key_name}.pem"
  file_permission = "0400"
}

resource "aws_instance" "back" { # crea la instancia EC2 para el backend
  ami                    = data.aws_ssm_parameter.amazon_linux_2_ami.value
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.deployed.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = file("docker_install.sh")

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