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
    # Exclude RHUI client packages — updating them mid-transaction causes
    # cache file not-found errors as Azure rotates the repo metadata.
    dnf update --exclude='rhui-*' -y
    dnf clean all
    ;;
  *)
    echo "Unsupported OS: $ID"
    exit 1
    ;;
esac

echo "Linux updates completed successfully."
