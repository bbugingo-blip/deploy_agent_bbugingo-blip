#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
cd "$SCRIPT_DIR" || { echo "ERROR: cannot enter $SCRIPT_DIR" >&2; exit 1; }

PROJECT_DIR=""
DEPLOYING=0

SAMPLE_NAMES=("Alice Johnson" "Bob Smith" "Carol Mukamana" "David Kamau"
              "Eve Uwase" "Frank Okello" "Grace Mutoni" "Henry Nkurunziza"
              "Irene Achieng" "James Habimana" "Kelly Ingabire" "Liam Mugisha"
              "Mary Wanjiku" "Noah Niyonzima" "Olivia Teta" "Peter Otieno"
              "Queen Uwimana" "Robert Kagame" "Sarah Nyambura" "Tom Ishimwe")

info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }
err()  { echo "[x] $*" >&2; }

die() {
    err "$*"
    if [[ $DEPLOYING -eq 1 && -n $PROJECT_DIR && -d $PROJECT_DIR ]]; then
        err "Removing incomplete project directory '$PROJECT_DIR'."
        rm -rf -- "$PROJECT_DIR"
    fi
    exit 1
}

is_number() { [[ ${1:-} =~ ^[0-9]+$ ]]; }

ask_count() {
    local prompt=$1 max=$2 v
    while true; do
        read -r -p "$prompt (1-$max): " v
        if is_number "$v" && (( v >= 1 && v <= max )); then
            REPLY_NUM=$v
            return
        fi
        err "Please enter a whole number between 1 and $max."
    done
}

ask_project_name() {
    local v
    while true; do
        read -r -p "Project name (attendance_tracker_<name>): " v
        if [[ $v =~ ^[A-Za-z0-9_-]+$ ]]; then
            PROJECT_NAME=$v
            return
        fi
        err "Use only letters, digits, '_' or '-' (no spaces, no empty input)."
    done
}

on_interrupt() {
    local sig=$1
    trap '' INT TSTP
    echo
    err "Deployment interrupted by $sig."
    if [[ -n $PROJECT_DIR && -d $PROJECT_DIR ]]; then
        local zipfile="${PROJECT_DIR}_archive.zip"
        info "Archiving the incomplete project into '$zipfile' ..."
        if zip -rq "$zipfile" "$PROJECT_DIR"; then
            ok "Archive created: $zipfile"
        else
            err "Could not create the archive."
        fi
        rm -rf -- "$PROJECT_DIR"
        ok "Removed incomplete directory '$PROJECT_DIR'."
    else
        info "Nothing had been created yet, so there is nothing to archive."
    fi
    echo "Session closed cleanly."
    exit 130
}

preflight_checks() {
    info "Running pre-flight checks ..."
    command -v python3 >/dev/null 2>&1 || die "python3 is not installed. Install it and try again."
    ok "$(python3 --version 2>&1)"
    command -v zip >/dev/null 2>&1 || die "zip is not installed. Install it (e.g. 'sudo apt install zip') and try again."
    ok "zip found."
    local f
    for f in attendance_checker.py assets.csv config.json; do
        [[ -f "$TEMPLATES_DIR/$f" ]] || die "Missing template: templates/$f"
    done
    ok "All template files present."
}

build_roster_from_template() {
    local total max
    total=$(( $(wc -l < "$TEMPLATES_DIR/assets.csv") ))
    max=$(( $(grep -c . "$TEMPLATES_DIR/assets.csv") - 1 ))
    (( max >= 1 )) || die "templates/assets.csv has no student rows."
    ask_count "How many students to copy from the template" "$max"
    head -n $(( REPLY_NUM + 1 )) "$TEMPLATES_DIR/assets.csv" > "$PROJECT_DIR/Helpers/assets.csv" \
        || die "Could not write Helpers/assets.csv (permission denied?)."
    SESSIONS=5
    ok "Copied $REPLY_NUM students (+ header). total_sessions will be $SESSIONS."
}

