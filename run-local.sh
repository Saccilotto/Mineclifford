#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
MODE="survival"
DIFFICULTY="normal"
MINECRAFT_VERSION="latest"
USE_BEDROCK=true
MEMORY="2G"

# Function to show help
function show_help {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -v, --version VERSION      Specify Minecraft version (default: latest)"
    echo -e "  -m, --mode MODE            Game mode: survival, creative, adventure, spectator (default: survival)"
    echo -e "  -d, --difficulty DIFFICULTY Game difficulty: peaceful, easy, normal, hard (default: normal)"
    echo -e "  -b, --no-bedrock           Skip Bedrock Edition deployment"
    echo -e "  -mem, --memory MEMORY      Memory allocation for Java Edition (default: 2G)"
    echo -e "  -h, --help                 Show this help message"
    echo -e "${YELLOW}Example:${NC}"
    echo -e "  $0 --version 1.19 --mode creative --difficulty easy"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            MINECRAFT_VERSION="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -d|--difficulty)
            DIFFICULTY="$2"
            shift 2
            ;;
        -b|--no-bedrock)
            USE_BEDROCK=false
            shift
            ;;
        -mem|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            ;;
    esac
done

# Validate parameters
if [[ ! "$MODE" =~ ^(survival|creative|adventure|spectator)$ ]]; then
    echo -e "${RED}Error: Invalid game mode. Must be one of: survival, creative, adventure, spectator${NC}"
    exit 1
fi

if [[ ! "$DIFFICULTY" =~ ^(peaceful|easy|normal|hard)$ ]]; then
    echo -e "${RED}Error: Invalid difficulty. Must be one of: peaceful, easy, normal, hard${NC}"
    exit 1
fi

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed. Please install Docker before running this script.${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed. Please install Docker Compose before running this script.${NC}"
    exit 1
fi

# Create necessary directories
mkdir -p data/minecraft-java
mkdir -p data/minecraft-bedrock
mkdir -p data/rcon

# Create a temporary docker-compose file with our parameters
echo -e "${BLUE}Configuring Minecraft server with:${NC}"
echo -e "  Version: ${YELLOW}$MINECRAFT_VERSION${NC}"
echo -e "  Game Mode: ${YELLOW}$MODE${NC}"
echo -e "  Difficulty: ${YELLOW}$DIFFICULTY${NC}"
echo -e "  Memory: ${YELLOW}$MEMORY${NC}"
echo -e "  Bedrock Edition: ${YELLOW}$([[ "$USE_BEDROCK" == "true" ]] && echo "Enabled" || echo "Disabled")${NC}"

# Create the docker-compose.yml file
cat > docker-compose.yml << EOF
version: '3.8'

services:
  # Java Edition Minecraft Server
  minecraft-java:
    image: itzg/minecraft-server:$MINECRAFT_VERSION
    container_name: minecraft-java
    environment:
      - EULA=TRUE
      - TYPE=PAPER
      - MEMORY=$MEMORY
      - DIFFICULTY=$DIFFICULTY
      - MODE=$MODE
      - MOTD=Mineclifford Java Server
      - ALLOW_NETHER=true
      - ENABLE_COMMAND_BLOCK=true
      - SPAWN_PROTECTION=0
      - VIEW_DISTANCE=10
      - TZ=America/Sao_Paulo
    ports:
      - "25565:25565"
    volumes:
      - ./data/minecraft-java:/data
    restart: unless-stopped
EOF

# Add Bedrock if enabled
if [[ "$USE_BEDROCK" == "true" ]]; then
  cat >> docker-compose.yml << EOF

  # Bedrock Edition Minecraft Server
  minecraft-bedrock:
    image: itzg/minecraft-bedrock-server:$MINECRAFT_VERSION
    container_name: minecraft-bedrock
    environment:
      - EULA=TRUE
      - GAMEMODE=$MODE
      - DIFFICULTY=$DIFFICULTY
      - SERVER_NAME=Mineclifford Bedrock Server
      - LEVEL_NAME=Mineclifford
      - ALLOW_CHEATS=false
      - TZ=America/Sao_Paulo
    ports:
      - "19132:19132/udp"
    volumes:
      - ./data/minecraft-bedrock:/data
    restart: unless-stopped
EOF
fi

# Add RCON
cat >> docker-compose.yml << EOF

  # RCON Web Admin
  rcon-web-admin:
    image: itzg/rcon:latest
    container_name: rcon-web-admin
    ports:
      - "4326:4326"
      - "4327:4327"
    volumes:
      - ./data/rcon:/opt/rcon-web-admin/db
    environment:
      - RWA_PASSWORD=minecraft
      - RWA_ADMIN=true
    depends_on:
      - minecraft-java
    restart: unless-stopped
EOF

# Start the services
echo -e "${YELLOW}Starting Minecraft servers...${NC}"
docker-compose up -d

# Check status
echo -e "${YELLOW}Checking if services are running...${NC}"
sleep 10
docker-compose ps

# Show connection info
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Minecraft server started successfully!${NC}"
echo -e "${GREEN}Java Edition connection info:${NC}"
echo -e "  ${YELLOW}Server address: localhost:25565${NC}"

if [[ "$USE_BEDROCK" == "true" ]]; then
  echo -e "${GREEN}Bedrock Edition connection info:${NC}"
  echo -e "  ${YELLOW}Server address: localhost${NC}"
  echo -e "  ${YELLOW}Port: 19132${NC}"
fi

echo -e "${GREEN}RCON Web Admin:${NC}"
echo -e "  ${YELLOW}URL: http://localhost:4326${NC}"
echo -e "  ${YELLOW}Password: minecraft${NC}"

echo -e "${BLUE}To view server logs:${NC}"
echo -e "  ${YELLOW}Java Edition: docker logs -f minecraft-java${NC}"
if [[ "$USE_BEDROCK" == "true" ]]; then
  echo -e "  ${YELLOW}Bedrock Edition: docker logs -f minecraft-bedrock${NC}"
fi

echo -e "${BLUE}To stop the servers:${NC}"
echo -e "  ${YELLOW}docker-compose down${NC}"
echo -e "${GREEN}==========================================${NC}"

exit 0