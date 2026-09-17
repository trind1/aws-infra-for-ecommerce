locals {
  name = "${var.project_name}-${var.environment}"
}

# ============ IMPORTED ALB CERTIFICATE ============

resource "aws_acm_certificate" "alb" {
  private_key_wo         = file(var.private_key_file)
  private_key_wo_version = var.certificate_version
  certificate_body       = file(var.certificate_file)

  tags = {
    Name       = "${local.name}-alb-imported-certificate"
    Component  = "certificates"
    Connection = "client-to-alb-test"
  }
}
