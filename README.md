# fotografm/nixos-config

NixOS flake for the fotografm homelab fleet, managed declaratively.

## Hosts

| Host | Location | IP | Role |
|---|---|---|---|
| `x11-5` | c38 | `192.168.8.80` | Incus hypervisor (containers + VMs) |

## Repository layout

```
nixos-config/
├── flake.nix                           # entry point, defines nixosConfigurations
├── .gitignore
├── README.md
├── modules/
│   └── common.nix                      # shared config (SSH, user, base packages)
└── hosts/
    └── x11-5/
        ├── default.nix                 # host-level: bootloader, hostname
        ├── hardware-configuration.nix  # generated during install
        ├── networking.nix              # bridge br0 + static IP 192.168.8.80
        └── incus.nix                   # virtualisation.incus + preseed
```

## Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Root filesystem | ext4 | Simple, well-understood, fine for /nix/store |
| Incus storage | btrfs on /dev/sda3 | Instant snapshots/clones (CoW), no ZFS RAM cost |
| Networking | Linux bridge `br0` enslaving physical NIC | Containers get real LAN IPs (Proxmox vmbr0 equivalent) |
| Container IPs | Static per container via `incus config device set` | Declarative, no router-side DHCP reservations |
| Container IP range | 192.168.8.126–149 (convention) | Reserved by hand for x11-5 instances |
| NixOS channel | nixos-26.05 ("Yarara") | Current stable |
| Incus | feature release (`pkgs.incus`) | Latest features; switch to `incus-lts` later if desired |

## Host network plan

- Host: `x11-5` at `192.168.8.80/24`
- IPMI BMC: `192.168.8.81`
- Gateway: `192.168.8.1`
- DNS: `192.168.8.70` (Pi-hole at c38), fallbacks `1.1.1.1`, `9.9.9.9`
- Incus REST API + Web UI: `https://192.168.8.80:8443`

## Partition layout (240 GB SSD at /dev/sda)

| Partition | Size | Filesystem | Purpose | Mount |
|---|---|---|---|---|
| /dev/sda1 | 1 GiB | FAT32 (label `BOOT`) | EFI system partition | `/boot` |
| /dev/sda2 | 60 GiB | ext4 (label `nixos`) | NixOS root + /nix/store | `/` |
| /dev/sda3 | ~178 GiB | btrfs (Incus-managed) | Incus storage pool `default` | (Incus) |

---

# End-to-end install procedure

Three phases:

1. **Workstation prep** — create the flake repo locally, push to private GitHub repo.
2. **Install via IPMI** — boot installer, wipe and partition the SSD, mount, generate hardware config, install.
3. **Post-install** — clone repo on the server for ongoing rebuilds, verify Incus.

## Prerequisites

- Workstation with `git`, `ssh`, `scp`, `gh` (GitHub CLI) installed.
- Network access to the x11-5 IPMI BMC at `192.168.8.81` (via Tailscale subnet route to 192.168.8.0/24).
- NixOS 26.05 minimal ISO downloaded from <https://nixos.org/download/#nixos-iso>.
- Your SSH public key at hand.

> **Note about the existing OS on the SSD**: It doesn't matter what's currently installed. The IPMI virtual media boot (step 2.1) takes precedence over the BIOS boot order, so the installer ISO always wins on first boot. Step 2.4 wipes all signatures off the SSD before partitioning, so the old OS is gone the moment you proceed past that step.

---

## Phase 1: Workstation prep

### 1.1. Create the directory and drop the files in

Place all the files from this repository skeleton under `~/repos/nixos-config/`:

```
mkdir -p ~/repos/nixos-config/{modules,hosts/x11-5}
```

Copy the downloaded files in:

- `flake.nix` → `~/repos/nixos-config/flake.nix`
- `gitignore` → `~/repos/nixos-config/.gitignore`
- `README.md` → `~/repos/nixos-config/README.md`
- `common.nix` → `~/repos/nixos-config/modules/common.nix`
- `x11-5-default.nix` → `~/repos/nixos-config/hosts/x11-5/default.nix`
- `x11-5-networking.nix` → `~/repos/nixos-config/hosts/x11-5/networking.nix`
- `x11-5-incus.nix` → `~/repos/nixos-config/hosts/x11-5/incus.nix`

### 1.2. Add your SSH public key

Open `~/repos/nixos-config/modules/common.nix` and replace the placeholder string in `openssh.authorizedKeys.keys` with the contents of your real public key:

```
cat ~/.ssh/id_ed25519.pub
```

