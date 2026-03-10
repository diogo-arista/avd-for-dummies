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

You need a Linux or macOS machine (or a Linux VM) with:
- At least **8 GB RAM** (16 GB recommended)
- **20 GB free disk space**
- **Docker** installed and running
- Python 3.10 or newer
- Internet access to pull images and packages

> **Note for macOS users:** containerlab requires a Linux kernel. You need Docker Desktop with a Linux VM backend, or you can use a Lima/Multipass VM. The cEOS image works fine.

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

Before running AVD, take a few minutes to read through the YAML files. This section explains what each file does.

### 3.1 The Inventory (`inventory/hosts.yml`)

This file tells Ansible about your devices and how they are grouped. Groups are important because AVD assigns different roles to different groups (spines vs. leaves).

```yaml
all:
  children:
    DC1:            # Top-level site group
      children:
        DC1_FABRIC: # All fabric devices — AVD reads this group
          children:
            DC1_SPINES:
              hosts:
                spine1:
                spine2:
            DC1_L3LEAVES:
              children:
                DC1_LEAF1_2:  # Leaf pair (MLAG or standalone)
                  hosts:
                    leaf1:
                    leaf2:
                DC1_LEAF3_4:
                  hosts:
                    leaf3:
                    leaf4:
```

The group hierarchy matters. AVD looks for variables in `group_vars/DC1_FABRIC.yml`, `group_vars/DC1_SPINES.yml`, etc.

### 3.2 The Fabric Variables (`group_vars/DC1_FABRIC.yml`)

This is the most important file. It describes the entire fabric design: BGP AS numbers, loopback ranges, VTEP ranges, and which device connects to which.

Key sections explained inline in the file comments.

### 3.3 The Tenants File (`group_vars/DC1_TENANTS_NETWORKS.yml`)

This describes VRFs, VLANs, and SVIs — the overlay networks your servers will use. You define the logical topology here.

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
