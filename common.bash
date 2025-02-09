MOODLE_DIR=$1
CURRENT_VERSION=$2
TARGET_VERSION=$3

# Check if MOODLE_DIR is a relative path
if [[ ! "$MOODLE_DIR" =~ ^/ ]]; then
  # Convert to absolute path
  MOODLE_DIR="$(cd "$MOODLE_DIR" && pwd)"
fi

if [[ -z "$MOODLE_DIR" || -z "$CURRENT_VERSION" || -z "$TARGET_VERSION" ]]; then
    echo "Usage: $0 <moodle_root_dir> <current_version> <target_version> <php81_command> <php74_command> <php72_command> <php56_command>"
    echo "The php versions are optional"
    exit 1
fi

# Prompt user to confirm backup
read -p "Have you backed up your Moodle data and database? (yes/no): " backup_confirm
if [[ "$backup_confirm" != "yes" ]]; then
    echo "Backup is required before proceeding. Exiting."
    exit 1
fi
CONFIG_FILE="$MOODLE_DIR/config.php"

# Extract the $CFG->dataroot value from config.php
if [[ -f "$CONFIG_FILE" ]]; then
    MOODLEDATA_DIR=$(sed -n "s/.*\$CFG->dataroot\s*=\s*'\([^']*\)'.*/\1/p" "$CONFIG_FILE")
    if [[ -n "$MOODLEDATA_DIR" ]]; then
        echo "Moodle data directory is: $MOODLEDATA_DIR"
    else
        echo "Error: Could not find \$CFG->dataroot in config.php. Docker wil not work"
    fi
else
    echo "Error: config.php file not found in $MOODLE_DIR."
fi


# Function to find the best available PHP version
find_php() {
    local version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

    # Check if the specific PHP version is installed
    if [[ "$version" == "$1" ]]; then
        echo "php"
        return
    fi

    # Check if the specific PHP version is installed
    if command -v "php$1" &> /dev/null; then
        echo "php$1"
        return
    fi

    # Check if Docker is installed and use the corresponding container
    if command -v docker &> /dev/null &&  [[ -n "$MOODLEDATA_DIR" ]]; then
        echo "docker run --rm -v $MOODLE_DIR:/app/moodle -v $MOODLEDATA_DIR:$MOODLEDATA_DIR -w /app/moodle --network host moodlehq/moodle-php-apache:$1 php"
        return
    fi

    # If neither is available, fallback to the default 'php'
    echo "php"
}

# Assign PHP versions based on priority order
PHP8_1="${4:-$(find_php 8.1)}"
PHP7_4="${5:-$(find_php 7.4)}"
PHP7_2="${6:-$(find_php 7.2)}"
PHP5_6="${7:-$(find_php 5.6)}"

version_format() {
    local version=$1
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        if [[ "${BASH_REMATCH[2]}" -ge 10 ]]; then
            echo "${BASH_REMATCH[1]}0${BASH_REMATCH[2]}"
        else
            echo "${BASH_REMATCH[1]}00${BASH_REMATCH[2]}"
        fi
    else
        echo "Error: Invalid version format $version" >&2
        exit 1
    fi
}

# Function to determine the correct PHP version based on Moodle version
determine_php_version() {
    local moodle_version=$(version_format $1)

    # Determine the PHP version based on Moodle version
    if (( $(echo "$moodle_version < 3004" | bc -l) )); then
        echo "$PHP5_6"
    elif (( $(echo "$moodle_version <= 3009" | bc -l) )); then
        echo "$PHP7_2"
    elif (( $(echo "$moodle_version < 4001" | bc -l) )); then
        echo "$PHP7_4"
    elif (( $(echo "$moodle_version <= 4005" | bc -l) )); then
        echo "$PHP8_1"
    else
        echo "php"
    fi
}

get_versions() {
    local version=$1
    local target=$2
    local result=()

    # Cast version and target to float explicitly to avoid issues with comparison
    local version_formatted=$(version_format "$version")
    local target_formatted=$(version_format "$target")

    # Check and add version conditions
    if (( $(echo "$version_formatted <= 1009" | bc -l) )); then
        result+=(1.9)
    fi
    if (( $(echo "$version_formatted <= 2002" | bc -l) )); then
        result+=(2.2)
    fi
    if (( $(echo "$version_formatted <= 2007" | bc -l) )); then
        result+=(2.7)
    fi
    if (( $(echo "$version_formatted <= 3001" | bc -l) )); then
        result+=(3.1)
    fi

    # Check target conditions
    if (( $(echo "$target_formatted < 3005" | bc -l) )); then
        result+=(3.5)
    elif (( $(echo "$target_formatted < 3006" | bc -l) )); then
        result+=(3.6)
    else
        if (( $(echo "$target_formatted >= 3007 && $target_formatted <= 3010" | bc -l) )); then
            # Prevent duplication by passing only the version
            result+=($(get_versions "$version" 3.5))
        elif (( $(echo "$target_formatted >= 3011 && $target_formatted <= 4000" | bc -l) )); then
            result+=($(get_versions "$version" 3.6))
        elif (( $(echo "$target_formatted >= 4001 && $target_formatted <= 4003" | bc -l) )); then
            result+=($(get_versions "$version" 3.11))
        elif (( $(echo "$target_formatted >= 4004 && $target_formatted <= 4005" | bc -l) )); then
            result+=($(get_versions "$version" 4.1))
        fi
        result+=($target)
    fi

    # If version is greater than target, reset result to empty array
    if (( $(echo "$version_formatted > $target_formatted" | bc -l) )); then
        result=()
    fi
    # Remove duplicates from the array before returning it
    result=($(echo "${result[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    # Output the result as an array
    echo "${result[@]}"
}




# Function to determine the upgrade path
get_upgrade_path() {
    local current=$1
    local target=$2
    local path=()

    if (( $(echo "$target < 3.5" | bc -l) )); then
        echo "Target version is not in compliance with GDPR and should not be used. Upgrading to 3.5 instead."
        target=3.5
    fi

    path=($(get_versions "$current" "$target"))
    echo "${path[@]}"
}

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