### 1.3. Init git on branch main

```
cd ~/repos/nixos-config
```

```
git init -b main
```

```
git add -A
```

```
git commit -m "Initial flake: x11-5 host skeleton"
```

### 1.4. Create the private GitHub repo and push (SSH remote)

```
gh repo create fotografm/nixos-config --private --source=. --remote=origin
```

```
git remote set-url origin git@github.com:fotografm/nixos-config.git
```

```
git push -u origin main
```

---

## Phase 2: Install via IPMI

### 2.1. Create a Samba share on the workstation and mount it via IPMI Virtual Media

The BMC on x11-5 uses SMB virtual media (HTTP virtual media is not supported on this firmware). Run these steps on your workstation (192.168.8.99).

**Install Samba and create the share directory:**

```
sudo apt install samba -y
```

```
mkdir ~/share
```

Copy the NixOS ISO into `~/share/`.

**Edit `/etc/samba/smb.conf`** — add the following two lines inside the existing `[global]` section under `## Browsing/Identification ###`:

```
server min protocol = NT1
server max protocol = SMB3
```

Then append the following at the **end of the file**:

```
[share]
path = /home/user/share
browseable = yes
read only = no
guest ok = yes
force user = user

[global]
server min protocol = NT1
```

**Restart Samba:**

```
sudo systemctl restart smbd
```

**Test the share is accessible:**

```
smbclient //192.168.8.99/share -N -c "ls"
```

You should see the ISO listed with no `ACCESS_DENIED` error.

**In the IPMI web UI** at `http://192.168.8.81`, open **Virtual Media** → **CD-ROM Image** and set:

- **Share Host**: `192.168.8.99`
- **Path to Image**: `\share\nixos-minimal-26.05.3494.714a5f8c4ead-x86_64-linux.iso`

