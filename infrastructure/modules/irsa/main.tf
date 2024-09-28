resource "aws_s3_bucket" "discovery_bucket" {
  bucket = "aws-irsa-oidc-discovery-${var.s3_suffix}"
}

resource "aws_s3_bucket_public_access_block" "discovery_bucket" {
  bucket = aws_s3_bucket.discovery_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "readonly_policy" {
  bucket = aws_s3_bucket.discovery_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.discovery_bucket.arn,
          "${aws_s3_bucket.discovery_bucket.arn}/*",
        ]
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.discovery_bucket]
}

resource "null_resource" "generate_keys" {
  provisioner "local-exec" {
    command = "bash ${path.module}/generate_keys.sh"
  }
}

data "local_file" "private_key" {
  depends_on = [null_resource.generate_keys]
  filename = "${path.module}/keys/oidc-issuer.key"
}

data "local_file" "public_key" {
  depends_on = [null_resource.generate_keys]
  filename = "${path.module}/keys/oidc-issuer.pub"
}

resource "aws_ssm_parameter" "private_key" {
  name  = "/k8s/irsa/private-key"
  description = "Private key for irsa"
  type  = "SecureString"
  value = data.local_file.private_key.content
}

resource "aws_ssm_parameter" "public_key" {
  name  = "/k8s/irsa/public-key"
  description = "Public key for irsa"
  type  = "SecureString"
  value = data.local_file.public_key.content
}

resource "aws_s3_object" "jwks_json" {
  depends_on = [null_resource.generate_keys]
  bucket     = aws_s3_bucket.discovery_bucket.id
  key        = "keys.json"
  source     = "${path.module}/keys/keys.json"
  content_type = "application/json"
}

resource "aws_s3_object" "discovery_json" {
  bucket = aws_s3_bucket.discovery_bucket.id
  key    = ".well-known/openid-configuration"
  content = templatefile("${path.module}/discovery.json", {
    issuer_hostpath = "s3-${var.region}.amazonaws.com/${aws_s3_bucket.discovery_bucket.id}"
  })
  content_type = "application/json"
}

data "tls_certificate" "s3" {
  url = "https://s3-${var.region}.amazonaws.com"
}

resource "aws_iam_openid_connect_provider" "main" {
  url             = "https://s3-${var.region}.amazonaws.com/${aws_s3_bucket.discovery_bucket.id}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.s3.certificates[0].sha1_fingerprint]
}

#resource "null_resource" "cleanup_keys" {
#  depends_on = [aws_s3_object.jwks_json, aws_iam_openid_connect_provider.main, aws_ssm_parameter.private_key, aws_ssm_parameter.public_key]
#
#  provisioner "local-exec" {
#    command = "rm -rf ${path.module}/keys"
#  }
#}
