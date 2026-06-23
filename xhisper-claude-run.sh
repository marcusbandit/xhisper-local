#!/bin/bash

# xhisper-claude-run.sh
# Speak a command and have Claude Code auto-execute it in a live, watchable
# tmux session.
#
# Invoked detached by xhisper.sh when it is called in --claude mode
# (Hyprland bind: SUPER SHIFT, R). $1 is the transcript to run as the prompt.
#
# How it works:
#   - keeps ONE long-lived interactive `claude` running inside a tmux session
#     (default name: claude-voice). Every voice command is typed into that same
#     session, so Claude keeps the full running context across commands AND you
#     can attach to watch it work live.
#   - the session resumes a fixed conversation id, so the context also survives
#     a tmux/reboot restart (it is created on first use, resumed afterwards).
#   - runs with --dangerously-skip-permissions so the task actually executes
#     without interactive prompts (personal-machine voice assistant; inherits
#     ~/CLAUDE.md and your normal Claude auth).
#   - on every command it pops a desktop notification telling you EXACTLY what
#     it heard and where it is running, and (first time) opens a terminal
#     attached to the session so you can watch.
#
# Watch the session any time:   tmux attach -t claude-voice
# Full transcript log:          ~/.claude/projects/<cwd>/<session-id>.jsonl
#
# Overridable via environment:
#   XHISPER_CLAUDE_BIN        path to the claude binary   (default ~/.local/bin/claude)
#   XHISPER_CLAUDE_DIR        working directory for the run (default $HOME)
#   XHISPER_CLAUDE_MODEL      model to use                 (default: claude's default)
#   XHISPER_CLAUDE_TMUX       tmux session name            (default: claude-voice)
#   XHISPER_CLAUDE_SESSION_ID conversation id to resume    (default: fixed id below)
#   XHISPER_CLAUDE_TERM       terminal for the viewer      (default: kitty)
#   XHISPER_CLAUDE_VIEWER     1=auto-open a viewer window  (default: 1)
#   XHISPER_CLAUDE_NTFY       ntfy URL to also push to     (optional)

PROMPT="$1"
[ -z "$PROMPT" ] && exit 0
# Collapse any newlines so the TUI gets one clean line (a stray newline would
# submit the prompt half-typed).
PROMPT="$(printf '%s' "$PROMPT" | tr '\n' ' ')"

CLAUDE_BIN="${XHISPER_CLAUDE_BIN:-$HOME/.local/bin/claude}"
WORKDIR="${XHISPER_CLAUDE_DIR:-$HOME}"
SESSION="${XHISPER_CLAUDE_TMUX:-claude-voice}"
SESSION_ID="${XHISPER_CLAUDE_SESSION_ID:-799980bd-41fd-4431-9acd-c17233afdda6}"
TERM_CMD="${XHISPER_CLAUDE_TERM:-kitty}"
VIEWER="${XHISPER_CLAUDE_VIEWER:-1}"
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

{
  echo "=== prompt ==="
  echo "$PROMPT"
  echo "=== dispatched $(date)  (cwd: $WORKDIR, tmux: $SESSION, id: $SESSION_ID) ==="
} > "$LOG"

# --- Ensure the persistent interactive Claude session exists -----------------

# Resume the fixed conversation if its transcript already exists, else create it.
MODEL_ARGS=()
[ -n "$XHISPER_CLAUDE_MODEL" ] && MODEL_ARGS=(--model "$XHISPER_CLAUDE_MODEL")
PROJDIR="$HOME/.claude/projects/$(printf '%s' "$WORKDIR" | sed 's#/#-#g')"
if [ -f "$PROJDIR/$SESSION_ID.jsonl" ]; then
  RESUME_ARGS=(--resume "$SESSION_ID")
else
  RESUME_ARGS=(--session-id "$SESSION_ID")
fi