> **Path syntax note**: the share name (`\share\`) is part of the path, not a separate field. Use backslashes exactly as shown.

Click **Mount**, then click **Reload** / check the ISO file status — it should show the file as mounted before you proceed.

**Reboot x11-5** and as the system POSTs, press **F11** to open the BIOS Boot Selection menu and pick the **virtual CD/DVD** entry (the one whose name contains "ATEN" or "Virtual CD").

The one-time boot menu overrides whatever is in the BIOS boot order. If you miss F11 and the existing OS boots, just reboot and try again.

The NixOS installer drops to a TTY running as user `nixos` with no password.

### 2.2. Enable SSH inside the installer

In the IPMI console:

```
sudo -i
```

```
passwd
```

(Set any temporary root password — this only lives in installer RAM.)

```
systemctl start sshd
```

```
ip -o -4 addr show
```

Note the installer's DHCP-assigned IP. From now on, work from the workstation via SSH:

```
ssh root@<installer-ip-from-above>
```

### 2.3. Identify the physical NIC name

Still in the installer SSH session:

```
ip -o link
```

Note the name of the physical ethernet (almost certainly `eno1` on a Supermicro X11, but verify). If it is **not** `eno1`, on the **workstation**:

1. Edit `~/repos/nixos-config/hosts/x11-5/networking.nix`, change `physicalNic = "eno1";` to the real name.
2. `git add hosts/x11-5/networking.nix && git commit -m "Set physicalNic for x11-5" && git push`.

### 2.4. Wipe the existing SSD

The 240 GB SSD has another OS on it. Before we partition, we need to remove all partition table signatures and filesystem signatures so the new layout is clean.

First, **confirm /dev/sda is actually the right disk** (no other drives visible):

```
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,FSTYPE
```

You should see `sda` at ~240 GB and probably a few existing partitions (sda1, sda2, …). If you see multiple disks, identify which is the 240 GB SSD before going further — the next commands are destructive and irreversible.

Wipe all filesystem signatures (UUIDs, magic numbers, labels) and any LVM/MD/swap headers:

```
wipefs -a /dev/sda
```

Zap the GPT structures (both primary at the start and backup at the end of the disk) and any leftover MBR:

```
sgdisk --zap-all /dev/sda
```

Optional but recommended for an SSD — issue a full TRIM so the controller's wear-levelling map starts fresh. This is fast (seconds) on modern SSDs:

```
blkdiscard -f /dev/sda
```

Verify the disk is now empty:

```
lsblk /dev/sda
```

You should see just `sda` with no child partitions.

### 2.5. Partition the SSD

```
parted /dev/sda -- mklabel gpt
```

```
parted /dev/sda -- mkpart ESP fat32 1MiB 1GiB
```

```
parted /dev/sda -- set 1 esp on
```

```
parted /dev/sda -- mkpart primary 1GiB 61GiB
```

```
parted /dev/sda -- mkpart primary 61GiB 100%
```

Verify the result:

```
lsblk /dev/sda
```

You should see `sda1` (~1 GB), `sda2` (~60 GB), `sda3` (~178 GB).

### 2.6. Format /dev/sda1 and /dev/sda2

`/dev/sda3` is **deliberately left unformatted** — Incus will create btrfs on it at first boot.

```
mkfs.fat -F32 -n BOOT /dev/sda1
```

```
mkfs.ext4 -L nixos /dev/sda2
```

### 2.7. Mount the targets

```
mount /dev/disk/by-label/nixos /mnt
```

```
mkdir -p /mnt/boot
```

```
mount /dev/disk/by-label/BOOT /mnt/boot
```

### 2.8. Generate hardware-configuration.nix

```
nixos-generate-config --root /mnt
```

This produces `/mnt/etc/nixos/hardware-configuration.nix`.

### 2.9. Copy hardware-configuration.nix back to the workstation

On the **workstation**:

```
scp root@<installer-ip>:/mnt/etc/nixos/hardware-configuration.nix ~/repos/nixos-config/hosts/x11-5/hardware-configuration.nix
```

```
cd ~/repos/nixos-config
```

```
git add hosts/x11-5/hardware-configuration.nix
```

```
git commit -m "Add hardware-configuration.nix for x11-5"
```

```
git push
```

### 2.10. Copy the full flake to the installer

Easiest path for a private repo — copy the whole working copy across rather than wrestling with GitHub auth inside the installer:

```
scp -r ~/repos/nixos-config root@<installer-ip>:/tmp/nixos-config
```

### 2.11. Run nixos-install from the flake

Back in the installer SSH session:

```
nixos-install --flake /tmp/nixos-config#x11-5 --no-root-passwd
```

This builds the system from your flake and writes it to `/mnt`. Expect 5–20 minutes depending on download speed (it pulls ~3 GB of packages on first install).

### 2.12. Unmount and reboot

```
umount -R /mnt
```

In the IPMI UI: **unmount the virtual ISO** so the BIOS now boots from the SSD, then:

```
reboot
```

The host should come up on `192.168.8.80` via `br0`, sshd listening, your SSH key working.

---

## Phase 3: Post-install

### 3.1. SSH in

From the workstation:

```
ssh user@192.168.8.80
```

### 3.2. Verify Incus is up

```
incus version
```

```
incus storage list
```

You should see the `default` btrfs pool backed by `/dev/sda3`.

```
incus profile show default
```

You should see the bridged `eth0` device with `parent: br0`.

### 3.3. Generate an SSH key on x11-5 for GitHub

```
ssh-keygen -t ed25519 -C "x11-5@c38" -f ~/.ssh/id_ed25519 -N ""
```

```
cat ~/.ssh/id_ed25519.pub
```

In the GitHub web UI: **Settings → Deploy keys** on `fotografm/nixos-config` → **Add deploy key** → paste, untick "Allow write access" (read-only is enough for rebuilds).

### 3.4. Clone the repo on x11-5

```
mkdir -p ~/repos
```

```
git clone git@github.com:fotografm/nixos-config.git ~/repos/nixos-config
```

### 3.5. Future rebuilds

From `~/repos/nixos-config` on x11-5:

```
sudo nixos-rebuild switch --flake .#x11-5
```

Or, to test changes without committing:

```
sudo nixos-rebuild test --flake .#x11-5
```

To pull and rebuild in one go:

```
git pull && sudo nixos-rebuild switch --flake .#x11-5
```

---

# Using Incus

## Launch a Debian container with a static LAN IP

```
incus launch images:debian/13 test1
```

```
incus config device override test1 eth0 ipv4.address=192.168.8.126
```

```
incus restart test1
```

```
incus list
```

The container should appear with `192.168.8.126` on the LAN, reachable from any other host on 192.168.8.0/24 (and via Tailscale from your Brighton workstation).

## Launch a VM (full QEMU/KVM)

```
incus launch images:debian/13 test-vm --vm
```

```
incus console test-vm --show-log
```

## USB device passthrough (e.g. RTL-SDR)

Identify the dongle on the host:

```
lsusb
```

Pass it through to a running container `sdr1`:

```
incus config device add sdr1 rtlsdr usb vendorid=0bda productid=2838
```

Common SDR vendor/product IDs:

| Device | vendorid | productid |
|---|---|---|
| RTL-SDR V4 / NESDR | `0bda` | `2838` |
| Airspy R2 / Mini | `1d50` | `60a1` |
| Airspy HF+ Discovery | `03eb` | `800c` |
| HackRF One | `1d50` | `6089` |
| RSPdx (SDRplay) | `1df7` | `3000` |

To make the passthrough survive the device being unplugged temporarily, add `required=false`:

```
incus config device set sdr1 rtlsdr required=false
```

## Snapshots and clones (cheap, thanks to btrfs)

```
incus snapshot create test1 before-experiment
```

```
incus snapshot list test1
```

```
incus snapshot restore test1 before-experiment
```

```
incus copy test1 test1-clone
```

## Incus web UI

Browse to <https://192.168.8.80:8443>.

You will see a "client certificate required" page. Easiest path: from your workstation, generate an Incus client cert and trust it on x11-5.

```
incus remote add x11-5 https://192.168.8.80:8443
```

This prompts for a trust token. Generate one on x11-5:

```
incus config trust add --name workstation
```

Copy the token printed, paste into the prompt on the workstation. After that:

```
incus --target x11-5 list
```

Or set x11-5 as the default remote:

```
incus remote switch x11-5
```

The web UI on `:8443` will also accept the client cert installed by `incus remote add`.

---

# Troubleshooting

## The installer didn't boot, the old OS came up

You missed the F11 one-time boot menu. Reboot and try again — when you see the Supermicro POST screen, hammer F11 until the **Please select boot device** menu appears, then pick the virtual CD entry. Alternatively, in the BIOS itself (F2 or DEL on POST) set the virtual CD as the first boot device permanently for the duration of the install, then change it back to SSD after.

## Samba virtual media — `ACCESS_DENIED` when testing the share

The guest/nobody unix user can't read the share directory. Make sure `force user = user` is present in the `[share]` stanza and restart smbd:

```
sudo systemctl restart smbd
```

Then re-test: `smbclient //192.168.8.99/share -N -c "ls"`

## "device is mounted" or "GPT signature found" warnings from parted

You skipped step 2.4. Run the three wipe commands (`wipefs -a`, `sgdisk --zap-all`, optionally `blkdiscard -f`) before trying `parted` again.

## Lost SSH after a rebuild

Use IPMI as your fallback path (192.168.8.81). At boot, the systemd-boot menu lets you pick the previous generation. Common causes:

- Wrong `physicalNic` in `hosts/x11-5/networking.nix` — bridge never came up.
- Firewall lost port 22.
- DNS misconfiguration broke nixos-rebuild fetches.

To roll back from a working generation:

```
sudo nixos-rebuild switch --rollback
```

## Incus preseed didn't apply

The NixOS Incus module applies the preseed on service start. If the daemon was already initialised manually (`incus admin init`), the preseed will MERGE in new entities but not change existing storage drivers. To re-bootstrap from scratch on a fresh box:

```
sudo systemctl stop incus.service incus.socket
```

```
sudo rm -rf /var/lib/incus/database
```

```
sudo systemctl start incus.service
```

Note this destroys all containers and metadata. Only do this on a fresh, empty host.

## Container can't reach the LAN

- Verify `incus list` shows an IPv4 on the LAN (192.168.8.x).
- Verify the host's `br0` is up: `ip -br link show br0` → state UP.
- Verify the container is on `br0`: `incus config show <name> --expanded | grep parent`.
- The host should NOT have `br_netfilter` loaded (Incus traffic shouldn't traverse the host firewall).

## Incus web UI is unreachable

```
sudo ss -ltn | grep 8443
```

If nothing's listening, check the daemon:

```
sudo systemctl status incus
```

If the daemon is up but port 8443 is closed, the firewall in `modules/common.nix` is the suspect.

---

# Next steps after the host is up

A few things worth doing once x11-5 is healthy:

1. **Tailscale**: add `services.tailscale.enable = true;` to the host config and rebuild, then `sudo tailscale up --advertise-routes=192.168.8.0/24` to make x11-5 a subnet router (or simply join the tailnet as a leaf node).
2. **Pin the Incus version**: optionally switch from `pkgs.incus` to `pkgs.incus-lts` in `hosts/x11-5/incus.nix` if you want the LTS line.
3. **Image cache**: `incus remote list` already includes `images:` and `ubuntu:` by default. No setup needed for normal use.
4. **First real workload**: spin up a Debian container at 192.168.8.126 and start re-creating one of your Reticulum / MeshChat services in it as a test of the migration pattern.
