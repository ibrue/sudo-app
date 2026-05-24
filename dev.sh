#!/bin/bash
# dev.sh — fast iteration helpers for sudo + macropad firmware.
#
# Usage:
#   ./dev.sh status                  # snapshot of pad/sudo state
#   ./dev.sh log [N]                 # tail last N lines of CDC log (default 30)
#   ./dev.sh events                  # show only milestone events (no heartbeats)
#   ./dev.sh tail                    # live-follow the CDC log
#   ./dev.sh clear                   # truncate the CDC log to zero
#   ./dev.sh build                   # swift build only (no install)
#   ./dev.sh deploy                  # build + install + relaunch
#   ./dev.sh fast-deploy             # build + install + relaunch (PRESERVES TCC grants*)
#   ./dev.sh reload                  # soft-reset CircuitPython via Ctrl-D over CDC
#   ./dev.sh fw-status               # check if CIRCUITPY is mounted + recent firmware version
#   ./dev.sh sync-fw <src>           # copy a code.py from <src> to /Volumes/CIRCUITPY/code.py
#   ./dev.sh press-summary           # parse log + report connect-to-first-press timing
#
# *Both deploy paths sign with a stable ad-hoc designated requirement so
# Accessibility grants survive normal iterative rebuilds.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Sudo"
BUNDLE_ID="supply.sudo.app"
LOG=/tmp/sudo-pad-console.log
APP_PATH="/Applications/Sudo.app"
DIST_APP="$SCRIPT_DIR/dist/Sudo.app"
TTY_GLOB='/dev/cu.usbmodem*'

err() { echo "[dev] $*" >&2; }
ok()  { echo "[dev] $*"; }

cmd_status() {
    local now
    now=$(date +%s%3N)
    echo "now: $now"
    echo ""
    echo "=== pad ==="
    if compgen -G "$TTY_GLOB" >/dev/null; then
        local devs
        devs=$(ls $TTY_GLOB 2>/dev/null | head -3)
        echo "tty: $devs"
    else
        echo "tty: NONE"
    fi
    if [ -d /Volumes/CIRCUITPY ]; then
        echo "CIRCUITPY: mounted"
    else
        echo "CIRCUITPY: hidden (production boot.py)"
    fi
    if [ -d /Volumes/RPI-RP2 ]; then
        echo "RPI-RP2: MOUNTED (pad in BOOTSEL)"
    fi
    if compgen -G "$TTY_GLOB" >/dev/null; then
        echo "USB: tty present"
    elif system_profiler SPUSBDataType 2>/dev/null | grep -qiE 'raspberry|adafruit|pico'; then
        echo "USB: pad in system_profiler but no tty"
    else
        echo "USB: pad NOT visible to macOS"
    fi
    # Latest firmware uptime from heartbeats (last sudo-alive t=Xms)
    if [ -f "$LOG" ]; then
        local lastfw
        lastfw=$(grep "## sudo-alive t=" "$LOG" | tail -1 | sed -n 's/.*t=\([0-9]*\)ms.*/\1/p')
        if [ -n "$lastfw" ]; then
            echo "firmware uptime: ${lastfw} ms (~$((lastfw / 1000))s, last heartbeat)"
        fi
    fi
    # Detect cold-boot by looking for the most recent sudo-code.py-start
    if [ -f "$LOG" ] && grep -q "sudo-code.py-start" "$LOG"; then
        local lastboot
        lastboot=$(grep "sudo-code.py-start" "$LOG" | tail -1)
        echo "last firmware cold-boot in log:"
        echo "  $lastboot"
    fi
    echo ""
    echo "=== sudo ==="
    if pgrep -fl Sudo.app >/dev/null; then
        local pid
        pid=$(pgrep -f Sudo.app | head -1)
        echo "running: pid=$pid"
        echo "binary: $(stat -f '%Sm' "$APP_PATH/Contents/MacOS/Sudo" 2>/dev/null || echo 'missing')"
    else
        echo "running: NO"
    fi
    echo ""
    echo "=== cdc log ==="
    if [ -f "$LOG" ]; then
        local lines size
        lines=$(wc -l < "$LOG" | tr -d ' ')
        size=$(stat -f '%z' "$LOG")
        echo "lines: $lines | bytes: $size | path: $LOG"
        if [ "$lines" -gt 0 ]; then
            echo "newest: $(tail -1 "$LOG")"
        fi
    else
        echo "log: not yet created"
    fi
}

