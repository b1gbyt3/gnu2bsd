# gnu2bsd

**GNU-first macOS compatibility layer that redirects Linux commands to safe macOS equivalents.**

`gnu2bsd` makes macOS friendlier for Linux users by preferring GNU tools over BSD defaults and mapping common Linux muscle-memory commands to macOS/Homebrew equivalents.

> Inspired by [pkill37/linuxify](https://github.com/pkill37/linuxify).

## GNU > BSD

`gnu2bsd` installs GNU tools with Homebrew and prioritizes their `gnubin` paths so the GNU versions are used first.

Examples:

```text
cat      -> GNU/coreutils
ls       -> GNU/coreutils
sed      -> gnu-sed
tar      -> gnu-tar
grep     -> GNU grep
awk      -> gawk
find     -> GNU findutils
make     -> GNU make
time     -> GNU time
which    -> GNU which
getopt   -> GNU getopt
indent   -> GNU indent
gpg      -> gnupg
tree     -> tree
```

The goal is simple:

```text
GNU tools first.
BSD tools only when needed.
```

## 308 mappings

A `308` mapping means the command is close enough to safely redirect and run.

```text
apt install jq        -> brew install jq
apt update            -> brew update
apt upgrade           -> brew update && brew upgrade

pacman -S jq          -> brew install jq
pacman -Syu           -> brew update && brew upgrade

dnf install jq        -> brew install jq
zypper in jq          -> brew install jq
apk add jq            -> brew install jq

systemctl start nginx -> brew services start nginx
service nginx restart -> brew services restart nginx

journalctl -f         -> log stream --style compact
journalctl -b         -> log show --last boot --style compact

lsblk                 -> diskutil list
lsusb                 -> system_profiler SPUSBDataType
lspci                 -> system_profiler SPPCIDataType
lscpu                 -> sysctl -a | grep machdep.cpu
free -h               -> vm_stat + sysctl + top memory summary

cat /proc/cpuinfo     -> sysctl CPU info
cat /proc/meminfo     -> vm_stat + sysctl hw.memsize
cat /etc/os-release   -> sw_vers-style macOS release info

ip addr               -> iproute2mac ip, or ifconfig fallback
ss -tulpn             -> sudo lsof -iTCP -sTCP:LISTEN -P -n

xdg-open .            -> open .
xclip                 -> pbcopy
xclip -o              -> pbpaste
xsel                  -> pbcopy
xsel -o               -> pbpaste
wl-copy               -> pbcopy
wl-paste              -> pbpaste

ldd ./binary          -> otool -L ./binary
nproc                 -> sysctl -n hw.ncpu
pidof name            -> pgrep -x name
```

Example output:

```text
308 Permanent Redirect: command "apt install jq" permanently moved to "brew install jq"
redirecting to: brew install jq
```

Then it runs the mapped command.

## 301 mappings

A `301` mapping means there is no safe direct equivalent. `gnu2bsd` explains the closest macOS command, but does not run it automatically.

```text
iptables -L      -> not a direct map, but closest concept is: sudo pfctl -sr
nft list ruleset -> not a direct map, but closest concept is: pfctl
ufw status       -> not a direct map, but closest concept is: socketfilterfw / pfctl

snap install app -> not a direct map, but try: brew search app
flatpak install  -> not a direct map, but try: brew search --cask app

modprobe module  -> not a direct map, but closest concept is: kmutil / kextload
lsmod            -> not a direct map, but try: kmutil showloaded

useradd name     -> not a direct map, but closest concept is: sysadminctl / dscl
usermod name     -> not a direct map, but closest concept is: dscl
userdel name     -> not a direct map, but closest concept is: sysadminctl -deleteUser / dscl

getenforce       -> not a direct map, but closest concept is: csrutil status
setenforce 0     -> not a direct map, SIP changes require macOS Recovery

update-grub      -> not a direct map, macOS does not use GRUB for normal boot
grub-install     -> not a direct map, macOS does not use GRUB for normal boot
mkinitcpio       -> not a direct map, not applicable on macOS
dracut           -> not a direct map, not applicable on macOS
```

Example output:

```text
301 Moved Permanently: command "iptables -L" permanently moved to "sudo pfctl -sr"
not auto-executing: mapping is conceptual, approximate, or not safely 1:1 compatible
BSD/macOS equivalent: sudo pfctl -sr
```

## Install

```sh
git clone https://github.com/YOUR_USERNAME/gnu2bsd.git
cd gnu2bsd
chmod +x gnu2bsd.sh
./gnu2bsd.sh
```

Restart your terminal, or reload your shell:

```sh
source ~/.zprofile
```

For Fish:

```fish
source ~/.config/fish/config.fish
```

## Help

```sh
gnu2bsd-help
```

## License

AGPL v3
