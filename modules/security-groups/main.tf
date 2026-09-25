locals {
  name = "${var.project_name}-${var.environment}"
}

# ============ SECURITY GROUPS  ============
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Ingress for direct HTTPS API clients to the ALB."
  vpc_id      = var.vpc_id

  # All rules are managed by standalone rule resources below.
  tags = {
    Name      = "${local.name}-alb-sg"
    Component = "security-groups"
    Tier      = "public"
  }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "Ingress for API instances from the ALB only."
  vpc_id      = var.vpc_id

  # All rules are managed by standalone rule resources below.
  tags = {
    Name      = "${local.name}-app-sg"
    Component = "security-groups"
    Tier      = "application"
  }
}

resource "aws_security_group" "database" {
  name        = "${local.name}-db-sg"
  description = "Ingress for the database from API instances only."
  vpc_id      = var.vpc_id

  # No egress rule is added; return traffic is stateful for allowed inbound connections.
  tags = {
    Name      = "${local.name}-db-sg"
    Component = "security-groups"
    Tier      = "database"
  }
}

# ============ ALB SECURITY GROUP RULES  ============
resource "aws_vpc_security_group_ingress_rule" "alb_from_https_test_clients" {
  for_each = var.alb_https_client_cidr_blocks

  security_group_id = aws_security_group.alb.id
  description       = "Explicit test client access to the optional ALB HTTPS listener."
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB may reach the API target port."
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}

# ============ APPLICATION SECURITY GROUP RULES  ============
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "API port from the ALB security group only."
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_database" {
  security_group_id            = aws_security_group.app.id
  description                  = "API instances may reach the database port."
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.database.id
}

resource "aws_vpc_security_group_egress_rule" "app_outbound" {
  security_group_id = aws_security_group.app.id
  description       = "Required for package installation, SSM and CloudWatch Agent."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ============ DATABASE SECURITY GROUP RULES  ============
resource "aws_vpc_security_group_ingress_rule" "database_from_app" {
  security_group_id            = aws_security_group.database.id
  description                  = "Database port from the API security group only."
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}
