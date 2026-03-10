# Network Automation with Arista AVD: A Hands-On Lab Guide

This guide is designed for network engineers who are new to network automation. You will learn how to use **Arista Validated Designs (AVD)** to automate the configuration of a data center fabric — without needing years of programming experience.

By the end of this guide, you will:
- Understand what AVD is and why it exists
- Have a working virtual lab using containerlab and cEOS
- Know how to describe your network in YAML and generate device configurations automatically
- Be able to push those configurations to devices using Ansible

---

## Fundamentals

### Why Network Automation?

Traditional network management means SSH-ing into every device and typing commands manually. This approach has several problems:

- **It does not scale.** Configuring 50 switches by hand takes days.
- **It is error-prone.** One typo can break the network.
- **It is not auditable.** There is no reliable record of what changed and why.

Automation treats network configuration as **code**: version-controlled, reviewable, repeatable, and testable.

### Key Concepts

| Term | What it means |
|------|--------------|
| **Ansible** | An automation tool that connects to devices and applies configurations. It reads instructions from files called *playbooks*. |
| **Playbook** | A YAML file that tells Ansible what to do and on which devices. |
| **Inventory** | A file (or folder of files) that lists your devices and groups them. |
| **Role** | A reusable package of Ansible tasks. AVD is delivered as a collection of roles. |
| **AVD** | Arista Validated Designs — an open-source Ansible collection that knows how to build full data center fabrics. |
| **cEOS** | Arista's containerized version of EOS (their network OS), which runs as a Docker container. |
| **containerlab** | A tool to build virtual network labs by connecting containers together. |

### What is AVD?

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

---

## Choose Your Lab

Two lab topologies are available. Pick one based on your hardware and learning goals:

| | [Codespaces Lab](docs/codespaces-lab.md) | [Full Lab](docs/full-lab.md) |
|--|------------------------------------------|------------------------------|
| **Spines** | 1 | 2 |
| **Leaves** | 2 standalone | 4 in 2 MLAG pairs |
| **Hosts** | 2 Linux hosts | None |
| **RAM required** | ~5 GB | ~12 GB |
| **MLAG** | No | Yes |
| **Startup** | One command (`start-lab.sh`) | Manual steps |
| **Best for** | GitHub Codespaces, learning the workflow | Full production-scale reference |

**Not sure which to choose?**
- Running on GitHub Codespaces or a laptop with limited RAM → [Codespaces Lab](docs/codespaces-lab.md)
- Have a dedicated Linux machine with 16+ GB RAM → [Full Lab](docs/full-lab.md)

Both labs teach the same AVD concepts and use the same workflow. The Codespaces lab also adds Linux hosts so you can run real ping tests across the VXLAN fabric.

---

## Dev Container & Environment Setup

The repository includes a **dev container** that installs all required tools automatically. When you open the repo in VS Code (locally or on GitHub Codespaces), VS Code reads `.devcontainer/devcontainer.json` and offers to reopen the project inside a pre-configured container.

```
.devcontainer/
├── Dockerfile          ← pre-creates the clab_admins group for the VS Code extension
├── devcontainer.json   ← configures the container, extensions, and Codespaces machine size
└── postCreate.sh       ← runs after the container starts and installs all tools
```

**What gets installed automatically:**
- containerlab (with correct group membership for the VS Code extension)
- Python packages from `requirements.txt` (Ansible, AVD Python library, etc.)
- Ansible Galaxy collections from `requirements.yml`
- Output directories (`intended/`, `documentation/`, `reports/`, `logs/`)

**What you must provide manually** (requires an Arista account to download):
```bash
docker import cEOS-lab-4.35.0F.tar.xz ceos:latest
```

### VS Code Extensions

The dev container installs these extensions automatically:

| Extension | Purpose |
|-----------|---------|
| `redhat.vscode-yaml` | Schema validation and auto-complete for AVD `group_vars` files using the AVD JSON schema |
| `srl-labs.vscode-containerlab` | Deploy, inspect, and open shells into nodes directly from VS Code |
| `wholroyd.jinja` | Syntax highlighting for AVD Jinja2 templates |
| `ms-python.python` | Python support |

