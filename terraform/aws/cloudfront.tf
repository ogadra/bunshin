data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_origin_request_policy" "api_ingress" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name    = "bunshin-api-ingress"
  comment = "Forward API request data without client-controlled fallback headers"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = [
        "Accept",
        "Accept-Language",
        "CloudFront-Viewer-Address",
        "Content-Type",
        "Origin",
        "Referer",
        "User-Agent",
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_origin_access_control" "static" {
  # checkov:skip=CKV_BUNSHIN_1:Resource does not support tags
  name                              = "bunshin-static-oac"
  description                       = "Access control for Bunshin static assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# trivy:ignore:AVD-AWS-0010 -- CloudFront access logs are not required for the initial deployment
resource "aws_cloudfront_distribution" "main" {
  # checkov:skip=CKV_AWS_86:CloudFront access logs are not required for the initial deployment
  # checkov:skip=CKV_AWS_310:Global Accelerator handles health-aware API origin routing
  # checkov:skip=CKV_AWS_374:Geo restriction is not required for this service
  # checkov:skip=CKV2_AWS_47:Log4j protection is not needed, backend does not use Java
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Bunshin public entrypoint"
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_200"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = module.apne1.static_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
    origin_id                = "static-s3-apne1"
  }

  origin {
    domain_name              = module.apne3.static_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
    origin_id                = "static-s3-apne3"
  }

  origin {
    domain_name = local.api_ingress_origin_domain_name
    origin_id   = "api-ingress-global-accelerator"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin_group {
    origin_id = "static-s3-failover"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "static-s3-apne1"
    }

    member {
      origin_id = "static-s3-apne3"
    }
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    compress                   = true
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    target_origin_id           = "static-s3-failover"
    viewer_protocol_policy     = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.api_ingress.id
    compress                   = false
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    target_origin_id           = "api-ingress-global-accelerator"
    viewer_protocol_policy     = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cloudfront.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = merge(local.common_tags, {
    Name    = "bunshin-cloudfront"
    Service = "cloudfront"
  })
}
