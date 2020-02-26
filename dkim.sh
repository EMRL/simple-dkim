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

# Configuration
#
# The DKIM settings below should work for anyone
DKIM_SELECTOR="sel01"
DKIM_NAME="default"

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
    grep -o '".*"' "/etc/opendkim/keys/${tld}/${DKIM_SELECTOR}.txt" | sed 's/"//g' > /tmp/dkim-${tld}.tmp
    sed -i ':a;N;$!ba;s/[\n \t]//g' "/tmp/dkim-${tld}.tmp"
    DKIM_KEY="$(cat /tmp/dkim-${tld}.tmp)"
}

# Run the script

# Check for exiting key
if [[ -f "/etc/opendkim/keys/${tld}/${DKIM_SELECTOR}.txt" ]]; then
    echo "There appears to be an existing key for ${tld}"
    echo
    create_record
    display_dkim
    exit 0
fi

# Create key
echo "Creating key..."
sudo mkdir "/etc/opendkim/keys/${tld}"
sudo opendkim-genkey -D "/etc/opendkim/keys/${tld}" -d "${tld}" -s ${DKIM_SELECTOR}
sleep 2

# Set permissions
echo "Setting permissions..."
sudo chown -R opendkim:opendkim "/etc/opendkim/keys/${tld}"
sudo chmod 640 "/etc/opendkim/keys/${tld}/${DKIM_SELECTOR}.private"
sudo chmod 644 "/etc/opendkim/keys/${tld}/${DKIM_SELECTOR}.txt"
sleep 2

# Setup tables
echo "Configuring tables..."
sudo echo "${DKIM_SELECTOR}._dkim.${tld} ${tld}:${DKIM_NAME}:/etc/opendkim/keys/${tld}/${DKIM_SELECTOR}.private" >> /etc/opendkim/KeyTable
sudo echo "*@${tld} ${DKIM_SELECTOR}._dkim.${tld}" >> /etc/opendkim/SigningTable
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
