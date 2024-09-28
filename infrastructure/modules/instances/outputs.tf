output "controlplane_instance_id" {
  description = "K8s control plane instance ID"
  value = aws_instance.controlplane[*].id
}

output "worker_instance_id" {
  description = "K8s worker instance ID"
  value = aws_instance.worker[*].id
}

output "k8s_join_command_arn" {
  description = "ARN for the k8s join command"
  value = aws_ssm_parameter.k8s_join_command.arn
}