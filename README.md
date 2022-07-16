# fedora-wayland-nvidia-suspend-fix
A short script to apply a work around to fixing suspend on Fedora when using the Nvidia proprietary driver and wayland

## How do I know if I need this
You can try this script if:
    1. You are using a relatively recent Fedora release (e.g. 36 at time of writing)
    2. You are using a relatively recent Nvidia proprietary driver (e.g. 515.57 at time of writing)
    3. You are using Wayland
    4. When you use suspend one of two problems occur:
        - The screen goes dark for about 30 seconds, the computer never goes into suspend, and you are returned to the lock screen
        - Suspend works but when you come back the video memory is completely corrupt and requires a window manager restart or computer restart

## How does it work
This script combines two separate work arounds:
    1. A fix from https://github.com/robswc/ubuntu-22-nvidia-suspend-fix-script to fix issue #1 above
    2. A fix to ensure the power configuration from xorg-x11-drv-nvidia-power is applied to fix issue #2 above

## How do I use this
Script usage can be found by running with no arugments, e.g.
```
$> ./fedora-wayland-nvidia-suspend-fix.sh
fedora-wayland-nvidia-suspend-fix.sh help
 * If no arguments are specified, print this help message
 * If an unrecognized argument is specified, print this help message.
 * If an argument of i or I is specified, uninstall the workarounds.
 * If an argument of u or U is specified, uninstall the workarounds.
```

To install the workarounds using the script directly from github, you can do:
```
curl -s "https://raw.githubusercontent.com/fontivan/fedora-wayland-nvidia-suspend-fix/main/src/fedora-wayland-nvidia-suspend-fix.sh" | bash -s -- i
```
