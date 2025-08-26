#!/bin/bash
# Sync changes across repos using Git patches (diffs/commits)
# - Uses data/ for logs + sessioned backups
# - Dry-run checks
# - 3-way tolerant apply (CRLF/whitespace)
# - Revert a whole session
# - Color summary + spinner

set -euo pipefail

# -------------------- Paths & globals --------------------
DATA_DIR="data/sync-changes"
SESS_DIR="$DATA_DIR/sessions"
LOG_FILE="$DATA_DIR/sync-changes.log"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
SESSION_ID="$TIMESTAMP"
SESSION_PATH="$SESS_DIR/$SESSION_ID"
PATCH_FILE="$DATA_DIR/tmp-$SESSION_ID.patch"

mkdir -p "$DATA_DIR" "$SESS_DIR" "$SESSION_PATH"
: > "$LOG_FILE"

# Colors
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; RESET="\033[0m"

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

# -------------------- Repo discovery --------------------
repos=()
for d in */ ; do [[ -d "$d/.git" ]] && repos+=("${d%/}"); done
if [[ ${#repos[@]} -eq 0 ]]; then
  echo -e "${RED}[ERROR] No Git repos found in current directory.${RESET}"
  exit 1
fi

# -------------------- Menu --------------------
echo -e "${CYAN}Main Menu:${RESET}"
echo "[1] Apply changes (generate patch from source → apply to targets)"
echo "[2] Revert a previous run (whole session)"
read -p "Enter choice: " main_choice

# -------------------- REVERT MODE --------------------
if [[ "$main_choice" == "2" ]]; then
  shopt -s nullglob
  sessions=( "$SESS_DIR"/* )
  shopt -u nullglob
  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No sessions found in $SESS_DIR.${RESET}"
    exit 1
  fi

  echo -e "${CYAN}Available sessions:${RESET}"
  for i in "${!sessions[@]}"; do sid=$(basename "${sessions[$i]}"); echo "[$i] $sid"; done
  read -p "Select a session to revert: " si
  SEL_SESSION="${sessions[$si]}"
  [[ -d "$SEL_SESSION" ]] || { echo -e "${RED}[ERROR] Invalid session.${RESET}"; exit 1; }

  echo -e "${YELLOW}[INFO] Dry-run preview of revert:${RESET}"
  # list stored repo backup patches inside session
  find "$SEL_SESSION" -maxdepth 1 -type f -name "*.pre.patch" -printf "Would reverse apply: %f\n"

  read -p "Proceed to revert this entire session? [y/N]: " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}[CANCELLED] Revert aborted.${RESET}"; exit 0; }

  echo -e "${YELLOW}[INFO] Reverting...${RESET}"
  while IFS= read -r bfile; do
    base=$(basename "$bfile")
    repo="${base%.pre.patch}"
    echo -ne "${CYAN}[REVERT] $repo ...${RESET}"
    (
      cd "$repo"
      # reverse apply the pre-change patch; be tolerant to whitespace/CRLF
      git apply -R --ignore-space-change --whitespace=nowarn "../$bfile"
      git add -A
      git commit -m "Revert sync session $(basename "$SEL_SESSION")"
    ) >> "$LOG_FILE" 2>&1 && echo -e "${GREEN} [REVERTED]${RESET}" || echo -e "${RED} [FAILED]${RESET}"
  done < <(find "$SEL_SESSION" -maxdepth 1 -type f -name "*.pre.patch" -print)

  echo -e "${GREEN}[DONE] Revert complete for session $(basename "$SEL_SESSION"). Logs in $LOG_FILE${RESET}"
  exit 0
fi

# -------------------- APPLY MODE --------------------
# Pick source repo
echo -e "${CYAN}Available repos:${RESET}"
for i in "${!repos[@]}"; do echo "[$i] ${repos[$i]}"; done
read -p "Enter source repo number: " src_choice
SOURCE_REPO=${repos[$src_choice]}

echo
echo -e "${CYAN}Copy options (what to export from source):${RESET}"
echo "[1] Uncommitted changes (working diff)"
echo "[2] Last commit (HEAD)"
echo "[3] Commit range (abc123..def456)"
echo "[4] Select specific commits (from recent history)"
read -p "Enter choice: " copy_choice

# Generate patch from source
echo -e "${CYAN}[INFO] Generating patch from ${SOURCE_REPO} ...${RESET}"
(
  cd "$SOURCE_REPO"
  case $copy_choice in
    1)
      # Uncommitted changes with extra context; binary-safe
      git diff -U10 --binary > "../$PATCH_FILE"
      ;;
    2)
      git format-patch -1 HEAD --stdout > "../$PATCH_FILE"
      ;;
    3)
      read -p "Enter commit range (e.g. abc123..def456): " range
      git format-patch "$range" --stdout > "../$PATCH_FILE"
      ;;
    4)
      git log --oneline -n 30
      read -p "Enter commit hashes (space-separated, newest first): " hashes
      git format-patch $hashes --stdout > "../$PATCH_FILE"
      ;;
    *)
      echo -e "${RED}[ERROR] Invalid choice${RESET}"; exit 1;;
  esac
) >> "$LOG_FILE" 2>&1

# Pick targets
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

# Dry-run checks
echo
echo -e "${YELLOW}[INFO] Running Dry-Run checks...${RESET}"
declare -A DRY
c=1; t=${#targets[@]}
for repo in "${targets[@]}"; do
  echo -ne "${CYAN}[CHECK] ($c/$t) $repo ...${RESET}"
  (
    cd "$repo"
    if [[ "$copy_choice" == "1" ]]; then
      git apply --check --3way --ignore-space-change --whitespace=nowarn "../$PATCH_FILE"
    else
      git am --check "../$PATCH_FILE"; git am --abort || true
    fi
  ) >> "$LOG_FILE" 2>&1 && { echo -e "${GREEN} [OK]${RESET}"; DRY["$repo"]="OK"; } || { echo -e "${RED} [FAILED]${RESET}"; DRY["$repo"]="FAILED"; }
  ((c++))
done

read -p "Apply these changes permanently? [y/N]: " go
[[ "${go:-}" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}[DONE] Dry-Run only. Logs in $LOG_FILE${RESET}"; rm -f "$PATCH_FILE"; exit 0; }

# Apply with per-repo pre-change backups (stored as patches)
echo
echo -e "${YELLOW}[INFO] Applying changes (session $SESSION_ID). Backups → $SESSION_PATH${RESET}"
declare -A RESULT
c=1
for repo in "${targets[@]}"; do
  echo -ne "${CYAN}[APPLY] ($c/$t) $repo ...${RESET}"
  (
    cd "$repo"
    # Save pre-change state as a patch (to allow full session revert)
    git diff -U10 --binary > "../$SESSION_PATH/${repo}.pre.patch"

    if [[ "$copy_choice" == "1" ]]; then
      # Uncommitted patch: apply with 3-way tolerance, then commit to capture state
      git apply --3way --ignore-space-change --whitespace=nowarn --reject "../$PATCH_FILE"
      git add -A
      git commit -m "Sync apply (uncommitted) from ${SOURCE_REPO} @ $SESSION_ID" || true
    else
      # Commit-based patch: use git am with 3-way; keep CRs; abort on fail
      git am -3 --keep-cr "../$PATCH_FILE" || git am --abort
    fi
  ) >> "$LOG_FILE" 2>&1 && { echo -e "${GREEN} [APPLIED]${RESET}"; RESULT["$repo"]="APPLIED"; } || { echo -e "${RED} [FAILED]${RESET}"; RESULT["$repo"]="FAILED"; }
  ((c++))
done

# Offer immediate revert of this session
echo
read -p "Revert this session now? [y/N]: " revnow
if [[ "${revnow:-}" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}[INFO] Reverting session $SESSION_ID ...${RESET}"
  for repo in "${targets[@]}"; do
    bfile="$SESSION_PATH/${repo}.pre.patch"
    [[ -f "$bfile" ]] || continue
    echo -ne "${CYAN}[REVERT] $repo ...${RESET}"
    (
      cd "$repo"
      git apply -R --ignore-space-change --whitespace=nowarn "../$bfile"
      git add -A
      git commit -m "Revert sync session $SESSION_ID"
    ) >> "$LOG_FILE" 2>&1 && echo -e "${GREEN} [REVERTED]${RESET}" || echo -e "${RED} [FAILED]${RESET}"
  done
fi

# Summary
echo
echo -e "${CYAN}================ Summary (session $SESSION_ID) ================${RESET}"
for repo in "${targets[@]}"; do
  status="${RESULT[$repo]:-N/A}"
  case "$status" in
    APPLIED) echo -e "  $repo : ${GREEN}APPLIED${RESET}" ;;
    FAILED)  echo -e "  $repo : ${RED}FAILED${RESET}" ;;
    *)       echo -e "  $repo : ${YELLOW}$status${RESET}" ;;
  esac
done
echo -e "${CYAN}==============================================================${RESET}"
echo -e "${CYAN}[DONE] Logs: $LOG_FILE | Backups: $SESSION_PATH | Patch: $PATCH_FILE${RESET}"
