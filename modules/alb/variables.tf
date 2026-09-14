variable "project_name" {
  description = "Project identifier used in ALB names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in ALB names."
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
}

variable "listener_port" {
  description = "ALB listener port. Use 80 in no-domain mode or 443 with an ACM certificate."
  type        = number
}

variable "certificate_arn" {
  description = "Regional ACM certificate ARN; null selects the explicit HTTP bootstrap fallback."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "origin_custom_header_name" {
  description = "Header name checked by the listener rule."
  type        = string
  default     = "X-CloudFront-Origin-Verify"
}

variable "origin_custom_header_value" {
  description = "Sensitive header value checked by the listener rule."
  type        = string
  sensitive   = true
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Common tags applied to taggable ALB resources."
  type        = map(string)
  default     = {}
}

locals {
  name              = "${var.project_name}-${var.environment}"
  alb_name          = substr(replace(lower("${local.name}-alb"), "/[^a-z0-9-]/", "-"), 0, 32)
  target_group_name = substr(replace(lower("${local.name}-api-tg"), "/[^a-z0-9-]/", "-"), 0, 32)
}
