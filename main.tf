

terraform {
  backend "s3" {
    bucket  = "portfolio-infra-tf-state-file"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
provider "aws" {
  region = "us-east-1"
}
resource "aws_s3_bucket" "portfolio_bucket" {
  bucket = local.domain # Update with a globally unique bucket name
  tags = {
    Name        = "My portfolio via terraform"
    Environment = "Production"
  }
}

resource "aws_s3_bucket_ownership_controls" "portfolio_bucket_ownership" {
  bucket = aws_s3_bucket.portfolio_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "portfolio_bucket_access" {
  bucket = aws_s3_bucket.portfolio_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "example" {
  depends_on = [
    aws_s3_bucket_ownership_controls.portfolio_bucket_ownership,
    aws_s3_bucket_public_access_block.portfolio_bucket_access,
  ]

  bucket = aws_s3_bucket.portfolio_bucket.id
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "portfolio_bucket_website" {
  bucket = aws_s3_bucket.portfolio_bucket.bucket
  index_document {
    suffix = "index.html"
  }

}
resource "aws_s3_bucket_policy" "allow_access_from_current_account" {
  bucket = aws_s3_bucket.portfolio_bucket.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:GetObject"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.portfolio_bucket.bucket}/*",
        "Principal" : {
          "AWS" : [
            "*"
          ]
        }
      }
    ]
  })
}
resource "aws_acm_certificate" "cert" {
  domain_name       = local.domain
  validation_method = "DNS"
  subject_alternative_names = [
    local.domain,
    local.www_domain,
    local.api_domain
    # Add additional domain names as needed
  ]
  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}
resource "aws_route53_zone" "portfolio" {
  name = local.domain
}
resource "aws_route53_record" "cname_records" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.portfolio.zone_id
}

resource "aws_acm_certificate_validation" "cert_validation" {

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cname_records : record.fqdn]
}
locals {
  s3_origin_id = "myS3Origin"
}
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.portfolio_bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  # logging_config {
  #   include_cookies = false
  #   bucket          = "mylogs.s3.amazonaws.com"
  #   prefix          = "myprefix"
  # }
  aliases = [
    local.domain,
    local.www_domain,
    local.api_domain
    ]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "Production via Terraform"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
resource "aws_route53_record" "cloudfront_distribution" {
  zone_id = aws_route53_zone.portfolio.zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
