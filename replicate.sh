#!/usr/bin/env bash
# Exit immediately if a command fails, treat unset vars as errors, and print each command
set -euo pipefail

# ───────────────────────────────
# Environment configuration
# ───────────────────────────────
export SUBSCRIPTION_ID=0660fddc-d191-4bad-b922-e69492903e0a
export RESOURCE_GROUP_NAME=packer
export SIG_GALLERY_NAME=akse2esig
export SIG_IMAGE_NAME=aks-ubuntu-containerd-22.04-gen2
export CAPTURED_SIG_VERSION=1.0.1   # from settings.json
export PACKER_BUILD_LOCATION=eastus
export REPLICATIONS="westus2=1"
export DRY_RUN='false'
./vhdbuilder/packer/replicate-captured-sig-image-version.sh
