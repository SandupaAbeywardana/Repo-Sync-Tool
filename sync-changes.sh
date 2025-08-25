#!/bin/bash
# Sync changes between repos with menu-driven Apply/Revert
# Timestamped file-based backups, logging, colors, spinner, and summary

PATCH_FILE="/tmp/repo_changes.patch"
LOG_FILE="sync-changes.log"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Spinner
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
}

# Clear old log
> "$LOG_FILE"

# -------- Menu 1: Apply or Revert --------
echo -e "${CYAN}Main Menu:${RESET}"
echo "[1] Apply changes"
echo "[2] Revert changes (from backups)"
read -p "Enter choice: " main_choice

# -------- Revert Mode --------
if [[ "$main_choice" == "2" ]]; then
  echo -e "${YELLOW}[INFO] Checking for available backups...${RESET}"
  backups=()
  for file in *.sync-backup-*; do
    repo=$(echo "$file" | sed -E 's/\.sync-backup-.*//')
    [[ -d "$repo/.git" ]] && backups+=("$file")
  done

  if [[ ${#backups[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No backups found. Nothing to revert.${RESET}"
    exit 1
  fi

  echo -e "${CYAN}Available backups:${RESET}"
  for i in "${!backups[@]}"; do echo "[$i] ${backups[$i]}"; done
  echo "[a] All"
  read -p "Select backups to revert (space-separated or 'a'): " choices

  targets=()
  if [[ "$choices" == "a" ]]; then
    targets=("${backups[@]}")
  else
    for choice in $choices; do targets+=("${backups[$choice]}"); done
  fi

  for file in "${targets[@]}"; do
    repo=$(echo "$file" | sed -E 's/\.sync-backup-.*//')
    echo -ne "${CYAN}[REVERT] $repo ($file) ...${RESET}"
    cd "$repo" || continue
    if git apply -R "../$file" >> "../$LOG_FILE" 2>&1; then
      echo -e "${GREEN} [REVERTED]${RESET}"
    else
      echo -e "${RED} [FAILED]${RESET}"
    fi
    cd ..
  done

  echo -e "${GREEN}[DONE] Revert complete. Logs in $LOG_FILE${RESET}"
  exit 0
fi

# -------- Apply Mode --------
# Step 1: Detect repos
repos=()
for d in */ ; do [[ -d "$d/.git" ]] && repos+=("${d%/}"); done

# Step 2: Select source repo
echo -e "${CYAN}Available repos:${RESET}"
for i in "${!repos[@]}"; do echo "[$i] ${repos[$i]}"; done
read -p "Enter source repo number: " src_choice
SOURCE_REPO=${repos[$src_choice]}

# Step 3: Copy mode
echo
echo -e "${CYAN}Copy options:${RESET}"
echo "[1] Uncommitted changes"
echo "[2] Last commit"
echo "[3] Commit range"
echo "[4] Select commits"
read -p "Enter choice: " copy_choice

# Step 4: Generate patch
cd "$SOURCE_REPO" || exit 1
case $copy_choice in
  1) git diff > "$PATCH_FILE";;
  2) git format-patch -1 HEAD --stdout > "$PATCH_FILE";;
  3) read -p "Enter commit range (e.g. abc..def): " range
     git format-patch "$range" --stdout > "$PATCH_FILE";;
  4) git log --oneline -n 20
     read -p "Enter commit hashes: " hashes
     git format-patch $hashes --stdout > "$PATCH_FILE";;
  *) echo -e "${RED}[ERROR] Invalid choice${RESET}"; exit 1;;
esac
cd ..

# Step 5: Select target repos
echo
echo -e "${CYAN}Target repos:${RESET}"
for i in "${!repos[@]}"; do [[ "${repos[$i]}" != "$SOURCE_REPO" ]] && echo "[$i] ${repos[$i]}"; done
echo "[a] All (except source)"
read -p "Enter repos (or 'a'): " choices

targets=()
if [[ "$choices" == "a" ]]; then
  for repo in "${repos[@]}"; do [[ "$repo" != "$SOURCE_REPO" ]] && targets+=("$repo"); done
else
  for choice in $choices; do
    repo=${repos[$choice]}
    [[ "$repo" != "$SOURCE_REPO" ]] && targets+=("$repo")
  done
fi

# Step 6: Dry-Run
echo -e "${YELLOW}[INFO] Running Dry-Run...${RESET}"
declare -A results
count=1; total=${#targets[@]}

for repo in "${targets[@]}"; do
  echo -ne "${CYAN}[CHECK] ($count/$total) $repo ...${RESET}"
  (
    cd "$repo" || exit 1
    if [[ "$copy_choice" == "1" ]]; then
      git apply --check "$PATCH_FILE"
    else
      git am --check "$PATCH_FILE"; git am --abort
    fi
  ) >>"$LOG_FILE" 2>&1 &
  spinner $!
  if [[ $? -eq 0 ]]; then
    results["$repo"]="OK"; echo -e "${GREEN} [OK]${RESET}"
  else
    results["$repo"]="FAILED"; echo -e "${RED} [FAILED]${RESET}"
  fi
  ((count++))
done

# Step 7: Ask to apply
echo
read -p "Apply these changes permanently? (y/n): " apply_choice
[[ "$apply_choice" != "y" ]] && { echo -e "${YELLOW}[DONE] Dry-Run only.${RESET}"; rm "$PATCH_FILE"; exit 0; }

# Step 8: Apply with timestamped backups
echo -e "${YELLOW}[INFO] Applying changes (saving backups)...${RESET}"
count=1
for repo in "${targets[@]}"; do
  echo -ne "${CYAN}[APPLY] ($count/$total) $repo ...${RESET}"
  cd "$repo" || continue
  git diff > "../$repo.sync-backup-$TIMESTAMP"
  if [[ "$copy_choice" == "1" ]]; then
    git apply "$PATCH_FILE"
  else
    git am "$PATCH_FILE" || git am --abort
  fi >> "../$LOG_FILE" 2>&1
  [[ $? -eq 0 ]] && results["$repo"]="APPLIED" && echo -e "${GREEN} [APPLIED]${RESET}" || results["$repo"]="FAILED" && echo -e "${RED} [FAILED]${RESET}"
  cd ..
  ((count++))
done

# Step 9: Offer immediate revert
echo
read -p "Revert applied changes now? (y/n): " revert_choice
if [[ "$revert_choice" == "y" ]]; then
  echo -e "${YELLOW}[INFO] Reverting repos...${RESET}"
  for repo in "${targets[@]}"; do
    backup_file=$(ls -t ${repo}.sync-backup-* 2>/dev/null | head -n1)
    [[ -f "$backup_file" ]] || continue
    echo -ne "${CYAN}[REVERT] $repo ($backup_file) ...${RESET}"
    cd "$repo" || continue
    git apply -R "../$backup_file" >> "../$LOG_FILE" 2>&1
    cd ..
    echo -e "${GREEN} [REVERTED]${RESET}"
  done
fi

# Step 10: Summary
echo
echo -e "${CYAN}================ Summary ================${RESET}"
for repo in "${targets[@]}"; do
  printf "%-10s : %s\n" "$repo" "${results[$repo]}"
done
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}[DONE] Finished. Logs in $LOG_FILE${RESET}"
