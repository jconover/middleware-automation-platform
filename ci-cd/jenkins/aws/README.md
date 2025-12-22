# Jenkins on AWS Management Server

Deploy Jenkins to the AWS management server (mw-prod-management) for production CI/CD pipelines.

## Prerequisites

- AWS management server running (deployed via Terraform)
- SSH access to the management server
- Ansible installed locally
- AWS credentials with ECR/ECS permissions

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│  ┌─────────────────┐     ┌─────────────────────────────┐   │
│  │ Management      │     │ ECS Fargate                  │   │
│  │ Server          │     │                              │   │
│  │ ┌─────────────┐ │     │  ┌─────────┐  ┌─────────┐   │   │
│  │ │   Jenkins   │─┼─────┼──│  Task   │  │  Task   │   │   │
│  │ │   :8080     │ │     │  │         │  │         │   │   │
│  │ └─────────────┘ │     │  └─────────┘  └─────────┘   │   │
│  │                 │     │                              │   │
│  │ ┌─────────────┐ │     └─────────────────────────────┘   │
│  │ │   Podman    │ │                                        │
│  │ │   (builds)  │ │     ┌─────────────────────────────┐   │
│  │ └─────────────┘ │     │ ECR                          │   │
│  └─────────────────┘     │  mw-prod-liberty:latest      │   │
│          │               └─────────────────────────────┘   │
│          │                                                  │
└──────────┼──────────────────────────────────────────────────┘
           │
    ┌──────▼──────┐
    │   Your PC   │
    │  (Ansible)  │
    └─────────────┘
```

## Quick Start

### 1. Get Management Server IP

```bash
cd automated/terraform/environments/prod-aws
terraform output management_public_ip
```

### 2. Create Inventory File

```bash
cat > inventory.ini << EOF
[management]
mw-prod-management ansible_host=<MANAGEMENT_IP> ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/your-key.pem
EOF
```

### 3. Run Ansible Playbook

```bash
cd ci-cd/jenkins/aws

# Set admin password (optional)
export JENKINS_ADMIN_PASSWORD="YourSecurePassword"

# Install Jenkins
ansible-playbook -i inventory.ini jenkins-install.yml
```

## Access Jenkins

After installation:

- **URL**: http://<MANAGEMENT_IP>:8080
- **Username**: admin
- **Password**: JenkinsAdmin2024! (or your custom password)

## Configuration

### AWS Credentials

The management server uses an IAM instance profile with ECR/ECS permissions. However, you may need to add explicit credentials for cross-account access.

1. Go to **Manage Jenkins > Credentials > System > Global credentials**
2. Add AWS Credentials:
   - **Kind**: AWS Credentials
   - **ID**: `aws-prod`
   - **Access Key ID**: Your AWS access key
   - **Secret Access Key**: Your AWS secret key

### Git Credentials

Add credentials for your Git repository:

1. Go to **Manage Jenkins > Credentials > System > Global credentials**
2. Add:
   - **Kind**: Username with password
   - **ID**: `github-token`
   - **Username**: Your GitHub username
   - **Password**: Personal access token

### Update Pipeline Job

1. Go to the `middleware-platform` job
2. Click **Configure**
3. Update the Git repository URL
4. Save

## IAM Permissions

The management server's IAM role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth"
      ],
      "Resource": "*"
    }
  ]
}
```

## Running a Build

### Manual Build

1. Go to `middleware-platform` job
2. Click **Build with Parameters**
3. Select:
   - **ENVIRONMENT**: prod-aws
   - **DEPLOY_TYPE**: full
   - **DRY_RUN**: false
4. Click **Build**

### Pipeline Stages

The build will execute:
1. **Checkout** - Clone repository
2. **Build Application** - Maven build
3. **Build Container** - Podman build
4. **Push to ECR** - Tag and push to ECR
5. **Deploy to ECS** - Update ECS service
6. **Health Check** - Verify deployment

## Troubleshooting

### Cannot connect to management server

Check security group allows inbound on port 8080:
```bash
aws ec2 describe-security-groups --group-ids <SG_ID> \
  --query 'SecurityGroups[0].IpPermissions[?ToPort==`8080`]'
```

### ECR push fails

Verify IAM permissions:
```bash
# SSH to management server
aws ecr get-login-password --region us-east-1 | \
  podman login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com
```

### ECS update fails

Check ECS permissions:
```bash
aws ecs describe-services --cluster mw-prod-cluster --services mw-prod-liberty
```

### Plugin installation errors

Check Jenkins logs:
```bash
sudo journalctl -u jenkins -f
```

## Updating Jenkins

```bash
# Re-run the playbook
ansible-playbook -i inventory.ini jenkins-install.yml
```

## Backup

Jenkins data is stored in `/var/lib/jenkins`. To backup:

```bash
ssh ec2-user@<MANAGEMENT_IP> "sudo tar -czf /tmp/jenkins-backup.tar.gz /var/lib/jenkins"
scp ec2-user@<MANAGEMENT_IP>:/tmp/jenkins-backup.tar.gz .
```

## Security Notes

- Jenkins runs on port 8080 (HTTP only)
- For HTTPS, configure a reverse proxy (nginx/ALB)
- Restrict security group access to trusted IPs
- Rotate credentials regularly
- Keep Jenkins and plugins updated
