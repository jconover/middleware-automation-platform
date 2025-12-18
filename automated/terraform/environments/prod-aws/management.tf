# =============================================================================
# Management Server - AWX/Jenkins for CI/CD and Automation
# =============================================================================
# This instance runs in a public subnet and can manage all other instances
# via SSM (no VPC peering required for multi-region).
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "create_management_server" {
  description = "Whether to create the AWX/Jenkins management server"
  type        = bool
  default     = true
}

variable "management_instance_type" {
  description = "EC2 instance type for management server (AWX needs 4GB+ RAM)"
  type        = string
  default     = "t3.medium"  # 2 vCPU, 4GB RAM (~$30/month)
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks allowed to access management server (your IP)"
  type        = list(string)
  default     = ["104.55.73.102/32"]  # Restrict this to your IP in production!
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "management" {
  count = var.create_management_server ? 1 : 0

  name        = "${local.name_prefix}-mgmt-sg"
  description = "Security group for AWX/Jenkins management server"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # AWX Web UI
  ingress {
    description = "AWX HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # AWX HTTP (redirects to HTTPS)
  ingress {
    description = "AWX HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Jenkins
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Prometheus (for monitoring)
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  # Grafana
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-mgmt-sg"
  }
}

# -----------------------------------------------------------------------------
# IAM Role - Full management permissions
# -----------------------------------------------------------------------------
resource "aws_iam_role" "management" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-mgmt-role"
  }
}

# SSM for managing other instances
resource "aws_iam_role_policy_attachment" "management_ssm" {
  count = var.create_management_server ? 1 : 0

  role       = aws_iam_role.management[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# EC2 for describing/managing instances
resource "aws_iam_role_policy_attachment" "management_ec2" {
  count = var.create_management_server ? 1 : 0

  role       = aws_iam_role.management[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# Secrets Manager for database credentials
resource "aws_iam_role_policy_attachment" "management_secrets" {
  count = var.create_management_server ? 1 : 0

  role       = aws_iam_role.management[0].name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# CloudWatch for logs and metrics
resource "aws_iam_role_policy_attachment" "management_cloudwatch" {
  count = var.create_management_server ? 1 : 0

  role       = aws_iam_role.management[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# S3 for Terraform state and artifacts
resource "aws_iam_role_policy_attachment" "management_s3" {
  count = var.create_management_server ? 1 : 0

  role       = aws_iam_role.management[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "management" {
  count = var.create_management_server ? 1 : 0

  name = "${local.name_prefix}-mgmt-profile"
  role = aws_iam_role.management[0].name
}

# -----------------------------------------------------------------------------
# Elastic IP (stable public IP)
# -----------------------------------------------------------------------------
resource "aws_eip" "management" {
  count = var.create_management_server ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-mgmt-eip"
  }
}

resource "aws_eip_association" "management" {
  count = var.create_management_server ? 1 : 0

  instance_id   = aws_instance.management[0].id
  allocation_id = aws_eip.management[0].id
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "management" {
  count = var.create_management_server ? 1 : 0

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.management_instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.management[0].id]
  iam_instance_profile   = aws_iam_instance_profile.management[0].name

  root_block_device {
    volume_size           = 50  # More storage for containers/artifacts
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name_prefix}-mgmt-root"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/user-data.log) 2>&1

    echo "=== Starting Management Server Setup ==="

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install prerequisites
    apt-get install -y \
      python3 python3-pip python3-venv \
      git curl wget unzip \
      apt-transport-https ca-certificates \
      gnupg lsb-release jq

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip

    # Install Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Install K3s (lightweight Kubernetes for AWX)
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

    # Wait for K3s to be ready
    sleep 30
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    # Install Ansible
    pip3 install ansible boto3 botocore

    # Install Ansible collections
    ansible-galaxy collection install amazon.aws community.general kubernetes.core

    # Create ansible user
    useradd -m -s /bin/bash ansible
    usermod -aG docker ansible
    mkdir -p /home/ansible/.ssh
    cp /home/ubuntu/.ssh/authorized_keys /home/ansible/.ssh/
    chown -R ansible:ansible /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
    chmod 600 /home/ansible/.ssh/authorized_keys
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

    # Copy kubeconfig for ansible user
    mkdir -p /home/ansible/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ansible/.kube/config
    chown -R ansible:ansible /home/ansible/.kube

    # Install AWX Operator (using kustomize method)
    kubectl apply -k "github.com/ansible/awx-operator/config/default?ref=2.19.1"

    # Wait for operator to be ready
    echo "Waiting for AWX operator to be ready..."
    sleep 120
    kubectl wait --for=condition=Available deployment/awx-operator-controller-manager -n awx --timeout=300s || true

    # Deploy AWX instance
    cat <<'AWXEOF' | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: NodePort
  nodeport_port: 30080
AWXEOF

    echo "=== Management Server Setup Complete ==="
    echo "AWX will be available at http://<public-ip>:30080 in ~5 minutes"
    echo "Get AWX admin password: kubectl get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d"
  EOF
  )

  tags = {
    Name        = "${local.name_prefix}-management"
    Role        = "management"
    AnsibleGroup = "management_servers"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# -----------------------------------------------------------------------------
# Allow management server to SSH to Liberty instances
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "liberty_ssh_from_management" {
  count = var.create_management_server ? 1 : 0

  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.liberty.id
  source_security_group_id = aws_security_group.management[0].id
  description              = "SSH from management server"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "management_public_ip" {
  description = "Public IP of the management server"
  value       = var.create_management_server ? aws_eip.management[0].public_ip : null
}

output "management_private_ip" {
  description = "Private IP of the management server"
  value       = var.create_management_server ? aws_instance.management[0].private_ip : null
}

output "awx_url" {
  description = "AWX Web UI URL"
  value       = var.create_management_server ? "http://${aws_eip.management[0].public_ip}:30080" : null
}

output "awx_admin_password_command" {
  description = "Command to get AWX admin password"
  value       = "ssh ubuntu@${var.create_management_server ? aws_eip.management[0].public_ip : "N/A"} 'sudo kubectl get secret awx-admin-password -o jsonpath=\"{.data.password}\" | base64 -d'"
}

output "management_ssh_command" {
  description = "SSH command to connect to management server"
  value       = var.create_management_server ? "ssh -i ~/.ssh/ansible_ed25519 ubuntu@${aws_eip.management[0].public_ip}" : null
}
