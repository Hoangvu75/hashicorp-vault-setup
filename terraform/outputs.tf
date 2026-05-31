output "instance_ids" {
  value       = aws_instance.vault_node[*].id
  description = "The instance IDs of the Vault nodes"
}

output "private_ips" {
  value       = aws_instance.vault_node[*].private_ip
  description = "The internal IPs of the Vault nodes"
}

output "public_ips" {
  value       = aws_instance.vault_node[*].public_ip
  description = "The public IPs of the Vault nodes"
}

output "lb_dns_name" {
  value       = aws_lb.vault_nlb.dns_name
  description = "The DNS name of the Vault load balancer"
}


