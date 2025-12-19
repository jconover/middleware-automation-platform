#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Starting Liberty Server Setup ==="

# Update system
apt-get update
apt-get upgrade -y

# Install prerequisites for Ansible
apt-get install -y python3 python3-pip

# Install AWS CLI
apt-get install -y awscli

# Create ansible user
useradd -m -s /bin/bash ansible
mkdir -p /home/ansible/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/ansible/.ssh/authorized_keys
chown -R ansible:ansible /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
chmod 600 /home/ansible/.ssh/authorized_keys

# Add ansible to sudoers
echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

# Tag instance as ready
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Status,Value=Ready --region ${aws_region}

echo "=== Liberty Server Setup Complete ==="
