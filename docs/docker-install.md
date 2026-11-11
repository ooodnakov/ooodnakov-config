# Docker Engine install guide (Ubuntu and Arch)

`oooconf deps docker` installs Docker Engine on Linux using the distribution's
official procedure — apt repository on Ubuntu/Debian, `pacman` on Arch, dnf
repository on Fedora — then enables and starts `docker.service` and
`containerd.service`. macOS and Windows still require Docker Desktop manually.

This page is the manual reference and the fallback when automatic installation
cannot run (unsupported apt derivative, missing distro codename, no systemd, or
a failed package-manager transaction). `oooconf doctor` reports `docker` as a
required Linux tool and points here when installation failed.

Official references:

- Ubuntu: <https://docs.docker.com/engine/install/ubuntu/>
- Arch Linux: <https://wiki.archlinux.org/title/Docker>

## Ubuntu

Use Docker's official apt repository; distribution packages are frequently
older than the pinned CLI expectations in this repository.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" |
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Docker also publishes a convenience script at
<https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script>
for throwaway hosts. Prefer the repository steps above on machines managed by
this repo, because the script's contents are not pinned.

## Arch Linux

Arch ships Docker in the official repositories.

```bash
sudo pacman -S --needed docker docker-compose
# Optional UI used by the developer capability (also installable via brew):
sudo pacman -S --needed lazydocker
```

## Enable the daemon (both distributions)

```bash
sudo systemctl enable --now docker.service containerd.service
oooconf deps docker   # verifies the CLI and re-checks the units
docker info           # must succeed without sudo for a normal user session
```

## Run Docker without sudo

Membership in the `docker` group is root-equivalent on the host; grant it only
on machines where that tradeoff is acceptable.

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## Verify

```bash
docker --version
docker info
oooconf doctor        # dependencies.required must pass
```

If `docker info` fails with a permissions error, the group change has not
applied to the current session: log out and back in (or run `newgrp docker`).
If the daemon is not running, re-run the systemctl command above; on non-systemd
hosts start `dockerd` with your init system and enable the units manually.
