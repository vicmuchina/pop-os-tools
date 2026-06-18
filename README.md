# Pop OS Tools

A collection of utility apps for Pop!_OS.

## Apps

### Pop Hotspot
A GUI app to create and manage a Wi-Fi hotspot (sharing Ethernet/Internet connection). Features:
- Start/stop hotspot with a toggle
- View connected clients (MAC, IP, signal)
- Block/unblock clients
- Change SSID, password, and Wi-Fi band

### Pop Brightness
A GUI app to adjust screen brightness. Features:
- Slider to set brightness (1-100%)
- **+1%** and **-1%** fine-tune buttons

## Installation

```bash
git clone https://github.com/vicmuchina/pop-os-tools.git
cd pop-os-tools

# Copy the app scripts
cp pop-hotspot pop-brightness ~/.local/bin/
chmod +x ~/.local/bin/pop-hotspot ~/.local/bin/pop-brightness

# Copy desktop entries (appears in app menu)
cp pop-hotspot.desktop pop-brightness.desktop ~/.local/share/applications/

# Refresh app menu
update-desktop-database ~/.local/share/applications/

# Brightness app needs sudo access — install this rule:
echo "$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/brightnessctl" \
  | sudo tee /etc/sudoers.d/brightnessctl
```

## Dependencies

- **Python 3** + `PyGObject` (`python3-gi`)
- **NetworkManager** (`nmcli`) — for Pop Hotspot
- **`brightnessctl`** — for Pop Brightness

Install them:

```bash
sudo apt install python3-gi brightnessctl network-manager
```
