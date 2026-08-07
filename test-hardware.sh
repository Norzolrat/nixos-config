#!/usr/bin/env bash
# Diagnostic matériel — MateBook GT sous NixOS live.
#   bash test-hardware.sh 2>&1 | tee /tmp/diag.txt
# Puis récupère /tmp/diag.txt sur la partition exFAT de ta clé Ventoy.

sec() { printf '\n\n═══ %s ═══\n\n' "$1"; }

sec "TACTILE — le point qui coince"
echo "--- Périphériques vus par libinput ---"
libinput list-devices 2>/dev/null | grep -iB2 -A12 'touch'
echo "--- Le noyau voit-il le FTSC1000 ? ---"
grep -iB2 -A6 'ftsc\|touch' /proc/bus/input/devices
echo "--- Messages noyau i2c-hid / multitouch ---"
sudo dmesg | grep -iE 'i2c[_-]hid|ftsc|hid-multitouch|hid_multitouch|thp'
echo "--- Ce que niri en fait ---"
niri msg outputs
niri msg --json outputs | grep -i name
echo
echo "Si libinput liste bien un périphérique tactile mais que rien ne réagit,"
echo "le problème est le mapping vers la sortie. Si le noyau ne le voit pas"
echo "du tout, c'est le pilote — le Huawei THP n'a pas d'équivalent Linux."

sec "AUDIO — haut-parleurs et micros"
cat /proc/asound/cards
aplay -l
arecord -l
sudo dmesg | grep -iE 'sof|snd_hda|alc256|firmware'
echo "Test sonore (Ctrl+C pour couper) :"
echo "  speaker-test -c2 -twav -l1"

sec "GRAPHIQUE"
lspci -nnk | grep -A3 -iE 'vga|display|3d'
echo "--- Pilote de rendu utilisé ---"
ls -l /dev/dri/by-path/
sudo dmesg | grep -iE 'i915|xe |drm'
command -v vainfo >/dev/null && vainfo 2>&1 | head -20

sec "THUNDERBOLT / eGPU"
boltctl list
lspci | grep -i nvidia || echo "Aucune NVIDIA sur le bus (eGPU débranché ou non énuméré)"
sudo dmesg | grep -iE 'thunderbolt|usb4'

sec "WEBCAM IPU6"
ls -l /dev/video* 2>/dev/null || echo "Aucun /dev/video — la caméra n'est pas montée"
sudo dmesg | grep -iE 'ipu6|ov0?[0-9]{4}|int3472|v4l2'
systemctl --user status v4l2-relayd 2>&1 | head -15

sec "WIFI / BLUETOOTH"
nmcli device
rfkill list
bluetoothctl list
sudo dmesg | grep -iE 'iwlwifi|btusb|firmware.*fail'

sec "ENTRÉES — clavier, touchpad, stylet"
libinput list-devices 2>/dev/null | grep -E '^Device|^Kernel|Tap-to-click|Natural scrolling'

sec "CAPTEURS / ÉNERGIE"
ls /sys/class/power_supply/
cat /sys/class/power_supply/BAT*/capacity 2>/dev/null
monitor-sensor --help >/dev/null 2>&1 && timeout 3 monitor-sensor
sensors 2>/dev/null | head -30
powerprofilesctl get 2>/dev/null

sec "LECTEUR SD / NVMe"
lsblk -f
lspci -nnk | grep -A3 -iE 'sd host|non-volatile'

sec "CE QUI A ÉCHOUÉ AU DÉMARRAGE"
systemctl --failed
systemctl --user --failed
echo "--- Erreurs noyau ---"
sudo journalctl -b -p err --no-pager | tail -40

sec "NIRI"
niri msg version
echo "--- Erreurs de config ou de session ---"
journalctl --user -b -u niri --no-pager 2>/dev/null | grep -iE 'error|warn' | tail -30

sec "FIN"
echo "Rapport complet : sudo hw-probe -all -save /tmp/probe"
