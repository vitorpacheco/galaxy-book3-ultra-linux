#!/bin/bash
# System part (run with sudo):
#  - ov02c10-galaxybook webcam driver (DKMS, rebuilt on kernel updates)
#  - libcamera tuning file
#  - webcam frame rate (system/modprobe.d/ov02c10.conf)
#  - --no-analog-audio: hide a dead ALC298 analog codec (see README)
set -e
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=ov02c10-galaxybook
VERSION=1.0
SRC=/usr/src/$NAME-$VERSION
NO_ANALOG=0
for a in "$@"; do
	case "$a" in
	--no-analog-audio) NO_ANALOG=1 ;;
	*) echo "unknown option $a"; exit 1 ;;
	esac
done

command -v dkms >/dev/null || { echo "install dkms and the kernel headers first (e.g. pacman -S dkms linux-omarchy-headers)"; exit 1; }

echo "== Webcam driver (DKMS)"
# Older community packages build a module with the same name
for old in ov02c10-26mhz ov02c10; do
	for v in $(dkms status -m "$old" 2>/dev/null | sed -n 's|^[^/]*/\([^,:]*\).*|\1|p' | sort -u); do
		dkms remove -m "$old" -v "$v" --all || true
		rm -rf "/usr/src/$old-$v"
	done
done
if dkms status -m "$NAME" -v "$VERSION" | grep -q .; then
	dkms remove -m "$NAME" -v "$VERSION" --all
fi
rm -rf "$SRC"
install -d "$SRC"
install -m644 "$HERE/driver/ov02c10.c" "$HERE/driver/Makefile" "$HERE/driver/dkms.conf" "$SRC/"
dkms add -m "$NAME" -v "$VERSION"
for k in /usr/lib/modules/*/build; do
	kver=$(basename "$(dirname "$k")")
	dkms install -m "$NAME" -v "$VERSION" -k "$kver" || echo "  build failed for $kver"
done

echo "== libcamera tuning"
install -Dm644 "$HERE/tuning/ov02c10.yaml" /etc/libcamera/ipa/simple/ov02c10.yaml
f=/usr/share/libcamera/ipa/simple/ov02c10.yaml
if [ -e "$f" ] && ! pacman -Qo "$f" >/dev/null 2>&1; then
	rm -v "$f"
fi

echo "== Webcam frame rate"
[ -e /etc/modprobe.d/ov02c10.conf ] || install -m644 "$HERE/system/modprobe.d/ov02c10.conf" /etc/modprobe.d/

if [ $NO_ANALOG = 1 ]; then
	echo "== Audio: SOF driver without the analog codec"
	install -m644 "$HERE/system/modprobe.d/sof-audio.conf" /etc/modprobe.d/
	install -m644 "$HERE/system/modprobe.d/galaxybook3-audio-no-analog.conf" /etc/modprobe.d/galaxybook3-audio.conf
fi

echo
echo "Done. Now run ./install-user.sh (without sudo) and reboot."
