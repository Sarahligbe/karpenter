output "cert_arn" {
  description = "ARN for the acm cert"
  value = aws_acm_certificate.main.arn
}