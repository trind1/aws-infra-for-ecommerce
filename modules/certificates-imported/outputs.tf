output "certificate_arn" {
  description = "ARN of the imported ACM certificate for the ALB HTTPS test listener."
  value       = aws_acm_certificate.alb.arn
}
