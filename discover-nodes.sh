#!/bin/bash

# Automatically discovers services, updates a Prometheus targets file,
# and adds discovered hosts as environments in Portainer.

set -e

# --- Default Configuration & Argument Parsing ---
LIST_ONLY_MODE=false
NETWORK_RANGES=()
TARGETS_FILE="prometheus/targets.json"

# --- Portainer Configuration ---
# REQUIRED: Set these variables or export them in your environment.
# The URL should point to your Portainer instance's HTTP port.
PORTAINER_URL="http://localhost:9000"
# Generate an API Key/Access Token from Portainer > User > Account > API Keys
# --- Load Environment Variables from .env file if it exists ---
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  export $(grep -v '^#' .env | xargs)
fi

# --- Script Logic ---

# Correctly parse command-line arguments using a while loop
while (( "$#" )); do
  case $1 in
    -l|--list-only)
      LIST_ONLY_MODE=true
      ;;
    *)
      # Assume any other argument is a network range
      NETWORK_RANGES+=("$1")
      ;;
  esac
  shift # Process the next argument
done


# If no network ranges are provided, auto-detect the local one
if [ ${#NETWORK_RANGES[@]} -eq 0 ]; then
    LOCAL_RANGE=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)
    if [ -z "$LOCAL_RANGE" ]; then
        echo "Error: Could not determine local network range and no subnets were provided."
        echo "Usage: $0 [--list-only] [subnet1] [subnet2] ..."
        echo "Example: $0 192.168.1.0/24 10.0.1.0/24"
        exit 1
    fi
    NETWORK_RANGES+=("$LOCAL_RANGE")
fi

echo "Scanning network(s): ${NETWORK_RANGES[@]}"

# --- Ensure targets.json exists ---
if [ ! -f "$TARGETS_FILE" ]; then
    echo "Targets file not found. Creating a new one."
    echo "[]" > "$TARGETS_FILE"
fi

# --- Discovery & Verification ---
VERIFIED_NODE_EXPORTER_TARGETS=""
VERIFIED_CADVISOR_TARGETS=""
VERIFIED_DCGM_EXPORTER_TARGETS=""

for RANGE in "${NETWORK_RANGES[@]}"; do
    echo ""
    echo "--- Scanning $RANGE ---"
    
    # Scan for all required ports in a single nmap command for efficiency
    POTENTIAL_NODE_EXPORTER_IPS=$(nmap -p 9100,9101 --open "$RANGE" -oG - | awk '/Up$/{print $2}')
    POTENTIAL_CADVISOR_IPS=$(nmap -p 8080,8081 --open "$RANGE" -oG - | awk '/Up$/{print $2}')
    POTENTIAL_DCGM_EXPORTER_IPS=$(nmap -p 9400,9401 --open "$RANGE" -oG - | awk '/Up$/{print $2}')

    echo "Verifying Node Exporter targets in $RANGE..."
    if [ -n "$POTENTIAL_NODE_EXPORTER_IPS" ]; then
        for IP in $POTENTIAL_NODE_EXPORTER_IPS; do
            echo -n "  - Checking $IP ... "
            if curl -s --connect-timeout 2 "http://$IP:9100/metrics" | grep -q "node_exporter_build_info"; then
                echo "OK (on port 9100)"
                VERIFIED_NODE_EXPORTER_TARGETS="$VERIFIED_NODE_EXPORTER_TARGETS $IP:9100"
            elif curl -s --connect-timeout 2 "http://$IP:9101/metrics" | grep -q "node_exporter_build_info"; then
                echo "OK (on fallback port 9101)"
                VERIFIED_NODE_EXPORTER_TARGETS="$VERIFIED_NODE_EXPORTER_TARGETS $IP:9101"
            else
                echo "Failed (No valid Node Exporter found on 9100 or 9101)"
            fi
        done
    else
        echo "  None found."
    fi

    echo "Verifying cAdvisor targets in $RANGE..."
    if [ -n "$POTENTIAL_CADVISOR_IPS" ]; then
        for IP in $POTENTIAL_CADVISOR_IPS; do
            echo -n "  - Checking $IP ... "
            if curl -s --connect-timeout 2 "http://$IP:8080/metrics" | grep -q "cadvisor_version_info"; then
                echo "OK (on port 8080)"
                VERIFIED_CADVISOR_TARGETS="$VERIFIED_CADVISOR_TARGETS $IP:8080"
            elif curl -s --connect-timeout 2 "http://$IP:8081/metrics" | grep -q "cadvisor_version_info"; then
                echo "OK (on fallback port 8081)"
                VERIFIED_CADVISOR_TARGETS="$VERIFIED_CADVISOR_TARGETS $IP:8081"
            else
                echo "Failed (No valid cAdvisor found on 8080 or 8081)"
            fi
        done
    else
        echo "  None found."
    fi

    echo "Verifying DCGM Exporter targets in $RANGE..."
    if [ -n "$POTENTIAL_DCGM_EXPORTER_IPS" ]; then
        for IP in $POTENTIAL_DCGM_EXPORTER_IPS; do
            echo -n "  - Checking $IP ... "
            if curl -s --connect-timeout 2 "http://$IP:9400/metrics" | grep -q "DCGM_FI_DRIVER_VERSION"; then
                echo "OK (on port 9400)"
                VERIFIED_DCGM_EXPORTER_TARGETS="$VERIFIED_DCGM_EXPORTER_TARGETS $IP:9400"
            elif curl -s --connect-timeout 2 "http://$IP:9401/metrics" | grep -q "DCGM_FI_DRIVER_VERSION"; then
                echo "OK (on port 9401)"
                VERIFIED_DCGM_EXPORTER_TARGETS="$VERIFIED_DCGM_EXPORTER_TARGETS $IP:9401"
            else
                echo "Failed (No valid DCGM Exporter found on 9400 or 9401)"
            fi
        done
    else
        echo "  None found."
    fi
done
echo ""

# --- Prometheus File Update ---
if [ "$LIST_ONLY_MODE" = true ]; then
    echo "List-only mode enabled. Prometheus targets file will not be updated."
else
    # Read the existing targets from the file
    EXISTING_TARGETS=$(jq -r '.[].targets[]' "$TARGETS_FILE")
    UPDATED_JSON=$(cat "$TARGETS_FILE")

    # Add new node-exporter targets if they don't already exist
    for TARGET in $VERIFIED_NODE_EXPORTER_TARGETS; do
        if ! echo "$EXISTING_TARGETS" | grep -q "^$TARGET$"; then
            echo "Adding new Node Exporter target: $TARGET"
            UPDATED_JSON=$(echo "$UPDATED_JSON" | jq --arg t "$TARGET" '. += [{"targets": [$t], "labels": {"env": "production", "job": "node-exporter-remote"}}]')
        else
            echo "Node Exporter target $TARGET already exists. Skipping."
        fi
    done

    # Add new cadvisor targets if they don't already exist
    for TARGET in $VERIFIED_CADVISOR_TARGETS; do
        if ! echo "$EXISTING_TARGETS" | grep -q "^$TARGET$"; then
            echo "Adding new cAdvisor target: $TARGET"
            UPDATED_JSON=$(echo "$UPDATED_JSON" | jq --arg t "$TARGET" '. += [{"targets": [$t], "labels": {"env": "production", "job": "cadvisor-remote"}}]')
        else
            echo "cAdvisor target $TARGET already exists. Skipping."
        fi
    done

    # Add new dcgm-exporter targets if they don't already exist
    for TARGET in $VERIFIED_DCGM_EXPORTER_TARGETS; do
        if ! echo "$EXISTING_TARGETS" | grep -q "^$TARGET$"; then
            echo "Adding new DCGM Exporter target: $TARGET"
            UPDATED_JSON=$(echo "$UPDATED_JSON" | jq --arg t "$TARGET" '. += [{"targets": [$t], "labels": {"env": "production", "job": "dcgm-exporter-remote"}}]')
        else
            echo "DCGM Exporter target $TARGET already exists. Skipping."
        fi
    done

    echo "Updating Prometheus targets file at $TARGETS_FILE..."
    echo "$UPDATED_JSON" | jq '.' > "$TARGETS_FILE"
fi


# --- Portainer Environment Update ---
# This section runs only if not in list-only mode and if an API key is provided.
if [ "$LIST_ONLY_MODE" = false ] && [ -n "$PORTAINER_API_KEY" ]; then
    echo ""
    echo "--- Updating Portainer Environments ---"

    # Combine all verified targets and extract unique IPs
    ALL_VERIFIED_TARGETS="$VERIFIED_NODE_EXPORTER_TARGETS $VERIFIED_CADVISOR_TARGETS $VERIFIED_DCGM_EXPORTER_TARGETS"
    UNIQUE_IPS=$(echo "$ALL_VERIFIED_TARGETS" | tr ' ' '\n' | sed 's/:.*//' | sort -u)

    if [ -z "$UNIQUE_IPS" ]; then
        echo "No new hosts discovered to add to Portainer."
    else
        # 1. Get existing environments from Portainer to prevent duplicates
        echo "Fetching existing Portainer environments..."
        EXISTING_ENDPOINTS=$(curl -s -k -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/endpoints")
        EXISTING_URLS=$(echo "$EXISTING_ENDPOINTS" | jq -r '.[].URL')

        # 2. Loop through discovered IPs and add them if they are new
        for IP in $UNIQUE_IPS; do
            # The Portainer Agent listens on port 9002 in your setup.
            ENDPOINT_URL="tcp://$IP:9002"
            # Sanitize the name by replacing dots with hyphens
            ENDPOINT_NAME="$IP"

            if ! echo "$EXISTING_URLS" | grep -qF "$ENDPOINT_URL"; then
                echo "Adding new Portainer environment: $ENDPOINT_NAME at $ENDPOINT_URL"
                
                # Build the form data string with the correct parameters
                FORM_DATA="Name=${ENDPOINT_NAME}&URL=${ENDPOINT_URL}&EndpointCreationType=2&GroupID=1&TLS=true&TLSSkipVerify=true&TLSSkipClientVerify=true"

                # POST the new environment to the Portainer API
                ADD_RESULT=$(curl -s -k -w "%{http_code}" -X POST \
                  -H "X-API-Key: $PORTAINER_API_KEY" \
                  -H "Content-Type: application/x-www-form-urlencoded" \
                  --data "$FORM_DATA" \
                  "$PORTAINER_URL/api/endpoints")
                
                HTTP_CODE=${ADD_RESULT: -3}
                if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
                    echo "  Successfully added $ENDPOINT_NAME."
                else
                    echo "  Error adding $ENDPOINT_NAME. Portainer API returned HTTP $HTTP_CODE."
                    # For debugging, you can uncomment the following lines:
                    # RESPONSE_BODY=${ADD_RESULT::${#ADD_RESULT}-3}
                    # echo "  Response: $RESPONSE_BODY"
                fi
            else
                echo "Portainer environment for $ENDPOINT_URL already exists. Skipping."
            fi
        done
    fi
elif [ "$LIST_ONLY_MODE" = true ]; then
    echo "List-only mode enabled. Portainer environments will not be updated."
else # API key is missing
    echo "Skipping Portainer update because PORTAINER_API_KEY is not set."
fi


echo ""
echo "Discovery and update complete."
