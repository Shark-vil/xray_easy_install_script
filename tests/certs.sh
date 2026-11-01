#!/usr/bin/env bash
# Run with bash tests/certs.sh; all system paths and service commands are isolated.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TEST_ROOT="$tmp"
sed "s|/etc/|$tmp/etc/|g; s|/usr/local/bin/xvei|$tmp/xvei|g" lib/certs.sh > "$tmp/certs.sh"
source "$tmp/certs.sh"
HY2_CONFIG="$tmp/no-hysteria"
HY2_SERVICE=hysteria-server
mode=letsencrypt
state_get() {
    case "$1" in
        domain) echo example.org ;;
        cert.mode) echo "$mode" ;;
        email) echo admin@example.org ;;
    esac
}
log() { :; }
die() { echo "$*" >&2; exit 1; }
check_service() { :; }
groupadd() { echo "$*" >> "$tmp/groups"; }
systemctl() { echo "$*" >> "$tmp/services"; }
# Record security options; copy without requiring root/group creation.
install() {
    echo "$*" >> "$tmp/installs"
    local args=() mode= dir=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o|-g) shift 2 ;;
            -m) mode="$2"; shift 2 ;;
            -d) dir=1; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done
    if [ "$dir" = 1 ]; then
        mkdir -p "${args[0]}"
    else
        cp "${args[@]}" || return 1
    fi
    chmod "$mode" "${args[${#args[@]}-1]}"
}
py() { printf '%s\n' "$*" >> "$tmp/meta"; }
_cert_enable_renew_timer() { :; }
_cert_install_deploy_hook() { :; }
mkdir -p "$tmp/etc/letsencrypt/live/example.org"
src="$tmp/etc/letsencrypt/live/example.org"
dst="$tmp/etc/xray/certs"
echo chain1 > "$src/fullchain.pem"
echo key1 > "$src/privkey.pem"
cert_issue
cmp "$src/fullchain.pem" "$dst/fullchain.pem"
cmp "$src/privkey.pem" "$dst/privkey.pem"
grep -q -- "-d -m 750 -o root -g xraycert $dst" "$tmp/installs"
grep -q -- "-m 640 -o root -g xraycert $src/privkey.pem $dst/privkey.pem" "$tmp/installs"
grep -q SupplementaryGroups=xraycert "$tmp/etc/systemd/system/xray.service.d/20-xvei-certificates.conf"
grep -q -- "--cert-fullchain $dst/fullchain.pem" "$tmp/meta"
echo key2 > "$src/privkey.pem"
RENEWED_LINEAGE="$tmp/etc/letsencrypt/live/other.org" cert_renew_hook_run
grep -q key1 "$dst/privkey.pem"
RENEWED_LINEAGE="$src" cert_renew_hook_run
cmp "$src/privkey.pem" "$dst/privkey.pem"
grep -q 'restart xray.service' "$tmp/services"
# Copy failures must prevent service restarts.
: > "$tmp/services"
mv "$src/privkey.pem" "$src/privkey.saved"
if cert_renew_hook_run 2>/dev/null; then exit 1; fi
[ ! -s "$tmp/services" ]
mv "$src/privkey.saved" "$src/privkey.pem"
# Removing only xvei must preserve copying in the generated standalone hook.
mkdir -p "$tmp/etc/letsencrypt/renewal-hooks/deploy"
touch "$tmp/etc/letsencrypt/renewal-hooks/deploy/xvei-restart.sh"
cert_hook_standalone
hook="$tmp/etc/letsencrypt/renewal-hooks/deploy/restart-xray.sh"
bash -n "$hook"
export -f install systemctl
export tmp
echo key3 > "$src/privkey.pem"
RENEWED_LINEAGE="$src" bash "$hook"
cmp "$src/privkey.pem" "$dst/privkey.pem"
echo 'certificate checks passed'
