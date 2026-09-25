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
  description = "HTTP listener port exposed by the ALB to CloudFront."
  type        = number
}

variable "enable_https_listener" {
  description = "Whether to create the optional HTTPS listener used by the ALB test path."
  type        = bool
  default     = false
  nullable    = false
}

variable "https_certificate_arn" {
  description = "ACM certificate ARN for the optional HTTPS listener."
  type        = string
  default     = null
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
  name = "${var.project_name}-${var.environment}"

  # ALB and target-group names are limited to 32 characters and cannot end
  # with a hyphen. Truncate the prefix before adding the resource suffix so
  # the suffix is preserved instead of being cut off by substr().
  normalized_name = trim(
    replace(lower(local.name), "/[^a-z0-9-]/", "-"),
    "-",
  )

  alb_name          = "${substr(local.normalized_name, 0, 32 - length("-alb"))}-alb"
  target_group_name = "${substr(local.normalized_name, 0, 32 - length("-api-tg"))}-api-tg"
}
