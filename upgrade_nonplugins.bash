#!/usr/bin/env bash

# Import functions from functions.sh
source ./functions.bash

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
MOODLE_PARENT_DIR=$(dirname "$MOODLE_DIR")
MOODLE_OLD_DIR="${MOODLE_DIR}_old"

if [[ -z "$MOODLE_DIR" || -z "$CURRENT_VERSION" || -z "$TARGET_VERSION" ]]; then
    echo "Usage: $0 <moodle_root_dir> <current_version> <target_version>"
    exit 1
fi

# Move the current Moodle directory to _old
mv "$MOODLE_DIR" "$MOODLE_OLD_DIR"

# Clone fresh Moodle repository
git clone https://github.com/moodle/moodle.git "$MOODLE_DIR"

# Copy config.php from the old installation
if [[ -f "$MOODLE_OLD_DIR/config.php" ]]; then
    cp "$MOODLE_OLD_DIR/config.php" "$MOODLE_DIR/config.php"
else
    echo "Warning: No config.php found in old installation. Manual configuration may be required."
fi



# Function to perform the upgrade using git
upgrade_moodle() {
    local current=$1
    local next=$2
    local dir=$3

    local current_formatted=$(to_moodle_version_format "$current")
    local next_formatted=$(to_moodle_version_format "$next")

    echo "Upgrading Moodle from $current to $next..."
    cd "$dir"
    git fetch --all
    git reset --hard
    git checkout "MOODLE_${next_formatted}_STABLE"
    php admin/cli/upgrade.php --non-interactive
    echo "Upgrade to $next completed."
}

# Get upgrade path
upgrade_steps=($(get_upgrade_path "$CURRENT_VERSION" "$TARGET_VERSION"))

# Perform the upgrade step-by-step
for next_version in "${upgrade_steps[@]}"; do
    upgrade_moodle "$CURRENT_VERSION" "$next_version" "$MOODLE_DIR"
    CURRENT_VERSION="$next_version"
done

echo "Moodle successfully upgraded to version $TARGET_VERSION!"
