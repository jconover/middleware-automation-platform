# ==============================================================================
# Middleware Automation Platform - Comprehensive Makefile
# ==============================================================================
# This Makefile provides automation for the entire platform lifecycle including:
# - Terraform infrastructure management
# - Ansible configuration management
# - Container builds and registry operations
# - Kubernetes deployments
# - AWS service management
# - Security scanning and compliance
# - Monitoring and observability
# - Development workflows
# ==============================================================================

.PHONY: help
.DEFAULT_GOAL := help

# ==============================================================================
# Configuration Variables
# ==============================================================================
ENV ?= dev
VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "latest")
CONTAINER_RUNTIME ?= podman
AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
DOCKER_HUB_USER ?= jconover

# Paths
PROJECT_ROOT := $(shell pwd)
TERRAFORM_DIR := $(PROJECT_ROOT)/automated/terraform
TERRAFORM_AWS_DIR := $(TERRAFORM_DIR)/environments/aws
TERRAFORM_LEGACY_DIR := $(TERRAFORM_DIR)/environments/prod-aws
ANSIBLE_DIR := $(PROJECT_ROOT)/automated/ansible
CONTAINER_DIR := $(PROJECT_ROOT)/containers/liberty
K8S_DIR := $(PROJECT_ROOT)/kubernetes
SCRIPTS_DIR := $(PROJECT_ROOT)/automated/scripts
MONITORING_DIR := $(PROJECT_ROOT)/monitoring
SAMPLE_APP_DIR := $(PROJECT_ROOT)/sample-app

# Container image names
LIBERTY_IMAGE := liberty-app
ECR_REPO_NAME := mw-$(ENV)-liberty
ECR_REPO := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO_NAME)
DOCKERHUB_REPO := docker.io/$(DOCKER_HUB_USER)/$(LIBERTY_IMAGE)

# Kubernetes namespaces
K8S_NAMESPACE ?= liberty
MONITORING_NAMESPACE ?= monitoring

# Homelab IPs
LIBERTY_IP := 192.168.68.200
PROMETHEUS_IP := 192.168.68.201
GRAFANA_IP := 192.168.68.202
ALERTMANAGER_IP := 192.168.68.203
LOKI_IP := 192.168.68.204
JAEGER_IP := 192.168.68.205
AWX_IP := 192.168.68.206

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# ==============================================================================
# Help
# ==============================================================================
help: ## Show this help message
	@echo "$(CYAN)Middleware Automation Platform$(RESET)"
	@echo "================================"
	@echo ""
	@echo "$(GREEN)Usage:$(RESET) make [target] [ENV=dev|stage|prod] [VERSION=tag]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; section=""} \
		/^##@/ { section=substr($$0, 5); printf "\n$(YELLOW)%s$(RESET)\n", section } \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  $(CYAN)%-30s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Quick Start
quick-start: ## Full local development setup (build + run container)
	@echo "$(GREEN)Starting local development environment...$(RESET)"
	$(MAKE) container-build
	$(MAKE) container-run
	@echo "$(GREEN)Liberty running at http://localhost:9080$(RESET)"