build_roster_fresh() {
    local max=${#SAMPLE_NAMES[@]} i name email
    ask_count "How many students to generate" "$max"
    {
        echo "Email,Names,Attendance Count,Absence Count"
        for (( i = 0; i < REPLY_NUM; i++ )); do
            name=${SAMPLE_NAMES[$i]}
            email=$(echo "$name" | tr '[:upper:] ' '[:lower:].')@example.com
            echo "$email,$name,0,0"
        done
    } > "$PROJECT_DIR/Helpers/assets.csv" \
        || die "Could not write Helpers/assets.csv (permission denied?)."
    SESSIONS=1
    ok "Generated $REPLY_NUM students. total_sessions will be $SESSIONS."
}

update_thresholds() {
    local ans warn fail cfg="$PROJECT_DIR/Helpers/config.json"
    read -r -p "Update the attendance alert thresholds? [y/N]: " ans
    [[ $ans =~ ^[Yy]$ ]] || { info "Keeping default thresholds (warning 75, failure 50)."; return; }

    while true; do
        read -r -p "New WARNING threshold [75]: " warn
        warn=${warn:-75}
        if is_number "$warn" && (( warn >= 0 && warn <= 100 )); then break; fi
        err "Warning must be a number from 0 to 100."
    done
    while true; do
        read -r -p "New FAILURE threshold [50]: " fail
        fail=${fail:-50}
        if is_number "$fail" && (( fail >= 0 && fail <= 100 )); then
            if (( fail < warn )); then break; fi
            err "Failure threshold must be lower than the warning threshold ($warn)."
        else
            err "Failure must be a number from 0 to 100."
        fi
    done

    sed -i.bak -E \
        -e "s/(\"warning\":[[:space:]]*)[0-9]+/\1${warn}/" \
        -e "s/(\"failure\":[[:space:]]*)[0-9]+/\1${fail}/" \
        "$cfg" || die "sed failed while updating config.json."
    rm -f -- "$cfg.bak"
    ok "Thresholds updated: warning=$warn, failure=$fail"
    grep -E '"(warning|failure)"' "$cfg"
}

deploy() {
    local ans
    preflight_checks
    ask_project_name
    PROJECT_DIR="attendance_tracker_${PROJECT_NAME}"

    if [[ -e $PROJECT_DIR ]]; then
        read -r -p "'$PROJECT_DIR' already exists. Overwrite it? [y/N]: " ans
        if [[ $ans =~ ^[Yy]$ ]]; then
            rm -rf -- "$PROJECT_DIR" || die "Cannot remove existing '$PROJECT_DIR' (permission denied?)."
        else
            PROJECT_DIR=""
            die "Aborted: '$PROJECT_NAME' already exists and was not overwritten."
        fi
    fi

    DEPLOYING=1
    trap 'on_interrupt SIGINT'  INT
    trap 'on_interrupt SIGTSTP' TSTP

    info "Creating directory structure ..."
    mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" \
        || die "Could not create directories (permission denied?)."

    cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py" \
        || die "Could not copy attendance_checker.py."
    cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/config.json" \
        || die "Could not copy config.json."

    echo
    echo "How should the roster (Helpers/assets.csv) be built?"
    echo "  A) Copy rows from templates/assets.csv"
    echo "  B) Generate a fresh roster (counts start at 0)"
    while true; do
        read -r -p "Choose A or B: " ans
        case ${ans^^} in
            A) build_roster_from_template; break ;;
            B) build_roster_fresh; break ;;
            *) err "Please type A or B." ;;
        esac
    done

    sed -i.bak -E "s/(\"total_sessions\":[[:space:]]*)[0-9]+/\1${SESSIONS}/" \
        "$PROJECT_DIR/Helpers/config.json" || die "Could not set total_sessions."
    rm -f -- "$PROJECT_DIR/Helpers/config.json.bak"

    info "Setting permissions ..."
    chmod +x "$PROJECT_DIR/attendance_checker.py" \
        || die "chmod +x failed on attendance_checker.py."
    chmod 600 "$PROJECT_DIR/Helpers/config.json" \
        || die "chmod 600 failed on config.json."
    ok "attendance_checker.py -> $(stat -c '%A' "$PROJECT_DIR/attendance_checker.py" 2>/dev/null || ls -l "$PROJECT_DIR/attendance_checker.py" | cut -c1-10) (executable)"
    ok "Helpers/config.json   -> $(stat -c '%A' "$PROJECT_DIR/Helpers/config.json" 2>/dev/null || ls -l "$PROJECT_DIR/Helpers/config.json" | cut -c1-10) (owner read/write only)"

    update_thresholds

    DEPLOYING=0
    trap - INT TSTP
    ok "Deployment complete: $PROJECT_DIR/"
    echo
    info "Verifying the deployment by starting the application ..."
    run_app "$PROJECT_NAME"
}

run_app() {
    local name=${1:-} dir
    if [[ -z $name ]]; then ask_project_name; name=$PROJECT_NAME; fi
    dir="attendance_tracker_${name}"
    [[ -d $dir ]] || die "Project '$dir' does not exist. Deploy it first (Feature 1)."
    [[ -f $dir/attendance_checker.py ]] || die "'$dir' is missing attendance_checker.py."
    command -v python3 >/dev/null 2>&1 || die "python3 is not installed."
    ( cd "$dir" && python3 attendance_checker.py )
    local rc=$?
    (( rc == 0 )) && ok "Application finished." || err "Application exited with code $rc."
    return 0
}

archive_logs() {
    local dir ts archived=0 log kind dest
    ask_project_name
    dir="attendance_tracker_${PROJECT_NAME}"
    [[ -d $dir ]] || die "Project '$dir' does not exist."
    ts=$(date +%Y%m%d_%H%M%S)

    for kind in attendance absent; do
        log="$dir/reports/${kind}.log"
        if [[ -f $log ]]; then
            mkdir -p "$dir/archives/$kind" || die "Cannot create $dir/archives/$kind."
            dest="$dir/archives/$kind/${kind}_${ts}.log"
            if mv -- "$log" "$dest"; then
                ok "Archived ${kind}.log -> $dest"
                archived=$(( archived + 1 ))
            else
                err "Could not archive $log."
            fi
        else
            info "No ${kind}.log found in $dir/reports/ (skipped)."
        fi
    done
    (( archived == 0 )) && info "Nothing was archived. Run the application first." || true
}

usage() {
    cat <<EOF
Usage: $0 [--deploy | --run | --archive | --help]
With no option an interactive menu is shown.
EOF
}

menu() {
    echo "=============================="
    echo "  Attendance Tracker Deployer"
    echo "=============================="
    echo "  1) Deploy the application"
    echo "  2) Run the application"
    echo "  3) Archive the logs"
    echo "  4) Quit"
    local c
    read -r -p "Select an option [1-4]: " c
    case $c in
        1) deploy ;;
        2) run_app ;;
        3) archive_logs ;;
        4) exit 0 ;;
        *) err "Invalid choice."; exit 1 ;;
    esac
}

case ${1:-} in
    --deploy)  deploy ;;
    --run)     run_app ;;
    --archive) archive_logs ;;
    --help|-h) usage ;;
    "")        menu ;;
    *)         usage; exit 1 ;;
esac
