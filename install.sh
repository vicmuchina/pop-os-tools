#!/usr/bin/env bash
# Pop OS Tools installer — installs Pop Hotspot (+ Pop Brightness) and the
# optional USB-tether engine used by the "USB Tether" switch.
#
#   ./install.sh                 install everything (apps + tether engine)
#   ./install.sh --no-tether     skip the Gnirehtet engine download
#   ./install.sh --no-brightness skip the brightnessctl sudoers rule
set -euo pipefail

GNIREHTET_VERSION="v2.5.1"
GNIREHTET_ZIP="gnirehtet-rust-linux64-${GNIREHTET_VERSION}.zip"
GNIREHTET_URL="https://github.com/Genymobile/gnirehtet/releases/download/${GNIREHTET_VERSION}/${GNIREHTET_ZIP}"
GNIREHTET_SHA256="dee55499ca4fef00ce2559c767d2d8130163736d43fdbce753e923e75309c275"

BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
TETHER_DIR="$HOME/.local/share/pop-hotspot/gnirehtet"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_TETHER=1
WITH_BRIGHTNESS_SUDO=1
for arg in "$@"; do
    case "$arg" in
        --no-tether)     WITH_TETHER=0 ;;
        --no-brightness) WITH_BRIGHTNESS_SUDO=0 ;;
        -h|--help)       sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- dependencies
say "Checking dependencies"
missing=()
for cmd in nmcli iw rfkill iptables curl unzip; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
python3 - <<'PY' >/dev/null 2>&1 || missing+=("python3-gi (PyGObject)")
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
PY
if [ "${#missing[@]}" -gt 0 ]; then
    warn "missing: ${missing[*]}"
    echo "    sudo apt install python3-gi network-manager iw rfkill iptables curl unzip"
    die "install the packages above and re-run"
fi
echo "    all present"

# ------------------------------------------------------------------- the apps
say "Installing apps into $BIN_DIR"
mkdir -p "$BIN_DIR" "$DESKTOP_DIR"
install -m 755 "$SRC_DIR/pop-hotspot"  "$BIN_DIR/pop-hotspot"
if [ -f "$SRC_DIR/pop-brightness" ]; then
    install -m 755 "$SRC_DIR/pop-brightness" "$BIN_DIR/pop-brightness"
fi
install -m 644 "$SRC_DIR/pop-hotspot.desktop" "$DESKTOP_DIR/pop-hotspot.desktop"
if [ -f "$SRC_DIR/pop-brightness.desktop" ]; then
    install -m 644 "$SRC_DIR/pop-brightness.desktop" "$DESKTOP_DIR/pop-brightness.desktop"
fi
if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$DESKTOP_DIR" || true
fi
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH — add: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ------------------------------------------------------------- USB tether engine
if [ "$WITH_TETHER" -eq 1 ]; then
    say "Installing USB-tether engine (Gnirehtet ${GNIREHTET_VERSION})"
    if [ -x "$TETHER_DIR/gnirehtet" ] && [ -f "$TETHER_DIR/gnirehtet.apk" ]; then
        echo "    already installed at $TETHER_DIR"
    else
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        echo "$GNIREHTET_SHA256  $tmp/$GNIREHTET_ZIP" > "$tmp/SUM"
        curl -fsSL -o "$tmp/$GNIREHTET_ZIP" "$GNIREHTET_URL" || die "download failed"
        ( cd "$tmp" && sha256sum -c SUM >/dev/null ) || die "checksum mismatch — refusing to install"
        unzip -qo "$tmp/$GNIREHTET_ZIP" -d "$tmp"
        mkdir -p "$TETHER_DIR"
        install -m 755 "$tmp/gnirehtet-rust-linux64/gnirehtet"     "$TETHER_DIR/gnirehtet"
        install -m 644 "$tmp/gnirehtet-rust-linux64/gnirehtet.apk" "$TETHER_DIR/gnirehtet.apk"
        echo "    installed to $TETHER_DIR (sha256 verified)"
    fi

    if command -v adb >/dev/null; then
        if adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
            say "Phone detected — installing the client APK on it"
            if ( cd "$TETHER_DIR" && ./gnirehtet install >/dev/null 2>&1 ); then
                echo "    client installed (the app installs it automatically too)"
            else
                warn "could not install the client — the app retries when you enable USB Tether"
            fi
        else
            echo "    no phone on USB right now — the app installs the client when you first enable USB Tether"
        fi
    else
        warn "adb not found (apt install android-tools-adb) — USB tether needs it"
    fi
else
    say "Skipping USB-tether engine (--no-tether)"
fi

