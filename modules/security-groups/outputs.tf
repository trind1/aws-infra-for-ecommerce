output "alb_security_group_id" {
  description = "Security group ID for the ALB."
  value       = aws_security_group.alb.id
}

output "application_security_group_id" {
  description = "Security group ID for API instances."
  value       = aws_security_group.app.id
}

output "database_security_group_id" {
  description = "Security group ID for RDS."
  value       = aws_security_group.database.id
}
