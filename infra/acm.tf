resource "aws_acm_certificate" "api" {
  domain_name       = "eks-gitops.fuhchu.org"
  validation_method = "DNS"

  lifecycle {
    # ACM certs can't be deleted while attached to a load balancer.
    # create_before_destroy ensures a new cert is issued before the old one
    # is removed during replacement — prevents downtime on cert rotation.
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-cert" }
}

output "acm_certificate_arn" {
  description = "Paste this ARN into helm/ingress values once cert is ISSUED"
  value       = aws_acm_certificate.api.arn
}

output "acm_validation_records" {
  description = "Add these CNAME records in Namecheap to validate the cert"
  value = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