The containerlab extension detects any file ending in `.clab.yml` as a topology. This is why all topology files in this repo use the `.clab.yml` suffix.

**Typical VS Code + containerlab workflow:**
1. Open the repo in VS Code (inside the dev container).
2. Open `codespaces/topology.clab.yml` in the Explorer.
3. Right-click the file → **Deploy lab** — nodes appear in the containerlab sidebar.
4. Right-click any node in the sidebar → **Open terminal** to get a shell inside the node.
5. Edit `group_vars` files — the YAML extension shows AVD schema errors inline.
6. Run Ansible playbooks from the VS Code terminal.
7. Right-click the topology file → **Destroy lab** when done.

### Using the Dev Container on GitHub Codespaces

1. Push the repo to GitHub.
2. Click **Code → Codespaces → Create codespace on main**.
3. GitHub builds the container and runs `postCreate.sh` automatically (watch it in the Terminal panel).
4. Import the cEOS image from the VS Code terminal when `postCreate.sh` finishes.

> The `hostRequirements` in `devcontainer.json` automatically selects a 4-core / 16 GB RAM / 32 GB storage Codespaces machine — no manual selection needed.

### Using the Dev Container Locally on macOS

**Prerequisites:**

| Tool | Where to get it |
|------|----------------|
| Docker Desktop for Mac | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| VS Code | [code.visualstudio.com](https://code.visualstudio.com/) |
| Dev Containers extension | `ms-vscode-remote.remote-containers` |

**Step 1 — Configure Docker Desktop resources**

Open Docker Desktop → **Settings → Resources** and set:
- **CPUs:** 4 or more
- **Memory:** 8 GB minimum (16 GB recommended for the full lab)
- **Disk image size:** 60 GB or more

Click **Apply & Restart**.

> **Apple Silicon (M1/M2/M3):** cEOS 4.32+ supports arm64 natively. Older images require Rosetta emulation — enable it in Docker Desktop → **Settings → General → Use Rosetta for x86/amd64 emulation**.

**Step 2 — Open in dev container**

1. Clone the repo and open the folder in VS Code.
2. Click **Reopen in Container** in the bottom-right notification, or open the Command Palette (`⌘ Shift P`) → **Dev Containers: Reopen in Container**.
3. VS Code builds the container (3–5 minutes on first run, seconds after that).
4. `postCreate.sh` runs in the background and installs all tools.

**Step 3 — Import the cEOS image**

> **Important:** The dev container uses Docker-in-Docker — its own Docker daemon, separate from Docker Desktop. Import the image from the **VS Code terminal** (inside the container), not from a macOS terminal.

```bash
docker import cEOS-lab-4.35.0F.tar.xz ceos:latest
docker images | grep ceos
```

---

## Repository Structure

```
.
├── .devcontainer/                  ← dev container configuration
│   ├── Dockerfile
│   ├── devcontainer.json
│   └── postCreate.sh
│
├── containerlab/                   ← full lab topology and startup config
│   ├── topology.clab.yml
│   └── startup-config.cfg
│
├── codespaces/                     ← lightweight lab (Codespaces-optimised)
│   ├── topology.clab.yml
│   ├── start-lab.sh                ← one-command lab automation
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── DC1.yml
│   │       ├── DC1_FABRIC.yml
│   │       └── DC1_TENANTS_NETWORKS.yml
│   └── playbooks/
│       ├── build.yml
│       ├── deploy.yml
│       └── validate.yml
│
├── inventory/                      ← full lab inventory
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       ├── DC1.yml
│       ├── DC1_FABRIC.yml
│       └── DC1_TENANTS_NETWORKS.yml
│
├── playbooks/                      ← full lab playbooks
│   ├── build.yml
│   ├── deploy.yml
│   └── validate.yml
│
├── docs/
│   ├── codespaces-lab.md           ← Codespaces lab: setup, exercises, troubleshooting
│   └── full-lab.md                 ← Full lab: setup, config files, exercises, troubleshooting
│
├── requirements.txt                ← Python dependencies
└── requirements.yml                ← Ansible Galaxy collections
```

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
