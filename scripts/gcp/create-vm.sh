#!/usr/bin/env bash
# Create a GCP Compute Engine VM for running the OpenClaw Gateway.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - A GCP project with billing enabled
#   - Compute Engine API enabled (gcloud services enable compute.googleapis.com)
#
# Usage:
#   ./scripts/gcp/create-vm.sh
#
# Override defaults via environment variables:
#   GCP_PROJECT=my-project GCP_ZONE=europe-west1-b ./scripts/gcp/create-vm.sh

set -euo pipefail

# --- Configuration (override via env) ---
VM_NAME="${GCP_VM_NAME:-openclaw-server}"
ZONE="${GCP_ZONE:-us-central1-a}"
MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-medium}"
BOOT_DISK_SIZE="${GCP_BOOT_DISK_SIZE:-30GB}"
IMAGE_FAMILY="ubuntu-2404-lts-amd64"
IMAGE_PROJECT="ubuntu-os-cloud"
PROJECT="${GCP_PROJECT:-}"

# --- Preflight checks ---
if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud CLI not found. Install from https://cloud.google.com/sdk/docs/install" >&2
  exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  echo "Error: No active gcloud account. Run: gcloud auth login" >&2
  exit 1
fi

PROJECT_ARGS=()
if [[ -n "$PROJECT" ]]; then
  PROJECT_ARGS=(--project "$PROJECT")
fi

ACTIVE_PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
if [[ -z "$ACTIVE_PROJECT" ]]; then
  echo "Error: No GCP project set. Run: gcloud config set project <PROJECT_ID>" >&2
  echo "  or pass GCP_PROJECT=<PROJECT_ID> to this script." >&2
  exit 1
fi

echo "==> Configuration"
echo "  VM name:       $VM_NAME"
echo "  Zone:          $ZONE"
echo "  Machine type:  $MACHINE_TYPE"
echo "  Boot disk:     $BOOT_DISK_SIZE"
echo "  Image:         $IMAGE_FAMILY ($IMAGE_PROJECT)"
echo "  Project:       $ACTIVE_PROJECT"
echo ""

# --- Check if VM already exists ---
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" "${PROJECT_ARGS[@]}" >/dev/null 2>&1; then
  echo "VM '$VM_NAME' already exists in zone '$ZONE'."
  echo "To SSH into it:"
  echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]}"
  echo ""
  echo "To set it up, copy and run the setup script on the VM:"
  echo "  gcloud compute scp scripts/gcp/setup-vm.sh $VM_NAME:~/setup-vm.sh --zone=$ZONE ${PROJECT_ARGS[*]}"
  echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]} -- bash ~/setup-vm.sh"
  exit 0
fi

# --- Create the VM ---
echo "==> Creating VM '$VM_NAME' in $ZONE..."
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --boot-disk-size="$BOOT_DISK_SIZE" \
  --boot-disk-type=pd-balanced \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --tags=openclaw-gateway \
  --metadata=startup-script='#!/bin/bash
# Minimal startup: ensure Docker is ready on first boot
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl git
  curl -fsSL https://get.docker.com | sh
fi' \
  "${PROJECT_ARGS[@]}"

echo ""
echo "==> VM created successfully."
echo ""
echo "Wait ~60 seconds for the startup script to install Docker, then:"
echo ""
echo "  # SSH into the VM"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]}"
echo ""
echo "  # Or copy and run the full setup script"
echo "  gcloud compute scp scripts/gcp/setup-vm.sh $VM_NAME:~/setup-vm.sh --zone=$ZONE ${PROJECT_ARGS[*]}"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]} -- bash ~/setup-vm.sh"
echo ""
echo "  # Access the gateway from your laptop via SSH tunnel"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]} -- -L 18789:127.0.0.1:18789"
echo "  # Then open http://127.0.0.1:18789/"
echo ""
echo "  # Install skill dependencies (optional, after setup):"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE ${PROJECT_ARGS[*]} -- bash ~/openclaw/scripts/gcp/install-skills.sh"
