# Network Automation with Arista AVD: A Hands-On Lab Guide for Beginners

## Introduction

This guide is designed for network engineers who are new to network automation. You will learn how to use **Arista Validated Designs (AVD)** to automate the configuration of a data center fabric — without needing years of programming experience.

By the end of this guide, you will:
- Understand what AVD is and why it exists
- Have a working virtual lab using containerlab and cEOS
- Know how to describe your network in YAML and generate device configurations automatically
- Be able to push those configurations to devices using Ansible

---

## Part 1: Fundamentals

### 1.1 Why Network Automation?

Traditional network management means SSH-ing into every device and typing commands manually. This approach has several problems:

- **It does not scale.** Configuring 50 switches by hand takes days.
- **It is error-prone.** One typo can break the network.
- **It is not auditable.** There is no reliable record of what changed and why.

Automation treats network configuration as **code**: version-controlled, reviewable, repeatable, and testable.

### 1.2 Key Concepts

Before diving in, let's clarify a few terms:

| Term | What it means |
|------|--------------|
| **Ansible** | An automation tool that connects to devices and applies configurations. It reads instructions from files called *playbooks*. |
| **Playbook** | A YAML file that tells Ansible what to do and on which devices. |
| **Inventory** | A file (or folder of files) that lists your devices and groups them. |
| **Role** | A reusable package of Ansible tasks. AVD is delivered as a collection of roles. |
| **AVD** | Arista Validated Designs — an open-source Ansible collection that knows how to build full data center fabrics. |
| **cEOS** | Arista's containerized version of EOS (their network OS), which runs as a Docker container. |
| **containerlab** | A tool to build virtual network labs by connecting containers together. |

### 1.3 What is AVD?

AVD (`arista.avd`) is an Ansible collection maintained by Arista. It provides:

1. **Data models** — a structured, human-readable YAML schema for describing a network.
2. **Roles** — Ansible roles that take your YAML description and generate complete EOS configurations.
3. **Validated designs** — proven architectures like EVPN VXLAN, Campus, and WAN.

The core workflow is:

```
Your YAML description
        │
        ▼
   AVD roles (build)
        │
        ▼
 EOS configs + docs
        │
        ▼
  AVD roles (deploy)
        │
        ▼
    Live devices
```

You describe **what** the network should look like. AVD figures out **how** to configure it.

### 1.4 Lab Architecture

The lab you will build looks like this:

```
                        ┌─────────────────────────┐
                        │      Management Net      │
                        │     172.20.20.0/24       │
                        └─┬─────┬─────┬─────┬─────┘
                          │     │     │     │
                     ┌────┘  ┌──┘  ┌──┘  ┌──┘
                     │       │     │     │
                  [spine1] [spine2]│     │
                     │   \ / |     │     │
                     │    X  |     │     │
                     │   / \ |     │     │
                  [leaf1] [leaf2] [leaf3] [leaf4]
                     │       │     │       │
                  (host1) (host2) (host3) (host4)
```

**Fabric type:** EVPN VXLAN Layer 3 Leaf-Spine
**Underlay:** eBGP
**Overlay:** iBGP EVPN

This is the most common data center design and the one AVD handles best.

---

## Part 2: Setting Up the Lab Environment

### 2.1 Prerequisites

#### Hardware / VM requirements

You need a Linux or macOS machine (or a Linux VM) with:
- At least **8 GB RAM** (16 GB recommended)
- **20 GB free disk space**
- Internet access to pull images and packages

> **Note for macOS users:** containerlab requires a Linux kernel. You need Docker Desktop with a Linux VM backend, or you can use a Lima/Multipass VM. The cEOS image works fine.

#### Install system packages (Linux)

On a fresh Linux install (Ubuntu/Debian), several tools are not present by default. Install everything you need before proceeding:

```bash
sudo apt-get update
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    ssh
```

> **Note:** On Ubuntu 22.04 and later the `python3-venv` package is separate from `python3`. If you skip it, the `python3 -m venv` command will fail with *"ensurepip is not available"*. Always install it explicitly.

