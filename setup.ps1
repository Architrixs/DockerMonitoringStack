# --- Style Definitions ---
$Green = "\e[32m"
$Yellow = "\e[33m"
$NC = "\e[0m" # No Color

Write-Host "${Green}### Docker Monitoring Stack Setup ###${NC}"

# 1. Check for Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "${Yellow}Error: Docker is not installed. Please install Docker and try again.${NC}"
    exit 1
}

# 2. Check if Docker is running
docker info > $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "${Yellow}Error: The Docker daemon is not running. Please start Docker and try again.${NC}"
    exit 1
}

Write-Host "✅ Prerequisites met."

# 3. Launch the stack
Write-Host "`n${Green}Starting the monitoring stack with 'docker-compose up -d'...${NC}"
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "${Yellow}Error: Docker Compose failed to start. Please check the logs.${NC}"
    exit 1
}

Write-Host "`n${Green}🚀 All services are starting up!${NC}"
Write-Host "It might take a minute for all services to become healthy."

# 4. Print URLs
Write-Host "`n${Green}--- Service URLs ---${NC}"
Write-Host "📊 ${Yellow}Grafana (Dashboards):${NC}  http://localhost:3000 (Login: admin/admin)"
Write-Host "📈 ${Yellow}Prometheus (Metrics):${NC} http://localhost:9091"
Write-Host "🔔 ${Yellow}AlertManager (Alerts):${NC} http://localhost:9093"
Write-Host "🐳 ${Yellow}Portainer (Docker GUI):${NC} https://localhost:9443 (Setup initial admin user)"
Write-Host "🔬 ${Yellow}cAdvisor (Raw Metrics):${NC} http://localhost:8080"
Write-Host "---------------------"

# 5. Open Grafana in browser
Write-Host "`nOpening Grafana in your default browser..."
Start-Sleep -Seconds 5
Start-Process "http://localhost:3000"

Write-Host "`n${Green}Setup complete! Enjoy your new monitoring stack. ✨${NC}"