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

# Build the prompt (using printf for color codes)
# Green arrow + cyan directory + blue git info + context usage
printf "\033[1;32m➜\033[0m  \033[36m%s\033[0m\033[1;34m%s\033[0m%b" "$dir_name" "$git_info" "$ctx_info"
