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
                 android-tools-adb brightnessctl
```

---

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

## Troubleshooting

| Symptom | Fix |
|---|---|
| “5 GHz could not start” | Card/driver restriction — see the section above; use 2.4 GHz + USB Tether |
| Hotspot times out | `nmcli connection up PopHotspot` in a terminal to read the real error; the profile is recreated on every toggle |
| USB Tether won't start | Check the cable + USB debugging (`adb devices` must show `device`), then retry; the app installs the phone client automatically |
| Phone shows VPN but no internet | Relay not running — toggle the switch off/on (see `~/.config/pop-hotspot/tether.log`) |
| An app says “no connection” although the tether works | Android reports the tunnel as a *separate* network, so apps that read the network state (Chrome, Play Store banners) may disagree while traffic flows fine. Leave Wi-Fi/mobile data on so Android has a validated network to report, and restart the app that complains. Verify the tunnel from the log: connections from `10.0.0.2` to `:80`/`:443`. |
