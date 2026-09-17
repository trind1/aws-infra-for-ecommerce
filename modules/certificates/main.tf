/*
CURRENT DEV STATUS:
This module is not used by environments/dev. Dev uses
modules/certificates-imported for the local self-signed ALB certificate.
The Terraform configuration is intentionally commented out, not deleted,
so it can be restored later for a public-domain environment.

locals {
  name = "${var.project_name}-${var.environment}"
}

# NOTE: This module is not consumed by environments/dev.
# dev uses modules/certificates-imported for the local self-signed ALB certificate.
# The resources below remain active for future environments with public domains.

# ============ ALB REGIONAL CERTIFICATE  ============

resource "aws_acm_certificate" "alb" {
  domain_name               = var.alb_origin_domain
  validation_method         = "DNS"
  subject_alternative_names = var.alb_subject_alternative_names

  tags = {
    Name       = "${local.name}-alb-certificate"
    Component  = "certificates"
    Connection = "cloudfront-to-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============ ALB CERTIFICATE DNS VALIDATION  ============

resource "aws_route53_record" "alb_validation" {
  for_each = var.alb_route53_zone_id != null ? {
    for option in aws_acm_certificate.alb.domain_validation_options : option.domain_name => option
  } : {}

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = var.alb_route53_zone_id
}

resource "aws_acm_certificate_validation" "alb" {
  count = var.alb_route53_zone_id != null ? 1 : 0

  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.alb_validation : record.fqdn]
}

# FUTURE FOR DEV: Custom CloudFront viewer certificate requires a public domain,
# DNS validation and an ACM certificate in us-east-1.
# ============ CLOUDFRONT VIEWER CERTIFICATE  ============

# CloudFront accepts a custom viewer certificate only from us-east-1.
resource "aws_acm_certificate" "cloudfront" {
  count    = var.enable_custom_viewer_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name               = var.cloudfront_viewer_domain
  validation_method         = "DNS"
  subject_alternative_names = var.cloudfront_subject_alternative_names

  tags = {
    Name       = "${local.name}-cloudfront-certificate"
    Component  = "certificates"
    Connection = "client-to-cloudfront"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============ CLOUDFRONT CERTIFICATE DNS VALIDATION  ============

resource "aws_route53_record" "cloudfront_validation" {
  for_each = var.enable_custom_viewer_domain && var.cloudfront_route53_zone_id != null ? {
    for option in aws_acm_certificate.cloudfront[0].domain_validation_options : option.domain_name => option
  } : {}

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = var.cloudfront_route53_zone_id
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count    = var.enable_custom_viewer_domain && var.cloudfront_route53_zone_id != null ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_validation : record.fqdn]
}
*/
