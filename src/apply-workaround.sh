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

function IsUserEffectivelyRoot() {
    if [[ "$EUID" -ne 0 ]]
    then
        echo "Please run as root - It is necessary to apply the workaround."
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
    ln -s "/usr/lib/modprobe.d/nvidia-power-management.conf" "/etc/modprobe.d/nvidia-power-management.conf"
    echo "install_items+=/etc/modprobe.d/nvidia-power-management.conf" > "/etc/dracut.conf.d/nvidia-power-management.conf"
    dracut --force
}

function ApplyGnomeShellSuspendWorkaround() {
    # Apply workaround from robswc
    # URLs for files that will be downloaded
    robswc_git_url_root="https://raw.githubusercontent.com/robswc/ubuntu-22-nvidia-suspend-fix-script/main/"
    robswc_script_url="${robswc_git_url_root}/suspend-gnome-shell.sh"
    robswc_suspend_url="${robswc_git_url_root}/gnome-shell-suspend.service"
    robswc_resume_url="${robswc_git_url_root}/gnome-shell-resume.service"

    # Download files to the appropriate directories
    curl -o "/usr/local/bin/suspend-gnome-shell.sh" "${robswc_script_url}"
    chmod +x "/usr/local/bin/suspend-gnome-shell.sh"
    curl -o "/etc/systemd/system/gnome-shell-suspend.service" "${robswc_suspend_url}"
    curl -o "/etc/systemd/system/gnome-shell-resume.service" "${robswc_resume_url}"

    # Enable new systemd service
    systemctl daemon-reload
    systemctl enable gnome-shell-suspend
    systemctl enable gnome-shell-resume

}

function main() {

    # Check that we are root
    if ! IsUserEffectivelyRoot
    then
        echo "Please run as root - It is necessary to apply the workaround."
        return 1
    fi

    # Check that we are on Fedora
    if ! IsFedoraDistribution
    then
        echo "This script should not be run on a non-Fedora system"
        return 1
    fi

    # Check if rpmfusion nonfree is enabled
    if ! IsPackageInstalled "rpmfusion-nonfree-release-$(rpm -E %fedora)"
    then
        echo "rpmfusion/nonfree must be installed."
        if ! InstallPackage "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$().noarch.rpm"
        then
            echo "An error occured attempting to install rpmfusion/nonfree repository"
            return 1
        fi
    fi

    # Install nvidia power management package
    if ! IsPackageInstalled "xorg-x11-drv-nvidia-power"
    then
        echo "Installing nvidia power management package"
        if ! InstallPackage "xorg-x11-drv-nvidia-power"
        then
            echo "An error occured attempting to install nvidia power management package"
            return 1
        fi
    fi

    ApplyGnomeShellSuspendWorkaround
    ApplyNvidiaPowerManagementPackageWorkaround
    echo "Please reboot your system now."
    return 0
}

########################################################################################################################
# Constants
########################################################################################################################
main
