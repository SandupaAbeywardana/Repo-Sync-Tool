#!/bin/bash
# Sync whole changed files between repos (copy & replace).
# Detects files from git, copies full files to targets, backs up per session for full-run revert.

set -euo pipefail

# -------------------- Config --------------------
DATA_DIR="data/sync-files"
SESS_DIR="$DATA_DIR/sessions"
LOG_FILE="$DATA_DIR/sync-files.log"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
SESSION_ID="$TIMESTAMP"
SESSION_PATH="$SESS_DIR/$SESSION_ID"

# Critical file globs (prompt before overwriting)
CRITICAL_GLOBS=("*.env" "config/*.php" "config/*.json" "app/Providers/*.php")

# Exclude patterns (skip copying)
EXCLUDE_GLOBS=("node_modules/**" "vendor/**" "storage/**" ".git/**" "$DATA_DIR/**")

# Colors
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; RESET="\033[0m"

# -------------------- Init --------------------
mkdir -p "$DATA_DIR" "$SESS_DIR" "$SESSION_PATH"
: > "$LOG_FILE"

# Spinner
spinner() {
  local pid=$1 delay=0.08 spin='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    printf " [%c] " "$spin"
    spin=${spin#?}${spin%???}
    sleep $delay
    printf "\b\b\b\b\b"
  done
}

# Helpers
match_globs() {
  local path="$1"; shift
  for g in "$@"; do
    if [[ "$path" == $g ]]; then return 0; fi
  done
  return 1
}
is_binary() {
  # Treat as text if grep -Iq finds no binary bytes
  grep -Iq . "$1" 2>/dev/null || return 0  # empty files OK
  grep -Iq . "$1"
}
confirm() { # confirm "message"
  read -p "$1 [y/N]: " ans; [[ "${ans:-}" =~ ^[Yy]$ ]]
}
ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    if confirm "Create missing directory: $dir?"; then
      mkdir -p "$dir"
    else
      return 1
    fi
  fi
  return 0
}
target_has_local_changes() { # repo file
  local repo="$1" file="$2"
  git -C "$repo" diff --quiet -- "$file" || return 0  # has changes
  return 1
}

