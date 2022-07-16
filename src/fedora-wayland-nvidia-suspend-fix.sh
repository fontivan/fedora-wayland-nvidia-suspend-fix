#!/usr/bin/env bash

########################################################################################################################
# MIT License
#
# Copyright (c) 2022 fontivan
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
########################################################################################################################

########################################################################################################################
### Configuration
########################################################################################################################
set -eou pipefail

########################################################################################################################
# Functions
########################################################################################################################

function LogInfo() {
    local logMessage
    logMessage="${1}"
    echo "[$(date '+%F %T')] INFO: ${logMessage}"
    return 0
}

function LogError() {
    local logMessage
    logMessage="${1}"
    echo "[$(date '+%F %T')] ERROR: ${logMessage}" 1>&2
    return 0
}

function IsUserEffectivelyRoot() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    fi
    return 0
}

function IsFedoraDistribution() {
    wc="$(grep -E '^NAME=' /etc/os-release | grep 'Fedora' | wc -l)"
    if [[ "${wc}" -gt 0 ]]
    then
        return 0
    fi
    return 1
}

function IsPackageInstalled() {
    local packageName
    packageName="${1}"
    dnf list installed "${packageName}" 2>&1 > /dev/null
    return $?
}

function InstallPackage() {
    local packageName
    packageName="${1}"
    dnf install -y "${packageName}" 2>&1 > /dev/null
    return $?
}

function ApplyNvidiaPowerManagementPackageWorkaround() {
    # Apply workaround for power settings
    LogInfo "Applying workaround for nvidia-power-management"

    # Create link and tell dracut to include this configuration
    ln -f -s "/usr/lib/modprobe.d/nvidia-power-management.conf" "/etc/modprobe.d/nvidia-power-management.conf"
    echo "install_items+=/etc/modprobe.d/nvidia-power-management.conf" > "/etc/dracut.conf.d/nvidia-power-management.conf"
    dracut --force

    return 0
}

function ApplyGnomeShellSuspendWorkaround() {
    # Apply workaround from robswc
    LogInfo "Applying workaround for gnome-shell suspend"

    # URLs for files that will be downloaded
    robswc_git_url_root="https://raw.githubusercontent.com/robswc/ubuntu-22-nvidia-suspend-fix-script/main"
    robswc_script_url="${robswc_git_url_root}/suspend-gnome-shell.sh"
    robswc_suspend_url="${robswc_git_url_root}/gnome-shell-suspend.service"
    robswc_resume_url="${robswc_git_url_root}/gnome-shell-resume.service"

    # Download files to the appropriate directories
    curl -s -o "/usr/local/bin/suspend-gnome-shell.sh" "${robswc_script_url}"
    chmod +x "/usr/local/bin/suspend-gnome-shell.sh"
    curl -s -o "/etc/systemd/system/gnome-shell-suspend.service" "${robswc_suspend_url}"
    curl -s -o "/etc/systemd/system/gnome-shell-resume.service" "${robswc_resume_url}"

    # Enable new systemd service
    systemctl daemon-reload
    systemctl -q enable gnome-shell-suspend
    systemctl -q enable gnome-shell-resume

    return 0
}

function precheck() {

    # Check that we are root
    if ! IsUserEffectivelyRoot
    then
        LogError "Root permissions are required for this to work."
        return 1
    fi

    # Check that we are on Fedora
    if ! IsFedoraDistribution
    then
        LogError "This script should not be run on a non-Fedora system."
        return 1
    fi

    return 0
}

function install_workaround() {

    if ! precheck
    then
        return 1
    fi

    # Check if power management is installed
    if ! IsPackageInstalled "xorg-x11-drv-nvidia-power"
    then
        LogInfo "Installing nvidia power management package."

        # Check if rpmfusion nonfree is enabled
        if ! IsPackageInstalled "rpmfusion-nonfree-release-$(rpm -E %fedora)"
        then
            LogInfo "rpmfusion/nonfree must be installed."
            echo
            read -p "Are you sure you want to install rpmfusion/nonfree? (y/n)"
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]
            then
                # Install the repo
                if ! InstallPackage "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$().noarch.rpm"
                then
                    LogError "An error occured attempting to install rpmfusion/nonfree repository."
                    return 1
                fi
            else
                LogError "Unable to apply fix without installing rpmfusion/nonfree."
                return 1
            fi
        fi

        # Install the package
        if ! InstallPackage "xorg-x11-drv-nvidia-power"
        then
            LogError "An error occured attempting to install nvidia power management package."
            return 1
        fi
    fi

    # Curl is required to download files from github
    if ! IsPackageInstalled "curl"
    then
        LogInfo "Installing curl package."
        if ! InstallPackage "curl"
        then
            LogError "An error occured attempting to install curl."
            return 1
        fi
    fi

    if ! ApplyGnomeShellSuspendWorkaround
    then
        LogError "An error occured attempting to apply the gnome-shell workaround."
        return 1
    fi

    if ! ApplyNvidiaPowerManagementPackageWorkaround
    then
        LogError "An error occured attempting to apply the nvidia-power-management workaround."
        return 1
    fi

    # Tell the user they need to reboot
    LogInfo "Please reboot your system now."
    return 0
}

function uninstall_workaround(){

    if ! precheck
    then
        return 1
    fi

    # Remove gnome shell suspend
    systemctl -q disable gnome-shell-suspend
    systemctl -q disable gnome-shell-resume
    rm -f "/etc/systemd/system/gnome-shell-resume.service"
    rm -f "/etc/systemd/system/gnome-shell-suspend.service"
    rm -f "/usr/local/bin/suspend-gnome-shell.sh"
    systemctl daemon-reload

    # Remove power management link & dracut config
    rm -f "/etc/modprobe.d/nvidia-power-management.conf"
    rm -f "/etc/dracut.conf.d/nvidia-power-management.conf"
    dracut --force

    LogInfo "Packages 'curl', 'xorg-x11-drv-nvidia-power, and 'rpmfusion-nonfree-release-$().noarch.rpm' may have been installed by this script but will not be removed automatically."
    LogInfo "Please reboot your system now."

    return 0
}

########################################################################################################################
# Main
########################################################################################################################

if [[ $# -eq 0 ]]
then
    LogInfo "Installing workarounds"
    if ! install_workaround
    then
        exit 1
    fi
elif [[ $1 =~ ^[Dd]$ ]]
then
    LogInfo "Uninstalling workarounds"
    if ! uninstall_workaround
    then
        exit 1
    fi
else
    echo "fedora-wayland-nvidia-suspend-fix.sh help"
    echo " * If no arguments are specified, install the workarounds."
    echo " * If an argument of D or d is specified, uninstall the workarounds."
    echo " * If an argument of H or h is specified, print this help message."
    echo " * If an unrecognized argument is specified, print this help message."
    exit 1
fi
exit 0
