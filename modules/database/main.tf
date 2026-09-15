locals {
  name          = "${var.project_name}-${var.environment}"
  db_identifier = substr(replace(lower("${local.name}-db"), "/[^a-z0-9-]/", "-"), 0, 63)
  subnet_group  = substr(replace(lower("${local.name}-db-subnet-group"), "/[^a-z0-9-]/", "-"), 0, 255)
}

# ============ RDS DB SUBNET GROUP  ============
resource "aws_db_subnet_group" "this" {
  name        = local.subnet_group
  description = "Private database subnets for ${local.name}."
  subnet_ids  = var.subnet_ids

  tags = {
    Name      = local.subnet_group
    Component = "database"
    Tier      = "database"
  }
}

# ============ RDS CLOUDWATCH LOG GROUPS  ============
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${local.db_identifier}/${each.value}"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name      = "${local.name}-rds-${each.value}-logs"
    Component = "database"
    Tier      = "database"
  }
}

# ============ SINGLE-AZ RDS INSTANCE  ============
resource "aws_db_instance" "this" {
  identifier                      = local.db_identifier
  engine                          = var.engine
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  allocated_storage               = var.allocated_storage
  max_allocated_storage           = var.max_allocated_storage
  storage_type                    = var.storage_type
  storage_encrypted               = true
  db_name                         = var.database_name == "" ? null : var.database_name
  username                        = var.username
  password                        = var.password
  port                            = var.port
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.security_group_id]
  publicly_accessible             = false
  multi_az                        = false
  backup_retention_period         = var.backup_retention_period
  backup_window                   = var.backup_window
  maintenance_window              = var.maintenance_window
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${local.db_identifier}-final")
  copy_tags_to_snapshot           = true
  delete_automated_backups        = var.delete_automated_backups
  apply_immediately               = var.apply_immediately
  auto_minor_version_upgrade      = var.auto_minor_version_upgrade
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  depends_on = [aws_cloudwatch_log_group.rds]

  tags = {
    Name      = local.db_identifier
    Component = "database"
    Tier      = "database"
  }
}
