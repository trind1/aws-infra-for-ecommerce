output "db_instance_arn" {
  description = "RDS instance ARN."
  value       = aws_db_instance.this.arn
}

output "db_instance_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "db_endpoint" {
  description = "RDS endpoint including port."
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS DNS address without port."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS database port."
  value       = aws_db_instance.this.port
}

output "db_subnet_group_name" {
  description = "RDS DB subnet group name."
  value       = aws_db_subnet_group.this.name
}

output "rds_log_group_names" {
  description = "RDS engine log groups managed by this module."
  value       = { for log_type, group in aws_cloudwatch_log_group.rds : log_type => group.name }
}
