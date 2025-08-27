# Docker Microservices Monitoring Stack

A complete, production-ready monitoring solution for Docker-based systems. This stack uses Prometheus, Grafana, cAdvisor, Node Exporter, AlertManager, and Portainer to provide deep insights into your container and host performance without modifying your application code.

## ✨ Features

-   **Zero Code Changes**: Monitors containers and hosts externally.
-   **Docker Compose**: Single-command setup for both the main stack and remote nodes.
-   **Automated Service Discovery**: Automatically discovers, verifies, and adds new remote nodes for monitoring.
-   **Centralized Multi-Node Management**: Use **Portainer** to manage all your local and remote Docker environments from a single, user-friendly GUI.
-   **Grafana Dashboards**: Pre-configured and custom-built dashboards for immediate visibility into host, container, and fleet-wide metrics.
-   **Precise & Robust Alerting**: A powerful set of refined alert rules for critical issues, with clean, readable notifications powered by custom templates.
-   **Secure by Default**: Manages secrets like passwords and API keys securely using an environment file, which is kept out of version control.
-   **Extensible**: Easily add new remote hosts by running a simple discovery script.

## ✅ System Requirements

-   **Docker**: Version 20.10+
-   **Docker Compose**: Version 1.29+ (or Docker Engine with compose plugin)
-   **Operating System**: Linux is recommended for the main node. Remote nodes can be Linux, macOS, or Windows.
-   **Required Tools (on main node):** `git`, `nmap`, and `jq`.
    -   On Debian/Ubuntu: `sudo apt-get install -y nmap jq`
    -   On CentOS/Fedora: `sudo yum install -y nmap jq`
-   **RAM**: 4GB+ recommended for the main monitoring node.
-   **(Optional) NVIDIA GPUs**: Requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) for GPU monitoring.

## 🚀 Quickstart Installation

1.  **Clone the Repository**
    ```sh
    git clone <repository_url>
    cd monitoring-stack
    ```

2.  **Configure Secrets**
    Create a `.env` file in the root of the directory. This is where you will store all your secrets. **This file should never be committed to Git.**
    ```
    # .env file

    # For Email Alerts (using Gmail as an example)
    SMTP_USERNAME=your-sender-email@gmail.com
    SMTP_PASSWORD=YOUR_16_CHARACTER_APP_PASSWORD

    # For Portainer API Integration
    PORTAINER_URL=https://your-portainer-ip:9443
    PORTAINER_API_KEY=ptr_your_portainer_api_key_here
    ```

3.  **Run the Setup Script**
    Choose the script for your operating system. It will check prerequisites and launch the main stack.

    **For Linux or macOS:**
    ```sh
    chmod +x setup.sh
    ./setup.sh
    ```

    **For Windows (in PowerShell):**
    ```powershell
    ./setup.ps1
    ```

4.  **Access Services**
    The script will open Grafana automatically. You can access all services at the URLs below.

## 🛠️ Accessing Services

| Service | URL | Credentials |
| :--- | :--- |:---|
| **Grafana** | `http://localhost:3000` | `admin` / `admin` |
| **Prometheus** | `http://localhost:9090` | N/A |
| **AlertManager** | `http://localhost:9093` | N/A |
| **Portainer (HTTPS)** | `https://localhost:9443` | Set up on first visit |
| **Portainer (HTTP API)**| `http://localhost:9000` | Use API Key |
| **cAdvisor** | `http://localhost:8080` | N/A |

## ⚙️ Multi-Node Monitoring & Management

This stack is designed to be the central control plane for all your Docker hosts.

### Adding a Remote Docker Host

1.  **On the remote server**, copy the `docker-compose.remote.yml` file.
2.  Run `docker-compose -f docker-compose.remote.yml up -d`. This will start the necessary exporters (`node-exporter`, `cadvisor`, etc.).
3.  Ensure the firewall on the remote host allows incoming traffic on the exporter ports (e.g., 9100, 8080) from your main monitoring server.
4.  **On your main monitoring node**, run the discovery script:
    ```sh
    # You can specify subnets or let it auto-discover the local one.
    ./discover-nodes.sh 192.168.5.0/24
    ```
    The script will automatically find the new node, add it to Prometheus's targets, and register it as a new environment in Portainer.

### Portainer Multi-Node Management
The discovery script automatically adds new hosts to Portainer as **Agent** environments. This allows you to manage all your remote Docker instances from the central Portainer UI without needing to manually configure certificates. Simply log in to Portainer and switch between your different environments from the home page.

## 📊 Embedding Dashboards in Your Application

You can embed any Grafana dashboard into your own web application using an iFrame.

1.  **Enable Embedding:** The `docker-compose.yml` file is already configured with the necessary environment variables (`GF_SECURITY_ALLOW_EMBEDDING=true`, etc.) to allow this.
2.  **Get the Embed URL:** In Grafana, go to the dashboard you want to embed, click the "Share" icon, and go to the "Embed" tab.
3.  **Use Kiosk Mode:** For a clean, UI-less view, add `&kiosk=tv` to the end of the URL. This mode is locked and cannot be exited with the `Esc` key.
4.  **Control Dynamically:** You can change dashboard variables like the theme or the selected host directly from your application by updating the iFrame's `src` URL with JavaScript.

**Example iFrame:**
```html
<iframe src="http://localhost:3000/d/your-dashboard-id/your-dashboard?orgId=1&kiosk=tv&theme=dark&var-host=192.168.1.101" width="100%" height="800"></iframe>
```
## 💣 Stopping the Stack
To stop and remove all containers: `docker-compose down`
To also remove the persistent data volumes (Prometheus history, Grafana settings): `docker-compose down -v`
