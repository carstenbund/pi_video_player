#!/bin/bash

# Source the configuration file for Wi-Fi credentials and new user details
CONFIG_FILE="config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
else
    echo "Configuration file '$CONFIG_FILE' not found. Please create it with your Wi-Fi credentials and new user details."
    exit 1
fi

# Function to download the Ubuntu image
download_ubuntu_image() {
    if [ ! -f "ubuntu-20.04.4-preinstalled-server-arm64+raspi.img" ]; then
        echo "Downloading the Ubuntu image..."
        OS_IMAGE_URL="https://cdimage.ubuntu.com/releases/20.04/release/ubuntu-20.04.4-preinstalled-server-arm64+raspi.img.xz"
        OS_IMAGE="ubuntu-20.04.4-preinstalled-server-arm64+raspi.img.xz"
        curl -L $OS_IMAGE_URL -o $OS_IMAGE
        echo "Download complete: $OS_IMAGE"
        echo "Extracting the Ubuntu image..."
        /System/Library/CoreServices/Applications/Archive\ Utility.app/Contents/MacOS/Archive\ Utility $OS_IMAGE
    else
        echo "OS image already downloaded."
    fi
    OS_IMAGE="ubuntu-20.04.4-preinstalled-server-arm64+raspi.img"
}

# Function to detect the SD card device
detect_sd_card() {
    echo "Detecting SD card device..."
    # List all disk devices before inserting the SD card
    disks_before=$(ls /dev/disk*)

    echo "Please insert the SD card and press Enter..."
    read -p ""

    # List all disk devices after inserting the SD card
    disks_after=$(ls /dev/disk*)

    # Find the new device
    new_disks=$(comm -13 <(echo "$disks_before") <(echo "$disks_after"))
    SDCARD=""
    for disk in $new_disks; do
        if [[ $disk == *disk* ]]; then
            SDCARD=$disk
            break
        fi
    done

    if [ -z "$SDCARD" ]; then
        echo "No new device detected. Please ensure the SD card is inserted correctly."
        exit 1
    fi

    echo "Detected SD card device: $SDCARD"
}

# Function to validate the provided SD card device
validate_sd_card() {
    if [[ ! -e $SDCARD ]]; then
        echo "Error: Device $SDCARD does not exist."
        exit 1
    fi

    echo "Validated SD card device: $SDCARD"
}

# Function to unmount all partitions of the SD card
unmount_sd_card() {
    echo "Unmounting all partitions of the SD card..."
    if diskutil unmountDisk $SDCARD; then
        echo "Unmounted $SDCARD successfully."
    else
        echo "Failed to unmount $SDCARD. Trying again..."
        if ! diskutil unmountDisk force $SDCARD; then
            echo "Error: Unable to unmount $SDCARD"
            exit 1
        fi
    fi
}

# Function to create the cloud-init configuration
create_cloud_init() {
    echo "Creating cloud-init configuration..."
    mkdir -p /tmp/cloud-init
    cat <<EOF > /tmp/cloud-init/user-data
#cloud-config
package_update: true
package_upgrade: true
write_files:
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: true
        wifis:
          wlan0:
            dhcp4: true
            optional: true
            access-points:
              "$SSID":
                password: "$PSK"
users:
  - default
  - name: $NEW_USER
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    plain_text_passwd: $NEW_PASS
ssh_pwauth: true
packages:
  - vlc
  - samba
  - avahi-daemon
runcmd:
  - sudo apt-get install -y rfkill
  - sudo rfkill unblock all
  - echo -e "[Videos]\n   path = /home/$NEW_USER/Videos\n   browseable = yes\n   writeable = yes\n   only guest = no\n   create mask = 0777\n   directory mask = 0777\n   public = yes" | sudo tee -a /etc/samba/smb.conf
  - sudo systemctl restart smbd nmbd
  - mkdir -p /home/$NEW_USER/Videos
  - echo -e "#!/bin/bash\ncvlc --fullscreen --loop /home/$NEW_USER/Videos/*" | sudo tee /home/$NEW_USER/play_video.sh
  - chmod +x /home/$NEW_USER/play_video.sh
  - echo "@reboot /home/$NEW_USER/play_video.sh" | sudo tee -a /var/spool/cron/crontabs/$NEW_USER
final_message: "Setup complete. The system will play videos from the Videos directory on startup."
EOF
    touch /tmp/cloud-init/meta-data
}

# Main script execution
download_ubuntu_image

if [ -z "$1" ]; then
    detect_sd_card
else
    SDCARD=$1
    validate_sd_card
fi

unmount_sd_card

# Write the OS image to the SD card using /dev/rdisk for better performance
rdisk_device=$(echo $SDCARD | sed 's/disk/rdisk/')
echo "Writing OS image to SD card..."
if sudo dd if=$OS_IMAGE of=$rdisk_device bs=4m status=progress conv=sync; then
    echo "OS image written to SD card."
else
    echo "Error writing OS image to SD card."
    exit 1
fi

# Mount the system-boot partition
BOOT_PARTITION="${SDCARD}s1"
diskutil mount $BOOT_PARTITION

# Create the cloud-init configuration
create_cloud_init

# Copy cloud-init configuration to the boot partition
cp -r /tmp/cloud-init/* /Volumes/system-boot/

# Unmount the SD card
if diskutil unmountDisk $SDCARD; then
    echo "Unmounted SD card successfully."
else
    echo "Failed to unmount SD card. Please manually unmount it."
    exit 1
fi

echo "SD card is ready. Insert it into your Raspberry Pi and power it on."
