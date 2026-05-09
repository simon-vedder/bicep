#!/bin/bash
set -e

. /etc/os-release

# Microsoft package repo is already configured by install-ama.sh if it ran first.
# Add it here independently to support standalone use.

case "$ID" in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    if [ ! -f /etc/apt/sources.list.d/packages-microsoft-prod.list ] && \
       ! apt-cache show mdatp >/dev/null 2>&1; then
      curl -sL "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" \
        -o /tmp/packages-microsoft-prod.deb
      dpkg -i /tmp/packages-microsoft-prod.deb
      apt-get update -y
      rm /tmp/packages-microsoft-prod.deb
    fi
    apt-get install -y mdatp
    ;;
  rhel)
    MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
    if [ ! -f /etc/yum.repos.d/packages-microsoft-prod.repo ]; then
      curl -sL "https://packages.microsoft.com/config/rhel/${MAJOR}/packages-microsoft-prod.repo" \
        -o /etc/yum.repos.d/packages-microsoft-prod.repo
    fi
    dnf install -y mdatp
    ;;
  *)
    echo "Unsupported OS: $ID"
    exit 1
    ;;
esac

# MDE full onboarding requires an org-specific onboarding package applied post-deployment
# via Defender portal, Intune, or Ansible. This script pre-stages the binary only.
echo "Microsoft Defender for Endpoint binary installed. Onboarding package required post-deployment."
