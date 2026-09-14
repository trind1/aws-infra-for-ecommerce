output "vpc_id" {
  description = "ID of the application VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the application VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs ordered by subnet number."
  value       = [for key in sort(keys(aws_subnet.public)) : aws_subnet.public[key].id]
}

output "database_subnet_ids" {
  description = "Private database subnet IDs ordered by subnet number."
  value       = [for key in sort(keys(aws_subnet.database)) : aws_subnet.database[key].id]
}

output "availability_zones" {
  description = "Availability Zones used by the subnet pairs."
  value       = var.availability_zones
}
