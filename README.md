# O(1) Labs Mina lightweight network Docker images building and publishing primitives

## Usage

1. Create `mina-build-system` (`x86`, `arm64`) cloud VMs from prepared snapshots (assign known IPs and SSH keys).
2. Update current repository on remote VMs over SSH.
3. Execute the `scripts/build-all.sh` script on remote VMs over SSH.
4. Update DockerHub manifests with the `scripts/manage-manifests.sh`.
5. Power off the VMs.
6. Delete the VMs.
