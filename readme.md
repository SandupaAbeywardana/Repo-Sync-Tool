# 🔄 Repo Sync Tool

A powerful shell script to **sync changes across multiple Git repositories** with maximum safety and flexibility.

---

## ✨ Features

- ✅ Menu-driven workflow (**Apply** or **Revert**)
- ✅ **Dry-Run** mode before applying changes to ensure compatibility
- ✅ **Timestamped backups** per repo (`repo.sync-backup-YYYYMMDDHHMMSS`)
- ✅ Multiple rollback points supported
- ✅ Selective revert menu (choose which repos/backups to undo)
- ✅ **Color-coded output** for clarity (green = success, red = failure, yellow = warnings)
- ✅ **Spinner progress** for long-running operations
- ✅ Detailed **logs** saved for troubleshooting
- ✅ Works **without touching Git history** (no extra branches created)
- ✅ Supports syncing **uncommitted changes, last commit, commit ranges, or specific commits**

---

## ⚙️ Setup

1. Save the script as `sync-changes.sh` in the parent folder containing all repos:

   ```
   ├── sync-changes.sh
   ├── repo1/
   ├── repo2/
   ├── repo3/
   ```

2. Make it executable:

   ```bash
   chmod +x sync-changes.sh
   ```

---

## 🚀 Usage

### 1. Run the tool

```bash
./sync-changes.sh
```

You’ll see a **main menu**:

```
Main Menu:
[1] Apply changes
[2] Revert changes (from backups)
```

---

### 2. Apply changes

1. Choose **Apply changes**.
2. Select the **source repo** (where your changes are).
3. Choose what to copy:

   - `[1]` Uncommitted changes (working directory diff)
   - `[2]` Last commit (HEAD)
   - `[3]` Commit range (e.g., `abc123..def456`)
   - `[4]` Select specific commits (from recent history)

4. Select **target repos** (specific repos or all except source).
5. The script runs a **Dry-Run check** in each target repo to ensure compatibility.
6. If all checks pass, confirm to **apply permanently**.

   - Each repo gets its own backup file, e.g.:

     ```
     repo1.sync-backup-20250826123015
     repo2.sync-backup-20250826123015
     ```

---

### 3. Revert changes

1. Choose **Revert changes** from the main menu.
2. The script will list all available backup files (`.sync-backup-*`).
3. You can:

   - Select specific repos/backups to revert
   - Or choose `all` to revert everything at once

4. The script restores each repo back to its pre-sync state using reverse patches (`git apply -R`).

You can also **revert immediately after applying** (script will ask after sync).

---

## 📂 Backups

- Backups are automatically created before applying changes.
- Saved as timestamped patch files:

  ```
  repo1.sync-backup-20250826124530
  repo2.sync-backup-20250826124530
  ```

- Each backup is a **diff file** containing the original state.
- Reverting applies the diff in reverse to restore state.
- Multiple backups are supported (you can revert to any previous one).

---

## 📜 Logs

- A log file is maintained for every run:

  ```
  sync-changes.log
  ```

- Contains detailed command outputs, error messages, and conflict details.
- Use this log for troubleshooting when a patch does not apply cleanly.

---

## ✅ Example Workflow

```bash
./sync-changes.sh
# → Select Apply changes
# → Pick source repo: repo1
# → Choose "Uncommitted changes"
# → Select target repos: repo2 repo3
# → Dry-Run passes
# → Apply permanently (yes)
# → Done, backups saved: repo2.sync-backup-..., repo3.sync-backup-...
```

To revert later:

```bash
./sync-changes.sh
# → Select Revert changes
# → Choose repo2.sync-backup-...
# → Repo restored
```

---

## 🔐 Safety & Best Practices

- Always review changes with **Dry-Run** before applying.
- Use **commit ranges** or **specific commits** for precise syncing.
- Keep backups for rollback — timestamped backups make it easy to undo at any time.
- If conflicts occur, check `sync-changes.log` for details.

---

## 👨‍💻 Developer

Developed and maintained by **CyberMatrix**.

---

## 📜 License

This project is released under the **MIT License**.
