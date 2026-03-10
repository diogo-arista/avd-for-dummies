#!/usr/bin/env bash
# postCreate.sh — runs once after the Codespace container is created.
#
# Why everything is here and not in a Dockerfile:
#   Codespaces restricts network access during the Docker image build phase,
#   so apt-get update, curl, and pip all fail unpredictably in a Dockerfile.
#   postCreate runs after the container is fully up with stable network access.

set -euo pipefail

WORKSPACE="${CODESPACE_VSCODE_FOLDER:-$(pwd)}"
cd "${WORKSPACE}"

echo ""
echo "==> AVD Lab: postCreate setup starting"
echo ""

# ── 1. containerlab ───────────────────────────────────────────────────────────
echo "==> Installing containerlab..."
bash -c "$(curl -sL https://get.containerlab.dev)"

# Allow the vscode user to run containerlab without sudo and activate the
# VS Code extension (which checks for clab_admins and docker group membership).
sudo groupadd -r clab_admins 2>/dev/null || true
sudo usermod -aG clab_admins,docker vscode
echo "    Done."
echo ""

# ── 2. Python packages ────────────────────────────────────────────────────────
echo "==> Installing Python packages..."
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
echo "    Done."
echo ""

# ── 3. Ansible Galaxy collections ────────────────────────────────────────────
echo "==> Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r requirements.yml --force-with-deps
echo "    Done."
echo ""

# ── 4. Output directories + script permissions ────────────────────────────────
echo "==> Creating output directories..."
for lab in "." "codespaces"; do
    mkdir -p "${lab}/intended/configs"
    mkdir -p "${lab}/intended/structured_configs"
    mkdir -p "${lab}/documentation"
    mkdir -p "${lab}/reports"
    mkdir -p "${lab}/logs"
done
chmod +x codespaces/start-lab.sh
echo "    Done."
echo ""

# ── 5. Verify key tools ───────────────────────────────────────────────────────
echo "==> Tool versions:"
python3 --version                      2>/dev/null || echo "    python3      : NOT FOUND"
ansible --version | head -1            2>/dev/null || echo "    ansible      : NOT FOUND"
containerlab version 2>/dev/null | head -1         || echo "    containerlab : NOT FOUND"
echo ""

# ── 5. Ready ──────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Environment ready! One manual step before starting:"
echo ""
echo "  Import the cEOS image (requires an Arista account to download):"
echo "    docker import cEOS-lab-4.35.0F.tar.xz ceos:latest"
echo ""
echo "  Then start the full lab with a single command:"
echo "    codespaces/start-lab.sh"
echo ""
echo "  start-lab.sh will:"
echo "    - Deploy the containerlab topology"
echo "    - Wait for all nodes to boot"
echo "    - Build and deploy AVD configurations automatically"
echo "============================================================"
echo ""
