#!/bin/bash
# User part (run as your user): PipeWire/WirePlumber camera setup.
#  --no-analog-audio: also install the WirePlumber audio config that goes with
#                     install-system.sh --no-analog-audio
set -e
[ "$EUID" -ne 0 ] || { echo "run without sudo"; exit 1; }
HERE="$(cd "$(dirname "$0")/user" && pwd)"
BACKUP="$HOME/.config/galaxy-book3-ultra-backup/$(date +%Y%m%d-%H%M%S)"
NO_ANALOG=0
for a in "$@"; do
	case "$a" in
	--no-analog-audio) NO_ANALOG=1 ;;
	*) echo "unknown option $a"; exit 1 ;;
	esac
done

put() { # src dest
	if [ -e "$2" ] && ! cmp -s "$1" "$2"; then
		mkdir -p "$BACKUP/$(dirname "${2#$HOME/}")"
		cp -a "$2" "$BACKUP/${2#$HOME/}"
		echo "  backup: $2"
	fi
	install -Dm644 "$1" "$2"
	echo "  $2"
}

put "$HERE/pipewire/pipewire.conf.d/60-libcamera-front-camera.conf" "$HOME/.config/pipewire/pipewire.conf.d/60-libcamera-front-camera.conf"
put "$HERE/wireplumber/wireplumber.conf.d/90-camera-monitors.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/90-camera-monitors.conf"
put "$HERE/wireplumber/scripts/node/create-item.lua" "$HOME/.local/share/wireplumber/scripts/node/create-item.lua"
for s in pipewire wireplumber; do
	for f in 10-force-intel-gpu.conf 20-wait-camera-acl.conf; do
		put "$HERE/systemd/user/$s.service.d/$f" "$HOME/.config/systemd/user/$s.service.d/$f"
	done
done
if [ $NO_ANALOG = 1 ]; then
	put "$HERE/wireplumber/wireplumber.conf.d/55-sof-hdmi-ucm.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/55-sof-hdmi-ucm.conf"
fi

wp=$(pacman -Q wireplumber 2>/dev/null | awk '{print $2}')
case "$wp" in
0.5.17-*) ;;
*) echo "WARNING: create-item.lua is a patched copy of WirePlumber 0.5.17, you have $wp." ;;
esac

systemctl --user daemon-reload
echo
echo "Done. Restart PipeWire (systemctl --user restart pipewire pipewire-pulse wireplumber) or reboot."
echo "Firefox/Zen: set media.webrtc.camera.allow-pipewire = true (see user/zen/user.js)."
