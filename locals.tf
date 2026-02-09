locals {
  domain = var.domain_name
  www_domain = "www.${var.domain_name}"
  api_domain = "api.${var.domain_name}"
}