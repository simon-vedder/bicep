#!/bin/bash
set -e

. /etc/os-release

case "$ID" in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    curl -sL "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" \
      -o /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb
    apt-get update -y
    apt-get install -y azuremonitoragent
    rm /tmp/packages-microsoft-prod.deb
    ;;
  rhel)
    MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
    curl -sL "https://packages.microsoft.com/config/rhel/${MAJOR}/packages-microsoft-prod.repo" \
      -o /etc/yum.repos.d/packages-microsoft-prod.repo
    dnf install -y azuremonitoragent
    ;;
  *)
    echo "Unsupported OS: $ID"
    exit 1
    ;;
esac

systemctl enable azuremonitoragent || true

echo "Azure Monitor Agent installed successfully."
