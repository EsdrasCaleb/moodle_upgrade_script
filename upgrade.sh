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
    [3.5]=3.9 [3.9]=3.11 [3.11]=4.0 [4.0]=4.1 [4.1]=4.2 [4.2]=4.3 [4.3]=4.5
)

# Function to perform the upgrade using git
upgrade_moodle() {
    local current=$1
    local next=$2
    local dir=$3

    if [[ ! -d "$dir/.git" ]]; then
        echo "Error: The specified Moodle directory is not a git repository."
        exit 1
    fi

    echo "Upgrading Moodle from $current to $next..."
    cd "$dir"
    git fetch --all
    git checkout "MOODLE_$next_STABLE"
    php admin/cli/upgrade.php --non-interactive
    echo "Upgrade to $next completed."
}

# Perform the upgrade step-by-step
current=$CURRENT_VERSION
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
