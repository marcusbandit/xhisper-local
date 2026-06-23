#!/bin/bash

# xhisper-claude-run.sh
# Run a voice transcript as a headless, auto-executing Claude Code task.
#
# Invoked detached by xhisper.sh when it is called in --claude mode
# (Hyprland bind: SUPER SHIFT, R). $1 is the transcript to run as the prompt.
#
# Behaviour:
#   - fires a desktop notification when the run starts and when it finishes
#   - runs `claude -p` with --dangerously-skip-permissions so the task actually
#     executes without interactive prompts (this is a personal-machine voice
#     assistant; the run inherits ~/CLAUDE.md and your normal Claude auth)
#   - logs the full prompt + output to ~/.local/share/xhisper-claude/<ts>.log
#
# Overridable via environment:
#   XHISPER_CLAUDE_BIN   path to the claude binary   (default ~/.local/bin/claude)
#   XHISPER_CLAUDE_DIR   working directory for the run (default $HOME)
#   XHISPER_CLAUDE_MODEL model to use                 (default: claude's default)
#   XHISPER_CLAUDE_NTFY  ntfy URL to also push the result to (optional)

PROMPT="$1"
[ -z "$PROMPT" ] && exit 0

CLAUDE_BIN="${XHISPER_CLAUDE_BIN:-$HOME/.local/bin/claude}"
WORKDIR="${XHISPER_CLAUDE_DIR:-$HOME}"
NOTIFY="$(command -v notify-send || echo /usr/bin/notify-send)"
APP="xhisper to Claude"

LOGDIR="$HOME/.local/share/xhisper-claude"
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/$TS.log"

notify() {
  # $1=urgency $2=icon $3=summary $4=body
  "$NOTIFY" -a "$APP" -u "$1" -i "$2" "$3" "$4" 2>/dev/null || true
}

notify normal audio-input-microphone "Claude running..." "$PROMPT"

{
  echo "=== prompt ==="
  echo "$PROMPT"
  echo "=== started $(date)  (cwd: $WORKDIR) ==="
} > "$LOG"

cd "$WORKDIR" || { notify critical dialog-error "Claude failed" "Cannot cd to $WORKDIR"; exit 1; }

# Optional model override
MODEL_ARGS=()
[ -n "$XHISPER_CLAUDE_MODEL" ] && MODEL_ARGS=(--model "$XHISPER_CLAUDE_MODEL")

RESULT="$("$CLAUDE_BIN" --print \
  --dangerously-skip-permissions \
  --output-format text \
  "${MODEL_ARGS[@]}" \
  "$PROMPT" 2>>"$LOG")"
STATUS=$?

{
  echo "=== result (exit $STATUS) ==="
  echo "$RESULT"
  echo "=== finished $(date) ==="
} >> "$LOG"

# Truncate for the notification bubble; full text is in the log.
SUMMARY="$RESULT"
[ "${#SUMMARY}" -gt 400 ] && SUMMARY="${SUMMARY:0:400}..."
[ -z "$SUMMARY" ] && SUMMARY="(no text output -- see $LOG)"

if [ "$STATUS" -eq 0 ]; then
  notify normal emblem-default "Claude done" "$SUMMARY"
else
  notify critical dialog-error "Claude failed (exit $STATUS)" "$SUMMARY
See $LOG"
fi

# Optional ntfy push (e.g. to your phone) if a URL is configured.
if [ -n "$XHISPER_CLAUDE_NTFY" ]; then
  curl -s -H "Title: Claude done" -d "$SUMMARY" "$XHISPER_CLAUDE_NTFY" >/dev/null 2>&1 || true
fi
