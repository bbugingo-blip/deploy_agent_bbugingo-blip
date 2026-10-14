# deploy_agent

`deploy_agent.sh` bootstraps, runs and archives logs for the Student Attendance Tracker, with clean Ctrl+C / Ctrl+Z handling during deployment.

## Repository layout

```
deploy_agent_<GithubUsername>/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py   (unmodified, from the course)
    ├── assets.csv              (10 students, 4 prior sessions each)
    └── config.json
```

## Running the script and choosing a feature

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh              # interactive menu (1 Deploy, 2 Run, 3 Archive, 4 Quit)
./deploy_agent.sh --deploy     # or use flags: --deploy | --run | --archive | --help
```

Both the menu and the flags are supported. Project names accept letters, digits, `_` and `-` only; the project is created as `attendance_tracker_<name>/`.

## Feature 1: Deploy

1. **Pre-flight:** checks `python3` (prints its version), `zip`, and that all three templates exist. Fails early with a clear message.
2. **Name:** asks for a name. If the directory exists, you choose overwrite or abort (abort exits with an error, nothing is touched).
3. **Structure:** creates `Helpers/` and `reports/`, copies `attendance_checker.py` (project root) and `config.json` (`Helpers/`) unmodified.
4. **Roster (`Helpers/assets.csv`):**
   - **A, copy:** asks how many students, copies that many rows plus the header from `templates/assets.csv`. Those rows carry 4 prior sessions, so `total_sessions` is set to **5**.
   - **B, generate:** asks how many (up to 20), builds rows from a names array with counts at 0, and sets `total_sessions` to **1**.
   - Rule: `total_sessions` = prior sessions in the roster + 1 (today).
5. **Permissions:** `chmod +x` on the checker, `chmod 600` on `config.json`; the resulting permission strings are printed.
6. **Thresholds:** asked whether to update. Warning (default 75) and failure (default 50) are validated as whole numbers 0–100 (empty input uses the default, text is rejected and re-asked, failure must be below warning). Then `sed -i -E` rewrites only the `"warning":` and `"failure":` values in place, so formatting and key order are unchanged.
7. **Verify:** deployment ends by launching Feature 2.

## Feature 2: Run

Asks for the project name, `cd`s into it and runs `python3 attendance_checker.py`. The terminal is handed to the instructor to mark students present/absent. Errors if the project does not exist.

## Feature 3: Archive logs

Asks for the project name, then for each of `reports/attendance.log` and `reports/absent.log`:

- if it exists, it is **moved** to `archives/attendance/attendance_YYYYMMDD_HHMMSS.log` or `archives/absent/absent_YYYYMMDD_HHMMSS.log` (directories are created as needed) and the final path is printed;
- if it does not exist (for example nobody was absent), it reports "skipped" and continues without crashing.

Moving (not copying) means the next run starts with fresh logs; timestamps keep every archived file unique.

## Interrupt handling (Ctrl+C / Ctrl+Z)

From the moment the project directory is about to be created until deployment finishes, `SIGINT` and `SIGTSTP` are trapped. On either signal the script:

1. prints that the deployment was interrupted,
2. runs `zip -r attendance_tracker_<name>_archive.zip attendance_tracker_<name>` on whatever exists so far,
3. deletes the incomplete directory so no half-made project is left behind,
4. prints "Session closed cleanly" and exits (code 130).

Other failures during deployment (`die`) also remove the partial directory. The trap is removed once deployment completes, so it does not affect the marking session in `attendance_checker.py`.

**How to test:** run `./deploy_agent.sh --deploy`, enter a name, and press Ctrl+C (or Ctrl+Z) at the roster prompt. Then run `ls` (only the `_archive.zip` remains) and `unzip -l attendance_tracker_<name>_archive.zip`. The zip contains the partial project, for example `attendance_checker.py`, `Helpers/config.json` and an empty `reports/`.

## How the deployment was tested

- `bash -n deploy_agent.sh` for syntax.
- Deployed with option A and option B; confirmed `Helpers/assets.csv` row counts, `total_sessions` (5 vs 1), and that `ls -l` shows `-rwxr-xr-x` on the checker and `-rw-------` on `config.json`.
- Updated thresholds and confirmed with `cat Helpers/config.json` that only those two values changed; tried empty, non-numeric and out-of-range input.
- Re-deployed over an existing name and chose both overwrite and abort.
- Ran the app, then archived: with `attendance.log` only (absent skipped) and with both logs present.
- Sent SIGINT mid-deploy and inspected the zip and the removed directory.
## Walkthrough video link
- https://www.youtube.com/watch?v=ptF5VsimmqE
