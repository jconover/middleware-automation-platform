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

# =============================================================================
# Tag instance as ready using IMDSv2
# =============================================================================
# IMDSv2 requires a session token for all metadata requests.
# We use retries and validation to handle transient network issues during boot.
# =============================================================================

# Function to retrieve IMDSv2 token with retries
get_imds_token() {
  local max_attempts=5
  local attempt=1
  local token=""

  while [ $attempt -le $max_attempts ]; do
    token=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
      --connect-timeout 5 \
      --max-time 10 \
      2>/dev/null) || true

    if [ -n "$token" ]; then
      echo "$token"
      return 0
    fi

    echo "IMDSv2 token retrieval attempt $attempt/$max_attempts failed, retrying in 2s..." >&2
    sleep 2
    attempt=$((attempt + 1))
  done

  echo "ERROR: Failed to retrieve IMDSv2 token after $max_attempts attempts" >&2
  return 1
}

# Function to retrieve instance metadata with retries
get_instance_metadata() {
  local token="$1"
  local path="$2"
  local max_attempts=3
  local attempt=1
  local value=""

  while [ $attempt -le $max_attempts ]; do
    value=$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/$path" \
      --connect-timeout 5 \
      --max-time 10 \
      2>/dev/null) || true

    if [ -n "$value" ]; then
      echo "$value"
      return 0
    fi

    echo "Metadata retrieval attempt $attempt/$max_attempts for $path failed, retrying..." >&2
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "ERROR: Failed to retrieve metadata $path after $max_attempts attempts" >&2
  return 1
}

# Retrieve IMDSv2 token
TOKEN=$(get_imds_token)
if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not obtain IMDSv2 token. Instance tagging skipped."
  exit 0  # Don't fail the entire user-data script for tagging failure
fi

# Retrieve instance ID
INSTANCE_ID=$(get_instance_metadata "$TOKEN" "instance-id")
if [ -z "$INSTANCE_ID" ]; then
  echo "ERROR: Could not obtain instance ID. Instance tagging skipped."
  exit 0
fi

# Validate instance ID format (i-xxxxxxxxxxxxxxxxx)
if ! echo "$INSTANCE_ID" | grep -qE '^i-[0-9a-f]{8,17}$'; then
  echo "ERROR: Invalid instance ID format: $INSTANCE_ID. Instance tagging skipped."
  exit 0
fi

# Tag instance as ready
echo "Tagging instance $INSTANCE_ID as Ready..."
if aws ec2 create-tags --resources "$INSTANCE_ID" --tags Key=Status,Value=Ready --region ${aws_region}; then
  echo "Successfully tagged instance $INSTANCE_ID as Ready"
else
  echo "WARNING: Failed to tag instance. This is non-fatal."
fi

echo "=== Liberty Server Setup Complete ==="
