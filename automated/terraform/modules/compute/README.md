# Compute Module

Generic EC2 compute module for deploying instances across availability zones.

## Features

- Count-based instance deployment with automatic subnet distribution
- AMI data source fallback (defaults to latest Ubuntu 22.04 LTS)
- Optional SSH key pair creation
- IAM role and instance profile management
- CloudWatch log group integration
- User data templating support
- IMDSv2 enforcement (configurable)
- EBS volume configuration (root and additional volumes)
- SSM Session Manager support

## Usage

### Basic Usage (Liberty Servers)

```hcl
module "liberty_compute" {
  source = "../../modules/compute"

  name_prefix        = "mw-prod-liberty"
  aws_region         = "us-east-1"
  instance_count     = 2
  instance_type      = "t3.small"
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [aws_security_group.liberty.id]
  ssh_public_key     = file("~/.ssh/ansible_ed25519.pub")

  user_data_template      = "${path.module}/templates/liberty-user-data.sh"
  user_data_template_vars = {
    db_endpoint = aws_db_instance.main.endpoint
  }

  iam_inline_policy_statements = [
    {
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db_credentials.arn]
    }
  ]

  tags = {
    Role        = "liberty-server"
    AnsibleGroup = "liberty_servers"
  }

  instance_tags = {
    LibertyServerName = "appServer"
  }
}
```

### Using Existing Key Pair and Instance Profile

```hcl
module "app_servers" {
  source = "../../modules/compute"

  name_prefix        = "mw-prod-app"
  aws_region         = "us-east-1"
  instance_count     = 3
  instance_type      = "m5.large"
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [aws_security_group.app.id]

  # Use existing resources
  create_key_pair                = false
  existing_key_name              = "existing-key"
  create_iam_role                = false
  existing_instance_profile_name = "existing-profile"

  # Skip CloudWatch log group (using existing)
  create_cloudwatch_log_group = false

  tags = {
    Role = "application-server"
  }
}
```

### With Additional EBS Volumes

```hcl
module "data_servers" {
  source = "../../modules/compute"

  name_prefix        = "mw-prod-data"
  aws_region         = "us-east-1"
  instance_count     = 2
  instance_type      = "r5.xlarge"
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [aws_security_group.data.id]
  ssh_public_key     = file("~/.ssh/id_rsa.pub")

  root_volume_size = 50
  root_volume_type = "gp3"

  additional_ebs_volumes = [
    {
      device_name = "/dev/sdf"
      volume_size = 500
      volume_type = "gp3"
      encrypted   = true
    },
    {
      device_name = "/dev/sdg"
      volume_size = 100
      volume_type = "io2"
      encrypted   = true
    }
  ]

  tags = {
    Role = "data-server"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for resource names | `string` | n/a | yes |
| aws_region | AWS region for deployment | `string` | n/a | yes |
| subnet_ids | List of subnet IDs to distribute instances across | `list(string)` | n/a | yes |
| security_group_ids | List of security group IDs | `list(string)` | n/a | yes |
| instance_count | Number of EC2 instances | `number` | `1` | no |
| instance_type | EC2 instance type | `string` | `"t3.small"` | no |
| ami_id | AMI ID (defaults to Ubuntu 22.04) | `string` | `null` | no |
| ssh_public_key | SSH public key content | `string` | `null` | no |
| create_key_pair | Create new SSH key pair | `bool` | `true` | no |
| existing_key_name | Existing key pair name | `string` | `null` | no |
| create_iam_role | Create IAM role | `bool` | `true` | no |
| existing_instance_profile_name | Existing instance profile | `string` | `null` | no |
| enable_ssm | Enable SSM access | `bool` | `true` | no |
| iam_managed_policy_arns | Managed policy ARNs | `list(string)` | `[]` | no |
| iam_inline_policy_statements | Inline policy statements | `list(object)` | `[]` | no |
| root_volume_size | Root volume size (GB) | `number` | `30` | no |
| root_volume_type | Root volume type | `string` | `"gp3"` | no |
| root_volume_encrypted | Encrypt root volume | `bool` | `true` | no |
| additional_ebs_volumes | Additional EBS volumes | `list(object)` | `[]` | no |
| user_data_base64 | Base64 user data | `string` | `null` | no |
| user_data_template | User data template path | `string` | `null` | no |
| user_data_template_vars | Template variables | `map(any)` | `{}` | no |
| require_imdsv2 | Require IMDSv2 | `bool` | `true` | no |
| detailed_monitoring | Enable detailed monitoring | `bool` | `false` | no |
| create_cloudwatch_log_group | Create log group | `bool` | `true` | no |
| log_retention_days | Log retention days | `number` | `30` | no |
| tags | Resource tags | `map(string)` | `{}` | no |
| instance_tags | Instance-only tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_ids | List of EC2 instance IDs |
| instance_arns | List of EC2 instance ARNs |
| instance_private_ips | List of private IP addresses |
| instance_public_ips | List of public IP addresses |
| instance_private_dns | List of private DNS names |
| instance_availability_zones | List of availability zones |
| ami_id | AMI ID used |
| iam_role_arn | IAM role ARN |
| iam_role_name | IAM role name |
| iam_instance_profile_name | Instance profile name |
| iam_instance_profile_arn | Instance profile ARN |
| ssh_key_name | SSH key pair name |
| ssh_key_fingerprint | SSH key fingerprint |
| cloudwatch_log_group_name | Log group name |
| cloudwatch_log_group_arn | Log group ARN |
| instances | Map of instance details |
| instance_count | Number of instances created |

## Notes

### AMI Selection

If `ami_id` is not provided, the module automatically selects the latest Ubuntu 22.04 LTS AMI from Canonical. For production use, consider pinning to a specific AMI ID for reproducibility.

### Instance Distribution

Instances are distributed across subnets using modulo: `subnet_ids[count.index % length(subnet_ids)]`. This provides automatic AZ distribution when multiple subnets are provided.

### Lifecycle Management

The module ignores changes to `ami` and `user_data` in the lifecycle to prevent unintended instance recreation. AMI updates should be handled through a controlled replacement strategy.

### User Data Templating

When using `user_data_template`, the following variables are automatically available:
- `aws_region` - The AWS region
- `name_prefix` - The name prefix
- `instance_id` - The instance index (1-based)

Additional variables can be passed via `user_data_template_vars`.

## Related Files

- [Production EC2 implementation](../../environments/prod-aws/compute.tf)
- [ECS module](../ecs/)
- [Networking module](../networking/)
