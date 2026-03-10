# Codespaces Lab: Lightweight Topology

← [Back to main README](../README.md) | [Full Lab Guide →](full-lab.md)

---

A self-contained lab environment designed to run entirely within **GitHub Codespaces** (4 cores, 16 GB RAM, 32 GB storage) or any machine with limited resources. Everything is in the `codespaces/` directory of the repository.

**What is the same as the full lab:** the AVD workflow (build → deploy → validate), the YAML structure, the same Ansible roles, the same core concepts.

**What is different:** smaller topology (1 spine, 2 standalone leaves, no MLAG) with two Linux hosts so you can test end-to-end connectivity across the VXLAN fabric.

---

## Topology

```
                 ┌─────────────────────────┐
                 │      Management Net      │
                 │     172.20.20.0/24       │
                 └──┬───────┬───────┬───┬──┘
                    │       │       │   │
                 [spine1] [leaf1] [leaf2] ...
                 .11      .13     .15
                              │       │
                           [host1] [host2]
                           .31     .32

Underlay links:
  spine1:eth1 ── leaf1:eth1
  spine1:eth2 ── leaf2:eth1

Host links (access, VLAN 10):
  leaf1:eth3 ── host1:eth1
  leaf2:eth3 ── host2:eth1
```

**Comparison with the full lab:**

| | Full Lab | Codespaces Lab |
|--|----------|---------------|
| Spines | 2 | 1 |
| Leaves | 4 in 2 MLAG pairs | 2 standalone (no MLAG) |
| Hosts | None | 2 Linux hosts for ping tests |
| RAM required | ~12 GB | ~5 GB |
| Config complexity | Higher (MLAG, dual uplinks) | Simpler (single uplinks, no peer-link) |

Because there is no MLAG, `DC1_FABRIC.yml` has one node per `node_group` and no MLAG-related pool variables. Each leaf has its own unique VTEP loopback address.

---

## Setting Up

The dev container (`.devcontainer/`) handles all software installation automatically. The only manual step is importing the cEOS image, which requires an Arista account to download.

### Option A — GitHub Codespaces (recommended)

1. Push the repo to GitHub (or fork it).
2. Click **Code → Codespaces → Create codespace on main**.
3. GitHub builds the dev container image — this takes about 3 minutes on first creation. Subsequent Codespaces reuse the cached image and start in seconds.
4. `postCreate.sh` runs automatically in the background (watch it in the Terminal panel). It installs containerlab, Ansible collections, and creates output directories.
5. Upload the cEOS image. Drag `cEOS-lab-4.35.0F.tar.xz` into the VS Code terminal, or use the Explorer upload option, then import it:
   ```bash
   docker import cEOS-lab-4.35.0F.tar.xz ceos:latest
   ```
6. Verify everything is ready:
   ```bash
   docker images | grep ceos        # should show ceos:latest
   containerlab version             # should print the installed version
   ansible --version                # should print ansible-core 2.15+
   ```

### Option B — macOS with Docker Desktop (local dev container)

