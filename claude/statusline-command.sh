#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract workspace info
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

# Get current directory name (like %c in zsh)
dir_name=$(basename "$cwd")

# Git status information (using --no-optional-locks to avoid locking issues)
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")

  # Check if repo is dirty
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    git_status="✗"
  else
    git_status=""
  fi

  git_info=" git:($branch)${git_status:+ $git_status}"
else
  git_info=""
fi

# Context window usage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    ctx_color="\033[1;31m"  # bold red
  elif [ "$used_int" -ge 50 ]; then
    ctx_color="\033[1;33m"  # bold yellow
  else
    ctx_color="\033[1;32m"  # bold green
  fi
  ctx_info=" ${ctx_color}ctx:${used_int}%\033[0m"
else
  ctx_info=""
fi

# Agent name: the address other sessions use with SendMessage. Only
# `claude agents --json` knows it, and that spawns a node process, so the
# lookup is cached and refreshed in the background rather than per render.
session_id=$(echo "$input" | jq -r '.session_id // empty')
name_cache="$HOME/.claude/.agent-names.json"
name_lock="$HOME/.claude/.agent-names.lock"
now=$(date +%s)

# Drop a lock left behind by a refresh that died.
if [ -d "$name_lock" ] && [ $(( now - $(stat -f %m "$name_lock" 2>/dev/null || echo "$now") )) -ge 120 ]; then
  rmdir "$name_lock" 2>/dev/null
fi

cache_age=$(( now - $(stat -f %m "$name_cache" 2>/dev/null || echo 0) ))
if [ "$cache_age" -ge 60 ] && mkdir "$name_lock" 2>/dev/null; then
  (
    trap 'rmdir "$name_lock" 2>/dev/null' EXIT
    tmp="$name_cache.$$"
    # `claude agents --json` exits nonzero even when it prints good output,
    # so validate the JSON rather than trusting the exit code.
    claude agents --json >"$tmp" 2>/dev/null
    if jq -e 'type == "array"' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$name_cache"
    else
      rm -f "$tmp"
    fi
  ) >/dev/null 2>&1 &
fi

agent_name=""
if [ -n "$session_id" ] && [ -f "$name_cache" ]; then
  agent_name=$(jq -r --arg sid "$session_id" \
    '.[] | select(.sessionId == $sid) | .name // empty' "$name_cache" 2>/dev/null | head -1)
fi

# Fall back to a short session-id prefix until the cache is warm.
session_label="${agent_name:-${session_id:0:8}}"
session_info="${session_label:+ \033[2m[$session_label]\033[0m}"

# Build the prompt (using printf for color codes)
# Green arrow + cyan directory + blue git info + context usage + dim agent name
printf "\033[1;32m➜\033[0m  \033[36m%s\033[0m\033[1;34m%s\033[0m%b%b" "$dir_name" "$git_info" "$ctx_info" "$session_info"
