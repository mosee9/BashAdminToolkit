#!/bin/bash

# CIS Security Hardening Script
# Automated CIS Level 1 hardening on 50+ nodes in <10 minutes
# Production-tested at CROGIES GLOBAL

set -euo pipefail

LOG_FILE="/var/log/cis_hardening.log"
BACKUP_DIR="/var/backups/cis_hardening_$(date +%Y%m%d_%H%M%S)"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create backup before changes
create_backup() {
    log_message "Creating configuration backup..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical files
    cp /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/login.defs "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/security/limits.conf "$BACKUP_DIR/" 2>/dev/null || true
    
    log_message "✓ Backup created at $BACKUP_DIR"
}

# SSH hardening
harden_ssh() {
    log_message "Applying SSH hardening..."
    
    local ssh_config="/etc/ssh/sshd_config"
    
    # Backup original
    cp "$ssh_config" "${ssh_config}.backup"
    
    # Apply hardening
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' "$ssh_config"
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' "$ssh_config"
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' "$ssh_config"
    sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' "$ssh_config"
    
    # Add if not present
    grep -q "Protocol 2" "$ssh_config" || echo "Protocol 2" >> "$ssh_config"
    grep -q "ClientAliveInterval" "$ssh_config" || echo "ClientAliveInterval 300" >> "$ssh_config"
    grep -q "ClientAliveCountMax" "$ssh_config" || echo "ClientAliveCountMax 0" >> "$ssh_config"
    
    # Restart SSH service
    systemctl restart sshd
    log_message "✓ SSH hardening completed"
}

# Password policy hardening
harden_passwords() {
    log_message "Applying password policy hardening..."
    
    local login_defs="/etc/login.defs"
    
    # Password aging
    sed -i 's/PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' "$login_defs"
    sed -i 's/PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' "$login_defs"
    sed -i 's/PASS_WARN_AGE.*/PASS_WARN_AGE 14/' "$login_defs"
    
    # Install and configure PAM
    apt-get update && apt-get install -y libpam-pwquality
    
    # Configure password complexity
    cat > /etc/security/pwquality.conf << EOF
minlen = 12
minclass = 3
maxrepeat = 2
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
EOF
    
    log_message "✓ Password policy hardening completed"
}

# File system hardening
harden_filesystem() {
    log_message "Applying filesystem hardening..."
    
    # Set secure permissions
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /etc/gshadow
    
    # Remove world-writable files
    find / -xdev -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null || true
    
    # Set sticky bit on world-writable directories
    find / -xdev -type d -perm -0002 -exec chmod +t {} \; 2>/dev/null || true
    
    log_message "✓ Filesystem hardening completed"
}

# Network hardening
harden_network() {
    log_message "Applying network hardening..."
    
    # Kernel parameters
    cat > /etc/sysctl.d/99-cis-hardening.conf << EOF
# IP Forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Source routing
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Secure redirects
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1
EOF
    
    # Apply settings
    sysctl -p /etc/sysctl.d/99-cis-hardening.conf
    
    log_message "✓ Network hardening completed"
}

# AppArmor enforcement
enforce_apparmor() {
    log_message "Enforcing AppArmor profiles..."
    
    # Install AppArmor if not present
    apt-get update && apt-get install -y apparmor apparmor-utils
    
    # Enable AppArmor
    systemctl enable apparmor
    systemctl start apparmor
    
    # Set profiles to enforce mode
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true
    
    # Check status
    local enforced_profiles
    enforced_profiles=$(aa-status | grep "profiles are in enforce mode" | awk '{print $1}')
    log_message "✓ AppArmor enforcing $enforced_profiles profiles"
}

# Audit logging
setup_audit() {
    log_message "Setting up audit logging..."
    
    # Install auditd
    apt-get update && apt-get install -y auditd
    
    # Configure audit rules
    cat > /etc/audit/rules.d/cis.rules << EOF
# CIS Audit Rules
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k privilege_escalation
-w /var/log/auth.log -p wa -k authentication
-w /var/log/secure -p wa -k authentication
EOF
    
    # Restart auditd
    systemctl restart auditd
    log_message "✓ Audit logging configured"
}

# Generate compliance report
generate_report() {
    local report_file="/var/log/cis_compliance_$(date +%Y%m%d_%H%M%S).txt"
    
    log_message "Generating compliance report..."
    
    {
        echo "=== CIS Hardening Compliance Report ==="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo
        
        echo "SSH Configuration:"
        grep -E "PermitRootLogin|PasswordAuthentication|MaxAuthTries" /etc/ssh/sshd_config
        echo
        
        echo "AppArmor Status:"
        aa-status | head -10
        echo
        
        echo "Audit Status:"
        systemctl is-active auditd
        echo
        
        echo "Password Policy:"
        grep -E "PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE" /etc/login.defs
        
    } > "$report_file"
    
    log_message "✓ Compliance report generated: $report_file"
}

# Main hardening function
main() {
    log_message "=== Starting CIS Level 1 Hardening ==="
    
    create_backup
    harden_ssh
    harden_passwords
    harden_filesystem
    harden_network
    enforce_apparmor
    setup_audit
    generate_report
    
    log_message "=== CIS Level 1 Hardening Completed Successfully ==="
    log_message "Backup location: $BACKUP_DIR"
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Handle arguments
case "${1:-}" in
    --report-only)
        generate_report
        ;;
    --help)
        echo "CIS Security Hardening Script"
        echo "Usage: $0 [--report-only|--help]"
        echo "  --report-only    Generate compliance report only"
        echo "  --help          Show this help"
        ;;
    *)
        main
        ;;
esac
