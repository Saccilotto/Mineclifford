# Mineclifford

An automated provisioning tool for Minecraft servers on AWS and Azure.

## Description

Mineclifford is a tool designed to facilitate the creation and management of Minecraft servers, both Java and Bedrock editions. Using infrastructure as code (Terraform) and configuration automation (Ansible), Mineclifford allows you to deploy complete Minecraft servers in a matter of minutes on cloud providers such as AWS and Azure.

## Features

- **Multiple provider support**: AWS and Azure
- **Support for both editions**: Java and Bedrock
- **Flexible configuration**: customization of version, game mode, difficulty
- **Infrastructure as code**: using Terraform for provisioning
- **Configuration automation**: using Ansible for configuration
- **Orchestration with Docker Swarm**: for high availability and easy management
- **Integrated monitoring**: with Prometheus and Grafana
- **Automatic backup**: daily backup of Minecraft worlds
- **Cluster visualization**: with Docker Visualizer
- **Automatic updates**: with Watchtower

## Requirements

- Terraform 0.13+
- Ansible 2.9+
- Docker
- AWS or Azure account with permissions to create resources
- AWS CLI (aws) or Azure CLI (az)

## Quick Start

1. Clone this repository:

   ```bash
   git clone https://github.com/your-username/mineclifford.git
   cd mineclifford
   ```

2. Run the deployment script:

   ```bash  
   ./deploy-minecraft.sh --provider aws
   ```

3. To customize the deployment:

   ```bash
   ./deploy-minecraft.sh --provider aws --minecraft-version 1.19 --mode creative --difficulty easy
   ```

## Configuration Options

The `deploy-minecraft.sh` script accepts the following options:

- `-p, --provider <aws|azure>`: Cloud provider (default: aws)
- `-s, --skip-terraform`: Skip Terraform provisioning
- `-v, --minecraft-version VERSION`: Minecraft version (default: latest)
- `-m, --mode <survival|creative>`: Game mode (default: survival)
- `-d, --difficulty <peaceful|easy|normal|hard>`: Game difficulty (default: normal)
- `-b, --no-bedrock`: Disable Bedrock edition deployment
- `--no-interactive`: Run in non-interactive mode
- `--no-rollback`: Disable rollback in case of failure
- `-h, --help`: Show help message

## Architecture

Mineclifford uses a layered architecture:

1. **Infrastructure Provisioning** (Terraform):
   - Creates VPCs, subnets, security groups, and instances
   - Configures firewall rules for Minecraft servers
   - Generates and manages SSH keys for secure access

2. **Server Configuration** (Ansible):
   - Installs and configures Docker and Docker Swarm
   - Configures the system to run Minecraft servers
   - Implements monitoring and backup system

3. **Container Orchestration** (Docker Swarm):
   - Runs Minecraft servers in containers
   - Manages the network between services
   - Facilitates updates and maintenance

## Deployed Services

- **Minecraft Java Edition**: Port 25565
- **Minecraft Bedrock Edition**: Port 19132/UDP
- **RCON Web Admin**: Web interface for server administration
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization and dashboards
- **Docker Visualizer**: Docker Swarm cluster visualization

## Maintenance

### Backups

Backups are performed automatically every day at 4:00 AM and stored in `/home/ubuntu/minecraft-backups`. The last 5 backups are kept.

### Updates

Watchtower checks for updates daily and automatically updates container images.

### Monitoring

Access Grafana on port 3000 of your server to view metrics and server status.

## Troubleshooting

### Check server logs

```bash
ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service logs Mineclifford_minecraft-java"
```

### Restart services

```bash
ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service update --force Mineclifford_minecraft-java"
```

## Contributions

Contributions are welcome! Please feel free to submit pull requests or open issues.
