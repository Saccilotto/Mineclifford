# Minecraft Server Deployment

This project automates the deployment of Minecraft servers on AWS with support for both vanilla and Bukkit/Paper servers.

## Features

- One-command deployment of Minecraft server on AWS
- Automatic world importing
- Support for both vanilla and Bukkit/Paper worlds
- Configurable server version

## Usage

### Basic Deployment

```bash
./deploy.sh
```

### Force Specific Version

```bash
./deploy.sh --force-version 1.21.4
```

Valid options:
vanilla: `1.21.4`, `1.22.5`
paper: `1.21.4`, `1.21.5`

### Specifying Server Type

```bash
./deploy.sh --server-type paper
```
