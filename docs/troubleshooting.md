# Mineclifford Troubleshooting Guide

This guide provides solutions for common issues encountered when using Mineclifford.

## Deployment Issues

### Terraform Errors

#### Error: No valid credential sources found

**Problem**: AWS or Azure credentials are not properly configured.

**Solution**:

For AWS:

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-2"

# Or configure with AWS CLI
aws configure
```

For Azure:

```bash
# Login with Azure CLI
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Export environment variable
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
```

#### Error: Error creating resource group

**Problem**: Insufficient permissions for creating Azure resources.

**Solution**:

1. Ensure your Azure account has the necessary permissions (Contributor role).
2. Check if you've reached resource quotas or limits.
3. Verify the region is valid and available for your subscription.

#### Error: Error launching EC2 instance

**Problem**: Issues with launching AWS EC2 instances.

**Solution**:

1. Check if you have reached your EC2 instance limit.
2. Verify the instance type is available in the selected region.
3. Check VPC and subnet configuration.
4. Ensure the AMI ID is valid and available.

### Ansible Errors

#### Error: SSH Error: Permission denied (publickey)

**Problem**: SSH authentication issues when connecting to instances.

**Solution**:

1. Check if SSH keys are properly generated and have correct permissions:

   ```bash
   chmod 400 ssh_keys/*.pem
   ```

2. Verify the SSH key was properly deployed to the instance.
3. Check the username used for SSH access (default is `ubuntu`).
4. Ensure the instance is fully initialized and SSH service is running.

#### Error: Ansible playbook execution failed

**Problem**: Ansible playbook fails to execute properly.

**Solution**:

1. Run Ansible with verbose output to identify the issue:

   ```bash
   ansible-playbook -vvv -i static_ip.ini deployment/ansible/swarm_setup.yml
   ```

2. Check if all required variables are defined.
3. Verify network connectivity to the instances.
4. Check for syntax errors in the YAML files.

### Docker Swarm Errors

#### Error: Error response from daemon: rpc error

**Problem**: Issues with Docker Swarm initialization or node joining.

**Solution**:

1. Check if Docker is running on all nodes:

   ```bash
   ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker swarm init --force-new-cluster"
   ```

#### Error: service creation failed

**Problem**: Unable to create Docker services.

**Solution**:

1. Check Docker service logs:

   ```bash
   docker service logs Mineclifford_minecraft-java
   ```

2. Verify that the Docker image exists and is accessible.
3. Check for resource constraints (memory, CPU).
4. Ensure network and volume configurations are correct.

### Kubernetes Errors

#### Error: Unable to connect to the server

**Problem**: kubectl cannot connect to the Kubernetes cluster.

**Solution**:

1. Check if the Kubernetes cluster is up and running.
2. Verify that kubectl is properly configured:

   ```bash
   kubectl config view
   ```

3. For EKS:

   ```bash
   aws eks update-kubeconfig --name <cluster-name> --region <region>
   ```

4. For AKS:

   ```bash
   az aks get-credentials --resource-group <resource-group> --name <cluster-name>
   ```

#### Error: Error from server (Forbidden)

**Problem**: Insufficient permissions to perform operations on the Kubernetes cluster.

**Solution**:

1. Check RBAC permissions.
2. Verify that you're using the correct service account or credentials.
3. Check if the cluster has RBAC enabled:

   ```bash
   kubectl api-versions | grep rbac
   ```

## Server Issues

### Minecraft Server Issues

#### Problem: Server doesn't start

**Solution**:

1. Check container logs:

   ```bash
   # Docker Swarm
   ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service logs Mineclifford_minecraft-java"
   
   # Kubernetes
   kubectl logs -n mineclifford -l app=minecraft-java
   
   # Local Docker
   docker-compose logs minecraft-java
   ```

2. Verify that the server has enough memory allocated.
3. Check for errors in the Minecraft server logs.
4. Ensure the EULA has been accepted (set `EULA=TRUE`).

#### Problem: Low TPS (ticks per second)

**Solution**:

1. Check server performance in Grafana.
2. Reduce view distance in the server configuration.
3. Allocate more memory to the server.
4. Optimize server settings by editing `server.properties`.
5. Upgrade the VM/instance to a more powerful one.

#### Problem: Players can't connect

**Solution**:

1. Verify that the server is running.
2. Check if the correct ports are open:
   - Java Edition: 25565/tcp
   - Bedrock Edition: 19132/udp
3. Verify the security group/firewall settings.
4. Check if the public IP is correctly assigned.
5. Test connectivity with tools like `nmap` or `telnet`.

### Monitoring Issues

#### Problem: Prometheus is not collecting metrics

**Solution**:

1. Check if Prometheus is running:

   ```bash
   # Docker Swarm
   ssh -i ssh_keys/instance1.pem ubuntu@<SERVER-IP> "docker service ls | grep prometheus"
   
   # Kubernetes
   kubectl get pods -n mineclifford -l app=prometheus
   ```

2. Verify the Prometheus configuration in `prometheus.yml`.
3. Check if the exporter services are running and accessible.
4. Test the endpoints manually:

   ```bash
   curl http://localhost:9150/metrics
   ```

#### Problem: Grafana dashboards not loading

**Solution**:

1. Check if Grafana is running.
2. Verify that Prometheus is configured as a data source in Grafana.
3. Check for errors in the Grafana logs.
4. Reload the dashboard configuration.

## Operations Script Issues

### Error: Missing required tool

**Problem**: The `minecraft-ops.sh` script complains about missing tools.

**Solution**:

1. Install the required tools:

   ```bash
   # For Terraform
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install terraform
   
   # For Ansible
   sudo apt-get install ansible
   
   # For kubectl
   curl -LO "https://dl.k8s.io/release/stable.txt"
   curl -LO "https://dl.k8s.io/release/$(cat stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
   
   # For AWS CLI
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip && sudo ./aws/install
   
   # For Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

2. Add the tools to your PATH environment variable if needed.

#### Error: Invalid parameters

**Problem**: The script reports invalid parameter values.

**Solution**:

1. Check the script's help message for valid options:

   ```bash
   ./minecraft-ops.sh --help
   ```

2. Verify that you're using the correct parameter format.
3. Check for typos in parameter names or values.

## State Management Issues

### Problem: Terraform state is missing or corrupted

**Solution**:

1. Check if the state file exists:

   ```bash
   ls -la terraform/aws/terraform.tfstate
   ```

2. Try to load the state from remote storage:

   ```bash
   ./minecraft-ops.sh load-state --provider aws
   ```

3. If the state is corrupted, try to recover it:

   ```bash
   terraform state pull > terraform.tfstate.backup
   terraform state push terraform.tfstate.backup
   ```

#### Problem: Resources not properly destroyed

**Solution**:

1. Use the verification script:

   ```bash
   ./verify-destruction.sh --provider aws --force
   ```

2. Check for orphaned resources in the cloud provider's console.
3. Manually delete any remaining resources.

## Common Error Messages and Their Solutions

### "Error: No available provider with installation constraints"

**Solution**: Initialize Terraform with the required providers:

```bash
cd terraform/aws
terraform init
```

### "Error: Error acquiring the state lock"

**Solution**: Release the state lock if no other Terraform operations are running:

```bash
terraform force-unlock <LOCK_ID>
```

### "Error: Host key verification failed"

**Solution**:

1. Clear known hosts:

   ```bash
   ssh-keygen -R <SERVER_IP>
   ```

2. Add the new host key:

   ```bash
   ssh-keyscan -H <SERVER_IP> >> ~/.ssh/known_hosts
   ```

### "Error: timeout while waiting for state to become 'Running'"

**Solution**:

1. Check the instance status in the cloud provider's console.
2. Verify that the instance type is available in the selected region.
3. Check if there are service quotas or limits that are being reached.

## Getting Help

If you continue to have issues after trying these troubleshooting steps, you can:

1. Open an issue on the GitHub repository.
2. Check the logs for more detailed error messages.
3. Join our community Discord for real-time help.

Remember to always include:

- The exact error message
- Steps to reproduce the issue
- Your environment details (OS, cloud provider, tool versions)
- Relevant log files
- Keys/instance1.pem ubuntu@`<SERVER-IP>` "systemctl status docker"

1. Verify network connectivity between nodes.
2. Check if the required ports are open (TCP 2377, 7946, and UDP 4789, 7946).
3. Reinitialize the swarm:

```bash
   ssh -i ssh-key.pem ubuntu@<SERVER-IP> "docker swarm init"
```