# Repo discovery
repos=()
for d in */ ; do [[ -d "$d/.git" ]] && repos+=("${d%/}"); done
if [[ ${#repos[@]} -eq 0 ]]; then
  echo -e "${RED}[ERROR] No Git repos found in current directory.${RESET}"
  exit 1
fi

# -------------------- Main Menu --------------------
echo -e "${CYAN}Main Menu:${RESET}"
echo "[1] Copy changed files"
echo "[2] Revert an entire previous run (session)"
read -p "Enter choice: " main_choice

# -------------------- Revert Mode --------------------
if [[ "$main_choice" == "2" ]]; then
  shopt -s nullglob
  sessions=( "$SESS_DIR"/* )
  shopt -u nullglob
  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No previous sessions found in $SESS_DIR.${RESET}"
    exit 1
  fi

  echo -e "${CYAN}Available sessions:${RESET}"
  for i in "${!sessions[@]}"; do sid=$(basename "${sessions[$i]}"); echo "[$i] $sid"; done
  read -p "Select a session to revert: " si
  SEL_SESSION="${sessions[$si]}"
  [[ -d "$SEL_SESSION" ]] || { echo -e "${RED}[ERROR] Invalid session.${RESET}"; exit 1; }

  echo -e "${YELLOW}[INFO] Dry-Run (revert preview):${RESET}"
  # List files that would be restored
  find "$SEL_SESSION" -type f -printf "%P\n" | while read -r f; do
    repo="${f%%/*}"
    rel="${f#*/}"
    rel="${rel//./\/}"               # reverse our dot encoding back to path
    rel="${rel%/backup}"             # safety; not used now
    # We saved backups as $repo.<path.with.dots>.file-backup
    echo "Would restore: $repo / ${rel}"
  done

  if confirm "Proceed to revert this entire session?"; then
    echo -e "${YELLOW}[INFO] Reverting...${RESET}"
    while IFS= read -r bfile; do
      base=$(basename "$bfile")
      repo="${base%%.*}"
      encoded="${base#*.}"; encoded="${encoded%.file-backup}"
      rel="${encoded//./\/}"
      echo -ne "${CYAN}[REVERT] $repo/$rel ...${RESET}"
      ensure_dir "$repo/$(dirname "$rel")" || { echo -e "${RED} [SKIPPED]${RESET}"; continue; }
      cp "$bfile" "$repo/$rel" && echo -e "${GREEN} [RESTORED]${RESET}" || echo -e "${RED} [FAILED]${RESET}"
    done < <(find "$SEL_SESSION" -type f -name "*.file-backup" -print)
    echo -e "${GREEN}[DONE] Revert complete for session $(basename "$SEL_SESSION").${RESET}"
  else
    echo -e "${YELLOW}[CANCELLED] Revert aborted.${RESET}"
  fi
  exit 0
fi

# -------------------- Copy Mode --------------------
echo -e "${CYAN}Available repos:${RESET}"
for i in "${!repos[@]}"; do echo "[$i] ${repos[$i]}"; done
read -p "Enter source repo number: " src_choice
SOURCE_REPO=${repos[$src_choice]}

echo
echo -e "${CYAN}File source options:${RESET}"
echo "[1] Changed since last commit (default)"
echo "[2] Changed in a specific commit"
echo "[3] Changed in a commit range"
echo "[4] Interactive selection from working tree changes"
read -p "Enter choice: " src_mode

echo
echo -e "${CYAN}Which changes to consider?${RESET}"
echo "[1] Unstaged only"
echo "[2] Staged only"
echo "[3] Both staged + unstaged (default)"
read -p "Enter choice: " stage_mode
stage_mode=${stage_mode:-3}

# Gather changed files
cd "$SOURCE_REPO"
case "$src_mode" in
  1)
    # since last commit; honour staged/unstaged/both
    files=""
    if [[ "$stage_mode" == "1" ]]; then
      files=$(git diff --name-only)
    elif [[ "$stage_mode" == "2" ]]; then
      files=$(git diff --name-only --cached)
    else
      # both
      files=$( (git diff --name-only; git diff --name-only --cached) | sort -u )
    fi
    ;;
  2)
    read -p "Enter commit hash: " one_commit
    files=$(git show --name-only --pretty="" "$one_commit")
    ;;
  3)
    read -p "Enter commit range (e.g. abc123..def456): " range
    files=$(git diff --name-only "$range")
    ;;
  4)
    # interactive based on working tree
    all=$(git status --porcelain | awk '{print $2}')
    if [[ -z "${all// /}" ]]; then
      echo -e "${YELLOW}[INFO] No changes detected for interactive selection.${RESET}"
      exit 0
    fi
    echo -e "${CYAN}Changed files:${RESET}"
    mapfile -t arr < <(echo "$all")
    for i in "${!arr[@]}"; do printf "[%d] %s\n" "$i" "${arr[$i]}"; done
    read -p "Select files (indexes, space-separated) or 'a' for all: " choices
    if [[ "$choices" == "a" ]]; then
      files="$all"
    else
      files=""
      for idx in $choices; do files+="${arr[$idx]}"$'\n'; done
    fi
    ;;
  *)
    echo -e "${RED}[ERROR] Invalid choice.${RESET}"; exit 1;;
esac
cd - >/dev/null

# Normalize file list
mapfile -t CHANGED_FILES < <(echo "$files" | sed '/^\s*$/d' | sort -u)

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}[INFO] No files to sync from $SOURCE_REPO.${RESET}"
  exit 0
fi

# Apply excludes
FILTERED_FILES=()
for f in "${CHANGED_FILES[@]}"; do
  skip=0
  for ex in "${EXCLUDE_GLOBS[@]}"; do
    [[ "$f" == $ex ]] && { skip=1; break; }
  done
  [[ $skip -eq 0 ]] && FILTERED_FILES+=("$f")
done

