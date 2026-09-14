output "bucket_id" {
  description = "Frontend S3 bucket name."
  value       = aws_s3_bucket.frontend.id
}

output "bucket_arn" {
  description = "Frontend S3 bucket ARN."
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution hostname."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "origin_access_control_id" {
  description = "CloudFront Origin Access Control ID."
  value       = aws_cloudfront_origin_access_control.frontend.id
}
