
#!/bin/bash
#
# setup_linux: installs the ECE 391 home environment on Linux
#
# This script only officially supports Ubuntu 16.04, Debian 9,
# and Arch Linux; however, you should be able to run it on
# other distributions without much problem. If your package
# manager is not supported, you may have to manually install
# any required dependencies.
#
# Note that this script should NOT be run as root/sudo.
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
share_dir="${script_dir}/ece391_share"
work_dir="${share_dir}/work"
qemu_dir="${script_dir}/qemu"
image_dir="${script_dir}/image"
vm_dir="${work_dir}/vm"
kernel_path="${work_dir}/source/linux-2.6.22.5/bzImage"

check_environment() {
    if [ "$EUID" -eq 0 ]; then
        echo "[-] Do not run this script as root/sudo!"
        exit 1
    fi

    if [ ! -f "${image_dir}/ece391.qcow" ]; then
        echo "[-] Required files not found, move this script to the right location!"
        exit 1
    fi
}

install_deps() {
    echo "[*] Installing dependencies"

    # Arch Linux
    command -v pacman &>/dev/null \
        && sudo pacman --needed --noconfirm -S \
            base base-devel samba git curl \
            qemu-full glib2 dtc pixman zlib sdl gtk2 \
        && return 0

    echo "[!] Unsupported package manager/distro/setup (or no network connection)"
    echo "[!] Please manually install: samba, curl, QEMU build dependencies"
    echo "[!] QEMU build info here: https://wiki.qemu.org/index.php/Hosts/Linux"
    echo "[!] When you are done, re-run this script to continue"
    read -r -p "[?] Have you installed the required dependencies? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "[*] Bypassing dependency check"
            ;;
        *)
            exit 1
            ;;
    esac
}


create_qcow() {
    echo "[*] Creating qcow files"
    mkdir -p "${vm_dir}"

    if [ ! -f "${vm_dir}/devel.qcow" ]; then
        echo "[*] Copying to devel.qcow"
        cp "${image_dir}/ece391.qcow" "${vm_dir}/devel.qcow"
    fi

    if [ ! -f "${vm_dir}/test.qcow" ]; then
        echo "[*] Copying to test.qcow"
        cp "${image_dir}/ece391.qcow" "${vm_dir}/test.qcow"
    fi
}

create_shortcuts() {
    echo "[*] Creating desktop shortcuts"
    mkdir -p ~/Desktop

    tee ~/Desktop/devel >/dev/null <<EOF
#!/bin/sh
"qemu-system-i386" -hda "${vm_dir}/devel.qcow" -m 512 -name devel
EOF

    tee ~/Desktop/test_debug >/dev/null <<EOF
#!/bin/sh
"qemu-system-i386" -hda "${vm_dir}/test.qcow" -m 512 -name test -gdb tcp:127.0.0.1:1234 -S
EOF

    tee ~/Desktop/test_nodebug >/dev/null <<EOF
#!/bin/sh
"qemu-system-i386" -hda "${vm_dir}/test.qcow" -m 512 -name test -gdb tcp:127.0.0.1:1234
EOF

    echo "[*] Making desktop shortcuts executable"
    chmod a+x ~/Desktop/devel ~/Desktop/test_debug ~/Desktop/test_nodebug

    # This will fail on distros that don't use Nautilus,
    # so swallow any errors that occur.
    gsettings set org.gnome.nautilus.preferences executable-text-activation launch &>/dev/null || true
}

config_samba() {
    echo "[*] Setting up Samba"

    # Ensure Samba config exists
    if [ ! -f "/etc/samba/smb.conf" ]; then
        if [ -f "/etc/samba/smb.conf.default" ]; then
            echo "[*] Copying smb.conf from smb.conf.default"
            sudo cp "/etc/samba/smb.conf.default" "/etc/samba/smb.conf"
        else
            echo "[*] Downloading default Samba config file"
            curl "https://git.samba.org/samba.git/?p=samba.git;a=blob_plain;f=examples/smb.conf.default;hb=HEAD" -o "/tmp/smb.conf.default"
            sudo cp "/tmp/smb.conf.default" "/etc/samba/smb.conf"
        fi
    fi

    # Username must be same as Linux username for some reason
    echo "[*] Creating Samba user"
    smb_user=$(whoami)
    cat <<EOF
#############################################################
# Your Samba username is: ${smb_user}
# You will now be asked set up your Samba password
# This will be used to mount /workdir in the VM
#############################################################
EOF
    while :; do
        sudo smbpasswd -a "${smb_user}" && break
    done

    echo "[*] Removing old Samba config"
    sudo sed -i '/### BEGIN ECE391 CONFIG ###/,/### END ECE391 CONFIG ###/d' "/etc/samba/smb.conf" &>/dev/null

    echo "[*] Adding new Samba config"
    sudo tee -a "/etc/samba/smb.conf" >/dev/null <<EOF
### BEGIN ECE391 CONFIG ###
[ece391_share]
  path = "${share_dir}"
  valid users = ${smb_user}
  create mask = 0755
  read only = no

[global]
  ntlm auth = yes
  lanman auth = no
  client lanman auth = no
  min protocol = NT1
### END ECE391 CONFIG ###
EOF

    echo "[*] Configuring Samba service to run on boot"
    sudo systemctl enable smb.service 2>/dev/null

    echo "[*] Starting Samba service"
    sudo systemctl start smb.service 2>/dev/null
}

config_tux() {
    echo "[*] Creating udev rules for Tux controller"
    sudo tee "/etc/udev/rules.d/99-tux.rules" >/dev/null <<EOF
SUBSYSTEM=="tty", ATTRS{serial}=="ECE391", MODE="666"
EOF

    echo "[*] Reloading udev rules"
    sudo udevadm control --reload-rules
}

echo "[*] ECE 391 home setup script for Arch Linux"
check_environment
install_deps
create_qcow
create_shortcuts
config_samba
config_tux
echo "[+] Done!"
