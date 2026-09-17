variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names and tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the security groups are created."
  type        = string
}

variable "alb_https_client_cidr_blocks" {
  description = "Client CIDR blocks allowed to reach the optional ALB HTTPS test listener."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "application_port" {
  description = "API application port used between ALB and EC2."
  type        = number
}

variable "database_port" {
  description = "Database port used between EC2 and RDS."
  type        = number
}
