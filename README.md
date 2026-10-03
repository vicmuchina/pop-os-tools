# Pop OS Tools

A collection of utility apps for Pop!_OS.

| App | What it does |
|---|---|
| **Pop Hotspot** | Create and manage a Wi-Fi hotspot from your Ethernet connection — plus a **USB Tether** switch that gives your phone internet *over the cable*. |
| **Pop Brightness** | Brightness slider with **+1%** / **-1%** fine-tune buttons. |

---

## Pop Hotspot

A GTK3 GUI over NetworkManager (`nmcli`) with a genuine answer to the “Wi-Fi dies
when Bluetooth is on” problem.

**Hotspot**
- Start/stop with a toggle, live status
- Connected clients: MAC, IP, signal, TX/RX
- Block / unblock clients (deauth + iptables), persisted in `blocked.json`
- SSID, password, **band** (Auto / 2.4 GHz / 5 GHz) and **channel** selection
- Wi-Fi interface is auto-detected, so a USB Wi-Fi dongle works too

**USB Tether** (the Bluetooth fix)
- Shares this laptop's Ethernet internet with the phone **over the USB cable**
- No Wi-Fi involved, so Bluetooth keeps the whole 2.4 GHz band to itself
- Uses [Gnirehtet](https://github.com/Genymobile/gnirehtet) (relay on the laptop,
  VPN client on the phone) — **no root** needed on either device
- Shows a live `N open connections` counter, optional “keep running after the
  window closes”

**5 GHz diagnostics**
- A status line that reports whether the card can actually run a 5 GHz AP
- `Prepare / check 5 GHz (admin)` button: privileged scan that dumps
  `iw scan` / `iw reg get` / `iw list` / `dmesg` to `/tmp/pop-hotspot-5ghz.txt`

### Install

```bash
git clone https://github.com/vicmuchina/pop-os-tools.git
cd pop-os-tools
./install.sh                  # add --no-tether to skip the tether engine
```

The installer verifies dependencies, copies the apps to `~/.local/bin`, installs the
desktop entries, downloads the Gnirehtet engine (SHA-256 verified) to
`~/.local/share/pop-hotspot/gnirehtet/`, and installs the phone client if a device
is attached.

### Dependencies

```bash
sudo apt install python3-gi network-manager iw rfkill iptables curl unzip \
                 android-tools-adb brightnessctl hostapd dnsmasq
```

### TV-compatible access point (hostapd)

NetworkManager builds its hotspot on **wpa_supplicant's AP mode**, which is the
least compatible AP implementation there is. Some clients — smart TVs in
particular — **never even try to associate** with it. That is not a password or
band problem: the AP's beacons lack the legacy 802.11b/g rate set and basic
capability flags those clients expect, so they silently ignore the network
(meanwhile phones and laptops connect fine).

Pop Hotspot therefore ships a second backend: a real **hostapd** access point
plus `dnsmasq` for DHCP/DNS and iptables NAT, controlled by the app's switch.

* `pop-hotspot-ap` — the AP controller (`start` / `stop` / `status`), installed to `/usr/local/sbin` (root-owned).
* `systemd/pop-hotspot-ap.service` — runs it as root (`Type=oneshot`, `RemainAfterExit=yes`).
* `polkit/49-pop-hotspot-ap.rules` — lets your desktop user start/stop **only** that unit, so the app toggles the hotspot with **no password prompt**.

Pick the backend in **Settings → AP backend**:

| Backend | Works best with |
|---|---|
| `hostapd` (default) | everything, including TVs, Android TV sticks, consoles |
| `NetworkManager` | phones/laptops; use if hostapd isn't installed |

The SSID, password, band and channel from Settings are rendered into
`~/.local/share/pop-hotspot/hostapd.conf` every time the hotspot starts, so
**Save & Recreate** applies to both backends.

Useful commands:

```bash
/usr/local/sbin/pop-hotspot-ap status   # ap=yes, ssid, channel, client count
systemctl status pop-hotspot-ap                # service state (journal: root's logs)
sudo systemctl enable pop-hotspot-ap           # optional: bring the AP up at boot
```

If the TV still refuses: forget the network on the TV, then connect again. The
hostapd log (`/run/pop-hotspot/hostapd.log`) records every attempt, including
`EAPOL-4WAY-HS-COMPLETED` (success) or the exact reason for rejection.

---

### Cast to TV (Miracast)

**Start casting…** in the app (or run `pop-cast`) mirrors this screen to a
Miracast sink — most smart TVs — and brings the hotspot back when you close the
casting window.

What matters, learned the hard way:

* **Miracast is Wi-Fi Direct**: a direct laptop ↔ TV link. How the TV gets its
  internet (this hotspot, a router, an ethernet cable) does not affect casting.
* The Wi-Fi card can be an **access point *or* a P2P sender, never both**
  (`#{ AP, P2P-client, P2P-GO } <= 1`), so the hotspot is stopped while casting.
  The laptop itself stays online over its cable — only the AP goes down.
* A TV on this hotspot **loses internet during a cast** (its single radio leaves
  the AP to build the direct link). A TV cabled to the router keeps internet.
* The TV must be in its **Screen Mirroring / Miracast / Wireless Display** mode,
  otherwise it never advertises itself as a sink and the list stays empty.
* Requirements: `gnome-network-displays`, a P2P-capable wpa_supplicant, and a
  working **ScreenCast portal**. Check it with:

  ```bash
  busctl --user introspect org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop | grep ScreenCast
  ```

  On COSMIC the backend is `xdg-desktop-portal-cosmic`. `xdg-desktop-portal` can
  start *before* that backend registers and then expose **no ScreenCast at all**
  (which breaks every screen recorder, not just casting) — `systemctl --user
  restart xdg-desktop-portal` fixes it; we also pin it in
  `~/.config/xdg-desktop-portal/portals.conf`.
