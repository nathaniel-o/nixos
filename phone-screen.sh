# Extra Qtile screen, shown on an Android phone over a USB cable.
# vkms adds the screen. wayvnc serves only that screen. adb reverse
# carries VNC on the cable, so the phone connects to 127.0.0.1.
port=5900

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf 'Usage: phone-screen [WIDTHxHEIGHT]\n'
  printf 'Adds a virtual screen and tunnels it to a phone over USB.\n'
  printf 'Default size is 720x1600, the Moto G Power panel.\n'
  printf 'Landscape example: phone-screen 1600x720\n'
  exit 0
fi

res="${1:-720x1600}"
if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
  printf 'Use a resolution like 720x1600 (got %s).\n' "$res" >&2
  exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'phone-screen needs the Qtile Wayland session.\n' >&2
  exit 1
fi

vkms_output=
vnc_pid=

cleanup() {
  if [[ -n "${vnc_pid}" ]] && kill -0 "$vnc_pid" 2>/dev/null; then
    kill "$vnc_pid" 2>/dev/null || true
    wait "$vnc_pid" 2>/dev/null || true
  fi
  if [[ -n "${vkms_output}" ]]; then
    wlr-randr --output "$vkms_output" --off >/dev/null 2>&1 || true
  fi
  adb reverse --remove "tcp:${port}" >/dev/null 2>&1 || true
}
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

vkms_loaded=0
for card in /sys/class/drm/card*-Virtual-* /sys/class/drm/card*-VKMS-*; do
  if [[ -e "$card" ]]; then
    vkms_loaded=1
    break
  fi
done
if [[ "$vkms_loaded" -eq 0 ]]; then
  printf 'Loading the virtual display. Enter your login password.\n'
  if ! /run/wrappers/bin/sudo /run/current-system/sw/bin/modprobe vkms; then
    printf 'Could not load the virtual display driver.\n' >&2
    exit 1
  fi
fi

for ((i = 0; i < 40; i++)); do
  vkms_output="$(
    wlr-randr --json | python3 -c '
import json, sys
for output in json.load(sys.stdin):
    name = output.get("name", "")
    if "VKMS" in name or name.startswith("Virtual"):
        print(name)
        break
'
  )"
  if [[ -n "${vkms_output}" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -n "${vkms_output}" ]]; then
  wlr-randr --output "$vkms_output" --on --custom-mode "$res" --right-of eDP-1
  qtile cmd-obj -f reconfigure_screens >/dev/null 2>&1 || true
else
  printf 'The virtual display driver is loaded, but Qtile did not add a screen.\n' >&2
  printf 'Qtile has to be restarted once to notice it. That closes open apps.\n' >&2
  vkms_output=
  exit 1
fi

cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/phone-screen"
mkdir -p "$cfgdir"
chmod 700 "$cfgdir"
if [[ ! -s "$cfgdir/tls_key.pem" || ! -s "$cfgdir/tls_cert.pem" ]]; then
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$cfgdir/tls_key.pem" \
    -out "$cfgdir/tls_cert.pem" \
    -days 3650 -nodes -subj /CN=phone-screen >/dev/null 2>&1
  chmod 600 "$cfgdir/tls_key.pem" "$cfgdir/tls_cert.pem"
fi
if [[ ! -s "$cfgdir/rsa_key.pem" ]]; then
  openssl genrsa -traditional -out "$cfgdir/rsa_key.pem" 2048 >/dev/null 2>&1
  chmod 600 "$cfgdir/rsa_key.pem"
fi
cat >"$cfgdir/wayvnc.config" <<EOF
use_relative_paths=true
address=127.0.0.1
port=${port}
enable_auth=true
password=Password
allow_broken_crypto=true
relax_encryption=true
certificate_file=tls_cert.pem
private_key_file=tls_key.pem
rsa_private_key_file=rsa_key.pem
EOF
chmod 600 "$cfgdir/wayvnc.config"

wayvnc \
  --config "$cfgdir/wayvnc.config" \
  --output "$vkms_output" \
  --render-cursor \
  --disable-resizing \
  --max-fps 30 \
  --keyboard us &
vnc_pid=$!

printf 'Extra screen %s at %s, to the right of the laptop.\n' "$vkms_output" "$res"
printf 'Leave this window open. Closing it turns the extra screen off.\n'

ready=0
for ((i = 0; i < 50; i++)); do
  if ! kill -0 "$vnc_pid" 2>/dev/null; then
    printf 'wayvnc stopped before it was listening.\n' >&2
    vnc_pid=
    exit 1
  fi
  if ss -H -ltn | grep -Eq "127.0.0.1:${port}([^0-9]|$)"; then
    ready=1
    break
  fi
  sleep 0.1
done

if [[ "$ready" -ne 1 ]]; then
  printf 'VNC port %s did not open.\n' "$port" >&2
  exit 1
fi

printf 'Plug the phone in with a data cable and allow USB debugging.\n'
printf 'If it only charges, choose File transfer in the USB notification.\n'

while true; do
  if ! kill -0 "$vnc_pid" 2>/dev/null; then
    printf 'The virtual screen stopped.\n' >&2
    vnc_pid=
    exit 1
  fi
  adb wait-for-device
  if adb devices | grep -q $'\tdevice$'; then
    break
  fi
  printf 'Tap Allow on the phone USB debugging prompt.\n'
  sleep 2
done

adb reverse "tcp:${port}" "tcp:${port}"

printf '\nIn the phone VNC app, connect to 127.0.0.1 port %s.\n' "$port"
printf 'Password: Password\n'
printf 'Move the pointer past the right edge of the laptop. That region is the phone.\n'
printf 'Super+period focuses the other screen. Super+Shift+period sends the focused window there.\n'

while kill -0 "$vnc_pid" 2>/dev/null; do
  if adb devices | grep -q $'\tdevice$'; then
    adb reverse "tcp:${port}" "tcp:${port}" >/dev/null 2>&1 || true
  else
    printf 'Phone unplugged. Plug it back in and allow USB debugging.\n'
    adb wait-for-device || true
  fi
  sleep 3
done