If you need a specific Python version (3.11 is a safe choice):

```bash
sudo apt-get install -y python3.11 python3.11-venv python3.11-pip
```

Then use `python3.11` instead of `python3` in all subsequent commands.

On **RHEL / Rocky / AlmaLinux**:

```bash
sudo dnf install -y python3 python3-pip curl git openssh-clients
# venv is included in the python3 package on RHEL-based systems
```

#### Install Docker

containerlab uses Docker to run cEOS containers. Install it using the official convenience script:

```bash
curl -fsSL https://get.docker.com | sudo sh
```

Add your user to the `docker` group so you can run Docker commands without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker          # Apply group change in the current shell
docker info            # Verify Docker is running
```

> If `docker info` returns a permission error, log out and back in for the group change to take full effect.

#### Verify all system prerequisites

Run these checks before moving on. All four must succeed:

```bash
python3 --version        # Should print Python 3.10 or newer
python3 -m venv --help   # Should print venv usage (not an error)
docker info              # Should print Docker system info
curl --version           # Should print curl version
```

### 2.2 Install Dependencies

#### Step 1 — Install containerlab

```bash
# Linux (and macOS via the install script)
bash -c "$(curl -sL https://get.containerlab.dev)"

# Verify
containerlab version
```

#### Step 2 — Obtain the cEOS image

Arista cEOS images require a free account at [arista.com](https://www.arista.com).

1. Go to **Software Downloads → EOS → cEOS-lab**
2. Download `cEOS-lab-4.32.0F.tar.xz` (or the latest 4.32.x release)
3. Import it into Docker:

```bash
docker import cEOS-lab-4.32.0F.tar.xz arista/ceos:4.32.0F
```

4. Verify:

```bash
docker images | grep ceos
```

#### Step 3 — Create a Python virtual environment

```bash
python3 -m venv ~/avd-lab/venv
source ~/avd-lab/venv/bin/activate
```

#### Step 4 — Install Ansible and AVD

```bash
pip install "ansible-core>=2.15,<2.17"
ansible-galaxy collection install arista.avd
pip install "pyavd[ansible]"
```

Verify the installation:

```bash
ansible-galaxy collection list | grep avd
```

#### Step 5 — Clone this lab repository

```bash
git clone <this-repo> ~/avd-lab/lab
cd ~/avd-lab/lab
```

Or create the directory structure manually:

```
avd-lab/
├── containerlab/
│   └── topology.yml
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       ├── DC1.yml
│       ├── DC1_FABRIC.yml
│       ├── DC1_SPINES.yml
│       ├── DC1_L3LEAVES.yml
│       └── DC1_TENANTS_NETWORKS.yml
├── playbooks/
│   ├── build.yml
│   ├── deploy.yml
│   └── validate.yml
├── ansible.cfg
└── requirements.txt
```

---

### 2.3 Start the Lab

#### Step 1 — Deploy the containerlab topology

```bash
cd ~/avd-lab/lab/containerlab
sudo containerlab deploy -t topology.yml
```

This will pull the cEOS image and start the containers. The first run may take a few minutes.

Verify that all nodes are running:

```bash
sudo containerlab inspect -t topology.yml
```

You should see output like:

```
+---+------------------+--------------+------------------------+---------+
| # |       Name       | Container ID |          Image         |  State  |
+---+------------------+--------------+------------------------+---------+
| 1 | clab-avd-spine1  | a1b2c3d4e5f6 | arista/ceos:4.32.0F    | running |
| 2 | clab-avd-spine2  | b2c3d4e5f6a1 | arista/ceos:4.32.0F    | running |
| 3 | clab-avd-leaf1   | c3d4e5f6a1b2 | arista/ceos:4.32.0F    | running |
| 4 | clab-avd-leaf2   | d4e5f6a1b2c3 | arista/ceos:4.32.0F    | running |
| 5 | clab-avd-leaf3   | e5f6a1b2c3d4 | arista/ceos:4.32.0F    | running |
| 6 | clab-avd-leaf4   | f6a1b2c3d4e5 | arista/ceos:4.32.0F    | running |
+---+------------------+--------------+------------------------+---------+
```

#### Step 2 — Verify connectivity to the devices

```bash
# SSH to spine1 (password: admin)
ssh admin@172.20.20.11
```

Once logged in, you should see the EOS CLI:

```
spine1>show version
```

Type `exit` to return to your shell.

---

## Part 3: Understanding the Configuration Files

Before running AVD, you need to understand what each file does and why it is structured the way it is. This section walks through every file in detail. Do not skip it — the exercises will make much more sense once you understand the intent behind each key.

---

### 3.1 The Inventory (`inventory/hosts.yml`)

The inventory answers one question: **what devices exist and how are they grouped?**

```yaml
all:
  children:
    DC1:
      children:
        DC1_FABRIC:
          children:
            DC1_SPINES:
              hosts:
                spine1:
                  ansible_host: 172.20.20.11
                spine2:
                  ansible_host: 172.20.20.12
            DC1_L3LEAVES:
              children:
                DC1_LEAF1_2:
                  hosts:
                    leaf1:
                      ansible_host: 172.20.20.13
                    leaf2:
                      ansible_host: 172.20.20.14
                DC1_LEAF3_4:
                  hosts:
                    leaf3:
                      ansible_host: 172.20.20.15
                    leaf4:
                      ansible_host: 172.20.20.16
        DC1_FABRIC_VALIDATION:
          children:
            DC1_SPINES:
            DC1_L3LEAVES:
