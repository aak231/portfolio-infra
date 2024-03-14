

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
  bucket = "ahadkhans.com" # Update with a globally unique bucket name
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
data "aws_iam_user" "runner" {
  user_name = "aak231-github-runner"
}

resource "aws_s3_bucket_policy" "allow_access_from_current_account" {
  bucket = aws_s3_bucket.portfolio_bucket.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PublicReadGetObject",
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "s3:GetObject",
        "Resource" : "${aws_s3_bucket.portfolio_bucket.arn}/*"
      },
      {
        "Sid" : "S3PolicyStmt-DO-NOT-MODIFY-1698088573404",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "${data.aws_iam_user.runner.arn}",
          "Service" : "logging.s3.amazonaws.com"
        },
        "Action" : "s3:PutObject",
        "Resource" : "${aws_s3_bucket.portfolio_bucket.arn}/*"
      }
    ]
  })
}
resource "aws_acm_certificate" "cert" {
  domain_name       = "ahadkhans.com"
  validation_method = "DNS"
  subject_alternative_names = [
    "ahadkhans.com",
    "www.ahadkhans.com",
    "api.ahadkhans.com",
    "locationapi.ahadkhans.com"
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
data "aws_route53_zone" "portfolio" {
  name = "ahadkhans.com"
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
  zone_id         = data.aws_route53_zone.portfolio.zone_id
}

resource "aws_acm_certificate_validation" "cert_validation" {

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cname_records : record.fqdn]
}

# resource "aws_cloudfront_distribution" "s3_distribution" {
#   depends_on = [aws_apigatewayv2_domain_name.custom_domain]
#   origin_group {
#     origin_id = "s3_origin"
#     failover_criteria {
#       status_codes = [403, 404, 500, 502]
#     }
#     member {
#       origin_id = "S3Origin"
#     }
#     member {
#       origin_id = "ApiGatewayOrigin"
#     }
#   }
#   origin {
#     # domain_name = aws_s3_bucket.portfolio_bucket.website_endpoint
#     domain_name = aws_s3_bucket_website_configuration.portfolio_bucket_website.website_endpoint
#     origin_id   = "S3Origin"
#     custom_origin_config {
#       http_port              = "80"
#       https_port             = "443"
#       origin_protocol_policy = "http-only"
#       origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
#     }
#   }
#   origin {
#     domain_name = aws_apigatewayv2_domain_name.custom_domain.domain_name
#     origin_id   = "ApiGatewayOrigin"
#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "https-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }

#   enabled         = true
#   is_ipv6_enabled = true
#   aliases         = ["ahadkhans.com", "www.ahadkhans.com", "api.ahadkhans.com"]
#   default_cache_behavior {
#     allowed_methods  = ["GET", "HEAD", "OPTIONS"]
#     cached_methods   = ["GET", "HEAD"]
#     target_origin_id = "s3_origin"

#     forwarded_values {
#       query_string = false

#       cookies {
#         forward = "none"
#       }
#     }

#     viewer_protocol_policy = "allow-all"
#     min_ttl                = 0
#     default_ttl            = 3600
#     max_ttl                = 86400
#   }

#   price_class = "PriceClass_200"

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   tags = {
#     Environment = "Production via Terraform"
#   }

#   viewer_certificate {
#     acm_certificate_arn      = aws_acm_certificate.cert.arn
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1.2_2021"
#   }
# }