See the [Dev Container section in the main README](../README.md#dev-container--environment-setup) for full Docker Desktop configuration instructions.

The key difference from Codespaces: import the cEOS image **from inside the VS Code terminal** (not from a macOS terminal), because the dev container runs its own Docker daemon separate from Docker Desktop.

### Option C — Linux machine (manual setup)

```bash
bash setup.sh
source ~/avd-lab/venv/bin/activate
cd codespaces
```

---

## Starting the Lab

The `codespaces/start-lab.sh` script handles the full lifecycle automatically:

```bash
codespaces/start-lab.sh
```

> Run this from the repo root, or `./start-lab.sh` from inside `codespaces/`.

**What the script does:**

1. Checks that `ceos:latest` is available in Docker (exits early with a clear error if not)
2. Deploys the containerlab topology (skips deploy if containers are already running)
3. Polls each cEOS node's eAPI every 10 seconds until it responds — cEOS typically takes 2–4 minutes to boot and initialise
4. Runs `ansible-playbook playbooks/build.yml` to generate EOS configurations
5. Runs `ansible-playbook playbooks/deploy.yml` to push configurations to devices
6. Prints SSH access details and next steps

Expected output when complete:

```
┌─────────────────────────────────────────────────────────────┐
│                     Lab is ready!                           │
└─────────────────────────────────────────────────────────────┘

  Device    Management IP    SSH access
  spine1    172.20.20.11     ssh ansible@172.20.20.11
  leaf1     172.20.20.13     ssh ansible@172.20.20.13
  leaf2     172.20.20.15     ssh ansible@172.20.20.15

  Credentials: ansible / ansible
```

### Manual steps (if you prefer step-by-step)

If you want to run each step individually instead of using `start-lab.sh`:

```bash
cd codespaces

# 1. Deploy topology
containerlab deploy -t topology.clab.yml

# 2. Wait for nodes to boot (~3 minutes), then verify
containerlab inspect -t topology.clab.yml

# 3. Build AVD configurations
ansible-playbook playbooks/build.yml

# 4. Deploy to devices
ansible-playbook playbooks/deploy.yml
```

> **No sudo required** — `postCreate.sh` adds the `vscode` user to the `clab_admins` and `docker` groups during environment setup.

---

## Exercises

Work through these in order. All Ansible commands run from inside the `codespaces/` directory (or the script handles the `cd` for you).

---

### Exercise CS-1: Explore the Topology

**Goal:** Understand the physical connections before any automation runs.

**Tasks:**

1. SSH into `spine1`:
   ```bash
   ssh admin@172.20.20.11
   ```

2. Run these commands and note that no BGP sessions exist yet — only the management interface is configured (this is the state after `start-lab.sh` deployed the topology but before build/deploy ran):
   ```
   show lldp neighbors
   show ip interface brief
   show bgp summary
   ```
   LLDP should show leaf1 and leaf2 as neighbours. BGP will show no peers.

3. Open `codespaces/topology.clab.yml`. Answer:
   - Which spine interface connects to leaf1?
   - Which spine interface connects to leaf2?
   - Which leaf interface connects to host1?

4. Open `codespaces/inventory/group_vars/DC1_FABRIC.yml`. Compare the `l3leaf` section with the full lab version in `inventory/group_vars/DC1_FABRIC.yml`. What is missing? What is simpler?

**Expected result:** You can reach all three EOS nodes, you understand the topology, and you can explain why the codespaces `DC1_FABRIC.yml` has no MLAG-related settings.

---

### Exercise CS-2: Build Configurations with AVD

**Goal:** Understand what AVD generates from your YAML files.

> If you ran `start-lab.sh`, the build already ran. You can still inspect the output, or change a value and rebuild to see the effect.

**Tasks:**

1. From inside the `codespaces/` directory, run the build:
   ```bash
   ansible-playbook playbooks/build.yml
   ```

2. Inspect the generated files:
   ```bash
   ls intended/configs/
   cat intended/configs/spine1.cfg
   cat intended/configs/leaf1.cfg
   ```

3. Answer these questions by reading the generated configs:
   - What Loopback0 address was assigned to leaf1? To leaf2?
   - What VNI is used for VLAN 10? (hint: `mac_vrf_vni_base + vlan_id`)
   - Find the `interface Vxlan1` section in `leaf1.cfg`. What is the source interface for the VXLAN tunnel?
   - How many BGP peers does spine1 have?

4. Open `intended/structured_configs/leaf1.yml`. This is the intermediate YAML that `eos_designs` produces before Jinja2 renders it into CLI syntax. Find the `bgp_as` field and the `vlans` list.

**Expected result:** Three `.cfg` files in `intended/configs/` and matching documentation in `documentation/`.

---

### Exercise CS-3: Deploy Configurations

**Goal:** Push the generated configurations to the running cEOS containers and verify the fabric comes up.

> If you ran `start-lab.sh`, the deploy already ran. You can still verify the state below, or modify something and redeploy.

**Tasks:**

1. Deploy:
   ```bash
   ansible-playbook playbooks/deploy.yml
   ```

2. SSH into `spine1` and verify the BGP underlay is up:
   ```
   show bgp summary
   show ip route
   ```
   You should see two eBGP peers (one per leaf) in the `Established` state.

3. SSH into `leaf1` and check the EVPN overlay:
   ```
   show bgp evpn summary
   show interface vxlan1
   show vxlan vtep
   ```
   You should see spine1 as the EVPN peer and leaf2's VTEP address in the VTEP table.

4. Check that the tenant VRF and SVIs were created:
   ```
   show vrf
   show ip interface brief vrf PROD
   ```

**Expected result:** eBGP underlay is up between spine1 and both leaves. EVPN overlay is up. VRF PROD and SVIs for VLAN 10 and VLAN 20 are present on both leaves.

---

### Exercise CS-4: Test Host Connectivity

**Goal:** Verify end-to-end data-plane connectivity across the VXLAN fabric using the Linux hosts.

**Tasks:**

1. Open a shell on **host1** by exec-ing into its container:
   ```bash
   docker exec -it clab-avd-cs-host1 bash
   ```

2. Configure host1 with an IP in VLAN 10:
   ```bash
   ip addr add 10.1.10.101/24 dev eth1
   ip route add default via 10.1.10.1
   ```

3. Open a second terminal and do the same for **host2**:
   ```bash
   docker exec -it clab-avd-cs-host2 bash
   ip addr add 10.1.10.102/24 dev eth1
   ip route add default via 10.1.10.1
   ```

4. From host1, ping host2:
   ```bash
   ping 10.1.10.102
   ```
   This traffic travels: host1 → leaf1 (VXLAN encapsulation) → spine1 → leaf2 (VXLAN decapsulation) → host2.

5. From host1, ping the anycast gateway:
   ```bash
   ping 10.1.10.1
   ```

6. On leaf1, check what MAC address was learned for host1:
   ```
   show mac address-table
   show bgp evpn route-type mac-ip
   ```

**Expected result:** Pings succeed between host1 and host2 across the VXLAN fabric.

> **Note:** The host IP configuration is not persistent. If you restart the containers, re-apply the `ip addr` and `ip route` commands.

---

### Exercise CS-5: Add a New VLAN

**Goal:** Practice the day-2 AVD workflow — a change via YAML only, no CLI.

**Scenario:** A new team needs a `Dev-Servers` network isolated from the production VRF.

**Tasks:**

1. Open `codespaces/inventory/group_vars/DC1_TENANTS_NETWORKS.yml`.

2. Add a new VRF after the `PROD` VRF:
   ```yaml
   - name: DEV
     vrf_vni: 2
     vtep_diagnostic:
       loopback: 101
       loopback_ip_range: 10.255.2.0/24
     svis:
       - id: 100
         name: Dev-Servers
         tags: [prod]
         enabled: true
         ip_address_virtual: 10.2.100.1/24
   ```

   > Note: the tag is `prod` here because the leaf filter uses `tags: [prod]`. The tag controls which leaves carry the network, not which VRF it belongs to.

3. Rebuild and redeploy:
   ```bash
   ansible-playbook playbooks/build.yml
   ansible-playbook playbooks/deploy.yml
   ```

4. Verify on leaf1:
   ```
   show vrf
   show vlan 100
   show interface vlan100
   ```

5. Compare the new `intended/configs/leaf1.cfg` against the previous version with `git diff intended/`. Which lines were added?

**Expected result:** VRF DEV and SVI `10.2.100.1/24` appear on both leaves.

---

### Exercise CS-6: Validate the Network State

**Goal:** Use AVD's validation role to confirm the fabric matches its intended state, and see what failure looks like.

**Tasks:**

1. Run the validation:
   ```bash
   ansible-playbook playbooks/validate.yml
   ```

2. Read the report in `reports/`.

3. **Introduce a fault:** SSH into `spine1` and shut down the interface towards `leaf1`:
   ```
   configure
   interface Ethernet1
     shutdown
   end
   ```

4. Run the validation again:
   ```bash
   ansible-playbook playbooks/validate.yml
   ```
   Observe which checks fail: the BGP session from spine1 to leaf1 will be down, and any EVPN routes that depend on leaf1's VTEP will be missing.

5. From host2, try to ping host1 while the interface is down:
   ```bash
   ping 10.1.10.101
   ```

6. Restore the interface and re-validate:
   ```
   configure
   interface Ethernet1
     no shutdown
   end
   ```

**Expected result:** You can observe validation failures caused by a real network fault, and watch the validation pass again after recovery.

---

## Tear Down

```bash
cd codespaces
containerlab destroy -t topology.clab.yml
```

---

## Troubleshooting

### `start-lab.sh` exits with "ceos:latest image not found"

Import the image from inside the VS Code terminal (not from a macOS terminal if using Docker Desktop):
```bash
docker import cEOS-lab-4.35.0F.tar.xz ceos:latest
docker images | grep ceos
```

### Nodes never become ready (script dots forever)

- Check that Docker has enough memory (at least 8 GB allocated in Docker Desktop → Resources)
- Inspect container status: `containerlab inspect -t topology.clab.yml`
- Check container logs: `docker logs clab-avd-cs-spine1`

### Ansible can't connect after deploy

- Verify the management IP responds: `ping 172.20.20.11`
- Confirm eAPI is up on the device: `curl -sk -u ansible:ansible https://172.20.20.11/command-api`
- Check that the startup-config was applied correctly: `ssh admin@172.20.20.11` and run `show management api http-commands`

### AVD build fails with schema errors

- Read the error message carefully — AVD gives specific field names
- Check that YAML indentation is correct (spaces, not tabs)
- Validate the YAML: `python3 -c "import yaml; yaml.safe_load(open('codespaces/inventory/group_vars/DC1_FABRIC.yml'))"`

### containerlab extension not working (permissions error)

The dev container pre-configures group membership. If the extension still complains after the container builds:
1. Open the Command Palette → **Developer: Reload Window**
2. If that doesn't help, rebuild the container: **Dev Containers: Rebuild Container**