```

The nesting is not just for organization — it has functional meaning at every level:

- **`all`** is the root group. Every device belongs to it implicitly.
- **`DC1`** is a site-level group. If you had a second data center, `DC2` would sit here as a sibling. Variables in `group_vars/DC1.yml` apply to every device under `DC1`.
- **`DC1_FABRIC`** is the group that AVD's `eos_designs` role specifically looks for. The role is designed to read node definitions (`spine:`, `l3leaf:`) from whichever group is passed via `hosts:` in the playbook. That is why `build.yml` says `hosts: DC1_FABRIC`.
- **`DC1_SPINES`** and **`DC1_L3LEAVES`** tell AVD which nodes are spines and which are leaves. These group names are not arbitrary — AVD uses them to apply the correct design templates and BGP roles.
- **`DC1_LEAF1_2`** and **`DC1_LEAF3_4`** are MLAG peer groups. AVD infers that two leaves in the same sub-group form an MLAG pair, and generates the peer-link and MLAG domain configuration automatically.
- **`DC1_FABRIC_VALIDATION`** is a separate group used only by the validate playbook. It contains the same devices as `DC1_FABRIC` but exists so validation can be run independently without touching the build/deploy group structure.

`ansible_host` is the actual IP Ansible dials. The hostname (`spine1`) is a label used consistently across all YAML files to refer to that device.

#### How Ansible loads variables from groups

Ansible automatically loads `group_vars/<groupname>.yml` for every group a host belongs to. Because of the nesting, `spine1` belongs to all of: `DC1_SPINES`, `DC1_FABRIC`, `DC1`, and `all`. Ansible merges variables from all four files.

The merge order, from lowest to highest priority:

```
all.yml  →  DC1.yml  →  DC1_FABRIC.yml  →  DC1_SPINES.yml  →  host_vars/spine1.yml
```

Variables closer to the device override more general ones. This lets you set a sensible default in `DC1.yml` and override it for a specific role in `DC1_SPINES.yml`, without duplicating data.

---

### 3.2 Connection Settings (`group_vars/all.yml`)

```yaml
ansible_connection: ansible.netcommon.httpapi
ansible_network_os: arista.eos.eos
ansible_httpapi_use_ssl: true
ansible_httpapi_port: 443
```

These settings tell Ansible **how** to talk to every device. Instead of SSH and CLI text-parsing, AVD uses **eAPI** — Arista's HTTP/JSON API built into EOS. The `httpapi` connection plugin handles this transparently. You send structured JSON, you get structured JSON back — no screen scraping, no fragile regex patterns.

This is important for the deploy step: eAPI is what allows the `eos_config_deploy_eapi` role to perform a true config replace rather than a line-by-line merge.

---

### 3.3 Site-Wide Settings (`group_vars/DC1.yml`)

```yaml
local_users:
  - name: admin
    privilege: 15
    role: network-admin
    no_password: true
  - name: ansible
    privilege: 15
    role: network-admin
    sha512_password: "..."

