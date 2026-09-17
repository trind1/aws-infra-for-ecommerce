/*
CURRENT DEV STATUS:
These inputs belong to the unused public-domain certificate module.
Dev uses modules/certificates-imported instead.

variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names."
  type        = string
}

# These inputs are intentionally not supplied by environments/dev.
# dev uses modules/certificates-imported because its ALB hostname is local and
# its certificate is generated locally instead of being issued by a public CA.

variable "alb_origin_domain" {
  description = "Hostname that CloudFront uses to connect to the ALB over HTTPS."
  type        = string
}

variable "alb_subject_alternative_names" {
  description = "Additional DNS names included in the regional ALB certificate."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "alb_route53_zone_id" {
  description = "Optional Route 53 public hosted zone ID for ALB certificate DNS validation."
  type        = string
  default     = null
}

variable "alb_certificate_ready" {
  description = "Set true after an externally validated ALB certificate is confirmed ISSUED."
  type        = bool
  default     = false
  nullable    = false
}

# FUTURE FOR DEV: Keep disabled until a public CloudFront custom domain exists.
variable "enable_custom_viewer_domain" {
  description = "Whether to request a future custom viewer-domain certificate for CloudFront."
  type        = bool
  default     = false
  nullable    = false
}

variable "cloudfront_viewer_domain" {
  description = "Custom viewer domain for CloudFront when the future viewer-domain feature is enabled."
  type        = string
  default     = null
}

variable "cloudfront_subject_alternative_names" {
  description = "Additional DNS names included in the future CloudFront viewer certificate."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "cloudfront_route53_zone_id" {
  description = "Optional Route 53 public hosted zone ID for CloudFront certificate DNS validation."
  type        = string
  default     = null
}

variable "cloudfront_certificate_ready" {
  description = "Set true after an externally validated CloudFront certificate is confirmed ISSUED."
  type        = bool
  default     = false
  nullable    = false
}
*/
