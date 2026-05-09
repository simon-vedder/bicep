#!/bin/bash
set -e

. /etc/os-release

case "$ID" in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    apt-get dist-upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y
    apt-get clean
    ;;
  rhel)
    dnf update -y
    dnf clean all
    ;;
  *)
    echo "Unsupported OS: $ID"
    exit 1
    ;;
esac

echo "Linux updates completed successfully."