STARTED=0
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  CMD="$(printf '%q ' "$CLAUDE_BIN" --dangerously-skip-permissions "${MODEL_ARGS[@]}" "${RESUME_ARGS[@]}")"
  tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$CMD"
  STARTED=1
  # If resume/create died immediately (e.g. a stale session id), fall back to a
  # fresh conversation so you never get a dead session.
  sleep 2
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "=== resume args failed; starting a fresh conversation ===" >> "$LOG"
    CMD="$(printf '%q ' "$CLAUDE_BIN" --dangerously-skip-permissions "${MODEL_ARGS[@]}")"
    tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$CMD"
  fi
fi

# On a fresh start, wait until the TUI has fully drawn before typing
# (the footer "bypass permissions on" only appears once it is ready), and
# auto-accept the one-time "trust this folder?" dialog.
if [ "$STARTED" -eq 1 ]; then
  notify low audio-input-microphone "Starting Claude session..." "$PROMPT"
  for _ in $(seq 1 60); do
    pane="$(tmux capture-pane -p -t "$SESSION" 2>/dev/null)"
    if printf '%s' "$pane" | grep -qiE "trust this folder|is this a project you"; then
      tmux send-keys -t "$SESSION" Enter   # default = "Yes, I trust this folder"
      sleep 1.5
      continue
    fi
    printf '%s' "$pane" | grep -qiE "bypass permissions|for shortcuts|for agents" && break
    sleep 0.5
  done
  sleep 0.5
fi

# Safety net: dismiss a trust prompt that may still be up.
if tmux capture-pane -p -t "$SESSION" 2>/dev/null \
     | grep -qiE "trust this folder|is this a project you"; then
  tmux send-keys -t "$SESSION" Enter
  sleep 1.5
fi

# --- Type the spoken command, confirm it landed, then submit -----------------
# Two stages with verification: (1) type until the text is actually in the input
# box, (2) press Enter until the box clears -- an Enter sent too soon after a
# burst of typing gets dropped, so we confirm the submission instead of assuming.

GLYPH="$(printf '\xe2\x9d\xaf')"   # the TUI input-prompt char: ❯
probe="$(printf '%s' "$PROMPT" | cut -d' ' -f1-2)"
input_line() { tmux capture-pane -p -t "$SESSION" 2>/dev/null | grep -F "$GLYPH" | tail -1; }

typed=0
for _ in 1 2 3 4; do
  tmux send-keys -t "$SESSION" -l -- "$PROMPT"
  sleep 0.6
  if input_line | grep -qF -- "$probe"; then typed=1; break; fi
  tmux send-keys -t "$SESSION" C-u   # clear partial input, then retry
  sleep 0.3
done

sent=0
if [ "$typed" -eq 1 ]; then
  sleep 0.6   # let the typed input settle so Enter registers as submit
  for _ in 1 2 3 4 5; do
    tmux send-keys -t "$SESSION" Enter
    sleep 0.8
    if ! input_line | grep -qF -- "$probe"; then sent=1; break; fi
  done
fi

if [ "$sent" -eq 1 ]; then
  echo "=== submitted to tmux session '$SESSION' ===" >> "$LOG"
else
  echo "=== WARNING: could not confirm submission to '$SESSION' (typed=$typed) ===" >> "$LOG"
  notify critical dialog-error "Claude: send may have failed" \
    "Couldn't confirm submission. Check: tmux attach -t $SESSION"
fi

# --- Tell the user clearly what just happened --------------------------------

notify normal audio-input-microphone "Sent to Claude -- watch it run" \
"\"$PROMPT\"

tmux: $SESSION   (attach: tmux attach -t $SESSION)"

# First time (or if nothing is attached), pop a terminal so it's visible.
# Launched as `$TERM_CMD tmux attach ...` (kitty-style, no -e); override
# XHISPER_CLAUDE_TERM with a terminal that uses the same form.
if [ "$VIEWER" = "1" ] && [ -z "$(tmux list-clients -t "$SESSION" 2>/dev/null)" ]; then
  setsid "$TERM_CMD" tmux attach -t "$SESSION" >/dev/null 2>&1 < /dev/null &
fi

# Optional ntfy push (e.g. to your phone).
if [ -n "$XHISPER_CLAUDE_NTFY" ]; then
  curl -s -H "Title: Sent to Claude" -d "$PROMPT" "$XHISPER_CLAUDE_NTFY" >/dev/null 2>&1 || true
fi
