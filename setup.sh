#!/usr/bin/env bash
# setup.sh — One-shot environment setup for the AVD lab
# Run once after cloning the repository.
# Usage: bash setup.sh

set -euo pipefail

VENV_DIR="${HOME}/avd-lab/venv"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> AVD Lab Setup"
echo "    Lab directory : ${LAB_DIR}"
echo "    Venv directory: ${VENV_DIR}"
echo ""

# ── 1. Check prerequisites ────────────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found. Install Python 3.10+."; exit 1; }
command -v docker  >/dev/null 2>&1 || { echo "ERROR: docker not found. Install Docker."; exit 1; }
command -v containerlab >/dev/null 2>&1 || {
  echo "==> containerlab not found. Installing..."
  bash -c "$(curl -sL https://get.containerlab.dev)"
}

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "==> Python version: ${PYTHON_VERSION}"

# ── 2. Create virtual environment ─────────────────────────────────────────────
if [ ! -d "${VENV_DIR}" ]; then
  echo "==> Creating virtual environment at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
else
  echo "==> Virtual environment already exists at ${VENV_DIR}"
fi

# Activate
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

# ── 3. Install Python packages ────────────────────────────────────────────────
echo "==> Installing Python packages"
pip install --upgrade pip --quiet
pip install -r "${LAB_DIR}/requirements.txt" --quiet

# ── 4. Install Ansible collections ───────────────────────────────────────────
echo "==> Installing Ansible Galaxy collections"
ansible-galaxy collection install -r "${LAB_DIR}/requirements.yml"

# ── 5. Create output directories ──────────────────────────────────────────────
echo "==> Creating output directories"
mkdir -p "${LAB_DIR}/intended/configs"
mkdir -p "${LAB_DIR}/intended/structured_configs"
mkdir -p "${LAB_DIR}/documentation"
mkdir -p "${LAB_DIR}/reports"
mkdir -p "${LAB_DIR}/logs"

# ── 6. Check cEOS image ───────────────────────────────────────────────────────
echo ""
if docker images | grep -q "ceos"; then
  echo "==> cEOS image found:"
  docker images | grep "ceos"
else
  echo "WARNING: No ceos image found in Docker."
  echo ""
  echo "  1. Download cEOS-lab from https://www.arista.com (free account required)"
  echo "  2. Import it: docker import cEOS-lab-4.35.0F.tar.xz ceos:latest"
  echo ""
fi

# ── 7. Create output directories for codespaces lab too ──────────────────────
mkdir -p "${LAB_DIR}/codespaces/intended/configs"
mkdir -p "${LAB_DIR}/codespaces/intended/structured_configs"
mkdir -p "${LAB_DIR}/codespaces/documentation"
mkdir -p "${LAB_DIR}/codespaces/reports"
mkdir -p "${LAB_DIR}/codespaces/logs"

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps — full lab (16 GB+ RAM):"
echo "  1. source ${VENV_DIR}/bin/activate"
echo "  2. cd ${LAB_DIR}"
echo "  3. sudo containerlab deploy -t containerlab/topology.clab.yml"
echo "  4. ansible-playbook playbooks/build.yml"
echo "  5. ansible-playbook playbooks/deploy.yml"
echo ""
echo "Next steps — Codespaces / lightweight lab (4 cores, 16 GB RAM):"
echo "  1. source ${VENV_DIR}/bin/activate"
echo "  2. cd ${LAB_DIR}/codespaces"
echo "  3. sudo containerlab deploy -t topology.clab.yml"
echo "  4. ansible-playbook playbooks/build.yml"
echo "  5. ansible-playbook playbooks/deploy.yml"