mgmt_vrf_routing: true
mgmt_gateway: 172.20.20.1
mgmt_interface: Management0

ntp:
  servers:
    - name: time.cloudflare.com
      vrf: MGMT
      preferred: true
```

These variables control configuration that goes into **every** device regardless of its role in the fabric: user accounts, NTP, DNS, AAA, and the management interface.

The `mgmt_vrf_routing: true` key tells AVD to place management traffic in a dedicated VRF called `MGMT`. This isolates management access from the data plane — a routing mistake in the fabric cannot accidentally cut off your SSH or eAPI access.

---

### 3.4 The Fabric Design (`group_vars/DC1_FABRIC.yml`)

This is the most important file in the lab. It is read exclusively by the `eos_designs` role and describes the entire physical fabric: routing protocols, IP address pools, and node-by-node definitions.

#### Routing protocols

```yaml
underlay_routing_protocol: ebgp
overlay_routing_protocol: ebgp
```

**Underlay** is the routing protocol used between physical interfaces — the point-to-point links between spines and leaves. eBGP is used here because each leaf pair has a unique AS number, making inter-AS peering natural and simple to reason about.

**Overlay** is the EVPN control plane that carries MAC and IP reachability information over VXLAN tunnels. In this lab it is also eBGP — the spines act as route-reflectors so that leaves do not need a full mesh of EVPN sessions with each other.

#### IP address pools

```yaml
loopback_ipv4_pool: 192.168.255.0/24
vtep_loopback_ipv4_pool: 192.168.254.0/24
underlay_p2p_network_summary: 192.168.0.0/22
mlag_peer_ipv4_pool: 10.255.252.0/24
mlag_peer_l3_ipv4_pool: 10.255.251.0/24
```

You never manually assign loopback or point-to-point addresses. AVD uses each node's `id` field as an offset into these pools and computes all addresses automatically.

For example, with `loopback_ipv4_pool: 192.168.255.0/24`:
- spine1 (`id: 1`) → Loopback0 = `192.168.255.1/32`
- spine2 (`id: 2`) → Loopback0 = `192.168.255.2/32`
- leaf1 (`id: 1` with `loopback_ipv4_offset: 2`) → Loopback0 = `192.168.255.3/32`
- leaf2 (`id: 2` with offset 2) → Loopback0 = `192.168.255.4/32`

The `loopback_ipv4_offset: 2` under `l3leaf.defaults` shifts leaf addresses so they don't collide with the two spine addresses at the start of the pool.

#### Spine node definitions

```yaml
spine:
  defaults:
    platform: cEOS-lab
    bgp_as: 65001
  nodes:
    - name: spine1
      id: 1
      mgmt_ip: 172.20.20.11/24
    - name: spine2
      id: 2
      mgmt_ip: 172.20.20.12/24
```

`platform: cEOS-lab` is not cosmetic. AVD has platform-specific logic — cEOS does not have hardware TCAM, so certain VXLAN and hardware offload settings differ from a physical switch like a 7050 or 7280. Specifying the platform ensures AVD generates the right configuration for the container environment.

All spines share the same BGP AS (`65001`). This is standard in a leaf-spine design: the spine layer is one AS, and each leaf pair is a separate AS.

#### Leaf node groups

```yaml
l3leaf:
  defaults:
    uplink_interfaces: [Ethernet1, Ethernet2]
    uplink_switches: [spine1, spine2]
    mlag_interfaces: [Ethernet3, Ethernet4]
    virtual_router_mac_address: 00:1c:73:00:dc:01
    filter:
      tenants: [ACME]
      tags: [prod, dev, web]

  node_groups:
    - group: DC1_LEAF1_2
      bgp_as: 65101
      nodes:
        - name: leaf1
          id: 1
          uplink_switch_interfaces: [Ethernet1, Ethernet1]
        - name: leaf2
          id: 2
          uplink_switch_interfaces: [Ethernet2, Ethernet2]
