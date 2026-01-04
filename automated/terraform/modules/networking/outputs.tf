# =============================================================================
# Networking Module - Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnets" {
  description = "List of public subnet objects"
  value       = aws_subnet.public
}

output "private_subnets" {
  description = "List of private subnet objects"
  value       = aws_subnet.private
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IPs"
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value = var.enable_nat_gateway ? (
    var.high_availability_nat ? aws_route_table.private_per_az[*].id : [aws_route_table.private[0].id]
  ) : [aws_route_table.private_no_nat[0].id]
}

output "flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC flow logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}

output "flow_logs_kms_key_arn" {
  description = "ARN of the KMS key used for flow logs encryption"
  value       = var.enable_flow_logs && var.enable_flow_logs_encryption ? aws_kms_key.logs[0].arn : null
}

# Backward compatibility outputs (singular names)
output "nat_gateway_id" {
  description = "ID of the first NAT Gateway (for backward compatibility)"
  value       = length(aws_nat_gateway.main) > 0 ? aws_nat_gateway.main[0].id : null
}

output "nat_gateway_public_ip" {
  description = "Public IP of the first NAT Gateway (for backward compatibility)"
  value       = length(aws_eip.nat) > 0 ? aws_eip.nat[0].public_ip : null
}

output "private_route_table_id" {
  description = "ID of the first private route table (for backward compatibility)"
  value = var.enable_nat_gateway ? (
    var.high_availability_nat ? aws_route_table.private_per_az[0].id : aws_route_table.private[0].id
  ) : aws_route_table.private_no_nat[0].id
}