cmd_log() {
    local n=${1:-30}
    tail -n "$n" "$LOG"
}

cmd_events() {
    grep -E "disconnected|hid-add|tty-opened|tapCreate|tap-press|sudo-press|sudo-flash|sudo-code.py-start|sudo-ready|sudo-hard-reset|sudo-send-fail|sudo-wdt|cdc-burst" "$LOG" | tail -50
}

cmd_tail() {
    tail -F "$LOG"
}

cmd_clear() {
    : > "$LOG"
    ok "cleared $LOG"
}

cmd_build() {
    cd "$SCRIPT_DIR/Sudo" && swift build -c release 2>&1 | tail -10
}

cmd_deploy() {
    "$SCRIPT_DIR/build.sh" 2>&1 | tail -5
    killall Sudo 2>/dev/null || true
    sleep 1
    rm -rf "$APP_PATH"
    cp -r "$DIST_APP" "$APP_PATH"
    open "$APP_PATH"
    sleep 2
    if pgrep -fl Sudo.app >/dev/null; then
        ok "deployed and launched (pid=$(pgrep -f Sudo.app | head -1))"
        ok "deployed without resetting TCC"
    else
        err "deploy launched but no Sudo process detected"
    fi
}

cmd_fast_deploy() {
    # Fast path for iterative development. Uses the same stable ad-hoc
    # designated requirement as build.sh so TCC can keep matching the
    # existing Accessibility grant across binary rebuilds.
    cd "$SCRIPT_DIR/Sudo"
    swift build -c release 2>&1 | tail -5
    cd "$SCRIPT_DIR"
    local bin=".build/release/$APP_NAME"
    # shellcheck disable=SC2086
    bin="$SCRIPT_DIR/Sudo/$bin"
    if [ ! -f "$bin" ]; then
        err "binary not found at $bin"
        return 1
    fi
    if [ ! -d "$DIST_APP" ]; then
        err "no dist/Sudo.app — run ./dev.sh deploy at least once first"
        return 1
    fi
    cp "$bin" "$DIST_APP/Contents/MacOS/$APP_NAME"
    codesign --force --deep --sign - \
        --identifier "$BUNDLE_ID" \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" \
        "$DIST_APP" >/dev/null 2>&1
    killall Sudo 2>/dev/null || true
    sleep 1
    rm -rf "$APP_PATH"
    cp -r "$DIST_APP" "$APP_PATH"
    open "$APP_PATH"
    sleep 2
    ok "fast-deployed (pid=$(pgrep -f Sudo.app | head -1)) — TCC not reset"
}

cmd_reload() {
    local tty
    tty=$(ls $TTY_GLOB 2>/dev/null | head -1 || true)
    if [ -z "$tty" ]; then
        err "no cdc tty — pad not enumerated"
        return 1
    fi
    python3 - <<PY
import os, time
fd = os.open("$tty", os.O_WRONLY | os.O_NONBLOCK)
os.write(fd, b'\x03'); time.sleep(0.1)   # Ctrl-C
os.write(fd, b'\x04')                     # Ctrl-D (soft-reload)
os.close(fd)
print("sent Ctrl-C + Ctrl-D to $tty")
PY
}

cmd_fw_status() {
    if [ -d /Volumes/CIRCUITPY ]; then
        ok "CIRCUITPY mounted at /Volumes/CIRCUITPY"
        echo "boot.py:"
        head -3 /Volumes/CIRCUITPY/boot.py 2>/dev/null
        echo "code.py header:"
        head -3 /Volumes/CIRCUITPY/code.py 2>/dev/null
        if [ -f /Volumes/CIRCUITPY/boot_out.txt ]; then
            echo "boot_out.txt:"
            cat /Volumes/CIRCUITPY/boot_out.txt
        fi
    else
        err "CIRCUITPY not mounted (hidden in production mode — hold button 1 + replug)"
    fi
}

