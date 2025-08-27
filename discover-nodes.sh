#!/bin/bash

# Phase 1: Discover all services and ensure hosts are in Portainer.
# Phase 2: Fetch the real hostnames from Portainer's snapshot data.
# Phase 3: Update the Prometheus targets file with the correct hostnames.

set -e

# --- Configuration ---
LIST_ONLY_MODE=false
NETWORK_RANGES=()
TARGETS_FILE="prometheus/targets.json"
PORTAINER_URL="http://localhost:9000"

if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  export $(grep -v '^#' .env | xargs)
fi

# --- Helper Functions ---
# Associative array to store IP -> Hostname mapping
declare -A HOST_NAMES_MAP

# --- Script Logic ---

# Parse command-line arguments
while (( "$#" )); do
  case $1 in
    -l|--list-only)
      LIST_ONLY_MODE=true
      ;;
    *)
      NETWORK_RANGES+=("$1")
      ;;
  esac
  shift
done

# Auto-detect network range if not provided
if [ ${#NETWORK_RANGES[@]} -eq 0 ]; then
    LOCAL_RANGE=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)
    if [ -z "$LOCAL_RANGE" ]; then
        echo "Error: Could not determine local network range." >&2
        exit 1
    fi
    NETWORK_RANGES+=("$LOCAL_RANGE")
fi

echo "Scanning network(s): ${NETWORK_RANGES[@]}"

# --- Phase 1: Discover All Services ---
echo ""
echo "--- Phase 1: Discovering All Services ---"
ALL_DISCOVERED_IPS=()
VERIFIED_NODE_EXPORTER_TARGETS=""
VERIFIED_CADVISOR_TARGETS=""
VERIFIED_DCGM_EXPORTER_TARGETS=""

for RANGE in "${NETWORK_RANGES[@]}"; do
    echo "--- Scanning $RANGE ---"
    ALL_IPS_IN_RANGE=$(nmap -sn "$RANGE" -oG - | awk '/Up$/{print $2}')
    
    for IP in $ALL_IPS_IN_RANGE; do
        # Check for Portainer Agent
        if nc -z -w 2 $IP 9001 || nc -z -w 2 $IP 9002; then
            echo "  - Found Portainer Agent on $IP"
            ALL_DISCOVERED_IPS+=("$IP")
        fi
        # Check for Node Exporter
        if curl -s --connect-timeout 2 "http://$IP:9100/metrics" | grep -q "node_exporter_build_info"; then
            echo "  - Found Node Exporter on $IP:9100"
            VERIFIED_NODE_EXPORTER_TARGETS="$VERIFIED_NODE_EXPORTER_TARGETS $IP:9100"
            ALL_DISCOVERED_IPS+=("$IP")
        elif curl -s --connect-timeout 2 "http://$IP:9101/metrics" | grep -q "node_exporter_build_info"; then
            echo "  - Found Node Exporter on $IP:9101"
            VERIFIED_NODE_EXPORTER_TARGETS="$VERIFIED_NODE_EXPORTER_TARGETS $IP:9101"
            ALL_DISCOVERED_IPS+=("$IP")
        fi
        # Check for cAdvisor
        if curl -s --connect-timeout 2 "http://$IP:8080/metrics" | grep -q "cadvisor_version_info"; then
            echo "  - Found cAdvisor on $IP:8080"
            VERIFIED_CADVISOR_TARGETS="$VERIFIED_CADVISOR_TARGETS $IP:8080"
            ALL_DISCOVERED_IPS+=("$IP")
        elif curl -s --connect-timeout 2 "http://$IP:8081/metrics" | grep -q "cadvisor_version_info"; then
            echo "  - Found cAdvisor on $IP:8081"
            VERIFIED_CADVISOR_TARGETS="$VERIFIED_CADVISOR_TARGETS $IP:8081"
            ALL_DISCOVERED_IPS+=("$IP")
        fi
        # Check for DCGM Exporter
        if curl -s --connect-timeout 2 "http://$IP:9400/metrics" | grep -q "DCGM_FI_DRIVER_VERSION"; then
            echo "  - Found DCGM Exporter on $IP:9400"
            VERIFIED_DCGM_EXPORTER_TARGETS="$VERIFIED_DCGM_EXPORTER_TARGETS $IP:9400"
            ALL_DISCOVERED_IPS+=("$IP")
        elif curl -s --connect-timeout 2 "http://$IP:9401/metrics" | grep -q "DCGM_FI_DRIVER_VERSION"; then
            echo "  - Found DCGM Exporter on $IP:9401"
            VERIFIED_DCGM_EXPORTER_TARGETS="$VERIFIED_DCGM_EXPORTER_TARGETS $IP:9401"
            ALL_DISCOVERED_IPS+=("$IP")
        fi
    done
done
UNIQUE_IPS=($(echo "${ALL_DISCOVERED_IPS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
echo "Service discovery complete. Found services on ${#UNIQUE_IPS[@]} unique hosts."

# --- Update Portainer Environments ---
echo ""
if [ "$LIST_ONLY_MODE" = false ] && [ -n "$PORTAINER_API_KEY" ]; then
    echo "--- Ensuring Hosts Exist in Portainer ---"
    EXISTING_ENDPOINTS=$(curl -s -k -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/endpoints")
    EXISTING_URLS=$(echo "$EXISTING_ENDPOINTS" | jq -r '.[].URL')
    NEW_HOSTS_ADDED=false

    for IP in "${UNIQUE_IPS[@]}"; do
        ENDPOINT_URL="tcp://$IP:9001"
        if ! echo "$EXISTING_URLS" | grep -qF "$ENDPOINT_URL"; then
            echo "Adding new Portainer environment for $IP..."
            FORM_DATA="Name=${IP}&URL=${ENDPOINT_URL}&EndpointCreationType=2&GroupID=1&TLS=true&TLSSkipVerify=true&TLSSkipClientVerify=true"
            ADD_RESULT=$(curl -s -k -w "%{http_code}" -X POST \
              -H "X-API-Key: $PORTAINER_API_KEY" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              --data "$FORM_DATA" \
              "$PORTAINER_URL/api/endpoints")
            HTTP_CODE=${ADD_RESULT: -3}
            if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
                echo "  Successfully added $IP. Portainer will now discover its hostname."
                NEW_HOSTS_ADDED=true
            else
                echo "  Error adding $IP. Portainer API returned HTTP $HTTP_CODE."
            fi
        else
            echo "Portainer environment for $IP already exists. Skipping."
        fi
    done

    # If we added any new hosts, wait for Portainer to process them
    if [ "$NEW_HOSTS_ADDED" = true ]; then
        echo "Waiting 10 seconds for Portainer to discover hostnames..."
        sleep 10
    fi
fi

# --- Phase 2: Fetch Hostnames from Portainer ---
echo ""
echo "--- Phase 2: Fetching Hostnames from Portainer API ---"
if [ -n "$PORTAINER_API_KEY" ]; then
    endpoints=$(curl -s -k -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/endpoints")
    while IFS="=" read -r key value; do
        HOST_NAMES_MAP["$key"]="$value"
    done < <(echo "$endpoints" | jq -r '.[] | .URL as $url | .Snapshots[0].DockerSnapshotRaw.Info.Name as $name | ($url | ltrimstr("tcp://") | split(":")[0]) + "=" + $name')
    echo "Successfully built name map from Portainer."
    echo "--- Discovered Host Names ---"
    for ip in "${!HOST_NAMES_MAP[@]}"; do
        echo "  $ip -> ${HOST_NAMES_MAP[$ip]}"
    done
    echo "---------------------------"
else
    echo "Warning: PORTAINER_API_KEY not set. Falling back to using IP addresses for names."
fi

# --- Phase 3: Update Prometheus Targets File ---
echo ""
if [ "$LIST_ONLY_MODE" = true ]; then
    echo "--- Prometheus Targets (List-Only Mode) ---"
    echo "Would check/add the following targets:"
    for TARGET in $VERIFIED_NODE_EXPORTER_TARGETS; do echo "  - Node Exporter: $TARGET (Host: ${HOST_NAMES_MAP[$(echo $TARGET | cut -d: -f1)]:-$(echo $TARGET | cut -d: -f1)})"; done
    for TARGET in $VERIFIED_CADVISOR_TARGETS; do echo "  - cAdvisor: $TARGET (Host: ${HOST_NAMES_MAP[$(echo $TARGET | cut -d: -f1)]:-$(echo $TARGET | cut -d: -f1)})"; done
    for TARGET in $VERIFIED_DCGM_EXPORTER_TARGETS; do echo "  - DCGM Exporter: $TARGET (Host: ${HOST_NAMES_MAP[$(echo $TARGET | cut -d: -f1)]:-$(echo $TARGET | cut -d: -f1)})"; done
else
    echo "--- Updating Prometheus Targets File ---"
    if [ ! -f "$TARGETS_FILE" ]; then
        echo "Targets file not found. Creating a new one."
        echo "[]" > "$TARGETS_FILE"
    fi
    EXISTING_TARGETS=$(jq -r '.[].targets[]' "$TARGETS_FILE")
    UPDATED_JSON=$(cat "$TARGETS_FILE")

    add_target() {
        local target_address=$1
        local job_name=$2
        local ip=$(echo "$target_address" | cut -d: -f1)
        
        if ! echo "$EXISTING_TARGETS" | grep -q "^$target_address$"; then
            local hostname=${HOST_NAMES_MAP[$ip]:-$ip}
            local server_name_label=""

            if [ "$hostname" != "$ip" ]; then
                server_name_label="$hostname ($ip)"
            else
                server_name_label="$ip"
            fi
            
            echo "Adding new target for $job_name: $target_address (Name: $server_name_label)"
            UPDATED_JSON=$(echo "$UPDATED_JSON" | jq \
                --arg t "$target_address" \
                --arg j "$job_name" \
                --arg s "$server_name_label" \
                '. += [{"targets": [$t], "labels": {"job": $j, "servername": $s}}]')
        else
            echo "Target $target_address already exists. Skipping."
        fi
    }

    for TARGET in $VERIFIED_NODE_EXPORTER_TARGETS; do add_target "$TARGET" "node-exporter-remote"; done
    for TARGET in $VERIFIED_CADVISOR_TARGETS; do add_target "$TARGET" "cadvisor-remote"; done
    for TARGET in $VERIFIED_DCGM_EXPORTER_TARGETS; do add_target "$TARGET" "dcgm-exporter-remote"; done

    echo "Updating Prometheus targets file at $TARGETS_FILE..."
    echo "$UPDATED_JSON" | jq '.' > "$TARGETS_FILE"
fi

echo ""
echo "Discovery and update complete."
