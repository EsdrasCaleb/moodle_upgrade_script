#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Prompt user to confirm backup
read -p "Have you backed up your Moodle data and database? (yes/no): " backup_confirm
if [[ "$backup_confirm" != "yes" ]]; then
    echo "Backup is required before proceeding. Exiting."
    exit 1
fi

MOODLE_DIR=$1
CURRENT_VERSION=$2
TARGET_VERSION=$3

if [[ -z "$MOODLE_DIR" || -z "$CURRENT_VERSION" || -z "$TARGET_VERSION" ]]; then
    echo "Usage: $0 <moodle_root_dir> <current_version> <target_version>"
    exit 1
fi

# Ensure the Moodle directory is a git repository
if [[ ! -d "$MOODLE_DIR/.git" ]]; then
    echo "Error: The specified Moodle directory is not a git repository."
    exit 1
fi

# Define the upgrade path based on Moodle's documentation
declare -A UPGRADE_PATH
UPGRADE_PATH=(
    [1.0]=1.9 [1.9]=2.2 [2.2]=2.7 [2.7]=3.1 [3.1]=3.5
    [3.5]=3.9 [3.6]=3.11 [3.9]=4.1 [3.11]=4.2 [4.0]=4.1 [4.1]=4.5 [4.2]=4.5 [4.3]=4.5
)

# Function to transform version string
to_moodle_version_format() {
    local version=$1
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        if [[ "${BASH_REMATCH[1]}" -ge 4 ]]; then
            echo "${BASH_REMATCH[1]}0${BASH_REMATCH[2]}"
        else
            echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
        fi
    else
        echo "Error: Invalid version format $version" >&2
        exit 1
    fi
}

# Function to perform the upgrade using git
upgrade_moodle() {
    local current=$1
    local next=$2
    local dir=$3

    if [[ ! -d "$dir/.git" ]]; then
        echo "Error: The specified Moodle directory is not a git repository."
        exit 1
    fi

    local next_formatted=$(to_moodle_version_format "$next")

    echo "Upgrading Moodle from $current to $next stable..."
    cd "$dir"
    git fetch --all
    git reset --hard
    git checkout "MOODLE_${next_formatted}_STABLE"
    php admin/cli/upgrade.php --non-interactive
    echo "Upgrade to $next completed."
}

# Perform the upgrade step-by-step
current=$CURRENT_VERSION
#update to the current stable
upgrade_moodle "$current" "$current" "$MOODLE_DIR"
while [[ "$current" != "$TARGET_VERSION" ]]; do
    if [[ -z "${UPGRADE_PATH[$current]}" ]]; then
        echo "No upgrade path found from version $current. Check Moodle's upgrade documentation."
        exit 1
    fi
    next_version=${UPGRADE_PATH[$current]}
    upgrade_moodle "$current" "$next_version" "$MOODLE_DIR"
    current=$next_version

done

echo "Moodle successfully upgraded to version $TARGET_VERSION!"
