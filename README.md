# fotografm/nixos-x11-5

NixOS config for x11-5 Incus hypervisor (192.168.8.80), repo-managed.

x11-4 has its own separate repo: [fotografm/nixos-x11-4](https://github.com/fotografm/nixos-x11-4)

---

## How this works

**This repo is the single source of truth for x11-5.** The config files live here
on pavi-mint (this desktop), not on the x11-5 machine itself. To change anything,
you edit the files here, commit, push, then rebuild on x11-5.

The `/etc/nixos/configuration.nix` on the x11-5 machine is the **default NixOS
install template and is not in use** — it has a warning comment at the top. Do
not edit it.

```
pavi-mint: ~/repos/nixos-x11-5/   ← edit files here
        │
        │  git push
        ▼
github.com/fotografm/nixos-x11-5   ← GitHub backup / history
        │
        │  git pull + nixos-rebuild switch
        ▼
x11-5 (192.168.8.80)               ← running system
```

---

## How to make a config change

1. Edit files on pavi-mint:

```
cd ~/repos/nixos-config
vim hosts/x11-5/default.nix        # or networking.nix, incus.nix, modules/common.nix
```

2. Commit and push:

```
git add -p
git commit -m "describe your change"
git push
```

3. Apply to x11-5 — either SSH in and pull+rebuild:

```
ssh user@192.168.8.80
cd ~/repos/nixos-config
git pull && sudo nixos-rebuild switch --flake .#x11-5
```

   Or rebuild remotely from pavi-mint without SSH-ing in:

```
cd ~/repos/nixos-config
sudo nixos-rebuild switch --flake .#x11-5 --target-host user@192.168.8.80 --use-remote-sudo
```

---

## How to roll back

If a rebuild breaks SSH or networking, use the systemd-boot menu at boot to
select the previous generation, or via IPMI console (BMC at 192.168.8.81):

```
sudo nixos-rebuild switch --rollback
```

---

## Password storage

`user` has a password-based SSH fallback (`PasswordAuthentication = true`) for
logging in from a machine that doesn't have this host's key trusted yet.

The password hash is **never committed to this repo** (it's public) - it lives
only on x11-5 itself, at `/etc/nixos/secrets/user-password-hash`, which is
root-only readable (`chmod 600`) and lives outside any git working tree (this
repo's checkout is at `~/repos/nixos-x11-5`, not `/etc/nixos`).
`modules/common.nix` only ever references the file *path* via
`hashedPasswordFile`.

To set or rotate the password, on x11-5:

```
ssh user@192.168.8.80
mkpasswd -m sha-512 | sudo tee /etc/nixos/secrets/user-password-hash > /dev/null
sudo chmod 600 /etc/nixos/secrets/user-password-hash
sudo nixos-rebuild switch --flake .#x11-5
```

`root` has no password and `PermitRootLogin = "no"` - root cannot log in over
SSH under any circumstances. Use `user` + sudo (passwordless for `wheel`).

This requires `users.mutableUsers = false;` (already set). Without it, NixOS
does not enforce a declared password onto an account that already has one set
outside of config.

---

## Repository layout

```
nixos-x11-5/
├── flake.nix          # entry point — defines nixosConfigurations.x11-5
├── flake.lock         # pins nixpkgs version
├── .gitignore
├── README.md
├── modules/
│   └── common.nix     # shared: SSH key, user, base packages, firewall, nftables
└── hosts/
    └── x11-5/
        ├── default.nix                 # bootloader, hostname, stateVersion, tailscale
        ├── hardware-configuration.nix  # generated at install time — do not edit
        ├── networking.nix              # bridge br0 + static IP 192.168.8.80
        └── incus.nix                   # virtualisation.incus preseed
```

---

## Host details

| Property | Value |
|---|---|
| Hostname | `x11-5` |
| IP | `192.168.8.80` |
| IPMI BMC | `192.168.8.81` |
| Role | Incus hypervisor (containers + VMs) |
| SSH | `ssh user@192.168.8.80` |
| Incus UI | `https://192.168.8.80:8443` |
| NixOS | 26.05 (Yarara) |
| Incus | 7.1 (feature release) |

## Hardware

| Component | Detail |
|---|---|
| Board | Supermicro X11 |
| Disk | 240 GB SSD at `/dev/sda` |
| `/dev/sda1` | 1 GiB FAT32 — EFI boot |
| `/dev/sda2` | 60 GiB ext4 — NixOS root + /nix/store |
| `/dev/sda3` | ~178 GiB btrfs — Incus storage pool |

---

## End-to-end install procedure (fresh machine)

### Phase 1 — Workstation prep

#### 1.1 Clone the repo on pavi-mint

```
git clone git@github.com:fotografm/nixos-x11-5.git ~/repos/nixos-config
```

#### 1.2 Verify your SSH key is in modules/common.nix

```
grep authorizedKeys ~/repos/nixos-config/modules/common.nix
```

Should show your ed25519 public key. If not, add it before installing.

---

### Phase 2 — Boot the NixOS installer via IPMI

#### 2.1 Mount the NixOS ISO via IPMI virtual media (SMB)

The x11-5 BMC uses SMB virtual media. On pavi-mint:

```
sudo apt install samba -y && mkdir -p ~/share
```

Copy the NixOS 26.05 minimal ISO into `~/share/`.

Add to `/etc/samba/smb.conf` (inside `[global]`):
```
server min protocol = NT1
server max protocol = SMB3
```

Append at the end:
```
[share]
path = /home/user/share
browseable = yes
read only = no
guest ok = yes
force user = user
```

```
sudo systemctl restart smbd
smbclient //192.168.8.99/share -N -c "ls"   # verify ISO is visible
```

In the IPMI web UI at `http://192.168.8.81` → Virtual Media → CD-ROM Image:
- Share Host: `192.168.8.99`
- Path to Image: `\share\nixos-minimal-26.05-x86_64-linux.iso`

Click Mount, reboot x11-5, press **F11** at POST to pick the virtual CD.

#### 2.2 Enable SSH in the installer

In the IPMI console:

```
sudo -i
passwd          # set any temporary password
systemctl start sshd
ip -o -4 addr show   # note the DHCP IP
```

Then from pavi-mint: `ssh root@<installer-ip>`

#### 2.3 Check the NIC name

```
ip -o link
```

If the physical ethernet is not `eno1`, edit `hosts/x11-5/networking.nix` on
pavi-mint, change `physicalNic = "eno1"` to the real name, commit and push
before continuing.

#### 2.4 Wipe and partition the SSD

```
lsblk -o NAME,SIZE,TYPE,FSTYPE    # confirm /dev/sda is the right disk
wipefs -a /dev/sda
sgdisk --zap-all /dev/sda
blkdiscard -f /dev/sda            # optional TRIM
```

```
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 1GiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary 1GiB 61GiB
parted /dev/sda -- mkpart primary 61GiB 100%
```

#### 2.5 Format and mount

```
mkfs.fat -F32 -n BOOT /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
# /dev/sda3 left unformatted — Incus formats it as btrfs on first boot
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
```

#### 2.6 Generate hardware-configuration.nix

```
nixos-generate-config --root /mnt
```

On pavi-mint, copy it into the repo and push:

```
scp root@<installer-ip>:/mnt/etc/nixos/hardware-configuration.nix \
    ~/repos/nixos-config/hosts/x11-5/hardware-configuration.nix
cd ~/repos/nixos-config
git add hosts/x11-5/hardware-configuration.nix
git commit -m "Add hardware-configuration.nix for x11-5"
git push
```

#### 2.7 Install

Copy the repo to the installer (avoids GitHub auth inside installer):

```
scp -r ~/repos/nixos-config root@<installer-ip>:/tmp/nixos-config
```

In the installer SSH session:

```
nixos-install --flake /tmp/nixos-config#x11-5 --no-root-passwd
umount -R /mnt
```

Unmount the ISO in IPMI, then `reboot`.

---

### Phase 3 — Post-install

#### 3.1 SSH in

```
ssh user@192.168.8.80
```

#### 3.2 Verify Incus

```
incus version
incus storage list      # should show default btrfs pool on /dev/sda3
incus profile show default
```

#### 3.3 Set up GitHub access on x11-5 (for on-machine rebuilds)

```
ssh-keygen -t ed25519 -C "x11-5" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Add the printed key as a read-only deploy key in GitHub:
Settings → Deploy keys on `fotografm/nixos-x11-5` → Add deploy key.

```
mkdir -p ~/repos
git clone git@github.com:fotografm/nixos-x11-5.git ~/repos/nixos-config
```

Future rebuilds from x11-5:

```
cd ~/repos/nixos-config && git pull && sudo nixos-rebuild switch --flake .#x11-5
```

---

## Using Incus

### Launch a Debian container with a static LAN IP

```
incus launch images:debian/12 mycontainer
```

Set a static IP inside the container (br0 is unmanaged so `ipv4.address` device
config doesn't work — set it inside the guest instead):

```
incus exec mycontainer -- bash -c 'cat > /etc/systemd/network/eth0.network <<EOF
[Match]
Name=eth0

[Network]
Address=192.168.8.126/24
Gateway=192.168.8.1
DNS=192.168.8.70
DNS=1.1.1.1
EOF'
incus restart mycontainer
```

### Launch a VM

```
incus launch images:debian/12 myvm --vm
```

### USB passthrough (e.g. RTL-SDR)

```
lsusb    # find vendorid and productid
incus config device add mycontainer rtlsdr usb vendorid=0bda productid=2838
incus config device set mycontainer rtlsdr required=false
```

Common SDR IDs:

| Device | vendorid | productid |
|---|---|---|
| RTL-SDR V4 | `0bda` | `2838` |
| Airspy Mini | `1d50` | `60a1` |
| Airspy HF+ | `03eb` | `800c` |
| HackRF One | `1d50` | `6089` |
| RSPdx | `1df7` | `3000` |

### Snapshots

```
incus snapshot create mycontainer snap1
incus snapshot restore mycontainer snap1
incus copy mycontainer mycontainer-clone
```

### Incus web UI

```
incus remote add x11-5 https://192.168.8.80:8443
# generates a trust token prompt — on x11-5: incus config trust add --name pavi-mint
```

---

## Troubleshooting

**Lost SSH after rebuild** — use IPMI (192.168.8.81) to access console. Select
previous generation at the systemd-boot menu or run `sudo nixos-rebuild switch --rollback`.

**Incus preseed didn't apply** — if the daemon was already initialised manually:

```
sudo systemctl stop incus.service incus.socket
sudo rm -rf /var/lib/incus/database
sudo systemctl start incus.service
```

**Container can't reach LAN** — verify `br0` is up (`ip -br link show br0`),
container is attached to br0 (`incus config show <name> --expanded | grep parent`).

**Incus web UI unreachable** — `sudo ss -ltn | grep 8443` to check if daemon is
listening. If not: `sudo systemctl status incus`.