dev-setup: ## Install development dependencies
	@echo "$(GREEN)Setting up development environment...$(RESET)"
	@command -v $(CONTAINER_RUNTIME) >/dev/null 2>&1 || { echo "$(RED)$(CONTAINER_RUNTIME) not found$(RESET)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(YELLOW)kubectl not found - K8s commands unavailable$(RESET)"; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(YELLOW)terraform not found - TF commands unavailable$(RESET)"; }
	@command -v ansible >/dev/null 2>&1 || { echo "$(YELLOW)ansible not found - Ansible commands unavailable$(RESET)"; }
	@echo "$(GREEN)Development environment ready$(RESET)"

# ==============================================================================
##@ Terraform - Infrastructure as Code
# ==============================================================================

## Bootstrap
tf-bootstrap: ## Bootstrap Terraform backend (S3 + DynamoDB)
	@echo "$(GREEN)Bootstrapping Terraform backend...$(RESET)"
	cd $(TERRAFORM_DIR)/bootstrap && terraform init && terraform apply -auto-approve

tf-bootstrap-destroy: ## Destroy Terraform backend (DANGER)
	@echo "$(RED)Destroying Terraform backend...$(RESET)"
	cd $(TERRAFORM_DIR)/bootstrap && terraform destroy

## Unified AWS Environment
tf-init: ## Initialize Terraform for environment (ENV=dev|stage|prod)
	@echo "$(GREEN)Initializing Terraform for $(ENV)...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform init -backend-config=backends/$(ENV).backend.hcl -reconfigure

tf-validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating Terraform configuration...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform validate

tf-fmt: ## Format Terraform files
	@echo "$(GREEN)Formatting Terraform files...$(RESET)"
	terraform fmt -recursive $(TERRAFORM_DIR)

tf-fmt-check: ## Check Terraform formatting
	terraform fmt -recursive -check $(TERRAFORM_DIR)

tf-plan: tf-init ## Plan Terraform changes for environment
	@echo "$(GREEN)Planning Terraform for $(ENV)...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform plan -var-file=envs/$(ENV).tfvars -out=tfplan-$(ENV)

tf-apply: ## Apply Terraform changes for environment
	@echo "$(GREEN)Applying Terraform for $(ENV)...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform apply tfplan-$(ENV)

tf-apply-auto: tf-init ## Apply Terraform with auto-approve
	@echo "$(GREEN)Auto-applying Terraform for $(ENV)...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform apply -var-file=envs/$(ENV).tfvars -auto-approve

tf-destroy: tf-init ## Destroy Terraform infrastructure for environment
	@echo "$(RED)Destroying Terraform infrastructure for $(ENV)...$(RESET)"
	cd $(TERRAFORM_AWS_DIR) && terraform destroy -var-file=envs/$(ENV).tfvars

tf-output: ## Show Terraform outputs for environment
	cd $(TERRAFORM_AWS_DIR) && terraform output

tf-state-list: ## List resources in Terraform state
	cd $(TERRAFORM_AWS_DIR) && terraform state list

tf-refresh: tf-init ## Refresh Terraform state
	cd $(TERRAFORM_AWS_DIR) && terraform refresh -var-file=envs/$(ENV).tfvars

tf-cost: ## Estimate infrastructure costs (requires infracost)
	@command -v infracost >/dev/null 2>&1 || { echo "$(RED)infracost not found$(RESET)"; exit 1; }
	cd $(TERRAFORM_AWS_DIR) && infracost breakdown --path . --terraform-var-file=envs/$(ENV).tfvars

## Legacy prod-aws Environment
tf-legacy-init: ## Initialize legacy prod-aws Terraform
	cd $(TERRAFORM_LEGACY_DIR) && terraform init

tf-legacy-plan: tf-legacy-init ## Plan legacy prod-aws changes
	cd $(TERRAFORM_LEGACY_DIR) && terraform plan -out=tfplan

tf-legacy-apply: ## Apply legacy prod-aws changes
	cd $(TERRAFORM_LEGACY_DIR) && terraform apply tfplan

tf-legacy-destroy: ## Destroy legacy prod-aws infrastructure
	cd $(TERRAFORM_LEGACY_DIR) && terraform destroy

## Terraform Security
tf-security-scan: ## Scan Terraform for security issues (tfsec)
	@command -v tfsec >/dev/null 2>&1 || { echo "$(RED)tfsec not found$(RESET)"; exit 1; }
	tfsec $(TERRAFORM_DIR)

tf-checkov: ## Run Checkov security scan
	@command -v checkov >/dev/null 2>&1 || { echo "$(RED)checkov not found$(RESET)"; exit 1; }
	checkov -d $(TERRAFORM_DIR)

tf-docs: ## Generate Terraform documentation
	@command -v terraform-docs >/dev/null 2>&1 || { echo "$(RED)terraform-docs not found$(RESET)"; exit 1; }
	terraform-docs markdown $(TERRAFORM_AWS_DIR) > $(TERRAFORM_AWS_DIR)/README.md
	@for dir in $(TERRAFORM_DIR)/modules/*; do \
		terraform-docs markdown $$dir > $$dir/README.md; \
	done

# ==============================================================================
##@ Ansible - Configuration Management
# ==============================================================================
ansible-lint: ## Lint Ansible playbooks
	@echo "$(GREEN)Linting Ansible playbooks...$(RESET)"
	cd $(ANSIBLE_DIR) && ansible-lint playbooks/

ansible-syntax: ## Check Ansible syntax
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/site.yml --syntax-check

ansible-deploy: ## Run full Ansible deployment
	@echo "$(GREEN)Running Ansible deployment for $(ENV)...$(RESET)"
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/$(ENV).yml playbooks/site.yml

ansible-deploy-check: ## Dry-run Ansible deployment
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/$(ENV).yml playbooks/site.yml --check --diff

ansible-liberty: ## Deploy only Liberty role
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/$(ENV).yml playbooks/site.yml --tags liberty

ansible-monitoring: ## Deploy only monitoring role
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/$(ENV).yml playbooks/site.yml --tags monitoring

ansible-health: ## Run health check playbook
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory/$(ENV).yml playbooks/health-check.yml

ansible-facts: ## Gather Ansible facts
	cd $(ANSIBLE_DIR) && ansible -i inventory/$(ENV).yml all -m setup

ansible-ping: ## Ping all Ansible hosts
	cd $(ANSIBLE_DIR) && ansible -i inventory/$(ENV).yml all -m ping

## Ansible Vault
vault-encrypt: ## Encrypt a file with Ansible Vault
	@read -p "File to encrypt: " file; \
	ansible-vault encrypt $$file

vault-decrypt: ## Decrypt a file with Ansible Vault
	@read -p "File to decrypt: " file; \
	ansible-vault decrypt $$file

vault-edit: ## Edit encrypted vault file
	@read -p "Vault file to edit: " file; \
	ansible-vault edit $$file

vault-view: ## View encrypted vault file
	@read -p "Vault file to view: " file; \
	ansible-vault view $$file

## Molecule Testing
molecule-test: ## Run Molecule tests for all roles
	cd $(ANSIBLE_DIR) && molecule test --all

molecule-converge: ## Converge Molecule instances
	cd $(ANSIBLE_DIR) && molecule converge

molecule-verify: ## Verify Molecule instances
	cd $(ANSIBLE_DIR) && molecule verify

molecule-destroy: ## Destroy Molecule instances
	cd $(ANSIBLE_DIR) && molecule destroy

# ==============================================================================
##@ Container - Build and Registry Operations
# ==============================================================================
container-build: ## Build Liberty container image
	@echo "$(GREEN)Building Liberty container...$(RESET)"
	$(CONTAINER_RUNTIME) build -t $(LIBERTY_IMAGE):$(VERSION) -f $(CONTAINER_DIR)/Containerfile $(PROJECT_ROOT)

container-build-no-cache: ## Build container without cache
	$(CONTAINER_RUNTIME) build --no-cache -t $(LIBERTY_IMAGE):$(VERSION) -f $(CONTAINER_DIR)/Containerfile $(PROJECT_ROOT)

container-run: ## Run Liberty container locally
	@echo "$(GREEN)Running Liberty container...$(RESET)"
	$(CONTAINER_RUNTIME) run -d -p 9080:9080 -p 9443:9443 --name liberty $(LIBERTY_IMAGE):$(VERSION)

container-stop: ## Stop Liberty container
	$(CONTAINER_RUNTIME) stop liberty 2>/dev/null || true
	$(CONTAINER_RUNTIME) rm liberty 2>/dev/null || true

container-logs: ## View Liberty container logs
	$(CONTAINER_RUNTIME) logs -f liberty

container-shell: ## Shell into running Liberty container
	$(CONTAINER_RUNTIME) exec -it liberty /bin/bash

container-health: ## Check container health endpoints
	@echo "$(GREEN)Checking container health...$(RESET)"
	@curl -sf http://localhost:9080/health/ready && echo "Ready: OK" || echo "Ready: FAIL"
	@curl -sf http://localhost:9080/health/live && echo "Live: OK" || echo "Live: FAIL"
	@curl -sf http://localhost:9080/health/started && echo "Started: OK" || echo "Started: FAIL"

container-scan: ## Scan container for vulnerabilities (trivy)
	@command -v trivy >/dev/null 2>&1 || { echo "$(RED)trivy not found$(RESET)"; exit 1; }
	trivy image $(LIBERTY_IMAGE):$(VERSION)

container-scan-grype: ## Scan container with Grype
	@command -v grype >/dev/null 2>&1 || { echo "$(RED)grype not found$(RESET)"; exit 1; }
	grype $(LIBERTY_IMAGE):$(VERSION)

## ECR Operations
ecr-login: ## Login to AWS ECR
	@echo "$(GREEN)Logging into ECR...$(RESET)"
	aws ecr get-login-password --region $(AWS_REGION) | $(CONTAINER_RUNTIME) login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

ecr-push: container-build ecr-login ## Build and push to ECR
	@echo "$(GREEN)Pushing to ECR...$(RESET)"
	$(CONTAINER_RUNTIME) tag $(LIBERTY_IMAGE):$(VERSION) $(ECR_REPO):$(VERSION)
	$(CONTAINER_RUNTIME) tag $(LIBERTY_IMAGE):$(VERSION) $(ECR_REPO):latest
	$(CONTAINER_RUNTIME) push $(ECR_REPO):$(VERSION)
	$(CONTAINER_RUNTIME) push $(ECR_REPO):latest

ecr-list: ## List images in ECR
	aws ecr describe-images --repository-name $(ECR_REPO_NAME) --region $(AWS_REGION)

## Docker Hub Operations
dockerhub-login: ## Login to Docker Hub
	$(CONTAINER_RUNTIME) login docker.io

dockerhub-push: container-build dockerhub-login ## Build and push to Docker Hub
	@echo "$(GREEN)Pushing to Docker Hub...$(RESET)"
	$(CONTAINER_RUNTIME) tag $(LIBERTY_IMAGE):$(VERSION) $(DOCKERHUB_REPO):$(VERSION)
	$(CONTAINER_RUNTIME) tag $(LIBERTY_IMAGE):$(VERSION) $(DOCKERHUB_REPO):latest
	$(CONTAINER_RUNTIME) push $(DOCKERHUB_REPO):$(VERSION)
	$(CONTAINER_RUNTIME) push $(DOCKERHUB_REPO):latest

# ==============================================================================
##@ Kubernetes - Cluster Operations
# ==============================================================================
k8s-context: ## Show current Kubernetes context
	kubectl config current-context

k8s-contexts: ## List all Kubernetes contexts
	kubectl config get-contexts

k8s-use-homelab: ## Switch to homelab context
	kubectl config use-context kubernetes-admin@kubernetes

k8s-ns: ## List all namespaces
	kubectl get namespaces

k8s-nodes: ## List cluster nodes
	kubectl get nodes -o wide

k8s-pods: ## List all pods
	kubectl get pods -A -o wide

k8s-services: ## List all services
	kubectl get services -A

## Liberty Deployments
k8s-deploy-local: ## Deploy Liberty to local homelab
	@echo "$(GREEN)Deploying Liberty to local homelab...$(RESET)"
	@kubectl create namespace liberty --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k $(K8S_DIR)/overlays/local-homelab

k8s-deploy-dev: ## Deploy Liberty to dev environment
	@echo "$(GREEN)Deploying Liberty to dev...$(RESET)"
	@kubectl create namespace liberty-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k $(K8S_DIR)/overlays/dev

k8s-deploy-prod: ## Deploy Liberty to prod environment
	@echo "$(GREEN)Deploying Liberty to prod...$(RESET)"
	@kubectl create namespace liberty-prod --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k $(K8S_DIR)/overlays/prod

k8s-deploy-aws: ## Deploy Liberty to AWS overlay
	@echo "$(GREEN)Deploying Liberty to AWS...$(RESET)"
	@kubectl create namespace liberty-aws --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -k $(K8S_DIR)/overlays/aws

k8s-delete-local: ## Delete Liberty from local homelab
	kubectl delete -k $(K8S_DIR)/overlays/local-homelab

k8s-status: ## Show Liberty deployment status
	kubectl get deployment,pod,service,ingress -n $(K8S_NAMESPACE) -l app=liberty

k8s-logs: ## View Liberty pod logs
	kubectl logs -n $(K8S_NAMESPACE) -l app=liberty -f --tail=100

k8s-describe: ## Describe Liberty pods
	kubectl describe pods -n $(K8S_NAMESPACE) -l app=liberty

k8s-shell: ## Shell into Liberty pod
	kubectl exec -n $(K8S_NAMESPACE) -it $$(kubectl get pod -n $(K8S_NAMESPACE) -l app=liberty -o jsonpath='{.items[0].metadata.name}') -- /bin/bash

k8s-restart: ## Restart Liberty deployment
	kubectl rollout restart deployment -n $(K8S_NAMESPACE) liberty-app

k8s-rollout-status: ## Check rollout status
	kubectl rollout status deployment -n $(K8S_NAMESPACE) liberty-app

k8s-rollback: ## Rollback Liberty deployment
	kubectl rollout undo deployment -n $(K8S_NAMESPACE) liberty-app

k8s-scale: ## Scale Liberty deployment (REPLICAS=3)
	kubectl scale deployment -n $(K8S_NAMESPACE) liberty-app --replicas=$(REPLICAS)

## Port Forwarding
k8s-port-forward-liberty: ## Port forward to Liberty
	kubectl port-forward -n $(K8S_NAMESPACE) svc/liberty-service 9080:9080

k8s-port-forward-prometheus: ## Port forward to Prometheus
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/prometheus-kube-prometheus-prometheus 9090:9090

k8s-port-forward-grafana: ## Port forward to Grafana
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/prometheus-grafana 3000:80

k8s-port-forward-alertmanager: ## Port forward to Alertmanager
	kubectl port-forward -n $(MONITORING_NAMESPACE) svc/prometheus-kube-prometheus-alertmanager 9093:9093

## Monitoring Stack
k8s-deploy-monitoring: ## Deploy Prometheus/Grafana stack
	@echo "$(GREEN)Deploying monitoring stack...$(RESET)"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
	helm repo update
	helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
		-n $(MONITORING_NAMESPACE) --create-namespace \
		-f $(K8S_DIR)/base/monitoring/prometheus-values.yaml

k8s-deploy-servicemonitor: ## Deploy Liberty ServiceMonitor
	kubectl apply -f $(K8S_DIR)/base/monitoring/liberty-servicemonitor.yaml

k8s-deploy-prometheusrule: ## Deploy Liberty PrometheusRule
	kubectl apply -f $(K8S_DIR)/base/monitoring/liberty-prometheusrule.yaml

k8s-deploy-loki: ## Deploy Loki log aggregation
	kubectl apply -k $(K8S_DIR)/base/monitoring/loki/

k8s-deploy-promtail: ## Deploy Promtail log collector
	kubectl apply -k $(K8S_DIR)/base/monitoring/promtail/

k8s-delete-monitoring: ## Delete monitoring stack
	helm uninstall prometheus -n $(MONITORING_NAMESPACE)
	kubectl delete -k $(K8S_DIR)/base/monitoring/loki/ || true
	kubectl delete -k $(K8S_DIR)/base/monitoring/promtail/ || true

## Network Policies
k8s-deploy-netpol: ## Deploy network policies
	kubectl apply -f $(K8S_DIR)/base/network-policies/

k8s-delete-netpol: ## Delete network policies
	kubectl delete -f $(K8S_DIR)/base/network-policies/

## Secrets and Certificates
k8s-create-tls-secret: ## Create TLS secret (CERT=path KEY=path)
	kubectl create secret tls liberty-tls --cert=$(CERT) --key=$(KEY)

k8s-secrets: ## List all secrets
	kubectl get secrets -A

# ==============================================================================
##@ AWS - Cloud Service Management
# ==============================================================================

## ECS Operations
ecs-deploy: ## Force new ECS deployment
	@echo "$(GREEN)Deploying to ECS...$(RESET)"
	aws ecs update-service --cluster mw-$(ENV)-cluster --service mw-$(ENV)-liberty --force-new-deployment --region $(AWS_REGION)

ecs-status: ## Show ECS service status
	aws ecs describe-services --cluster mw-$(ENV)-cluster --services mw-$(ENV)-liberty --region $(AWS_REGION) --query 'services[0].{status:status,running:runningCount,desired:desiredCount,pending:pendingCount}'

ecs-tasks: ## List ECS tasks
	aws ecs list-tasks --cluster mw-$(ENV)-cluster --service-name mw-$(ENV)-liberty --region $(AWS_REGION)

ecs-logs: ## View ECS task logs
	@TASK_ID=$$(aws ecs list-tasks --cluster mw-$(ENV)-cluster --service-name mw-$(ENV)-liberty --region $(AWS_REGION) --query 'taskArns[0]' --output text | cut -d'/' -f3); \
	aws logs tail /ecs/mw-$(ENV)-liberty --follow

ecs-scale: ## Scale ECS service (COUNT=2)
	aws ecs update-service --cluster mw-$(ENV)-cluster --service mw-$(ENV)-liberty --desired-count $(COUNT) --region $(AWS_REGION)

ecs-stop: ## Scale ECS to 0
	$(MAKE) ecs-scale COUNT=0

## EC2 Operations
ec2-list: ## List EC2 instances
	aws ec2 describe-instances --filters "Name=tag:Project,Values=middleware-platform" --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType,IP:PrivateIpAddress,Name:Tags[?Key==`Name`].Value|[0]}' --output table --region $(AWS_REGION)

ec2-start: ## Start EC2 instances
	@echo "$(GREEN)Starting EC2 instances...$(RESET)"
	aws ec2 start-instances --instance-ids $$(aws ec2 describe-instances --filters "Name=tag:Project,Values=middleware-platform" "Name=instance-state-name,Values=stopped" --query 'Reservations[].Instances[].InstanceId' --output text --region $(AWS_REGION)) --region $(AWS_REGION)

ec2-stop: ## Stop EC2 instances
	@echo "$(YELLOW)Stopping EC2 instances...$(RESET)"
	aws ec2 stop-instances --instance-ids $$(aws ec2 describe-instances --filters "Name=tag:Project,Values=middleware-platform" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text --region $(AWS_REGION)) --region $(AWS_REGION)

## RDS Operations
rds-status: ## Show RDS status
	aws rds describe-db-instances --query 'DBInstances[?TagList[?Key==`Project` && Value==`middleware-platform`]].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine,Class:DBInstanceClass}' --output table --region $(AWS_REGION)

rds-start: ## Start RDS instance
	aws rds start-db-instance --db-instance-identifier mw-$(ENV)-postgres --region $(AWS_REGION)

rds-stop: ## Stop RDS instance
	aws rds stop-db-instance --db-instance-identifier mw-$(ENV)-postgres --region $(AWS_REGION)

rds-snapshot: ## Create RDS snapshot
	aws rds create-db-snapshot --db-instance-identifier mw-$(ENV)-postgres --db-snapshot-identifier mw-$(ENV)-manual-$$(date +%Y%m%d%H%M) --region $(AWS_REGION)

## ElastiCache Operations
elasticache-status: ## Show ElastiCache status
	aws elasticache describe-cache-clusters --query 'CacheClusters[].{ID:CacheClusterId,Status:CacheClusterStatus,Engine:Engine,Type:CacheNodeType}' --output table --region $(AWS_REGION)

## ALB Operations
alb-status: ## Show ALB status
	aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `mw-`)].{Name:LoadBalancerName,State:State.Code,DNS:DNSName}' --output table --region $(AWS_REGION)

alb-targets: ## Show ALB target health
	@ALB_ARN=$$(aws elbv2 describe-target-groups --names mw-$(ENV)-liberty-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region $(AWS_REGION) 2>/dev/null); \
	if [ "$$ALB_ARN" != "None" ] && [ -n "$$ALB_ARN" ]; then \
		aws elbv2 describe-target-health --target-group-arn $$ALB_ARN --region $(AWS_REGION); \
	else \
		echo "Target group not found"; \
	fi

## Cost Management
aws-start: ## Start all AWS services
	@echo "$(GREEN)Starting AWS services...$(RESET)"
	$(SCRIPTS_DIR)/aws-start.sh

aws-stop: ## Stop all AWS services (cost saving)
	@echo "$(YELLOW)Stopping AWS services...$(RESET)"
	$(SCRIPTS_DIR)/aws-stop.sh

aws-destroy: ## Destroy all AWS infrastructure
	@echo "$(RED)Destroying AWS infrastructure...$(RESET)"
	$(SCRIPTS_DIR)/aws-stop.sh --destroy

aws-costs: ## Show current month costs
	aws ce get-cost-and-usage \
		--time-period Start=$$(date -d "first day of this month" +%Y-%m-%d),End=$$(date +%Y-%m-%d) \
		--granularity MONTHLY \
		--metrics BlendedCost \
		--group-by Type=TAG,Key=Project \
		--region us-east-1

## Secrets Manager
secrets-list: ## List secrets in Secrets Manager
	aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `mw-`)].{Name:Name,Description:Description}' --output table --region $(AWS_REGION)

secrets-get: ## Get a secret value (SECRET=name)
	aws secretsmanager get-secret-value --secret-id $(SECRET) --query SecretString --output text --region $(AWS_REGION)

secrets-rotate: ## Rotate a secret (SECRET=name)
	aws secretsmanager rotate-secret --secret-id $(SECRET) --region $(AWS_REGION)

# ==============================================================================
##@ Security - Scanning and Compliance
# ==============================================================================
security-scan-all: container-scan tf-security-scan ansible-lint ## Run all security scans

security-sast: ## Run SAST on application code
	@command -v semgrep >/dev/null 2>&1 || { echo "$(RED)semgrep not found$(RESET)"; exit 1; }
	semgrep --config auto $(SAMPLE_APP_DIR)

security-secrets-scan: ## Scan for leaked secrets
	@command -v gitleaks >/dev/null 2>&1 || { echo "$(RED)gitleaks not found$(RESET)"; exit 1; }
	gitleaks detect --source $(PROJECT_ROOT) --verbose

security-deps: ## Scan dependencies for vulnerabilities
	cd $(SAMPLE_APP_DIR) && mvn org.owasp:dependency-check-maven:check

security-sbom: ## Generate SBOM for container
	@command -v syft >/dev/null 2>&1 || { echo "$(RED)syft not found$(RESET)"; exit 1; }
	syft $(LIBERTY_IMAGE):$(VERSION) -o spdx-json > sbom.json

security-guardduty: ## Show GuardDuty findings
	aws guardduty list-findings --detector-id $$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --region $(AWS_REGION)) --region $(AWS_REGION)

security-securityhub: ## Show Security Hub findings
	aws securityhub get-findings --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' --max-items 10 --region $(AWS_REGION)

# ==============================================================================
##@ Monitoring - Prometheus, Grafana, Loki
# ==============================================================================

## Prometheus Queries
prom-query: ## Run Prometheus query (QUERY="up")
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/query?query=$(QUERY)" | jq

prom-targets: ## List Prometheus targets
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health: .health, endpoint: .scrapeUrl}'

prom-alerts: ## List Prometheus alerts
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/alerts" | jq

prom-rules: ## List Prometheus rules
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/rules" | jq

prom-liberty-up: ## Check Liberty targets
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/query?query=up{job='liberty'}" | jq

prom-liberty-requests: ## Liberty request rate
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/query?query=rate(liberty_http_requests_total[5m])" | jq

prom-liberty-latency: ## Liberty p95 latency
	curl -s "http://$(PROMETHEUS_IP):9090/api/v1/query?query=histogram_quantile(0.95,rate(liberty_http_request_duration_seconds_bucket[5m]))" | jq

## Grafana
grafana-open: ## Open Grafana in browser
	xdg-open "http://$(GRAFANA_IP):3000" 2>/dev/null || open "http://$(GRAFANA_IP):3000"

grafana-dashboards: ## List Grafana dashboards
	curl -s "http://admin:admin@$(GRAFANA_IP):3000/api/search?type=dash-db" | jq '.[].title'

grafana-datasources: ## List Grafana datasources
	curl -s "http://admin:admin@$(GRAFANA_IP):3000/api/datasources" | jq '.[].name'

grafana-import-dashboard: ## Import dashboard from file (FILE=path)
	curl -X POST -H "Content-Type: application/json" -d @$(FILE) "http://admin:admin@$(GRAFANA_IP):3000/api/dashboards/db"

## Loki Log Queries
loki-query: ## Query Loki logs (QUERY="{app=\"liberty\"}")
	curl -s "http://$(LOKI_IP):3100/loki/api/v1/query_range" \
		--data-urlencode "query=$(QUERY)" \
		--data-urlencode "start=$$(date -d '1 hour ago' +%s)000000000" \
		--data-urlencode "end=$$(date +%s)000000000" \
		--data-urlencode "limit=100" | jq

loki-liberty-logs: ## Get Liberty logs
	$(MAKE) loki-query QUERY='{app="liberty-app"}'

loki-liberty-errors: ## Get Liberty error logs
	$(MAKE) loki-query QUERY='{app="liberty-app"} |= "ERROR"'

loki-labels: ## List Loki labels
	curl -s "http://$(LOKI_IP):3100/loki/api/v1/labels" | jq

loki-ready: ## Check Loki readiness
	curl -s "http://$(LOKI_IP):3100/ready"

## Alertmanager
alertmanager-alerts: ## List active alerts
	curl -s "http://$(ALERTMANAGER_IP):9093/api/v2/alerts" | jq

alertmanager-silence: ## Create silence (MATCHER="alertname=TestAlert")
	curl -X POST "http://$(ALERTMANAGER_IP):9093/api/v2/silences" \
		-H "Content-Type: application/json" \
		-d '{"matchers":[{"name":"alertname","value":"$(MATCHER)","isRegex":false}],"startsAt":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'","endsAt":"'$$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)'","createdBy":"makefile","comment":"Silenced via Makefile"}'

alertmanager-silences: ## List silences
	curl -s "http://$(ALERTMANAGER_IP):9093/api/v2/silences" | jq

# ==============================================================================
##@ Application - Build and Test
# ==============================================================================
app-build: ## Build sample application
	@echo "$(GREEN)Building sample application...$(RESET)"
	cd $(SAMPLE_APP_DIR) && mvn clean package -DskipTests

app-build-full: ## Build with tests
	cd $(SAMPLE_APP_DIR) && mvn clean package

app-test: ## Run application tests
	cd $(SAMPLE_APP_DIR) && mvn test

app-test-integration: ## Run integration tests
	cd $(SAMPLE_APP_DIR) && mvn verify -Pintegration

app-clean: ## Clean build artifacts
	cd $(SAMPLE_APP_DIR) && mvn clean

app-deps: ## Download dependencies
	cd $(SAMPLE_APP_DIR) && mvn dependency:resolve

app-deps-tree: ## Show dependency tree
	cd $(SAMPLE_APP_DIR) && mvn dependency:tree

app-update-deps: ## Check for dependency updates
	cd $(SAMPLE_APP_DIR) && mvn versions:display-dependency-updates

# ==============================================================================
##@ Deployment - Full Stack Operations
# ==============================================================================
deploy-local: container-build k8s-deploy-local ## Deploy to local Kubernetes
	@echo "$(GREEN)Deployed to local Kubernetes$(RESET)"

deploy-aws-ecs: ecr-push ecs-deploy ## Build, push, and deploy to ECS
	@echo "$(GREEN)Deployed to AWS ECS$(RESET)"

deploy-aws-ec2: ecr-push ansible-deploy ## Build, push, and deploy to EC2
	@echo "$(GREEN)Deployed to AWS EC2$(RESET)"

deploy-full: tf-apply-auto deploy-aws-ecs ## Full infrastructure + deployment
	@echo "$(GREEN)Full deployment complete$(RESET)"

rollback-ecs: ## Rollback ECS to previous task definition
	@CURRENT=$$(aws ecs describe-services --cluster mw-$(ENV)-cluster --services mw-$(ENV)-liberty --query 'services[0].taskDefinition' --output text --region $(AWS_REGION)); \
	PREV=$$(aws ecs list-task-definitions --family-prefix mw-$(ENV)-liberty --sort DESC --max-items 2 --query 'taskDefinitionArns[1]' --output text --region $(AWS_REGION)); \
	echo "Rolling back from $$CURRENT to $$PREV"; \
	aws ecs update-service --cluster mw-$(ENV)-cluster --service mw-$(ENV)-liberty --task-definition $$PREV --region $(AWS_REGION)

health-check: ## Check all health endpoints
	@echo "$(GREEN)Checking health endpoints...$(RESET)"
	@echo "Local container:"
	@curl -sf http://localhost:9080/health/ready 2>/dev/null && echo "  Ready: OK" || echo "  Ready: FAIL"
	@echo "Homelab Liberty ($(LIBERTY_IP)):"
	@curl -sf http://$(LIBERTY_IP):9080/health/ready 2>/dev/null && echo "  Ready: OK" || echo "  Ready: FAIL"

smoke-test: ## Run smoke tests against deployed application
	@echo "$(GREEN)Running smoke tests...$(RESET)"
	@echo "Testing health endpoints..."
	@curl -sf http://$(LIBERTY_IP):9080/health/ready || { echo "$(RED)Health check failed$(RESET)"; exit 1; }
	@curl -sf http://$(LIBERTY_IP):9080/health/live || { echo "$(RED)Liveness check failed$(RESET)"; exit 1; }
	@echo "Testing metrics endpoint..."
	@curl -sf http://$(LIBERTY_IP):9080/metrics | head -5 || { echo "$(RED)Metrics check failed$(RESET)"; exit 1; }
	@echo "$(GREEN)All smoke tests passed$(RESET)"

# ==============================================================================
##@ Git and CI/CD
# ==============================================================================
git-status: ## Show git status
	git status

git-log: ## Show recent commits
	git log --oneline -10

git-diff: ## Show unstaged changes
	git diff

git-branch: ## List branches
	git branch -a

pre-commit: tf-fmt ansible-lint app-build ## Run pre-commit checks
	@echo "$(GREEN)Pre-commit checks passed$(RESET)"

ci-local: pre-commit container-build container-scan ## Run CI pipeline locally
	@echo "$(GREEN)Local CI passed$(RESET)"

# ==============================================================================
##@ Utilities
# ==============================================================================
clean: container-stop app-clean ## Clean all build artifacts
	@echo "$(GREEN)Cleaned all artifacts$(RESET)"
	rm -f $(TERRAFORM_AWS_DIR)/tfplan-*

clean-all: clean ## Deep clean including caches
	rm -rf $(SAMPLE_APP_DIR)/target
	rm -rf .terraform
	$(CONTAINER_RUNTIME) system prune -f

versions: ## Show tool versions
	@echo "$(CYAN)Tool Versions$(RESET)"
	@echo "============="
	@$(CONTAINER_RUNTIME) --version 2>/dev/null || echo "$(CONTAINER_RUNTIME): not found"
	@terraform --version 2>/dev/null | head -1 || echo "terraform: not found"
	@ansible --version 2>/dev/null | head -1 || echo "ansible: not found"
	@kubectl version --client --short 2>/dev/null || echo "kubectl: not found"
	@aws --version 2>/dev/null || echo "aws-cli: not found"
	@helm version --short 2>/dev/null || echo "helm: not found"
	@mvn --version 2>/dev/null | head -1 || echo "maven: not found"

info: ## Show environment information
	@echo "$(CYAN)Environment Information$(RESET)"
	@echo "======================="
	@echo "PROJECT_ROOT:     $(PROJECT_ROOT)"
	@echo "ENV:              $(ENV)"
	@echo "VERSION:          $(VERSION)"
	@echo "CONTAINER_RUNTIME: $(CONTAINER_RUNTIME)"
	@echo "AWS_REGION:       $(AWS_REGION)"
	@echo "AWS_ACCOUNT_ID:   $(AWS_ACCOUNT_ID)"
	@echo "ECR_REPO:         $(ECR_REPO)"
	@echo "DOCKERHUB_REPO:   $(DOCKERHUB_REPO)"

endpoints: ## Show all service endpoints
	@echo "$(CYAN)Service Endpoints$(RESET)"
	@echo "================="
	@echo "$(GREEN)Local:$(RESET)"
	@echo "  Liberty:      http://localhost:9080"
	@echo ""
	@echo "$(GREEN)Homelab Kubernetes:$(RESET)"
	@echo "  Liberty:      http://$(LIBERTY_IP):9080"
	@echo "  Prometheus:   http://$(PROMETHEUS_IP):9090"
	@echo "  Grafana:      http://$(GRAFANA_IP):3000"
	@echo "  Alertmanager: http://$(ALERTMANAGER_IP):9093"
	@echo "  Loki:         http://$(LOKI_IP):3100"
	@echo "  Jaeger:       http://$(JAEGER_IP):16686"
	@echo "  AWX:          http://$(AWX_IP)"
