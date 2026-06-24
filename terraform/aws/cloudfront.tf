locals {
  has_azure_origin = var.azure_blob_endpoint != ""
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project_name} multicloud CDN"

  # Primary origin - S3
  origin {
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id                = "s3-primary"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Failover origin - Azure Blob Storage (only if endpoint provided)
  dynamic "origin" {
    for_each = local.has_azure_origin ? [1] : []
    content {
      domain_name = var.azure_blob_endpoint
      origin_id   = "azure-failover"
      origin_path = "/${var.azure_container_name}"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Origin failover group (only if Azure origin exists)
  dynamic "origin_group" {
    for_each = local.has_azure_origin ? [1] : []
    content {
      origin_id = "multicloud-failover-group"

      failover_criteria {
        status_codes = [403, 404, 500, 502, 503, 504]
      }

      member {
        origin_id = "s3-primary"
      }

      member {
        origin_id = "azure-failover"
      }
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.has_azure_origin ? "multicloud-failover-group" : "s3-primary"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
