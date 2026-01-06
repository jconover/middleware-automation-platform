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
echo "AWX admin user: admin"
echo "Retrieve AWX admin password: kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d"
