# Mineclifford

An automated provisioning tool for Minecraft servers on AWS and Azure.

## Description

Mineclifford is a tool designed to facilitate the creation and management of Minecraft servers, both Java and Bedrock editions. Using infrastructure as code (Terraform) and configuration automation (Ansible), Mineclifford allows you to deploy complete Minecraft servers in a matter of minutes on cloud providers such as AWS and Azure.

## Features

- **Multiple provider support**: AWS and Azure
- **Multiple orchestration options**: Docker Swarm or Kubernetes
- **Support for both editions**: Java and Bedrock
- **Flexible configuration**: customization of version, game mode, difficulty
- **Infrastructure as code**: using Terraform for provisioning
- **Configuration automation**: using Ansible for configuration
- **Integrated monitoring**: with Prometheus and Grafana
- **Automatic backup**: daily backup of Minecraft worlds
- **Cluster visualization**: with Docker Visualizer
- **Automatic updates**: with Watchtower

## Requirements

- Terraform 0.13+
- Ansible 2.9+
- Docker
- Kubernetes CLI (kubectl) for Kubernetes deployments
- AWS or Azure account with permissions to create resources
- AWS CLI (aws) or Azure CLI (az)

## Quick Start

### Docker Swarm Deployment

1. Clone this repository:
   ```
   git clone https://github.com/your-username/mineclifford.git
   cd mineclifford
   ```

2. Run the deployment script:
   ```
   ./deploy-minecraft.sh --provider aws
   ```

3. To customize the deployment:
   ```
   ./deploy-minecraft.sh --provider aws --minecraft-version 1.19 --mode creative --difficulty easy
   ```

### Kubernetes Deployment

1. Clone this repository:
   ```
   git clone https://github.com/your-username/mineclifford.git
   cd mineclifford
   ```

2. Run the Kubernetes deployment script:
   ```
   ./deploy-kubernetes.sh --provider aws --k8s eks
   ```

3. To customize the Kubernetes deployment:
   ```
   ./deploy-kubernetes.sh --provider aws --k8s eks --minecraft-version 1.19 --mode creative --difficulty easy
   ```

### Local Testing

For local testing without cloud deployment:

```
./run-local.sh --version 1.19 --mode creative --difficulty easy
```

## Configuration Options

### Docker Swarm Deployment Options

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

### Kubernetes Deployment Options

The `deploy-kubernetes.sh` script accepts the following options:

- `-p, --provider <aws|azure|gcp>`: Cloud provider (default: aws)
- `-k, --k8s <eks|aks|gke|k3s>`: Kubernetes provider (default: eks)
- `-s, --skip-infrastructure`: Skip infrastructure provisioning
- `-n, --namespace NAMESPACE`: Kubernetes namespace (default: mineclifford)
- `-v, --minecraft-version VERSION`: Minecraft version (default: latest)
- `-m, --mode <survival|creative>`: Game mode (default: survival)
- `-d, --difficulty <peaceful|easy|normal|hard>`: Game difficulty (default: normal)
- `-b, --no-bedrock`: Disable Bedrock edition deployment
- `--no-interactive`: Run in non-interactive mode
- `--no-rollback`: Disable rollback in case of failure
- `-h, --help`: Show help message

## Architecture

Mineclifford supports two different deployment architectures:

### Docker Swarm Architecture

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

### Kubernetes Architecture

1. **Infrastructure Provisioning** (Terraform):
   - Creates managed Kubernetes clusters (EKS on AWS, AKS on Azure)
   - Configures networking and security
   - Sets up storage classes and node groups

2. **Kubernetes Deployment**:
   - Deploys Minecraft servers as Kubernetes Deployments
   - Creates services and persistent volumes
   - Configures monitoring with Prometheus and Grafana
   - Sets up ingress for web interfaces

## Deployed Services

- **Minecraft Java Edition**: Port 25565
- **Minecraft Bedrock Edition**: Port 19132/UDP
- **RCON Web Admin**: Web interface for server administration
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization and dashboards
- **Docker Visualizer** (Docker Swarm only): Docker Swarm cluster visualization

## Maintenance

### Backups

#### Docker Swarm

Backups are performed automatically every day at 4:00 AM and stored in `/home/ubuntu/minecraft-backups`. The last 5 backups are kept.

#### Kubernetes

Backups are handled through Kubernetes PersistentVolume snapshots. You can manage them using:

```bash
kubectl get volumesnapshots --namespace=mineclifford
```

### Updates

#### Docker Swarm

Watchtower checks for updates daily and automatically updates container images.

#### Kubernetes

To update Minecraft versions or configuration in Kubernetes:

```bash
./deploy-kubernetes.sh --provider aws --k8s eks --minecraft-version <new-version> --skip-infrastructure
```

### Monitoring

#### Docker Swarm

Access Grafana on port 3000 of your server to view metrics and server status.

#### Kubernetes

Access Grafana through the Ingress URL (typically http://monitor.your-domain.com).

## Troubleshooting

### Docker Swarm

#### Check server logs

```bash
ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service logs Mineclifford_minecraft-java"
```

#### Restart services

```bash
ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service update --force Mineclifford_minecraft-java"
```

### Kubernetes

#### Check pod logs

```bash
kubectl logs -f -l app=minecraft-java --namespace=mineclifford
```

#### Restart deployments

```bash
kubectl rollout restart deployment minecraft-java --namespace=mineclifford
```

## Contributions

Contributions are welcome! Please feel free to submit pull requests or open issues.