if [[ ${#FILTERED_FILES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}[INFO] All changed files are excluded by patterns.${RESET}"
  exit 0
fi

echo -e "${CYAN}Files to sync from ${SOURCE_REPO}:${RESET}"
for i in "${!FILTERED_FILES[@]}"; do printf "[%d] %s\n" "$i" "${FILTERED_FILES[$i]}"; done

# Skip binary?
echo
if confirm "Skip binary files?"; then SKIP_BIN=1; else SKIP_BIN=0; fi

# Targets
echo
echo -e "${CYAN}Target repos:${RESET}"
for i in "${!repos[@]}"; do [[ "${repos[$i]}" != "$SOURCE_REPO" ]] && echo "[$i] ${repos[$i]}"; done
echo "[a] All (except source)"
read -p "Enter repos (indexes or 'a'): " tsel

targets=()
if [[ "$tsel" == "a" ]]; then
  for r in "${repos[@]}"; do [[ "$r" != "$SOURCE_REPO" ]] && targets+=("$r"); done
else
  for idx in $tsel; do
    r=${repos[$idx]}
    [[ "$r" != "$SOURCE_REPO" ]] && targets+=("$r")
  done
fi
[[ ${#targets[@]} -gt 0 ]] || { echo -e "${RED}[ERROR] No targets selected.${RESET}"; exit 1; }

# Dry-run preview
echo
echo -e "${YELLOW}[INFO] Dry-Run preview:${RESET}"
for repo in "${targets[@]}"; do
  echo -e "${CYAN} -> $repo${RESET}"
  for f in "${FILTERED_FILES[@]}"; do
    echo "    would copy: $f"
  done
done
echo

# Confirm copy
if ! confirm "Proceed to copy files (this will create per-file backups in session $SESSION_ID)?"; then
  echo -e "${YELLOW}[CANCELLED] No changes made.${RESET}"
  exit 0
fi

# Copy loop with progress + summary
declare -A SUMMARY  # key: repo:file -> OK|SKIPPED|FAILED
count=0
total=$(( ${#targets[@]} * ${#FILTERED_FILES[@]} ))

echo -e "${YELLOW}[INFO] Copying... (session $SESSION_ID)${RESET}"
for repo in "${targets[@]}"; do
  # Ensure we can run git queries
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] $repo is not a git repo. Skipping.${RESET}"
    continue
  fi

  for f in "${FILTERED_FILES[@]}"; do
    ((count++))
    src="$SOURCE_REPO/$f"
    dest="$repo/$f"

    printf "${CYAN}[%d/%d] %s → %s${RESET}" "$count" "$total" "$f" "$repo"

    # Existence and path
    if [[ ! -f "$src" ]]; then
      echo -e " ${RED} [MISSING in source]${RESET}"
      SUMMARY["$repo:$f"]="FAILED"
      continue
    fi
    if ! ensure_dir "$(dirname "$dest")"; then
      echo -e " ${RED} [NO PATH]${RESET}"
      SUMMARY["$repo:$f"]="FAILED"
      continue
    fi

    # Skip binary?
    if [[ "$SKIP_BIN" -eq 1 ]] && ! is_binary "$src"; then
      true  # text file, ok
    elif [[ "$SKIP_BIN" -eq 1 ]] && is_binary "$src"; then
      echo -e " ${YELLOW} [SKIPPED binary]${RESET}"
      SUMMARY["$repo:$f"]="SKIPPED"
      continue
    fi

    # Conflict check (local mods in target)
    if target_has_local_changes "$repo" "$f"; then
      echo -e " ${YELLOW} [CONFLICT: local changes in target]${RESET}"
      if ! confirm "Overwrite $repo/$f anyway?"; then
        SUMMARY["$repo:$f"]="SKIPPED"
        continue
      fi
    fi

    # Critical file confirmation
    if match_globs "$f" "${CRITICAL_GLOBS[@]}"; then
      if ! confirm "Critical file match ($f). Overwrite in $repo?"; then
        echo -e " ${YELLOW} [SKIPPED critical]${RESET}"
        SUMMARY["$repo:$f"]="SKIPPED"
        continue
      fi
    fi

    # Backup current target (if exists)
    if [[ -f "$dest" ]]; then
      # encode slashes with dots
      enc="${f//\//.}"
      backup="$SESSION_PATH/${repo}.${enc}.file-backup"
      cp "$dest" "$backup" >>"$LOG_FILE" 2>&1 || true
    fi

    # Copy
    (
      cp "$src" "$dest"
    ) >>"$LOG_FILE" 2>&1 &
    spinner $!

    if [[ -f "$dest" ]]; then
      echo -e " ${GREEN}[OK]${RESET}"
      SUMMARY["$repo:$f"]="OK"
    else
      echo -e " ${RED}[FAILED]${RESET}"
      SUMMARY["$repo:$f"]="FAILED"
    fi
  done
done

echo
echo -e "${CYAN}================ Summary (session $SESSION_ID) ================${RESET}"
for repo in "${targets[@]}"; do
  echo -e "${CYAN}Repo: $repo${RESET}"
  for f in "${FILTERED_FILES[@]}"; do
    status="${SUMMARY["$repo:$f"]:-SKIPPED}"
    case "$status" in
      OK)      echo -e "  $f : ${GREEN}OK${RESET}" ;;
      FAILED)  echo -e "  $f : ${RED}FAILED${RESET}" ;;
      SKIPPED) echo -e "  $f : ${YELLOW}SKIPPED${RESET}" ;;
    esac
  done
done
echo -e "${CYAN}==============================================================${RESET}"
echo -e "${CYAN}[DONE] Backups stored in: $SESSION_PATH${RESET}"
echo -e "${CYAN}[NOTE] To revert, run again and choose 'Revert an entire previous run'.${RESET}"
