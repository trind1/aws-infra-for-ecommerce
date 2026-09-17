# These outputs belong to the public-domain/future certificate flow.
# environments/dev does not consume this module or these outputs.

/*
CURRENT DEV STATUS:
These outputs belong to the unused public-domain certificate module.
Dev consumes certificate_arn from modules/certificates-imported instead.

output "alb_certificate_arn" {
  description = "Issued regional ACM certificate ARN for the ALB origin, or null until external validation is confirmed."
  value = var.alb_route53_zone_id != null ? (
    aws_acm_certificate_validation.alb[0].certificate_arn
    ) : (
    var.alb_certificate_ready ? aws_acm_certificate.alb.arn : null
  )
}

output "cloudfront_certificate_arn" {
  description = "Issued us-east-1 ACM certificate ARN for a custom CloudFront viewer domain, or null when not ready."
  value = var.enable_custom_viewer_domain ? (
    var.cloudfront_route53_zone_id != null ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : (
      var.cloudfront_certificate_ready ? aws_acm_certificate.cloudfront[0].arn : null
    )
  ) : null
}

output "alb_certificate_validation_records" {
  description = "ACM DNS validation CNAMEs for the regional ALB certificate."
  value = [
    for option in aws_acm_certificate.alb.domain_validation_options : {
      domain_name = option.domain_name
      name        = option.resource_record_name
      type        = option.resource_record_type
      value       = option.resource_record_value
    }
  ]
}

output "cloudfront_certificate_validation_records" {
  description = "ACM DNS validation CNAMEs for the us-east-1 CloudFront viewer certificate."
  value = var.enable_custom_viewer_domain ? [
    for option in aws_acm_certificate.cloudfront[0].domain_validation_options : {
      domain_name = option.domain_name
      name        = option.resource_record_name
      type        = option.resource_record_type
      value       = option.resource_record_value
    }
  ] : []
}
*/