```

A few details worth understanding:

**`node_groups`** maps directly to MLAG pairs. Leaves in the same group share a BGP AS number and an MLAG domain. AVD generates the MLAG peer-link configuration (Port-Channel, VLAN, peer addresses) automatically.

**`uplink_switch_interfaces: [Ethernet1, Ethernet1]`** means "connect my first uplink to spine1's Ethernet1, and my second uplink to spine2's Ethernet1". The list maps positionally to `uplink_switches: [spine1, spine2]`. AVD uses this to know exactly which interfaces to configure on the spine side, which is how it can generate the complete configuration for both ends of every link.

**`virtual_router_mac_address: 00:1c:73:00:dc:01`** is the anycast gateway MAC address. The same MAC is configured for the SVI on every leaf switch. When a server ARPs for its default gateway, every leaf responds with this identical MAC, so the server does not need to re-ARP or update its ARP table when traffic is forwarded through a different leaf — this enables seamless virtual machine mobility across the fabric.

**`filter.tags`** controls which VLANs and VRFs are provisioned on this leaf group. A leaf only carries networks whose `tags` appear in this filter list. This prevents every VLAN from being provisioned everywhere, which is important in large fabrics with many tenants.

---

### 3.5 The Overlay Networks (`group_vars/DC1_TENANTS_NETWORKS.yml`)

If `DC1_FABRIC.yml` describes the physical underlay, this file describes the **logical overlay** — the networks that servers actually see. Think of it as the "tenant view" of the fabric.

```yaml
tenants:
  - name: ACME
    mac_vrf_vni_base: 10000
    vrfs:
      - name: PROD
        vrf_vni: 1
        svis:
          - id: 10
            name: App-Tier
            tags: [prod]
            ip_address_virtual: 10.1.10.1/24
    l2vlans:
      - id: 200
        name: Storage
        tags: [prod]
        vni: 10200
```

#### Tenants

A tenant is a logical customer or business unit that groups related VRFs and VLANs. The `mac_vrf_vni_base: 10000` means that each VLAN's VNI is computed as `base + vlan_id`. VLAN 10 gets VNI 10010, VLAN 20 gets VNI 10020, and so on. This makes VNI assignment automatic and predictable without requiring a separate mapping table.

#### VRFs

Each VRF is a separate routing table. Traffic between VRFs must be explicitly routed (inter-VRF routing is possible but must be configured). `vrf_vni: 1` is the Layer 3 VNI — it appears in the VXLAN header to identify which VRF a routed packet belongs to when it traverses the fabric. This is part of the symmetric IRB model used by EVPN.

#### SVIs

An SVI (Switched Virtual Interface) is the IP default gateway for a VLAN. `ip_address_virtual` is the anycast address — the same IP is configured on all leaf switches that carry this VLAN. A server always points to `10.1.10.1` as its gateway, regardless of which physical leaf it is attached to.

This works because of the shared `virtual_router_mac_address` set in `DC1_FABRIC.yml`. Every leaf responds to ARP requests for `10.1.10.1` with the same MAC, so the server's ARP cache never becomes stale during failover.

#### Tags

```yaml
tags: [prod]
```

Tags connect the tenant file to the fabric file. In `DC1_FABRIC.yml`, the leaf defaults have:

```yaml
filter:
  tenants: [ACME]
  tags: [prod, dev, web]
```

A leaf only receives VLANs and SVIs whose tags are in its filter list. For example, if you wanted leaf pair 2 to carry only `dev` networks (no production traffic), you would set `tags: [dev]` in that group's definition. This is a common pattern in multi-tenant fabrics where different leaf pods serve different environments.

#### L2 VLANs

```yaml
l2vlans:
  - id: 200
    name: Storage
    tags: [prod]
    vni: 10200
