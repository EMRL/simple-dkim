#!/usr/bin/env bash

###############################################################################
# dkim.sh
#   A simple script for creating DKIM keys
#
# Arguments:
#   [domain]    The top level domain the key is being made for. Do not include
#               subdomains. Ex. `./dkim.sh emrl.com` 
###############################################################################  

# 
#
# TODO: Add full configuration variables
#       Add environment/dependency checks
#       Add support for system that are not booted used systemd as init system

# Configuration
#
# The DKIM settings below should work for anyone
DKIM_SELECTOR="sel01"
DKIM_NAME="default"
OPENDKIM_FILES="/etc/opendkim"
OPENDKIM_USER="opendkim"
OPENDKIM_GROUP="opendkim"

# No root, no fun
if [[ "${EUID}" -ne 0 ]]; then
  echo "You must have root access to create DKIM keys." 2>&1
  exit 2
fi

if [[ -z "${1}" ]]; then
    echo "Domain parameter required"
    exit 3
else
    tld="${1}"
fi

# Setup functions

function check_env() {
    if [[ ! -w "${OPENDKIM_FILES}" ]]; then
        echo "configured path ${OPENDKIM_FILES} does not exist or is not writable"
        exit 4
    fi

    if [[ ! command -v opendkim-genkey &> /dev/null ]]; then
        echo "Can't find required command 'opendkim-genkey'"
        exit 5
    exit
fi
}

function display_dkim() {
    # Print to screen
    echo
    echo "Your DKIM entry for ${tld}"
    echo "-----"
    echo "Type: TXT"
    echo "Name: ${DKIM_NAME}._domainkey"
    echo "Key:  ${DKIM_KEY}"
}

function create_record() {
    # Create DNS record
    grep -o '".*"' "${OPENDKIM_FILES}/keys/${tld}/${DKIM_SELECTOR}.txt" | sed 's/"//g' > /tmp/dkim-${tld}.tmp
    sed -i ':a;N;$!ba;s/[\n \t]//g' "/tmp/dkim-${tld}.tmp"
    DKIM_KEY="$(cat /tmp/dkim-${tld}.tmp)"
}

# Run the script
check_env

# Check for exiting key
if [[ -f "${OPENDKIM_FILES}/keys/${tld}/${DKIM_SELECTOR}.txt" ]]; then
    echo "There appears to be an existing key for ${tld}"
    echo
    create_record
    display_dkim
    exit 0
fi

# Create key
echo "Creating key..."
sudo mkdir "${OPENDKIM_FILES}/keys/${tld}"
sudo opendkim-genkey -D "${OPENDKIM_FILES}/keys/${tld}" -d "${tld}" -s ${DKIM_SELECTOR}
sleep 2

# Set permissions
echo "Setting permissions..."
sudo chown -R "${OPENDKIM_USER}":"${OPENDKIM_GROUP}" "${OPENDKIM_FILES}/keys/${tld}"
sudo chmod 640 "${OPENDKIM_FILES}/keys/${tld}/${DKIM_SELECTOR}.private"
sudo chmod 644 "${OPENDKIM_FILES}/keys/${tld}/${DKIM_SELECTOR}.txt"
sleep 2

# Setup tables
echo "Configuring tables..."
sudo echo "${DKIM_SELECTOR}._dkim.${tld} ${tld}:${DKIM_NAME}:${OPENDKIM_FILES}/keys/${tld}/${DKIM_SELECTOR}.private" >> ${OPENDKIM_FILES}/KeyTable
sudo echo "*@${tld} ${DKIM_SELECTOR}._dkim.${tld}" >> ${OPENDKIM_FILES}/SigningTable
sleep 2

# Restarting
echo "Restarting services..."
sudo systemctl restart postfix
sudo systemctl restart opendkim

echo "Creating DNS record"
create_record
display_dkim

# Cleanup
rm -f "/tmp/dkim-${tld}.tmp"
echo; exit 0
