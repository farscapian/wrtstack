# Configuration

## Env file format

```bash
# env/<router>.env -- sourced as a bash script

# Mode B fallback (commented out while a backup exists)
#HOSTNAME=gw
#LAN_IP=192.168.4.2
#SSH_PUBKEY="ssh-ed25519 AAAA..."

PACKAGES="hostapd-openssl dawn ..."
PACKAGES_REMOVE="wpad-basic-wolfssl ..."
```

## Accepted variables

`HOSTNAME`, `LAN_IP`, `SSH_PUBKEY`, `PACKAGES`, `PACKAGES_REMOVE`. Any other variable is silently available to the script (sourced directly) -- keep env files minimal.

## Git tracking

| Track | Do not track |
|-------|--------------|
| `env/*.env` (package lists, optional identity) | `backups/**/*.tar.gz` (may contain PSKs, VPN keys) |