cmd_sync_fw() {
    local src="${1:-}"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        err "usage: $0 sync-fw <src-file>   # filename must contain 'boot' or 'code'"
        return 1
    fi
    if [ ! -d /Volumes/CIRCUITPY ]; then
        err "CIRCUITPY not mounted — hold button 1 + replug"
        return 1
    fi
    local base
    base=$(basename "$src")
    local dst
    if [[ "$base" == *boot* ]]; then
        dst=/Volumes/CIRCUITPY/boot.py
    else
        dst=/Volumes/CIRCUITPY/code.py
    fi
    cp "$src" "$dst"
    sync
    ok "synced $src → $dst"
    if [[ "$dst" == *boot.py ]]; then
        err "boot.py changes only take effect on cold-boot — unplug + replug to apply"
    fi
}

cmd_press_summary() {
    # Find the LAST disconnect line, then report milestones that follow it.
    local last_disc_ms
    last_disc_ms=$(grep -n "── disconnected ──" "$LOG" | tail -1 | cut -d: -f1)
    if [ -z "$last_disc_ms" ]; then
        echo "no disconnect events in log"
        return
    fi
    awk -v start="$last_disc_ms" '
    NR == start                                   { disc = $1; print "disconnect: t=" disc; next }
    NR < start                                    { next }
    NR > start && /\[mac\] hid-add/              { if (!hid) { hid = $1 - disc; printf "hid-add:    +%dms\n", hid } next }
    NR > start && /\[mac\] tapCreate-OK/         { if (!tap) { tap = $1 - disc; printf "tap-OK:     +%dms\n", tap } next }
    NR > start && /\[mac\] tty-opened/           { if (!tty) { tty = $1 - disc; printf "tty-opened: +%dms\n", tty } next }
    NR > start && /\[mac\] cdc-burst connected/  { if (!cb)  { cb  = $1 - disc; printf "cdc-burst:  +%dms (%s)\n", cb, $0 } next }
    NR > start && /## sudo-code.py-start/        { if (!fs)  { fs  = $1 - disc; printf "fw-start:   +%dms (firmware cold-boot)\n", fs } next }
    NR > start && /## sudo-ready/                { if (!fr)  { fr  = $1 - disc; printf "fw-ready:   +%dms\n", fr } next }
    NR > start && /## sudo-alive/                { if (!al)  { al  = $1 - disc; printf "1st alive:  +%dms\n", al } next }
    NR > start && /\[mac\] tap-press/            { if (!p)   { p   = $1 - disc; printf "1st press:  +%dms\n", p } next }
    END {
        if (!hid)   print "(hid-add not seen yet — pad not re-enumerated)"
        else if (!p) print "(press path is up; just no button press registered after the last disconnect)"
    }
    ' "$LOG"
}

cmd_check() {
    # All-in-one diagnostic dump. Intended as a Conductor run-script —
    # one command, complete snapshot.
    echo "════════════════════════════════════════"
    echo "  sudo + macropad diagnostic snapshot"
    echo "════════════════════════════════════════"
    echo ""
    cmd_status
    echo ""
    echo "=== last reconnect cycle ==="
    cmd_press_summary
    echo ""
    echo "=== recent milestone events ==="
    cmd_events | tail -20
    echo ""
    echo "=== recent firmware errors ==="
    if grep -E "sudo-loop-error|sudo-send-fail|sudo-hard-reset|sudo-flash-noop|sudo-flash-err" "$LOG" | tail -10 | grep -q .; then
        grep -E "sudo-loop-error|sudo-send-fail|sudo-hard-reset|sudo-flash-noop|sudo-flash-err" "$LOG" | tail -10
    else
        echo "(none)"
    fi
    echo ""
    echo "=== sudo binary version ==="
    if [ -f "$APP_PATH/Contents/MacOS/Sudo" ]; then
        strings "$APP_PATH/Contents/MacOS/Sudo" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-beta$' | head -1
        codesign -dvv "$APP_PATH" 2>&1 | grep -E "cdhash|Identifier" | head -2
    else
        echo "(not installed)"
    fi
}

