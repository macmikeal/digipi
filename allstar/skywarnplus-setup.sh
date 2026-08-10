#!/usr/bin/env bash
#
# skywarnplus-setup.sh — set up SkywarnPlus weather alerting on an
# AllStarLink / HamVoIP node.
#
# SkywarnPlus itself ships an installer. This wrapper handles the parts that
# differ between node versions and are easy to get wrong: file ownership, the
# cron user, and writing the county SAME code into config.yaml.
#
# Usage:
#   sudo ./skywarnplus-setup.sh --county ILC031
#   sudo ./skywarnplus-setup.sh --county ILC031 --county ILC097
#   sudo ./skywarnplus-setup.sh --county ILC031 --skip-install
#   sudo ./skywarnplus-setup.sh --verify
#   sudo ./skywarnplus-setup.sh --test
#
# Upstream project: https://github.com/Mason10198/SkywarnPlus (GPL-3.0)

set -euo pipefail

SWP_DIR="/usr/local/bin/SkywarnPlus"
CONFIG="${SWP_DIR}/config.yaml"
CRON_FILE="/etc/cron.d/SkywarnPlus"
INSTALLER_URL="https://raw.githubusercontent.com/Mason10198/SkywarnPlus/main/swp-install"

COUNTIES=()
SKIP_INSTALL=0
VERIFY_ONLY=0
TEST_ONLY=0
PLATFORM=""
CRON_USER=""
TEST_BACKUP=""

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '    \033[0;32mok\033[0m   %s\n' "$*"; }
warn() { printf '    \033[0;33mnote\033[0m %s\n' "$*"; }
die()  { printf '\n\033[0;31mstopped:\033[0m %s\n\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------- arguments

while [[ $# -gt 0 ]]; do
  case "$1" in
    --county|-c)   [[ $# -ge 2 ]] || die "--county needs a SAME code, e.g. --county ILC031"
                   COUNTIES+=("${2^^}"); shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --verify)      VERIFY_ONLY=1; shift ;;
    --test)        TEST_ONLY=1; shift ;;
    -h|--help)     usage ;;
    *)             die "unrecognized option: $1  (try --help)" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run this with sudo — it writes to /usr/local/bin and /etc/cron.d"

for code in "${COUNTIES[@]:-}"; do
  [[ -z "$code" ]] && continue
  [[ "$code" =~ ^[A-Z]{2}C[0-9]{3}$ ]] || die \
"'$code' is not a county SAME code.

SAME codes are two letters for the state, then C, then three digits — ILC031
is Cook County, Illinois. Look yours up under your state heading at
https://github.com/Mason10198/SkywarnPlus/blob/main/CountyCodes.md

Do not substitute a zone code (the ones with a Z). Zone queries leave out
county-specific products, so the node silently misses alerts."
done

# ---------------------------------------------------------------- platform

detect_platform() {
  if command -v pacman >/dev/null 2>&1; then
    PLATFORM="HamVoIP"; CRON_USER="root"
  elif id asterisk >/dev/null 2>&1 && \
       asterisk -V 2>/dev/null | grep -qE 'Asterisk 2[0-9]'; then
    PLATFORM="ASL3"; CRON_USER="asterisk"
  else
    PLATFORM="ASL1/2"; CRON_USER="root"
  fi
}

detect_platform
info "Node looks like: ${PLATFORM}  (cron will run as '${CRON_USER}')"
[[ "$PLATFORM" == "ASL3" ]] && \
  warn "ASL3 runs Asterisk as a non-root user; permissions and cron differ accordingly."

# ---------------------------------------------------------------- actions

do_install() {
  info "Running the upstream SkywarnPlus installer"
  warn "It will prompt you. Choose YES to back up any existing install,"
  warn "and choose NO when it offers to switch to UpdateSWP.py."
  command -v curl >/dev/null 2>&1 || die "curl is not installed"
  bash -c "$(curl -fsSL "$INSTALLER_URL")"
  [[ -d "$SWP_DIR" ]] || die "installer finished but $SWP_DIR does not exist"
  ok "installed to $SWP_DIR"
}

