# Mineclifford Operations Guide

This guide explains how to use the unified `minecraft-ops.sh` script for deploying and managing Minecraft servers across different cloud providers and orchestration methods.

## Overview

The `minecraft-ops.sh` script provides a unified interface for managing Minecraft deployments with the following features:

- **Multiple cloud providers**: AWS and Azure
- **Multiple orchestration methods**: Docker Swarm, Kubernetes, or local Docker
- **Deployment and destruction workflows**: Deploy, destroy, check status, and manage state
- **Customizable Minecraft settings**: Version, game mode, difficulty, etc.

## Prerequisites

Before using this script, ensure you have:

1. Required CLI tools installed:
   - `terraform` for infrastructure provisioning
   - `ansible` for configuration management (for Swarm deployments)
   - `kubectl` for Kubernetes deployments
   - `docker` and `docker-compose` for local deployments
   - `aws` CLI for AWS deployments
   - `az` CLI for Azure deployments

2. Valid cloud provider credentials:
   - AWS credentials configured (for AWS deployments)
   - Azure credentials configured (for Azure deployments)

3. Environment variables (in `.env` file or exported):
   - For AWS: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.
   - For Azure: AZURE_SUBSCRIPTION_ID

## Basic Usage

The script's basic syntax is:

```bash
./minecraft-ops.sh [ACTION] [OPTIONS]
```

### Actions

- `deploy`: Deploy Minecraft infrastructure (default)
- `destroy`: Destroy Minecraft infrastructure
- `status`: Check status of deployed infrastructure
- `save-state`: Save Terraform state to remote storage
- `load-state`: Load Terraform state from remote storage

### Common Options

- `-p, --provider <aws|azure>`: Specify the cloud provider (default: aws)
- `-o, --orchestration <swarm|kubernetes|local>`: Orchestration method (default: swarm)
- `-v, --minecraft-version VERSION`: Specify Minecraft version (default: latest)
- `-m, --mode <survival|creative>`: Game mode (default: survival)
- `-d, --difficulty <peaceful|easy|normal|hard>`: Game difficulty (default: normal)
- `-b, --no-bedrock`: Skip Bedrock Edition deployment
- `--no-interactive`: Run in non-interactive mode (no prompts)
- `--no-rollback`: Disable automatic rollback on failure
- `-h, --help`: Show help message

## Examples

### Deploying with Docker Swarm on AWS

```bash
./minecraft-ops.sh deploy --provider aws --orchestration swarm
```

### Deploying with Kubernetes on Azure

```bash
./minecraft-ops.sh deploy --provider azure --orchestration kubernetes --k8s aks
```

### Deploying locally with Docker

```bash
./minecraft-ops.sh deploy --orchestration local
```

### Customizing Minecraft settings

```bash
./minecraft-ops.sh deploy --provider aws --minecraft-version 1.19 --mode creative --difficulty easy
```

### Destroying infrastructure

```bash
./minecraft-ops.sh destroy --provider aws --orchestration swarm
```

### Checking deployment status

```bash
./minecraft-ops.sh status --provider aws --orchestration swarm
```

## Advanced Features

### Kubernetes-Specific Options

- `-k, --k8s <eks|aks>`: Kubernetes provider (eks for AWS, aks for Azure)
- `-n, --namespace NAMESPACE`: Kubernetes namespace (default: mineclifford)

```bash
./minecraft-ops.sh deploy --provider aws --orchestration kubernetes --k8s eks --namespace minecraft-prod
```

### Terraform State Management

You can save or load Terraform state to/from remote storage:

```bash
# Save state to S3
./minecraft-ops.sh save-state --provider aws --storage-type s3

# Load state from Azure storage
./minecraft-ops.sh load-state --provider azure --storage-type azure
```

### Force Cleanup during Destruction

For thorough cleanup when destroying infrastructure:

```bash
./minecraft-ops.sh destroy --provider aws --force
```

## Troubleshooting

### Logs

All operations are logged to a file named `minecraft_ops_YYYYMMDD_HHMMSS.log` in the current directory. Check this file for detailed information about any errors.

### Common Issues

1. **SSH key permissions**: Ensure SSH keys in `ssh_keys/` have proper permissions (400)
2. **Cloud credentials**: Verify your AWS or Azure credentials are valid
3. **Missing tools**: Ensure all required CLI tools are installed
4. **Failed deployments**: Use the `--no-rollback` option to prevent automatic rollback for debugging

### Retrying Failed Deployments

If a deployment fails, you can retry after fixing the issue:

```bash
./minecraft-ops.sh deploy --provider aws --skip-terraform
```

This will skip the Terraform provisioning step and continue with configuration.

## Extending the Script

The script is designed to be modular and extensible. To add support for new providers or orchestration methods:

1. Add validation in the `validate_environment` function
2. Implement deployment logic in a new function
3. Modify the main action handler to call your new function

## Security Considerations

- Sensitive data like passwords and keys should be stored in the `.env` file (not checked into version control)
- SSH keys generated during deployment are stored in the `ssh_keys/` directory
- State files may contain sensitive information and should be secured

## Maintenance Tasks

### Regular Updates

Update your Minecraft server:

```bash
./minecraft-ops.sh deploy --provider aws --minecraft-version latest --skip-terraform
```

### Backups

For Docker Swarm deployments, backups are automatically configured daily. For other deployments, manual backups are recommended.