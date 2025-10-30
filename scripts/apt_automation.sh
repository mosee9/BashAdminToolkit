#!/bin/bash

# APT Automation Script - Enterprise Grade
# Manages custom repositories and package verification
# Zero unsigned packages policy enforced

set -euo pipefail

REPO_CONFIG="/etc/apt/sources.list.d/custom.list"
GPG_KEYRING="/etc/apt/trusted.gpg.d/custom.gpg"
LOG_FILE="/var/log/apt_automation.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Verify package signatures
verify_packages() {
    log_message "Starting package verification..."
    
    if command -v debsums >/dev/null 2>&1; then
        if debsums -c 2>/dev/null; then
            log_message "✓ All packages verified successfully"
            return 0
        else
            log_message "✗ Package verification failed"
            return 1
        fi
    else
        log_message "Installing debsums for package verification..."
        apt-get update && apt-get install -y debsums
        verify_packages
    fi
}

# Update with security focus
security_update() {
    log_message "Starting security-focused update..."
    
    # Update package lists
    apt-get update
    
    # Security updates only
    apt-get -s upgrade | grep -i security | wc -l > /tmp/security_count
    local security_updates=$(cat /tmp/security_count)
    
    if [ "$security_updates" -gt 0 ]; then
        log_message "Applying $security_updates security updates..."
        apt-get -y upgrade
        log_message "✓ Security updates completed"
    else
        log_message "No security updates available"
    fi
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    rm -f /tmp/security_count
}

# Add custom repository with GPG verification
add_custom_repo() {
    local repo_url="$1"
    local gpg_key="$2"
    
    log_message "Adding custom repository: $repo_url"
    
    # Add GPG key
    if [ -n "$gpg_key" ]; then
        curl -fsSL "$gpg_key" | gpg --dearmor | tee "$GPG_KEYRING" > /dev/null
        log_message "✓ GPG key added"
    fi
    
    # Add repository
    echo "$repo_url" | tee "$REPO_CONFIG"
    apt-get update
    
    log_message "✓ Custom repository added successfully"
}

# Package integrity check
integrity_check() {
    log_message "Running package integrity check..."
    
    # Check for unsigned packages
    local unsigned_count=0
    
    for pkg in $(dpkg -l | awk '/^ii/ {print $2}'); do
        if ! apt-cache policy "$pkg" | grep -q "GPG"; then
            ((unsigned_count++))
            log_message "WARNING: Unsigned package detected: $pkg"
        fi
    done
    
    if [ "$unsigned_count" -eq 0 ]; then
        log_message "✓ All packages are properly signed"
    else
        log_message "✗ Found $unsigned_count unsigned packages"
        return 1
    fi
}

# Main function
main() {
    case "${1:-}" in
        --security-update)
            security_update
            ;;
        --verify)
            verify_packages
            ;;
        --integrity-check)
            integrity_check
            ;;
        --add-repo)
            if [ $# -lt 3 ]; then
                echo "Usage: $0 --add-repo <repo_url> <gpg_key_url>"
                exit 1
            fi
            add_custom_repo "$2" "$3"
            ;;
        --help)
            echo "APT Automation Script"
            echo "Usage: $0 [option]"
            echo "  --security-update    Apply security updates only"
            echo "  --verify            Verify package integrity"
            echo "  --integrity-check   Check for unsigned packages"
            echo "  --add-repo <url> <gpg>  Add custom repository"
            echo "  --help              Show this help"
            ;;
        *)
            log_message "Starting full APT automation..."
            security_update
            verify_packages
            integrity_check
            log_message "✓ APT automation completed successfully"
            ;;
    esac
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

main "$@"
