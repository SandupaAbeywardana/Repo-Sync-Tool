# 🔄 Repo Sync Tools

Two complementary tools for syncing changes across multiple Git repositories. These scripts are designed for **multi-portal/multi-repo projects** where changes often need to be propagated across similar but not identical repos.

* **`sync-changes.sh`** → Patch-based syncing (uses Git diffs/commits). Best when changes are **logical edits** that can be merged.
* **`sync-files.sh`** → Whole-file syncing (copies changed files entirely). Best when you need **exact file replacement**.

Both are menu-driven, safe, and store logs & backups in the `data/` folder.

---

## ✨ Shared Features

* ✅ Interactive menus for source & target selection
* ✅ Supports **selecting all repos except source**
* ✅ **Dry-Run previews** (see what will happen before changes)
* ✅ **Session-based backups** stored in `data/sessions/<timestamp>/`
* ✅ **Full session revert** (reverts all repos to their pre-sync state)
* ✅ **Color-coded output** (green = success, yellow = skipped, red = failed)
* ✅ **Spinner/progress feedback** for long runs
* ✅ Detailed **logs** saved in `data/`
* ✅ Safe for production repos (backups ensure rollback)

---

## ⚙️ Setup

1. Place the scripts in the parent folder containing all repos:

   ```
   ├── sync-changes.sh
   ├── sync-files.sh
   ├── repo1/
   ├── repo2/
   ├── repo3/
   ```

2. Make them executable:

   ```bash
   chmod +x sync-changes.sh sync-files.sh
   ```

3. Run via **Git Bash** or **WSL** on Windows:

   ```bash
   ./sync-changes.sh
   ./sync-files.sh
   ```

---

## 🚀 Tool 1: `sync-changes.sh` (Patch-based)

### 📌 When to Use

* When you want to **sync code changes as diffs/commits** rather than replacing entire files.
* Useful for **merging logical changes** while preserving repo-specific modifications.
* Works best if repos share common history or have minimal divergence.

### 🔧 Options

* **Uncommitted changes** (working directory diff)
* **Last commit (HEAD)**
* **Commit range** (e.g. `abc123..def456`)
* **Select specific commits** (choose interactively from history)

### 🛠 Workflow

1. Select source repo.
2. Choose change type (diff/commit/range).
3. Select target repos.
4. Script generates a patch → runs Dry-Run → Apply.
5. Each target repo gets a **pre-change backup patch** stored in:

   ```
   data/sessions/<timestamp>/<repo>.pre.patch
   ```
6. To revert, select session → all repos restored to previous state.

### 🔐 Safety Features

* Uses `git apply` with **3-way merges** and whitespace tolerance for uncommitted patches.
* Uses `git am -3 --keep-cr` for commit-based patches (handles CRLF issues).
* Session-based revert ensures you can undo everything in one step.

---

## 🚀 Tool 2: `sync-files.sh` (Whole-file)

### 📌 When to Use

* When you want to **copy entire files** instead of diffs.
* Useful when files diverged too much for patches to apply cleanly.
* Best for **large rewrites, configs, or generated code** where full replacement is safer.

### 🔧 Options

* **Changed since last commit** (default)
* **Changed in a specific commit**
* **Changed in a commit range**
* **Interactive selection** (pick files manually from detected changes)
* **Include staged / unstaged / both**

### 🛠 Workflow

1. Select source repo.
2. Choose which changed files to sync.
3. Dry-Run preview of files → confirm.
4. Each file is copied to target repos, with **per-file backups** under:

   ```
   data/sessions/<timestamp>/<repo>.<path.with.dots>.file-backup
   ```
5. Session revert restores all copied files.

### 🔐 Extra Safety

* Confirmation for **critical files** (like `.env`, configs, providers).
* Skips or confirms on **binary files**.
* Warns if **target repo already modified the file**.
* Creates missing directories only after confirmation.
* Excludes folders by default (`node_modules/`, `vendor/`, `storage/`, `.git/`, `data/`).

---

## 📂 Data Storage

* **Logs**

  * `data/sync-changes.log`
  * `data/sync-files.log`
* **Backups**

  * Patch backups (for `sync-changes.sh`): `data/sessions/<timestamp>/<repo>.pre.patch`
  * File backups (for `sync-files.sh`): `data/sessions/<timestamp>/<repo>.<path.with.dots>.file-backup`
* **Temp patches** (for patch sync): `data/tmp-<timestamp>.patch`

---

## ✅ Example Workflows

### Using `sync-changes.sh`

```bash
./sync-changes.sh
# → Select Apply changes
# → Pick source repo: repo1
# → Choose "Last commit"
# → Select target repos: repo2 repo3
# → Dry-Run passes
# → Apply permanently
# → Backups stored in data/sessions/<timestamp>/
```

### Using `sync-files.sh`

```bash
./sync-files.sh
# → Select Copy changed files
# → Pick source repo: repo1
# → Choose "Changed since last commit"
# → Preview file list
# → Select targets: repo2 repo3
# → Confirm & apply
# → Backups stored in data/sessions/<timestamp>/
```

---

## ⚠️ Best Practices

* Always run with **Dry-Run** first.
* Revert entire sessions if something goes wrong — don’t cherry-pick.
* Run only in clean working directories (commit/stash local changes first).
* For **binary files**, prefer `sync-files.sh` (patches often fail).
* For **source code changes**, prefer `sync-changes.sh` (keeps Git history clean).
* Review `data/sync-*.log` if errors occur.
* Regularly clean up old sessions if disk space is a concern.

---

## 👨‍💻 Developer

Developed and maintained by **CyberMatrix**.

---

## 📜 License

Released under the **MIT License**.
