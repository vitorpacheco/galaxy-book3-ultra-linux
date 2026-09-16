#!/bin/bash
# Temporarily load the freshly built ov02c10.ko (until reboot), without
# installing it. Close camera apps first; PipeWire is restarted here.
# Module parameters can be passed: sudo ./test-load.sh frame_rate=20
set -e
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"
[ -f ov02c10.ko ] || { echo "ov02c10.ko not built, run make in driver/"; exit 1; }

user_systemctl() {
	[ -n "$SUDO_USER" ] && systemctl --user -M "$SUDO_USER@" "$@"
}
PW_UNITS="wireplumber pipewire-pulse pipewire pipewire-pulse.socket pipewire.socket"
user_systemctl stop $PW_UNITS || true

# rmmod, not modprobe -r: stale softdeps (ivsc-camera.conf) make modprobe -r fail
for m in intel_ipu6_isys ov02c10; do
	if lsmod | grep -q "^$m "; then rmmod "$m"; fi
done
for m in $(modinfo -F depends ./ov02c10.ko | tr , ' '); do
	modprobe "$m"
done
insmod ./ov02c10.ko "$@"
modprobe intel_ipu6
modprobe intel_ipu6_isys
sleep 2
user_systemctl start $PW_UNITS || true
dmesg | grep -E 'ov02c10|intel-ipu6|ipu6_isys' | tail -8
