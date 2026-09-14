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

variable "cloudfront_origin_prefix_list_id" {
  description = "CloudFront origin-facing managed prefix list ID."
  type        = string
}

variable "alb_listener_port" {
  description = "ALB listener port exposed to CloudFront."
  type        = number
}

variable "application_port" {
  description = "API application port used between ALB and EC2."
  type        = number
}

variable "database_port" {
  description = "Database port used between EC2 and RDS."
  type        = number
}