cmd_monitor() {
    # Watch the CDC log; whenever a disconnect → reconnect cycle happens,
    # print a per-stage timing breakdown. Runs until Ctrl-C.
    #
    # Wire this to a Conductor run-script and you'll see live cycle
    # timings every time the pad is unplugged + replugged.
    : > /tmp/sudo-monitor-cursor
    echo "[monitor] watching $LOG for disconnect/reconnect cycles…"
    echo "[monitor] unplug + replug your pad and a per-cycle timing will print"
    echo ""
    awk -v log="$LOG" '
    BEGIN { disc = 0 }
    /── disconnected ──/ {
        if (disc) {
            printf "\n[INCOMPLETE PRIOR CYCLE]\n\n"
        }
        disc = $1
        printf "\n══ cycle started @ %s ══\n", strftime("%H:%M:%S", disc/1000)
        printf "  disconnect:  0ms\n"
        delete fired
        next
    }
    disc == 0 { next }
    /\[mac\] hid-add/         { if (!fired["hid"])    { printf "  hid-add:    +%dms\n", $1 - disc; fired["hid"]=1 } next }
    /\[mac\] tapCreate-OK/    { if (!fired["tap"])    { printf "  tap-OK:     +%dms\n", $1 - disc; fired["tap"]=1 } next }
    /\[mac\] tty-opened/      { if (!fired["tty"])    { printf "  tty-opened: +%dms\n", $1 - disc; fired["tty"]=1 } next }
    /\[mac\] cdc-burst/       { if (!fired["burst"])  { printf "  cdc-burst:  +%dms (%s)\n", $1 - disc, substr($0, index($0,"connected")); fired["burst"]=1 } next }
    /## sudo-code.py-start/   { if (!fired["fw"])     { printf "  fw-start:   +%dms (firmware cold-boot ✓)\n", $1 - disc; fired["fw"]=1 } next }
    /## sudo-ready/           { if (!fired["rdy"])    { printf "  fw-ready:   +%dms\n", $1 - disc; fired["rdy"]=1 } next }
    /## sudo-alive/           { if (!fired["alv"])    { printf "  1st alive:  +%dms\n", $1 - disc; fired["alv"]=1 } next }
    /\[mac\] tap-press/       {
        if (!fired["p"]) {
            printf "  1st press:  +%dms ← USER-PERCEIVED CONNECT TIME\n", $1 - disc
            printf "  cycle done.\n"
            fired["p"] = 1
            disc = 0
        }
        next
    }
    ' < <(tail -n 0 -F "$LOG")
}

cmd_test_reload() {
    # Trigger a soft-reload via Ctrl-D + verify the firmware comes back
    # cleanly within a few seconds. Doesn't need a physical replug.
    ok "soft-reload test: triggering Ctrl-D..."
    cmd_reload || return 1
    sleep 3
    if grep "sudo-code.py-start" "$LOG" | tail -1 | awk '{print $1}' | xargs -I{} test {} -gt $(($(date +%s%3N) - 5000)) 2>/dev/null; then
        ok "firmware came back within 5s ✓"
    else
        local last_boot
        last_boot=$(grep "sudo-code.py-start" "$LOG" | tail -1)
        err "no recent firmware boot detected. last: $last_boot"
    fi
}

case "${1:-}" in
    status)        cmd_status ;;
    log)           shift; cmd_log "$@" ;;
    events)        cmd_events ;;
    tail)          cmd_tail ;;
    clear)         cmd_clear ;;
    build)         cmd_build ;;
    deploy)        cmd_deploy ;;
    fast-deploy)   cmd_fast_deploy ;;
    reload)        cmd_reload ;;
    fw-status)     cmd_fw_status ;;
    sync-fw)       shift; cmd_sync_fw "$@" ;;
    press-summary) cmd_press_summary ;;
    check)         cmd_check ;;
    monitor)       cmd_monitor ;;
    test-reload)   cmd_test_reload ;;
    "")            sed -n '3,30p' "$0" ;;     # print the usage banner
    *)             err "unknown command: $1"; exit 1 ;;
esac
