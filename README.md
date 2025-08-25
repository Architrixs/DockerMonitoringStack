# Docker Microservices Monitoring Stack

A complete, production-ready monitoring solution for Docker-based systems. This stack uses Prometheus, Grafana, cAdvisor, Node Exporter, and AlertManager to provide deep insights into your container and host performance without modifying your application code.

## ✨ Features

-   **Zero Code Changes**: Monitors containers and hosts externally.
-   **Docker Compose**: Single-command setup and management.
-   **Grafana Dashboards**: Pre-configured dashboards for immediate visibility.
-   **Prometheus & AlertManager**: Powerful metrics and alerting engine.
-   **cAdvisor**: Detailed per-container metrics (CPU, Memory, Network, I/O).
-   **Node Exporter**: Detailed host metrics (CPU, Memory, Disk, System Load).
-   **Extensible**: Easily add remote hosts or other exporters.

## ✅ System Requirements

-   **Docker**: Version 20.10+
-   **Docker Compose**: Version 1.29+ (or Docker Engine with compose plugin)
-   **Operating System**: Windows, macOS, or Linux.
-   **RAM**: 4GB+ recommended for smooth operation.
-   **Git**: Required for cloning this repository.
-   **(Optional) NVIDIA GPUs**: Requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) for GPU monitoring.

## 🚀 Quickstart Installation

1.  **Clone the Repository**
    ```sh
    git clone <repository_url>
    cd DockerMomitoringStack
    ```

2.  **Run the Setup Script**

    Choose the script for your operating system. It will check prerequisites and launch the stack.

    **For Linux or macOS:**
    ```sh
    chmod +x setup.sh
    ./setup.sh
    ```

    **For Windows (in PowerShell):**
    ```powershell
    ./setup.ps1
    ```

3.  **Access Services**
    The script will open Grafana automatically. You can access all services at the URLs below.

## 🛠️ Accessing Services

| Service | URL | Credentials |
| :--- | :--- |:---|
| **Grafana** | `http://localhost:3000` | `admin` / `admin` |
| **Prometheus** | `http://localhost:9091` | N/A |
| **AlertManager** | `http://localhost:9093` | N/A |
| **Portainer** | `https://localhost:9443` | Set up on first visit |
| **cAdvisor** | `http://localhost:8080` | N/A |

## ⚙️ Configuration

### Adding a Remote Docker Host to Monitor

To monitor a remote server (e.g., a VM at `192.168.1.101`):

1.  **On the remote server**, install and run Node Exporter:
    ```sh
    docker run -d --name=node-exporter --net="host" --pid="host" -v "/:/host:ro,rslave" prom/node-exporter:v1.8.1
    ```
    *Ensure the firewall on the remote host allows incoming traffic on port `9100` from your monitoring server.*

2.  **On your local machine**, edit `prometheus/prometheus.yml`:
    ```yaml
    # In scrape_configs:
    - job_name: 'node-exporter'
      static_configs:
        - targets: ['localhost:9100']
        # Uncomment and edit the following line:
        - targets: ['192.168.1.101:9100']
    ```

3.  **Restart Prometheus** to apply the changes:
    ```sh
    docker-compose restart prometheus
    ```

### Enabling NVIDIA GPU Monitoring

1.  Ensure you have the **NVIDIA Container Toolkit** installed on your Docker host.
2.  Uncomment the `dcgm-exporter` service in `docker-compose.yml`.
3.  Uncomment the `dcgm-exporter` job in `prometheus/prometheus.yml`.
4.  Restart the stack: `docker-compose up -d`.

### Customizing Alerts

1.  **Add Rules**: Edit `alertmanager/alert.rules.yml` to add or modify alerting rules. Use the [Prometheus documentation](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) for syntax.
2.  **Configure Notifiers**: Edit `alertmanager/alertmanager.yml` to configure receivers like Slack, PagerDuty, or email. See the [AlertManager documentation](https://prometheus.io/docs/alerting/latest/configuration/) for examples.
3.  Restart the relevant services: `docker-compose restart prometheus alertmanager`.

## 🔍 Sample PromQL Queries

Use these in the Grafana "Explore" tab or the Prometheus UI to query your data.

-   **Top 5 containers by memory usage:**
    `topk(5, sum(container_memory_usage_bytes) by (name))`

-   **CPU usage per container (as a percentage of one core):**
    `sum(rate(container_cpu_usage_seconds_total[5m])) by (name) * 100`

-   **Network I/O received by containers:**
    `sum(rate(container_network_receive_bytes_total[5m])) by (name)`

## 💣 Stopping the Stack

To stop and remove all containers:
```sh
docker-compose down