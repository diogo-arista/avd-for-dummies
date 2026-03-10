FROM mcr.microsoft.com/devcontainers/python:3.11-bookworm

# Pre-create the clab_admins group and add vscode to it BEFORE the container
# starts. VS Code server (and extensions) start with the process-level group
# list fixed at launch time — usermod in postCreate.sh runs too late because
# the VS Code server is already up. No apt-get / network operations here so
# this build step works in Codespaces without network access.
RUN groupadd -r clab_admins && usermod -aG clab_admins vscode
