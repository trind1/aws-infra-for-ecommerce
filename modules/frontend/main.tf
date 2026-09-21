# ============ CLOUDFRONT MANAGED POLICIES  ============

data "aws_cloudfront_cache_policy" "s3_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "api_disabled" {
  count = var.enable_api_origin ? 1 : 0

  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api_all_viewer_except_host" {
  count = var.enable_api_origin ? 1 : 0

  name = "Managed-AllViewerExceptHostHeader"
}

# ============ FRONTEND NAMING  ============

locals {
  name          = "${var.project_name}-${var.environment}"
  bucket_prefix = substr(replace(lower("${local.name}-frontend"), "/[^a-z0-9-]/", "-"), 0, 37)
}

# ============ PRIVATE FRONTEND BUCKET  ============

resource "aws_s3_bucket" "frontend" {
  bucket_prefix = "${local.bucket_prefix}-"
  force_destroy = var.bucket_force_destroy

  tags = {
    Name      = "${local.name}-frontend"
    Component = "frontend"
    Tier      = "frontend"
  }
}

# ============ FRONTEND BUCKET PUBLIC ACCESS BLOCK  ============

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============ FRONTEND BUCKET OWNERSHIP  ============

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ============ FRONTEND BUCKET VERSIONING  ============

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============ FRONTEND BUCKET ENCRYPTION  ============

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ============ CLOUDFRONT ORIGIN ACCESS CONTROL  ============

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend-oac"
  description                       = "SigV4 access from CloudFront to the private frontend bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============ CLOUDFRONT DISTRIBUTION  ============

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${local.name} frontend distribution"
  default_root_object = "index.html"
  aliases             = var.cloudfront_aliases
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = local.frontend_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  dynamic "origin" {
    for_each = var.enable_api_origin ? [var.alb_origin_dns_name] : []

    content {
      domain_name = origin.value
      origin_id   = local.api_origin_id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = var.alb_origin_protocol_policy
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = var.origin_custom_header_name
        value = var.origin_custom_header_value
      }
    }
  }

  # Static assets are private in S3 and are fetched only through the OAC.
  default_cache_behavior {
    target_origin_id       = local.frontend_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.s3_optimized.id
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
  }

  # ============ SPA FALLBACK ============
  # S3 returns 403 for missing private objects. Rewrite both missing-object
  # responses to index.html so client-side routes work through CloudFront.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.enable_api_origin ? [1] : []

    content {
      path_pattern             = "/api/*"
      target_origin_id         = local.api_origin_id
      viewer_protocol_policy   = "redirect-to-https"
      compress                 = true
      cache_policy_id          = data.aws_cloudfront_cache_policy.api_disabled[0].id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api_all_viewer_except_host[0].id
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods           = ["GET", "HEAD"]
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.cloudfront_certificate_arn
    cloudfront_default_certificate = var.cloudfront_certificate_arn == null
    minimum_protocol_version       = var.cloudfront_certificate_arn == null ? null : "TLSv1.2_2021"
    ssl_support_method             = var.cloudfront_certificate_arn == null ? null : "sni-only"
  }

  tags = {
    Name      = "${local.name}-cloudfront"
    Component = "frontend"
    Tier      = "edge"
  }

  lifecycle {
    precondition {
      condition = (length(var.cloudfront_aliases) == 0) == (
        var.cloudfront_certificate_arn == null
      )
      error_message = "cloudfront_aliases and cloudfront_certificate_arn must be enabled together."
    }
  }
}

# ============ FRONTEND BUCKET POLICY  ============

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}
