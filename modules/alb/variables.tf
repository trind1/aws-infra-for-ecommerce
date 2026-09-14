variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC hosting the ALB and target group."
  type        = string
}

variable "subnet_ids" {
  description = "Exactly two public subnet IDs for the internet-facing ALB."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) == 2
    error_message = "subnet_ids must contain the two public subnets."
  }
}

variable "security_group_id" {
  description = "ALB security group ID."
  type        = string
}

variable "target_port" {
  description = "NodeJS port exposed by the API target."
  type        = number
}

variable "health_check_path" {
  description = "API health endpoint path."
  type        = string
  default     = "/health"
  nullable    = false
}

variable "listener_port" {
  description = "HTTPS listener port exposed by the ALB to CloudFront."
  type        = number
}

variable "certificate_arn" {
  description = "Issued regional ACM certificate ARN matching the ALB origin hostname used by CloudFront."
  type        = string
  nullable    = false
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  nullable    = false
}

variable "origin_custom_header_name" {
  description = "Header name checked by the listener rule."
  type        = string
  default     = "X-Origin-Verify"
  nullable    = false
}

variable "origin_custom_header_value" {
  description = "Sensitive header value checked by the listener rule."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion."
  type        = bool
  default     = false
  nullable    = false
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds."
  type        = number
  default     = 60
  nullable    = false
}

locals {
  name              = "${var.project_name}-${var.environment}"
  alb_name          = substr(replace(lower("${local.name}-alb"), "/[^a-z0-9-]/", "-"), 0, 32)
  target_group_name = substr(replace(lower("${local.name}-api-tg"), "/[^a-z0-9-]/", "-"), 0, 32)
}
