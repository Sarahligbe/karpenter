output "ssm_role_name" {
  description = "ssm role name"
  value = aws_iam_role.k8s_ssm_role.name
}

output "ssm_profile_name" {
  description = "ssm role name"
  value = aws_iam_instance_profile.ssm_profile.name
}

output "aws_lb_role_name" {
  description = "aws loadbalancer role name"
  value = aws_iam_role.aws_lb_role.name
}

output "aws_lb_role_arn" {
  description = "aws loadbalancer role arn"
  value = aws_iam_role.aws_lb_role.arn
}

output "dns_role_arn" {
  description = "external dns role arn"
  value = aws_iam_role.dns_role.arn
}

output "karpenter_controller_role_arn" {
  description = "karpenter controller role arn"
  value = aws_iam_role.karpenter_controller_role.arn
}

output "karpenter_instance_role_arn" {
  description = "karpenter instance role arn"
  value = aws_iam_role.karpenter_instance_role.arn
}