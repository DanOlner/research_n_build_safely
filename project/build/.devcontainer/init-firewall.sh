#!/bin/bash
# Based on anthropics/claude-code .devcontainer/init-firewall.sh. Changes from the reference:
#   - the allowlist is the Anthropic API plus the domains in allowed-domains.txt; GitHub, npm,
#     Sentry, Statsig and the VS Code hosts are not included by default
#   - no outbound SSH (port 22) to arbitrary hosts
#   - no outbound connections to the Docker host network; inbound from the host is still accepted
#   - IPv6 is dropped entirely, so enabling IPv6 on the Docker network can't bypass these rules
#   - addresses shared between domains are added once, and each lookup is tried three times, so
#     neither stops the container starting
# Outbound DNS is unchanged: Docker's resolver needs it, and DNS queries can still carry data out.
# Closing that needs a filtering DNS resolver, which this script doesn't provide.
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Allowed domains: the Anthropic API, plus any listed in the root-owned domain file, which is
# copied from .devcontainer/allowed-domains.txt when the image is built.
DOMAINS_FILE=/usr/local/etc/allowed-domains.txt
domains=("api.anthropic.com")
if [ -f "$DOMAINS_FILE" ]; then
    while read -r line; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [ -z "$line" ] && continue
        if [[ ! "$line" =~ ^[A-Za-z0-9.-]+$ ]]; then
            echo "ERROR: Invalid domain in $DOMAINS_FILE: $line"
            exit 1
        fi
        domains+=("$line")
    done < "$DOMAINS_FILE"
fi

for domain in "${domains[@]}"; do
    echo "Resolving $domain..."
    ips=""
    for attempt in 1 2 3; do
        ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}') || true
        [ -n "$ips" ] && break
        [ "$attempt" -lt 3 ] && { echo "No answer for $domain, retrying..."; sleep 2; }
    done
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi
    
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add -exist allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules. Replies to host-initiated connections leave through the
# ESTABLISHED rule below, so no outbound rule for the host network is needed.
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT

# Drop all IPv6 except loopback
if ip6tables -L >/dev/null 2>&1; then
    ip6tables -F
    ip6tables -X
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
fi

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# GitHub is not on the allowlist: commits and pushes happen on the host
if curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://api.github.com as expected"
fi

# Verify Anthropic API access
if ! curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.anthropic.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.anthropic.com as expected"
fi
