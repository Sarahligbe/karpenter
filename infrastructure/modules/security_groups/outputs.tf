output "controlplane_sg_id" {
  value = aws_security_group.k8s_controlplane_node.id
}

output "worker_sg_id" {
  value = aws_security_group.k8s_worker_node.id
}

output "eice_sg_id" {
  value = aws_security_group.instance_connect_endpoint.id
}