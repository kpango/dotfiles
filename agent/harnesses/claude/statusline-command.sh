#!/usr/bin/env bash
# Claude Code status line — cwd / git branch+status / model / context remaining
# Input: JSON from stdin (Claude Code statusLine protocol)

input=$(cat)

command -v jq &>/dev/null || { printf ""; exit 0; }

# --- directory (truncate to last 6 path segments, home as ~) ---
cwd=$(echo "$input" | jq -r '.cwd // ""')
cwd="${cwd/#$HOME/\~}"
IFS='/' read -ra parts <<< "$cwd"
if [ "${#parts[@]}" -gt 6 ]; then
  cwd="…/$(IFS='/'; echo "${parts[*]: -6}")"
fi

# --- git branch ---
git_cwd=$(echo "$input" | jq -r '.cwd // "."')
branch=$(git -C "$git_cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  if [ "${#branch}" -gt 12 ]; then
    branch="${branch:0:12}…"
  fi
  git_part="  ${branch}"
else
  git_part=""
fi

# --- git status (staged / unstaged / untracked) ---
if [ -n "$branch" ]; then
  unstaged=$(git -C "$git_cwd" --no-optional-locks diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  staged=$(git -C "$git_cwd" --no-optional-locks diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git -C "$git_cwd" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  status_str=""
  [ "$staged" -gt 0 ]    && status_str="${status_str}+${staged}"
  [ "$unstaged" -gt 0 ]  && status_str="${status_str}!${unstaged}"
  [ "$untracked" -gt 0 ] && status_str="${status_str}?${untracked}"
  [ -n "$status_str" ] && git_part="${git_part} [${status_str}]"
fi

# --- model (short name) ---
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- context remaining ---
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$remaining" ]; then
  ctx_part=" ctx:$(printf '%.0f' "$remaining")%"
else
  ctx_part=""
fi

# --- assemble ---
printf "\033[34m%s\033[0m%s  \033[33m%s\033[0m%s" \
  "$cwd" \
  "$git_part" \
  "$model" \
  "$ctx_part"