```

L2 VLANs have no IP gateway on the fabric — the leaf switches just bridge the VLAN over VXLAN tunnels. The VNI is set manually here rather than derived from the base, because storage arrays often have specific VNI requirements that must match the array's configuration exactly.

---

### 3.6 The Playbooks

The lab uses three playbooks, each with a distinct purpose. They are designed to be run in sequence.

#### `playbooks/build.yml` — Generate configs without touching any device

```yaml
- name: Build EOS configurations from AVD data models
  hosts: DC1_FABRIC
  gather_facts: false
  connection: local

  tasks:
    - name: Generate structured EOS configuration
      import_role:
        name: arista.avd.eos_designs

    - name: Generate EOS configuration files and documentation
      import_role:
        name: arista.avd.eos_cli_config_gen
```

`connection: local` is the key detail here. This playbook runs entirely on your laptop — it never opens a connection to any switch. It is pure Python and Jinja2 processing your YAML files.

The two roles run in sequence and represent a two-stage pipeline:

**Stage 1 — `eos_designs`:** Reads all your `group_vars` files and computes an intermediate representation called the *structured config* — a normalized YAML document that represents the complete device configuration in a vendor-neutral schema. This is written to `intended/structured_configs/<device>.yml`.

The structured config is extremely useful for debugging. If a generated config looks wrong, check the structured config first. It shows you exactly what `eos_designs` computed before any text rendering happened. If the structured config is correct but the final config is wrong, the bug is in a Jinja2 template. If the structured config itself is wrong, the bug is in your input YAML.

**Stage 2 — `eos_cli_config_gen`:** Takes the structured config as input and renders it through Jinja2 templates into actual EOS CLI syntax. Output goes to `intended/configs/<device>.cfg`. It also generates Markdown documentation in `documentation/` — topology diagrams, BGP peer tables, and VLAN lists derived directly from your intent.

The separation between these two stages is intentional. In a real workflow, you would commit the generated configs to Git and have a colleague review the diff before any device is touched.

#### `playbooks/deploy.yml` — Push configs to devices

```yaml
- name: Deploy EOS configurations to devices
  hosts: DC1_FABRIC
  gather_facts: false

  tasks:
    - name: Deploy configurations via eAPI (config replace)
      import_role:
        name: arista.avd.eos_config_deploy_eapi
      vars:
        config_replace: true
```

This playbook connects to each device via eAPI and uses EOS's `configure replace` command to atomically swap the entire running config with the generated config. The operation is equivalent to:

```
copy <file> flash:intended.cfg
configure replace flash:intended.cfg
```

`config_replace: true` is the safe, idempotent mode. Running the deploy twice produces exactly the same result as running it once — if nothing in the YAML changed, no config changes are made on the device. This is called **idempotency** and it is a core principle of good automation.

If you used `config_replace: false` (merge mode), Ansible would apply only the lines that are different from the running config. This is faster but risks leaving behind stale configuration that is no longer in your intent — for example, an old VLAN that you removed from `DC1_TENANTS_NETWORKS.yml` would remain on the device.

#### `playbooks/validate.yml` — Check live state against intended state

```yaml
- name: Validate network state against intended design
  hosts: DC1_FABRIC_VALIDATION
  gather_facts: false

  tasks:
    - name: Validate EOS state
      import_role:
        name: arista.avd.eos_validate_state
      vars:
        save_catalog: true
        halt_on_failure: false
