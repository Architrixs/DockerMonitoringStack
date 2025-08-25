#!/bin/bash

# --- Style Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}### Docker Monitoring Stack Setup ###${NC}"

# 1. Check for Docker
if ! [ -x "$(command -v docker)" ]; then
  echo -e "${YELLOW}Error: Docker is not installed. Please install Docker and try again.${NC}" >&2
  exit 1
fi

# 2. Check for Docker Compose (v2)
if ! docker compose version >/dev/null 2>&1; then
    echo -e "${YELLOW}Error: Docker Compose V2 is not available. Please ensure you have a modern version of Docker Desktop or Docker Engine.${NC}" >&2
    exit 1
fi


# 3. Check if Docker is running
if ! docker info >/dev/null 2>&1; then
  echo -e "${YELLOW}Error: The Docker daemon is not running. Please start Docker and try again.${NC}" >&2
  exit 1
fi

echo "✅ Prerequisites met."

# 4. Launch the stack
echo -e "\n${GREEN}Starting the monitoring stack with 'docker compose up -d'...${NC}"
docker compose up -d

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Error: Docker Compose failed to start. Please check the logs.${NC}" >&2
    exit 1
fi

echo -e "\n${GREEN}🚀 All services are starting up!${NC}"
echo "It might take a minute for all services to become healthy."

# 5. Print URLs
echo -e "\n${GREEN}--- Service URLs ---${NC}"
echo -e "📊 ${YELLOW}Grafana (Dashboards):${NC}  http://localhost:3000 (Login: admin/admin)"
echo -e "📈 ${YELLOW}Prometheus (Metrics):${NC} http://localhost:9091"
echo -e "🔔 ${YELLOW}AlertManager (Alerts):${NC} http://localhost:9093"
echo -e "🐳 ${YELLOW}Portainer (Docker GUI):${NC}https://localhost:9443 (Setup initial admin user)"
echo -e "🔬 ${YELLOW}cAdvisor (Raw Metrics):${NC} http://localhost:8080"
echo -e "---------------------"

# 6. Open Grafana in browser
echo -e "\nOpening Grafana in your default browser..."
sleep 5
if command -v xdg-open >/dev/null; then
  xdg-open http://localhost:3000
elif command -v open >/dev/null; then
  open http://localhost:3000
else
  echo -e "${YELLOW}Could not automatically open browser. Please navigate to http://localhost:3000 manually.${NC}"
fi

echo -e "\n${GREEN}Setup complete! Enjoy your new monitoring stack. ✨${NC}"