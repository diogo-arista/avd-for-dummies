#!/usr/bin/env bash
# start-lab.sh — one-command setup for the AVD Codespaces lab.
#
# What it does:
#   1. Checks that ceos:latest is available in Docker
#   2. Deploys the containerlab topology (skips if already running)
#   3. Polls each cEOS node's eAPI until it responds (nodes take ~3 min to boot)
#   4. Runs eos_designs + eos_cli_config_gen to generate EOS configs
#   5. Deploys the generated configs to devices via eAPI
#
# Prerequisites (handled by postCreate.sh):
#   - containerlab installed
#   - ansible + arista.avd collection installed
#
# Only thing you must do manually first:
#   docker import cEOS-lab-4.35.0F.tar.xz ceos:latest

set -euo pipefail

# Always run relative to this script's directory (codespaces/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "==> $*"; }
ok()   { echo "    ✓ $*"; }
fail() { echo ""; echo "ERROR: $*" >&2; exit 1; }

# ── Header ───────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│           AVD Codespaces Lab — Auto-Setup                   │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

# ── 1. Pre-flight: ceos image ─────────────────────────────────────────────────
log "Checking for ceos:latest Docker image..."
if ! docker image inspect ceos:latest &>/dev/null; then
  fail "ceos:latest image not found.

  Import it first (from inside the VS Code terminal):
    docker import cEOS-lab-4.35.0F.tar.xz ceos:latest

  Then re-run this script."
fi
ok "ceos:latest found"

# ── 2. Deploy containerlab topology ──────────────────────────────────────────
echo ""
log "Containerlab topology..."

TOPO="topology.clab.yml"
LAB_NAME="avd-cs"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "clab-${LAB_NAME}-spine1"; then
  ok "Topology '${LAB_NAME}' is already running — skipping deploy"
else
  log "Deploying topology (this creates the cEOS containers)..."
  containerlab deploy -t "$TOPO"
  ok "Topology deployed"
fi

# ── 3. Wait for cEOS nodes to boot and accept eAPI connections ────────────────
echo ""
log "Waiting for cEOS nodes to boot and accept eAPI connections..."
echo "    (cEOS typically takes 2–4 minutes on first boot)"
echo ""

# Node name → management IP mappings
declare -A NODES=(
  [spine1]="172.20.20.11"
  [leaf1]="172.20.20.13"
  [leaf2]="172.20.20.15"
)

wait_for_eapi() {
  local name="$1"
  local ip="$2"
  local timeout=360   # 6 minutes max per node
  local elapsed=0
  local interval=10

  printf "    %-10s " "${name}"

  until curl -sk \
        --connect-timeout 3 \
        --max-time 5 \
        -u ansible:ansible \
        -o /dev/null \
        -w "%{http_code}" \
        "https://${ip}/command-api" 2>/dev/null \
        | grep -q "^200$"
  do
    if [[ $elapsed -ge $timeout ]]; then
      echo ""
      fail "${name} (${ip}) did not respond within ${timeout}s.
  Check node status: containerlab inspect -t ${TOPO}"
    fi
    printf "."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  printf " ready (%ds)\n" "$elapsed"
}

for name in spine1 leaf1 leaf2; do
  wait_for_eapi "$name" "${NODES[$name]}"
done

echo ""
ok "All nodes are up"

# ── 4. Build EOS configurations ───────────────────────────────────────────────
echo ""
log "Building EOS configurations (eos_designs + eos_cli_config_gen)..."
ansible-playbook playbooks/build.yml
ok "Configurations written to intended/configs/"

# ── 5. Deploy configurations to devices ──────────────────────────────────────
echo ""
log "Deploying configurations to devices via eAPI..."
ansible-playbook playbooks/deploy.yml
ok "Configurations deployed"

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│                     Lab is ready!                           │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""
echo "  Device    Management IP    SSH access"
echo "  spine1    172.20.20.11     ssh ansible@172.20.20.11"
echo "  leaf1     172.20.20.13     ssh ansible@172.20.20.13"
echo "  leaf2     172.20.20.15     ssh ansible@172.20.20.15"
echo ""
echo "  Credentials: ansible / ansible"
echo ""
echo "  Next steps:"
echo "    Validate the fabric:   ansible-playbook playbooks/validate.yml"
echo "    Explore configs:       ls intended/configs/"
echo "    Tear down:             containerlab destroy -t topology.clab.yml"
echo ""
