# Mineclifford Configuration Guide

This guide explains how to configure your Mineclifford deployment.

## Environment Variables

Mineclifford uses environment variables to configure the deployment. You can set these variables in a `.env` file in the root directory of the project or export them in your shell environment.

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key ID (for AWS provider) | - | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key (for AWS provider) | - | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | AWS region (for AWS provider) | `us-east-2` | `us-west-2` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID (for Azure provider) | - | `00000000-0000-0000-0000-000000000000` |

### Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `MINECRAFT_VERSION` | Minecraft server version | `latest` | `1.19.2` |
| `MINECRAFT_GAMEMODE` | Game mode | `survival` | `creative` |
| `MINECRAFT_DIFFICULTY` | Game difficulty | `normal` | `peaceful` |
| `MINECRAFT_MEMORY` | Memory allocation for the Java server | `2G` | `4G` |
| `MINECRAFT_OPS` | Comma-separated list of operators | - | `user1,user2` |
| `TZ` | Timezone | `America/Sao_Paulo` | `Europe/London` |

## Terraform Variables

Terraform variables can be set in a `.tfvars` file or passed directly to the `terraform apply` command.

### AWS Terraform Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `project_name` | Name of the project | `mineclifford` | `my-minecraft-server` |
| `region` | AWS region | `us-east-2` | `eu-west-1` |
| `vpc_cidr` | CIDR block for the VPC | `10.0.0.0/16` | `172.16.0.0/16` |
| `subnet_cidr` | CIDR block for the subnet | `10.0.1.0/24` | `172.16.1.0/24` |
| `instance_type` | EC2 instance type | `t2.small` | `t3.medium` |
| `vm_names` | List of server instance names | `["instance1"]` | `["survival", "creative"]` |
| `username` | Username for SSH access | `ubuntu` | `admin` |

### Azure Terraform Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `resource_group_name` | Azure resource group name | `mineclifford` | `mc-production` |
| `location` | Azure region | `East US 2` | `West Europe` |
| `address_space` | Address space for the virtual network | `["10.0.0.0/16"]` | `["172.16.0.0/16"]` |
| `subnet_prefixes` | Address prefixes for the subnet | `["10.0.1.0/24"]` | `["172.16.1.0/24"]` |
| `vm_size` | Azure VM size | `Standard_B2s` | `Standard_D2s_v3` |
| `vm_names` | List of VM names | `["instance1"]` | `["survival", "creative"]` |
| `username` | Username for SSH access | `ubuntu` | `admin` |

## Docker Swarm Configuration

For Docker Swarm deployments, you can customize the service configuration by modifying the templates in `deployment/swarm/templates/`.

### Minecraft Java Template Variables

These variables can be set in `deployment/ansible/minecraft_vars.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `minecraft_java_version` | Server version | `latest` |
| `minecraft_java_memory` | Memory allocation | `2G` |
| `minecraft_java_gamemode` | Game mode | `survival` |
| `minecraft_java_difficulty` | Game difficulty | `normal` |
| `minecraft_java_motd` | Server MOTD | `Mineclifford Java Server` |
| `minecraft_java_ops` | Operator usernames | - |
| `minecraft_java_allow_nether` | Enable nether | `true` |
| `minecraft_java_enable_command_block` | Enable command blocks | `true` |
| `minecraft_java_spawn_protection` | Spawn protection radius | `0` |
| `minecraft_java_view_distance` | View distance | `10` |

### Minecraft Bedrock Template Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `minecraft_bedrock_version` | Server version | `latest` |
| `minecraft_bedrock_gamemode` | Game mode | `survival` |
| `minecraft_bedrock_difficulty` | Game difficulty | `normal` |
| `minecraft_bedrock_server_name` | Server name | `Mineclifford Bedrock Server` |
| `minecraft_bedrock_level_name` | Level name | `Mineclifford` |
| `minecraft_bedrock_allow_cheats` | Enable cheats | `false` |
| `minecraft_bedrock_max_players` | Maximum players | `10` |
| `minecraft_bedrock_view_distance` | View distance | `10` |

### Monitoring Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `grafana_password` | Grafana admin password | `admin` |
| `prometheus_version` | Prometheus version | `latest` |
| `grafana_version` | Grafana version | `latest` |
| `prometheus_port` | Prometheus port | `9090` |
| `grafana_port` | Grafana port | `3000` |

## Kubernetes Configuration

For Kubernetes deployments, you can customize the configuration using Kustomize.

### Base Configuration

The base configuration in `deployment/kubernetes/base/` defines the core resources for the Minecraft deployment.

### Provider-Specific Overlays

Provider-specific overlays in `deployment/kubernetes/aws/` and `deployment/kubernetes/azure/` customize the deployment for each cloud provider.

To customize the configuration:

1. Edit the `kustomization.yaml` file in the provider directory
2. Modify the patches in the `patches/` directory
3. Add or remove resources as needed

### Helm Chart Configuration

If using the Helm chart in `deployment/helm/minecraft/`, you can customize the configuration by creating a values file:

```yaml
# custom-values.yaml
javaEdition:
  server:
    gameMode: creative
    difficulty: peaceful
    memory: 4G
  
  resources:
    requests:
      memory: "4Gi"
    limits:
      memory: "5Gi"

bedrockEdition:
  enabled: false  # Disable Bedrock Edition

grafana:
  adminPassword: "my-secure-password"
```

Then deploy with:

```bash
helm upgrade --install minecraft ./deployment/helm/minecraft/ \
  --namespace minecraft \
  --values custom-values.yaml
```

## Monitoring Configuration

### Prometheus

Prometheus is configured using the file `deployment/swarm/prometheus/prometheus.yml` for Docker Swarm or through the Helm chart for Kubernetes.

To add custom alerting rules, edit or add files in the `deployment/swarm/prometheus/rules/` directory.

### Grafana

Grafana comes pre-configured with a Minecraft dashboard. To add more dashboards, add JSON files to the `deployment/swarm/grafana/dashboards/` directory.

The default credentials for Grafana are:

- Username: `admin`
- Password: `admin` (change this after first login)

## Advanced Configuration

### Multi-Server Deployment

To deploy multiple Minecraft servers:

1. Set the `vm_names` variable to a list of server names:

   ```terraform
   vm_names = ["survival", "creative", "adventure"]
   ```

2. Configure each server separately in the Ansible variables or Kubernetes resources.

### Custom Domains

To use a custom domain:

1. Update the `DOMAIN_NAME` environment variable in your `.env` file
2. Configure DNS to point to your server's IP address
3. Update the `ACME_EMAIL` environment variable for Let's Encrypt

### Backup Configuration

By default, backups are scheduled daily at 4:00 AM and stored in `/home/ubuntu/minecraft-backups`.

To customize the backup schedule, edit the cron job in `deployment/ansible/swarm_setup.yml`:

```yaml
- name: Add cron job for daily Minecraft backups
  cron:
    name: "Minecraft world backups"
    hour: "4"  # Change this to your preferred hour
    minute: "0"  # Change this to your preferred minute
    job: "/home/{{ ansible_ssh_user }}/backup-minecraft.sh > /home/{{ ansible_ssh_user }}/minecraft-backup.log 2>&1"
```
