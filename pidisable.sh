#!/bin/bash

# Files to store Pi-hole addresses and the encrypted/plain API key
PIHOLE_ADDRESSES_FILE="./.pihole.addresses"
API_KEY_FILE="./.piholeapi.key"

# Function to setup Pi-hole addresses and API key
setup_pihole() {
    echo "Setting up Pi-hole configuration."

    read -p "Enter primary Pi-hole address: " primary_address
    echo "${primary_address}" > "${PIHOLE_ADDRESSES_FILE}"

    read -p "Do you want to enter a secondary/failover Pi-hole address? (yes/no): " setup_secondary
    if [[ "${setup_secondary}" == "yes" || "${setup_secondary}" == "y" ]]; then
        read -p "Enter secondary Pi-hole address: " secondary_address
        echo "${secondary_address}" >> "${PIHOLE_ADDRESSES_FILE}"
    fi

    read -sp "Enter Pi-hole API Key: " api_key
    echo

    read -p "Do you want to encrypt the API Key? (yes/no): " encrypt_api_key
    if [[ "${encrypt_api_key}" == "yes" || "${encrypt_api_key}" == "y" ]]; then
        echo "${api_key}" | openssl enc -aes-256-cbc -a -salt -out "${API_KEY_FILE}"
    else
        echo "${api_key}" > "${API_KEY_FILE}"
    fi
}

# Function to check if a Pi-hole is reachable
check_pihole_reachable() {
    local address=$1
    if [ -z "${address}" ]; then
        return 1 # Return failure if address is empty
    fi

    if ping -c 3 "${address}" &> /dev/null; then
        echo "Pi-hole ${address} is reachable."
        return 0
    else
        echo "Error: Pi-hole ${address} is not reachable. Check your network connection."
        return 1
    fi
}

# Function to disable or enable Pi-hole
toggle_pihole() {
    local address=$1
    local action=$2
    local seconds=$3
    local pihole_url="http://${address}/admin/api.php"

    case "${action}" in
        disable)
            if ! [[ "$seconds" =~ ^[1-9][0-9]{0,3}$ && "$seconds" -le 3600 ]]; then
                echo "Error: Seconds must be a valid number between 1 and 3600 for 'disable' action."
                exit 1
            fi
            local toggle_url="${pihole_url}?auth=${API_KEY}&disable=${seconds}"
            echo "Pi-hole disabled for ${seconds} seconds."
            ;;
        enable)
            local toggle_url="${pihole_url}?auth=${API_KEY}&enable"
            echo "Pi-hole enabled."
            ;;
        *)
            echo "Invalid action. Use 'disable' or 'enable'."
            exit 1
            ;;
    esac

    local response=$(curl -sw '%{http_code}' -o /dev/null "${toggle_url}")
    if [ "${response}" -ne 200 ]; then
        echo "Error: Failed to communicate with Pi-hole API at ${address}."
        exit 1
    fi
}

# Check if script is run with --setup or -s
if [ "$1" == "--setup" ] || [ "$1" == "-s" ]; then
    setup_pihole
    exit 0
fi

# Validate command line arguments for normal operation
if [ $# -lt 1 ]; then
    echo "Usage: $0 [enable|disable] [seconds]"
    exit 1
fi

# Read API key and decrypt if necessary
if grep -q 'BEGIN OPENSSL' "${API_KEY_FILE}"; then
    API_KEY=$(openssl enc -aes-256-cbc -d -a -in "${API_KEY_FILE}")
else
    API_KEY=$(<"${API_KEY_FILE}")
fi

# Read Pi-hole addresses
PIHOLE_ADDRESSES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    PIHOLE_ADDRESSES+=("$line")
done < "${PIHOLE_ADDRESSES_FILE}"

action=$1
seconds=$2

# Try each Pi-hole address in order until one is reachable
for address in "${PIHOLE_ADDRESSES[@]}"; do
    if check_pihole_reachable "${address}"; then
        # Toggle Pi-hole for the specified time and action
        toggle_pihole "${address}" "${action}" "${seconds}"
        break
    fi
done
