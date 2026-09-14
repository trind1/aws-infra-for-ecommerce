variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names."
  type        = string
}

variable "alb_origin_dns_name" {
  description = "ALB DNS name used as the CloudFront API origin."
  type        = string
}

variable "alb_origin_protocol_policy" {
  description = "CloudFront-to-ALB protocol; HTTP is the explicit no-domain fallback."
  type        = string

  validation {
    condition     = contains(["http-only", "https-only"], var.alb_origin_protocol_policy)
    error_message = "alb_origin_protocol_policy must be http-only or https-only."
  }
}

variable "cloudfront_aliases" {
  description = "Optional aliases for CloudFront; empty uses its default hostname."
  type        = list(string)
  default     = []
}

variable "cloudfront_certificate_arn" {
  description = "Optional issued us-east-1 ACM certificate ARN."
  type        = string
  default     = null
}

variable "cloudfront_price_class" {
  description = "CloudFront price class selected for this environment."
  type        = string
  default     = "PriceClass_100"
}

variable "origin_custom_header_name" {
  description = "Header name CloudFront sends to the ALB for origin authentication."
  type        = string
  default     = "X-CloudFront-Origin-Verify"
}

variable "origin_custom_header_value" {
  description = "Sensitive shared value CloudFront sends to the ALB."
  type        = string
  sensitive   = true
}

variable "bucket_force_destroy" {
  description = "Allow Terraform to delete frontend objects during destroy; keep false for safety."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to taggable frontend resources."
  type        = map(string)
  default     = {}
}

locals {
  frontend_origin_id = "${var.project_name}-${var.environment}-s3"
  api_origin_id      = "${var.project_name}-${var.environment}-alb"
}