assert_installed() {
  # Guard before we touch permissions or cron: a cron entry pointing at a
  # script that isn't there errors once a minute, forever.
  [[ -d "$SWP_DIR" ]] || die "$SWP_DIR does not exist — SkywarnPlus is not installed.
Run without --skip-install to install it first."
  [[ -f "$CONFIG" ]] || die "$CONFIG is missing — the install looks incomplete.
Re-run without --skip-install."
  ok "found an existing install at $SWP_DIR"
}

fix_perms() {
  info "Setting file permissions"
  chmod +x "$SWP_DIR"/*.py 2>/dev/null || true
  if [[ "$PLATFORM" == "ASL3" ]]; then
    chown -R asterisk:asterisk "$SWP_DIR"
    chmod -R u+rw "$SWP_DIR"
    ok "granted the asterisk user ownership of $SWP_DIR"
  else
    ok "running as root — no ownership change needed"
  fi
}

install_cron() {
  info "Scheduling the once-a-minute poll"
  printf '* * * * * %s %s/SkywarnPlus.py\n' "$CRON_USER" "$SWP_DIR" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  ok "wrote $CRON_FILE running as '$CRON_USER'"
}

backup_config() {
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONFIG" "${CONFIG}.bak-${stamp}"
  echo "${CONFIG}.bak-${stamp}"
}

set_counties() {
  [[ ${#COUNTIES[@]} -gt 0 ]] || return 0
  [[ -f "$CONFIG" ]] || die "$CONFIG not found — install SkywarnPlus first"

  info "Writing county code(s) into config.yaml: ${COUNTIES[*]}"
  local backup; backup="$(backup_config)"
  ok "backed up existing config to $backup"

  python3 - "$CONFIG" "${COUNTIES[@]}" <<'PY'
import sys
try:
    from ruamel.yaml import YAML
except ImportError:
    sys.exit("ruamel.yaml is missing. SkywarnPlus installs it; run without "
             "--skip-install, or: apt install python3-ruamel.yaml")

path, codes = sys.argv[1], sys.argv[2:]
yaml = YAML()          # round-trip mode: preserves comments and layout
yaml.preserve_quotes = True

with open(path) as fh:
    data = yaml.load(fh)

if data is None or "Alerting" not in data:
    sys.exit("No 'Alerting' section in config.yaml — the file layout is not "
             "what this script expects. Edit it by hand rather than risk "
             "corrupting it; nothing has been changed.")

data["Alerting"]["CountyCodes"] = list(codes)

with open(path, "w") as fh:
    yaml.dump(data, fh)
print("    ok   CountyCodes set to: " + ", ".join(codes))
PY

  if [[ "$PLATFORM" == "ASL3" ]]; then
    chown asterisk:asterisk "$CONFIG"
  fi
}

verify() {
  info "Checking the installation"
  local problems=0

  if [[ -d "$SWP_DIR" ]]; then ok "$SWP_DIR present"
  else warn "$SWP_DIR missing"; problems=$((problems+1)); fi

  if [[ -f "$CONFIG" ]]; then ok "config.yaml present"
  else warn "config.yaml missing"; problems=$((problems+1)); fi

  if [[ -f "$CRON_FILE" ]]; then
    ok "cron entry: $(tr -d '\n' < "$CRON_FILE")"
    if ! grep -q " ${CRON_USER} " "$CRON_FILE"; then
      warn "cron does not run as '${CRON_USER}' — wrong user for ${PLATFORM}"
      problems=$((problems+1))
    fi
  else
    warn "no cron entry at $CRON_FILE — alerts will never be polled"
    problems=$((problems+1))
  fi

  if [[ -f "$CONFIG" ]]; then
    if grep -qE '^\s*-\s*[A-Z]{2}C[0-9]{3}' "$CONFIG"; then
      ok "county code(s) configured: $(grep -oE '[A-Z]{2}C[0-9]{3}' "$CONFIG" | sort -u | tr '\n' ' ')"
    elif grep -qE '[A-Z]{2}Z[0-9]{3}' "$CONFIG"; then
      warn "a ZONE code is configured — you will miss alerts. Use a county (C) code."
      problems=$((problems+1))
    else
      warn "no county code configured yet — nothing will be announced"
      problems=$((problems+1))
    fi
  fi

  if [[ "$PLATFORM" == "ASL3" && -d "$SWP_DIR" ]]; then
    if [[ "$(stat -c '%U' "$SWP_DIR")" == "asterisk" ]]; then
      ok "$SWP_DIR owned by asterisk"
    else
      warn "$SWP_DIR is not owned by asterisk — ASL3 will not be able to write"
      problems=$((problems+1))
    fi
  fi

  echo
  if [[ $problems -eq 0 ]]; then
    printf '\033[0;32mAll checks passed.\033[0m Run with --test to hear a simulated alert.\n\n'
  else
    printf '\033[0;33m%d item(s) need attention above.\033[0m\n\n' "$problems"
  fi
}

run_test() {
  [[ -f "$CONFIG" ]] || die "$CONFIG not found — install SkywarnPlus first"
  info "Injecting a simulated Tornado Warning"
  warn "Your node will transmit. Make sure that is acceptable right now."

  # Always put the real config back, even if the run fails or is interrupted.
  # The path is expanded into the trap now, not read from a variable later —
  # a function-local would be out of scope by the time EXIT fires, leaving
  # INJECT switched on and the node announcing a fake alert every minute.
  TEST_BACKUP="$(backup_config)"
  ok "backed up config to $TEST_BACKUP"
  trap "cp -p '${TEST_BACKUP}' '${CONFIG}'; printf '\n    restored original config\n'" EXIT INT TERM

  python3 - "$CONFIG" <<'PY'
import sys
from ruamel.yaml import YAML
path = sys.argv[1]
yaml = YAML(); yaml.preserve_quotes = True
with open(path) as fh:
    data = yaml.load(fh)
dev = data.setdefault("DEV", {})
dev["INJECT"] = True
dev["INJECTALERTS"] = [{"Title": "Tornado Warning"}]
with open(path, "w") as fh:
    yaml.dump(data, fh)
PY

  [[ "$PLATFORM" == "ASL3" ]] && chown asterisk:asterisk "$CONFIG"

  if [[ "$PLATFORM" == "ASL3" ]]; then
    sudo -u asterisk "$SWP_DIR/SkywarnPlus.py" || warn "the run reported an error — see above"
  else
    "$SWP_DIR/SkywarnPlus.py" || warn "the run reported an error — see above"
  fi

  # Restore now and stand the trap down, then prove INJECT really is off.
  cp -p "$TEST_BACKUP" "$CONFIG"
  trap - EXIT INT TERM
  [[ "$PLATFORM" == "ASL3" ]] && chown asterisk:asterisk "$CONFIG"

  if grep -qE '^[[:space:]]*INJECT:[[:space:]]*true' "$CONFIG"; then
    die "INJECT is still enabled in $CONFIG after the test.
Set it to false by hand right now — otherwise cron will announce a fake
alert every minute. A good copy is at $TEST_BACKUP"
  fi
  ok "INJECT confirmed off — the node is back to real alerts only"

  info "Test finished"
  echo "    If you heard nothing, set 'Logging: Debug: true' in config.yaml and"
  echo "    watch the console with: asterisk -rvvv"
}

# ---------------------------------------------------------------- main

if [[ $VERIFY_ONLY -eq 1 ]]; then verify; exit 0; fi
if [[ $TEST_ONLY  -eq 1 ]]; then run_test; exit 0; fi

if [[ ${#COUNTIES[@]} -eq 0 ]]; then
  die "no county code given.

Run it like:   sudo $0 --county ILC031

Find your county's SAME code under your state heading at
https://github.com/Mason10198/SkywarnPlus/blob/main/CountyCodes.md
Use the county (C) code, never a zone (Z) code."
fi

[[ $SKIP_INSTALL -eq 1 ]] || do_install
assert_installed
fix_perms
set_counties
install_cron   # last, so cron never points at a broken or absent install
verify

info "Done"
cat <<EOF
    Next:
      1. sudo $0 --test        hear a simulated alert
      2. Optional — add DTMF controls to rpt.conf so you can silence it
         over the air:

           831 = cmd,${SWP_DIR}/SkyControl.py enable toggle
           834 = cmd,${SWP_DIR}/SkyControl.py tailmessage toggle

         On ASL3 these need a sudo prefix.
      3. Tail messages also need this line in rpt.conf:

           tailmessagelist = /tmp/SkywarnPlus/wx-tail

EOF