```

This playbook connects to each device, collects operational state via eAPI, and checks that it matches what the build playbook computed as the intended state. It uses **ANTA** (Arista Network Test Automation) under the hood.

Based on the same YAML variables used during the build, AVD knows what to expect: which BGP sessions should be established, which VTEPs should be reachable, which interfaces should be active, what routes should be in the routing table. It does not check configurations — it checks *operational state*.

`halt_on_failure: false` means that even if a check fails, the playbook continues running all remaining checks and shows you the complete picture at the end. Set it to `true` if you want the playbook to stop at the first failure — useful in CI pipelines where a critical failure should abort the entire run.

The playbook targets `DC1_FABRIC_VALIDATION` rather than `DC1_FABRIC`. These two groups contain the same devices, but keeping them separate means you can modify the scope of validation independently from the scope of build/deploy. For example, you could validate only the spines by changing the target to `DC1_SPINES` without touching the deploy playbook.

#### How the three playbooks fit together

```
YAML files (your intent)
        │
        ▼
  build.yml              ← runs locally, no device connections
  eos_designs            → reads group_vars, computes structured configs
  eos_cli_config_gen     → renders structured configs into EOS CLI text
        │
        ▼
  intended/configs/      ← review and commit these to Git before deploying
        │
        ▼
  deploy.yml             ← connects to devices via eAPI
  eos_config_deploy_eapi → config replace, fully idempotent
        │
        ▼
  validate.yml           ← connects to devices via eAPI
  eos_validate_state     → compares live operational state to build output
