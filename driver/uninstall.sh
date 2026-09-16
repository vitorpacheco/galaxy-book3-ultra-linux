#!/bin/bash
# Remove the DKMS driver; the in-tree ov02c10 is used again after reboot.
set -e
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }

dkms remove -m ov02c10-galaxybook -v 1.0 --all || true
rm -rf /usr/src/ov02c10-galaxybook-1.0
echo "Removed. Reboot to load the in-tree driver."
