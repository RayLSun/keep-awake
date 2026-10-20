#!/usr/bin/env bash
# keep-awake.sh v1.0
# Keeps macOS awake for long-running AI agent tasks.
# Wraps the built-in `caffeinate` command - no install needed.
#
# Usage:
#   ./keep-awake.sh [options]
# Options:
#   -d, --display   also keep the display awake (for UI-automation agents)
#   --no-display     do not keep the display awake (skips the prompt)
#   --no-disk       do not prevent disk sleep
#   -m, --minutes N  auto-stop after N minutes (0 = run until Ctrl+C)
#
# Stop: Ctrl+C (or killall caffeinate). No settings are modified, nothing to restore.
# Verify: pmset -g assertions | grep -i caffeinate

set -u

KEEP_DISPLAY=0
KEEP_DISK=1
MINUTES=0
PROMPT_DISPLAY=1

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--display)   KEEP_DISPLAY=1; PROMPT_DISPLAY=0 ;;
        --no-display)   KEEP_DISPLAY=0; PROMPT_DISPLAY=0 ;;
        -n|--no-disk)   KEEP_DISK=0 ;;
        --disk)         KEEP_DISK=1 ;;
        --minutes)      MINUTES="${2:-0}"; shift ;;
        -h|--help)
            sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "keep-awake: unknown option: $1 (see --help)"; exit 1 ;;
    esac
    shift
done

# display choice: prompt when running interactively without flags
if [ "$PROMPT_DISPLAY" -eq 1 ] && [ -t 0 ]; then
    printf 'Keep display awake too? [y/N] '
    read -r ans
    case "$ans" in
        y|Y|yes|YES) KEEP_DISPLAY=1 ;;
    esac
fi

if ! command -v caffeinate >/dev/null 2>&1; then
    echo "keep-awake: caffeinate not found (macOS only)."; exit 1
fi

FLAGS="-i -s"                 # no idle sleep, no system sleep (AC power)
[ "$KEEP_DISK" -eq 1 ]    && FLAGS="$FLAGS -m"   # no disk idle sleep
[ "$KEEP_DISPLAY" -eq 1 ] && FLAGS="$FLAGS -d"   # no display sleep

if [ "$MINUTES" -gt 0 ]; then
    FLAGS="$FLAGS -t $((MINUTES * 60))"
    echo "keep-awake: active for $MINUTES min (caffeinate $FLAGS)"
else
    echo "keep-awake: active, Ctrl+C to stop (caffeinate $FLAGS)"
fi

exec caffeinate $FLAGS