# ------------------------------------------------------------------- brightness
if [ "$WITH_BRIGHTNESS_SUDO" -eq 1 ] && [ -f "$SRC_DIR/pop-brightness" ]; then
    if [ -f /etc/sudoers.d/brightnessctl ]; then
        echo "    brightness sudoers rule already present"
    else
        say "Pop Brightness needs passwordless brightnessctl"
        printf '    rule: %s ALL=(ALL) NOPASSWD: /usr/bin/brightnessctl\n' "$(whoami)"
        printf '    add it now? [y/N] '
        read -r reply </dev/tty || reply=n
        case "$reply" in
            [yY]*) echo "$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/brightnessctl" \
                       | sudo tee /etc/sudoers.d/brightnessctl >/dev/null \
                   && sudo chmod 440 /etc/sudoers.d/brightnessctl \
                   && echo "    added"
                   ;;
            *) echo "    skipped" ;;
        esac
    fi
fi

# ------------------------------------------------------------------ AP backend
# The hotspot's preferred backend is hostapd. NetworkManager builds its AP on
# wpa_supplicant's AP mode, which advertises no legacy 802.11b rates and only
# basic capabilities — many TVs (Vitron, Android TV, consoles) simply never
# associate with it. hostapd beacons properly, so it is the default.
if [ -f "$SRC_DIR/pop-hotspot-ap" ]; then
    say "Installing the hostapd AP backend (TV-compatible)"
    missing=""
    for pkg in hostapd dnsmasq; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
    done
    if [ -n "$missing" ]; then
        printf '    missing:%s — install now? [Y/n] ' "$missing"
        read -r reply </dev/tty || reply=n
        case "$reply" in
            [nN]*) echo "    skipped — the app will fall back to NetworkManager" ;;
            *)     sudo apt-get install -y $missing ;;
        esac
    fi
    sudo install -m 755 "$SRC_DIR/pop-hotspot-ap" /usr/local/sbin/pop-hotspot-ap
    sudo mkdir -p /etc/systemd/system /etc/polkit-1/rules.d
    sed "s|@HOME@|$HOME|" "$SRC_DIR/systemd/pop-hotspot-ap.service" \
        | sudo tee /etc/systemd/system/pop-hotspot-ap.service >/dev/null
    sed "s|@USER@|$(whoami)|" "$SRC_DIR/polkit/49-pop-hotspot-ap.rules" \
        | sudo tee /etc/polkit-1/rules.d/49-pop-hotspot-ap.rules >/dev/null
    sudo systemctl daemon-reload
    echo "    installed: /usr/local/sbin/pop-hotspot-ap + pop-hotspot-ap.service"
    echo "    the app toggles it with no password (polkit rule scoped to that unit)"
    echo "    want it on at boot?  sudo systemctl enable pop-hotspot-ap"
fi

# ------------------------------------------------------------------- casting
# "Cast to TV" needs gnome-network-displays (Miracast), and NetworkManager must
# keep its hands off the Wi-Fi P2P device or the caster cannot create a P2P link.
if [ -f "$SRC_DIR/pop-cast" ]; then
    say "Installing screen casting (Miracast)"
    dpkg -s gnome-network-displays >/dev/null 2>&1 || {
        printf '    gnome-network-displays is missing — install now? [Y/n] '
        read -r reply </dev/tty || reply=n
        case "$reply" in
            [nN]*) echo "    skipped — the Cast button will not work" ;;
            *)     sudo apt-get install -y gnome-network-displays ;;
        esac
    }
    install -m 755 "$SRC_DIR/pop-cast" "$HOME/.local/bin/pop-cast"
    if [ -f /etc/NetworkManager/conf.d/99-p2p-unmanaged.conf ]; then
        echo "    P2P already reserved for the caster"
    else
        sudo install -m 644 "$SRC_DIR/nm-conf/99-p2p-unmanaged.conf" \
             /etc/NetworkManager/conf.d/99-p2p-unmanaged.conf
        sudo nmcli general reload >/dev/null 2>&1 || true
        echo "    reserved Wi-Fi P2P for the caster (NetworkManager 1.44+ would steal it)"
    fi
    mkdir -p "$HOME/.config/xdg-desktop-portal"
    if [ ! -f "$HOME/.config/xdg-desktop-portal/portals.conf" ]; then
        printf '[preferred]\nscreencast=cosmic\nscreen-cast=cosmic\nremote-desktop=cosmic\n' \
            > "$HOME/.config/xdg-desktop-portal/portals.conf"
        echo "    pinned ScreenCast to the COSMIC portal backend"
    fi
fi

say "Done."
echo "    Pop Hotspot  : launch from your app menu, or run: pop-hotspot"
echo "    USB tether   : toggle it inside Pop Hotspot (needs the USB cable + USB debugging)"