* NetworkManager ≥ 1.44 manages Wi-Fi P2P devices and breaks the caster, so
  `install.sh` installs `/etc/NetworkManager/conf.d/99-p2p-unmanaged.conf`.

## USB Tether — setup and use

1. Plug the phone in over USB and enable **USB debugging** on it.
2. Open Pop Hotspot and flip **USB Tether** on.
3. Accept the **VPN connection request** on the phone (first time only).

That's it — the phone now routes its traffic through the laptop's Ethernet.
The laptop's Wi-Fi can stay off entirely and Bluetooth is free of Wi-Fi contention.

Notes
- The USB cable must stay connected. If you unplug it, the tether goes stale:
  flip the switch off and on again to re-establish.
- DNS: the tunnel advertises `8.8.8.8` plus `1.1.1.1` as a fallback
  (`gnirehtet ... -d 8.8.8.8,1.1.1.1`), so a blocked resolver does not take the
  whole tunnel down. Override with the `tether_dns` key in `config.json`.
- Some apps may still claim there is **no connection** while the tunnel works
  perfectly (verified: a cache-busted `example.com` fetch left through the
  laptop's network). Android treats the VPN as a separate network, so apps that
  read the system network state, rather than actually testing traffic, can show
  offline banners. Leaving Wi-Fi or mobile data switched on gives Android a
  validated network to report (traffic still prefers the tunnel), and restarting
  the complaining app clears its cached state.
- Turning the switch off (or closing the window, unless you ticked
  *“Keep USB tether running after closing this window”*) stops the phone client
  **before** the relay — a live VPN with a dead relay would black-hole the phone's
  internet.
- Logs and state: `~/.config/pop-hotspot/tether.log`, `tether.pid`.

---

## Why “Bluetooth kills my Wi-Fi”, and what to do about it

Bluetooth and 2.4 GHz Wi-Fi share the same band (2.400–2.4835 GHz). A phone's
combo radio has to time-share, so an active A2DP stream can cut Wi-Fi throughput to
a few Mbps — worst on a 2.4 GHz link that is already capped (a 1×1 phone at 20 MHz
negotiates 72 Mbps PHY ≈ 30 Mbps usable, before Bluetooth takes its share).

Three real fixes, best first:

1. **USB Tether** (this app) — removes Wi-Fi from the phone entirely.
2. **5 GHz Wi-Fi** — moves Wi-Fi out of Bluetooth's band. Requires an AP that does
   5 GHz. Check what your card allows:

   ```bash
   iw list | sed -n '/Band 2:/,/Band 3:/p' | grep -E '^\s+\* 5[0-9]{3}'
   ```

   Channels marked **`no IR`** (no initiate radiation) cannot host an access point.
   If *every* 5 GHz channel says `no IR` while `iw reg get` shows your country
   allowing 5 GHz, the restriction is in the driver/firmware, not the regulatory
   database — the `Prepare / check 5 GHz (admin)` button documents exactly what
   your chip allows. Some Intel cards (e.g. **Wireless-N 7265 “Stone Peak 2 AGN”**)
   keep the whole 5 GHz band in `no IR` state on modern kernels, and newer kernels
   no longer expose the old `lar_disable` module parameter — for those, a cheap
   MT7612U / RTL8812AU USB dongle is the practical 5 GHz AP.
3. **Reduce Bluetooth airtime** — turn Bluetooth off when you need throughput, and
   prefer SBC/AAC over LDAC or aptX HD (high-bitrate codecs consume far more
   2.4 GHz airtime).

---

## Files

| Path | Purpose |
|---|---|
| `~/.local/bin/pop-hotspot` | the app |
| `~/.local/share/applications/pop-hotspot.desktop` | app-menu entry |
| `~/.config/pop-hotspot/config.json` | SSID, password, band, channel, tether preferences |
| `~/.config/pop-hotspot/blocked.json` | blocked client MACs |
| `~/.local/share/pop-hotspot/gnirehtet/` | tether engine + phone APK |
| `~/.local/bin/pop-cast` | cast this screen to a Miracast TV, restoring the hotspot afterwards |
| `/etc/NetworkManager/conf.d/99-p2p-unmanaged.conf` | keeps NM off the Wi-Fi P2P device so casting works |
| `~/.local/share/pop-hotspot/hostapd.conf` | generated AP config (SSID/password/channel) for the hostapd backend |
| `/usr/local/sbin/pop-hotspot-ap` | AP controller: hostapd + dnsmasq + NAT (installed by `install.sh`) |
| `/etc/systemd/system/pop-hotspot-ap.service` | runs the AP controller as root |
| `/etc/polkit-1/rules.d/49-pop-hotspot-ap.rules` | lets your user toggle that unit with no password |
| `/run/pop-hotspot/hostapd.log` | live AP log — every client association attempt |

## Troubleshooting

| Symptom | Fix |
|---|---|
| “5 GHz could not start” | Card/driver restriction — see the section above; use 2.4 GHz + USB Tether |
| Hotspot times out | `nmcli connection up PopHotspot` in a terminal to read the real error; the profile is recreated on every toggle |
| USB Tether won't start | Check the cable + USB debugging (`adb devices` must show `device`), then retry; the app installs the phone client automatically |
| Phone shows VPN but no internet | Relay not running — toggle the switch off/on (see `~/.config/pop-hotspot/tether.log`) |
| An app says “no connection” although the tether works | Android reports the tunnel as a *separate* network, so apps that read the network state (Chrome, Play Store banners) may disagree while traffic flows fine. Leave Wi-Fi/mobile data on so Android has a validated network to report, and restart the app that complains. Verify the tunnel from the log: connections from `10.0.0.2` to `:80`/`:443`. |
