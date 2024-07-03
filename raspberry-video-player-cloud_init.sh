#!/bin/bash

# Source the configuration file for Wi-Fi credentials and new user details
CONFIG_FILE="config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
else
    echo "Configuration file '$CONFIG_FILE' not found. Please create it with your Wi-Fi credentials and new user details."
    exit 1
fi

# either armhf or aarch64 (experimental)
ARCH=armhf

# Function to download the Raspberry Pi OS image for macOS
download_os_image_macos() {
    echo "Downloading the Raspberry Pi OS image for macOS..."
    OS_IMAGE=2021-05-10-raspios-buster-$ARCH-lite-cloud-init.zip
    echo $OS_IMAGE
    #OS_IMAGE=2021-12-02-raspios-buster-armhf-lite.zip
    
    if [ ! -f $OS_IMAGE ]; then
        
        OS_IMAGE_URL=https://github.com/timebertt/pi-cloud-init/releases/download/2021-05-10/2021-05-10-raspios-buster-$ARCH-lite-cloud-init.zip
        
        #OS_IMAGE_URL=https://downloads.raspberrypi.org/raspios_oldstable_lite_armhf/images/raspios_oldstable_lite_armhf-2021-12-02/2021-12-02-raspios-buster-armhf-lite.zip
        #OS_IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2022-01-28/2022-01-28-raspios-bullseye-arm64-lite.zip"
        #OS_IMAGE="2022-01-28-raspios-bullseye-arm64-lite.zip"
        curl -L $OS_IMAGE_URL -o $OS_IMAGE
        if [ $? -ne 0 ]; then
            echo "Failed to download OS image."
            exit 1
        fi
        echo "Download complete: $OS_IMAGE"
        unzip $OS_IMAGE
        if [ $? -ne 0 ]; then
            echo "Failed to unzip OS image."
            exit 1
        fi
    else
        echo "OS image already downloaded."
    fi
    OS_IMAGE="2022-01-28-raspios-bullseye-arm64-lite.img"
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
    echo "Validating SD card device..."
    if [[ ! -e $SDCARD ]]; then
        echo "Error: Device $SDCARD does not exist."
        exit 1
    fi

    # Ensure the device is not a system disk
    system_mounts=$(mount | grep '^/dev/disk' | awk '{print $3}')
    for mount_point in $system_mounts; do
        if [[ $mount_point == "/" || $mount_point == "/System" || $mount_point == "/dev" ]]; then
            echo "Error: Device $SDCARD is a system disk."
            exit 1
        fi
    done

    echo "Validated SD card device: $SDCARD"
}

# Function to unmount all partitions of the SD card
unmount_sd_card() {
    echo "Unmounting all partitions of the SD card..."
    partitions=$(diskutil list $SDCARD | grep -o 'disk[0-9]*s[0-9]*')
    echo ${partitions}
    if diskutil unmountDisk $SDCARD; then
        echo "Unmounted $SDCARD successfully."
    else
        echo "Failed to unmount $SDCARD. Trying again..."
        if ! diskutil unmountDisk force $SDCARD; then
            echo "Error: Unable to unmount $SDCARD."
            exit 1
        fi
    fi
}

# Function to create wpa_supplicant.conf
create_wpa_supplicant() {
    echo "Creating wpa_supplicant.conf..."
    sudo bash -c "cat <<EOF > /Volumes/boot/wpa_supplicant.conf
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid=\"$SSID\"
    psk=\"$PSK\"
    key_mgmt=WPA-PSK
}
EOF"
    if [ $? -ne 0 ]; then
        echo "Failed to create wpa_supplicant.conf."
        exit 1
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
        passwd: $NEW_PASS
ssh_pwauth: true
packages:
    - omxplayer
    - samba
    - avahi-daemon
runcmd:
    - sudo apt-get install -y rfkill
    - sudo rfkill unblock all
    - echo -e "[Videos]\n   path = /home/$NEW_USER/Videos\n   browseable = yes\n   writeable = yes\n   only guest = no\n   create mask = 0777\n   directory mask = 0777\n   public = yes" | sudo tee -a /etc/samba/smb.conf
    - sudo systemctl restart smbd nmbd
    - mkdir -p /home/$NEW_USER/Videos
    - echo -e "#!/bin/bash\omxplayer -o local --loop /home/$NEW_USER/video.mp4 --orientation 270 | sudo tee /home/$NEW_USER/play_video.sh
    - chmod +x /home/$NEW_USER/play_video.sh
    - echo "@reboot /home/$NEW_USER/play_video.sh" | sudo tee -a /var/spool/cron/crontabs/$NEW_USER
final_message: "Setup complete. The system will play videos from the Videos directory on startup."
EOF
    touch /tmp/cloud-init/meta-data
}


# Main script execution
echo "Starting main script execution..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    download_os_image_macos
else
    download_os_image_linux
fi

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

# Mount the boot partition
BOOT_PARTITION="${SDCARD}s1"
echo "Mounting the boot partition..."
diskutil mount $BOOT_PARTITION
if [ $? -ne 0 ]; then
    echo "Failed to mount the boot partition."
    #exit 1
fi

# Create the cloud-init configuration
create_cloud_init

# Copy cloud-init configuration to the boot partition
cp -r /tmp/cloud-init/* /Volumes/boot/

# Unmount the SD card
echo "Unmounting the SD card..."
if diskutil unmountDisk $SDCARD; then
    echo "Unmounted SD card successfully."
else
    echo "Failed to unmount SD card. Please manually unmount it."
    exit 1
fi

echo "SD card is ready. Insert it into your Raspberry Pi and power it on."
        