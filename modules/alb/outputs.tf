output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "AWS-assigned ALB DNS name used by the environment's CloudFront origin."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Canonical ELB zone ID for a future Route 53 alias; this module creates no DNS record."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "API target group ARN."
  value       = aws_lb_target_group.api.arn
}

output "target_group_arn_suffix" {
  description = "API target group ARN suffix for CloudWatch dimensions."
  value       = aws_lb_target_group.api.arn_suffix
}

output "load_balancer_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions."
  value       = aws_lb.this.arn_suffix
}

output "https_listener_arn" {
  description = "ARN of the optional ALB HTTPS test listener, or null when disabled."
  value       = var.enable_https_listener ? aws_lb_listener.api_https_test[0].arn : null
}