```

This separation of build → deploy → validate is intentional and mirrors how professional network automation pipelines work. The build step is fast and safe (no device access). The deploy step is the only step that changes the network. The validate step confirms the network converged to the intended state after the change.

---

## Part 4: Lab Exercises

Work through these exercises in order. Each builds on the previous one.

---

### Exercise 1: Explore the Lab Topology

**Goal:** Understand what you are working with before you automate anything.

**Tasks:**

1. SSH into `spine1` and run:
   ```
   show lldp neighbors
   show ip interface brief
   show bgp summary
   ```

2. Notice that EOS has a default configuration from the containerlab startup-config. There are no fabric-level BGP sessions yet — only management is configured.

3. Open `containerlab/topology.yml` and find:
   - Which interfaces connect spine1 to leaf1?
   - What management IP is assigned to leaf3?

4. Draw a simple diagram of the physical connections on paper or in a text file.

**Expected result:** You can SSH to all 6 devices and understand the physical topology.

---

### Exercise 2: Build Configurations with AVD

**Goal:** Generate EOS configuration files from YAML without touching any device.

**Tasks:**

1. Activate your virtual environment:
   ```bash
   source ~/avd-lab/venv/bin/activate
   ```

2. Navigate to the lab directory:
   ```bash
   cd ~/avd-lab/lab
   ```

3. Run the build playbook:
   ```bash
   ansible-playbook playbooks/build.yml
   ```

4. Inspect the output:
   ```bash
   ls intended/configs/
   cat intended/configs/spine1.cfg
   ```

5. Answer these questions by reading the generated config:
   - What BGP AS number was assigned to spine1?
   - What is the loopback0 address of leaf1?
   - How many VLANs are configured on leaf1?

**Expected result:** A folder `intended/configs/` containing one `.cfg` file per device, and a folder `documentation/` with Markdown topology docs.

---

### Exercise 3: Deploy Configurations to the Lab

**Goal:** Push the generated configurations to the running cEOS containers.

**Tasks:**

1. Run the deploy playbook:
   ```bash
   ansible-playbook playbooks/deploy.yml
   ```

2. SSH into `spine1` and verify BGP came up:
   ```
   show bgp summary
   show ip route
   ```

3. SSH into `leaf1` and check the EVPN overlay:
   ```
   show bgp evpn summary
   show vxlan address-table
   show interface vxlan1
   ```

4. Verify end-to-end VXLAN:
   ```
   show bgp evpn route-type mac-ip
   ```

**Expected result:** BGP underlay and EVPN overlay are fully established across all devices.

---

### Exercise 4: Add a New VLAN

**Goal:** Understand the day-2 workflow — making a change via YAML, not CLI.

**Scenario:** The application team needs a new VLAN 110 (`Web-Tier`) in the production VRF, available on all leaf switches.

**Tasks:**

1. Open `inventory/group_vars/DC1_TENANTS_NETWORKS.yml`

2. Under the `PROD` VRF, add a new SVI entry:
   ```yaml
   - id: 110
     name: Web-Tier
     tags: ['web']
     enabled: true
     ip_address_virtual: 10.1.110.1/24
   ```

3. Under `l2vlans`, add the corresponding VLAN:
   ```yaml
   - id: 110
     name: Web-Tier
     tags: ['web']
   ```

4. Rebuild and redeploy:
   ```bash
   ansible-playbook playbooks/build.yml
   ansible-playbook playbooks/deploy.yml
   ```

5. Verify on a leaf:
   ```
   show vlan 110
   show interface vlan110
   ```

6. Use `git diff` (if the directory is a git repo) or manually compare the old and new config to see exactly what changed.

**Expected result:** VLAN 110 and SVI 10.1.110.1/24 appear on all leaves with the `web` tag.

---

### Exercise 5: Add a New Leaf Pair

**Goal:** Scale the fabric by adding a new leaf pair through YAML alone.

**Scenario:** The data center is expanding. You need to add `leaf5` and `leaf6` as a new MLAG pair.

**Tasks:**

1. Open `containerlab/topology.yml` and add the two new nodes and their links to both spines.

2. Redeploy the topology:
   ```bash
   sudo containerlab deploy -t containerlab/topology.yml --reconfigure
   ```

3. Add the new nodes to `inventory/hosts.yml` under a new group `DC1_LEAF5_6`.

4. Add node-specific variables to `inventory/group_vars/DC1_FABRIC.yml` under `l3leaf.nodes`.

5. Rebuild and deploy:
   ```bash
   ansible-playbook playbooks/build.yml
   ansible-playbook playbooks/deploy.yml
   ```

6. Verify the new leaves have BGP sessions to both spines:
   ```
   ssh admin@172.20.20.17  # leaf5
   show bgp summary
   ```

**Expected result:** leaf5 and leaf6 are fully integrated into the EVPN fabric with no manual CLI changes.

---

### Exercise 6: Validate the Network State

**Goal:** Use AVD's validation role to check that the network matches its intended state.

**Tasks:**

1. Run the validation playbook:
   ```bash
   ansible-playbook playbooks/validate.yml
   ```

2. Read the report in `reports/`.

3. **Break something on purpose:** SSH into `spine1` and shut down the interface toward `leaf1`:
   ```
   configure
   interface Ethernet1
     shutdown
   end
   ```

4. Run the validation again and observe the failure.

5. Restore the interface:
   ```
   configure
   interface Ethernet1
     no shutdown
   end
   ```

**Expected result:** You can distinguish a passing validation from a failing one, and you understand how AVD detects drift between intended and actual state.

---

## Part 5: Troubleshooting Common Issues

### containerlab won't start

- Check that Docker is running: `docker info`
- Check for port conflicts: `sudo netstat -tulpn | grep 22`
- Run with `--debug` flag: `sudo containerlab deploy -t topology.yml --debug`

### Ansible can't connect to devices

- Verify the management IP: `ping 172.20.20.11`
- Check SSH works manually: `ssh admin@172.20.20.11`
- Confirm `ansible.cfg` has the right connection settings

### AVD build fails with schema errors

- Read the error message carefully — AVD gives specific field names
- Check that indentation in YAML is correct (use spaces, not tabs)
- Validate your YAML: `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"`

### BGP sessions not coming up

- Check interface status: `show interface status`
- Check BGP config: `show running-config section bgp`
- Check logs: `show logging last 50`

---

## Next Steps

Once you are comfortable with this lab, explore:

- **Campus AVD designs** — for access/distribution/core networks
- **AVD with CloudVision** — push configs through Arista's management platform
- **CI/CD pipelines** — run AVD builds automatically on every Git commit
- **Custom templates** — override AVD's Jinja2 templates for non-standard configs
- **Structured configs** — use the `eos_designs` output as input to other tools

---

## Reference

- [AVD Documentation](https://avd.arista.com)
- [containerlab Documentation](https://containerlab.dev)
- [Arista cEOS-lab](https://www.arista.com/en/support/software-download)
- [AVD GitHub](https://github.com/aristanetworks/avd)
