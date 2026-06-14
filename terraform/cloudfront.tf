data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_origin_access_control" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name                              = "bunshin-static-oac"
  description                       = "Access control for Bunshin static assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_vpc_origin" "api_ingress_apne1" {
  vpc_origin_endpoint_config {
    arn                    = module.apne1.api_ingress_alb_arn
    http_port              = 80
    https_port             = 443
    name                   = "bunshin-apne1-api-ingress-alb"
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne1-api-ingress-origin"
    Service = "cloudfront"
  })
}

resource "aws_cloudfront_vpc_origin" "api_ingress_apne3" {
  vpc_origin_endpoint_config {
    arn                    = module.apne3.api_ingress_alb_arn
    http_port              = 80
    https_port             = 443
    name                   = "bunshin-apne3-api-ingress-alb"
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(local.common_tags, {
    Name    = "bunshin-apne3-api-ingress-origin"
    Service = "cloudfront"
  })
}

resource "aws_cloudfront_function" "api_origin_selector" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name    = "bunshin-api-origin-selector"
  runtime = "cloudfront-js-2.0"
  comment = "Selects the API ingress origin for active-active routing"
  publish = true
  code    = file("${path.module}/cloudfront/api-origin-selector.js")
}

# trivy:ignore:AVD-AWS-0010 -- CloudFront access logs are not required for the initial deployment
# trivy:ignore:AVD-AWS-0011 -- CloudFront WAF is not part of the initial entrypoint replacement
resource "aws_cloudfront_distribution" "main" {
  # checkov:skip=CKV_AWS_68:CloudFront WAF is not part of the initial entrypoint replacement
  # checkov:skip=CKV_AWS_86:CloudFront access logs are not required for the initial deployment
  # checkov:skip=CKV_AWS_310:Origin failover is handled separately from active-active routing
  # checkov:skip=CKV_AWS_374:Geo restriction is not required for this service
  # checkov:skip=CKV2_AWS_47:Log4j protection is not needed, backend does not use Java
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Bunshin public entrypoint"
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_All"

  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
    origin_id                = "static-s3"
  }

  origin {
    domain_name = module.apne1.api_ingress_alb_dns_name
    origin_id   = "api-ingress-apne1"

    vpc_origin_config {
      origin_keepalive_timeout = 60
      origin_read_timeout      = 120
      vpc_origin_id            = aws_cloudfront_vpc_origin.api_ingress_apne1.id
    }
  }

  origin {
    domain_name = module.apne3.api_ingress_alb_dns_name
    origin_id   = "api-ingress-apne3"

    vpc_origin_config {
      origin_keepalive_timeout = 60
      origin_read_timeout      = 120
      vpc_origin_id            = aws_cloudfront_vpc_origin.api_ingress_apne3.id
    }
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress                   = true
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    target_origin_id           = "static-s3"
    viewer_protocol_policy     = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                   = false
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    target_origin_id           = "api-ingress-apne1"
    viewer_protocol_policy     = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.api_origin_selector.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = merge(local.common_tags, {
    Name    = "bunshin-cloudfront"
    Service = "cloudfront"
  })
}
