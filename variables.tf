variable "region" {
  description = "Región de AWS para desplegar los recursos."
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Nombre base para los recursos (VPC, SGs, etc.)"
  type        = string
  default     = "ing-soft-2"
}

variable "ecr_repo_name" {
  description = "Nombre del repositorio ECR para las imágenes Docker."
  type        = string
  default     = "mi-app-repo"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "subnet_public_cidr_1" {
  type        = string
  description = "CIDR for the public subnet"
  default     = "10.0.1.0/24"
}

variable "subnet_public_cidr_2" {
  type        = string
  description = "CIDR para la segunda subnet pública (necesaria para ALB en 2 AZs)."
  default     = "10.0.2.0/24"
}

variable "subnet_public_cidr_3" {
  type        = string
  description = "CIDR para la tercera subnet pública (necesaria para ALB en 2 AZs)."
  default     = "10.0.3.0/24"
}

variable "subnet_private_cidr" {
  type        = string
  description = "CIDR for the first private subnet"
  default     = "10.0.6.0/24"
}

variable "subnet_private_cidr_2" {
  type        = string
  description = "CIDR for the second private subnet"
  default     = "10.0.7.0/24"
}

variable "public_subnet_az_1" {
  description = "Availability zone for the first public subnet (e.g. us-east-1a)"
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_az_2" {
  description = "Availability zone for the second public subnet (e.g. us-east-1b)"
  type        = string
  default     = "us-east-1b"
}

variable "public_subnet_az_3" {
  description = "Availability zone for the second public subnet (e.g. us-east-1b)"
  type        = string
  default     = "us-east-1c"
}


variable "private_subnet_az_4" {
  type        = string
  description = "Availability Zone for the first private subnet (e.g. us-east-1a)"
  default     = "us-east-1d"
}

variable "private_subnet_az_1" {
  type        = string
  description = "Availability Zone for the first private subnet (e.g. us-east-1a)"
  default     = "us-east-1e"
}

variable "ec2_key_name" {
  description = "Nombre del Key Pair de EC2 para el acceso SSH."
  type        = string
  default     = "ssh-keys-mi-app-new"
}

variable "ec2_instance_type" {
  description = "Tipo de instancia para el servidor de la app (Capa Gratuita)."
  type        = string
  default     = "t3.micro"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR format for SSH access, e.g. 1.2.3.4/32"
  default     = "0.0.0.0/0"
}

variable "db_instance_class" {
  description = "Tipo de instancia para RDS (Capa Gratuita)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos inicial."
  type        = string
  default     = "miappdb"
}

variable "db_user" {
  description = "Usuario administrador de la base de datos."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = lower(var.db_user) != "user" && lower(var.db_user) != "postgres"
    error_message = "db_user no puede ser 'user' ni 'postgres' (palabras reservadas). Elige otro usuario, p.ej. 'dbadmin'."
  }
}

variable "db_password" {
  description = "Contraseña para el administrador de la base de datos."
  type        = string
  sensitive   = true
  default     = "123456Absrc"
}

variable "route53_zone_name" {
  description = "Nombre de la zona hospedada en Route 53."
  type        = string
  default     = "blogresenas-is2-7190.lat"
}
