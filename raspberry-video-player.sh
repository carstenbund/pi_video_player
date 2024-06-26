#!/bin/bash

# Debug mode flag
DEBUG_MODE=true

# Raspberry Pi OS image
OS_IMAGE="2022-01-28-raspios-buster-arm64-lite.img"

# Raspberry Pi OS boot partition
if [ "$DEBUG_MODE" = true ]; then
    TARGET_DRIVE="test"
else
    TARGET_DRIVE="Volumes/boot"
fi

# Source the configuration file for Wi-Fi credentials and new user details
CONFIG_FILE="config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
else
    echo "Configuration file '$CONFIG_FILE' not found. Please create it with your Wi-Fi credentials and new user details."
    exit 1
fi

# Ensure target drive directory exists in debug mode
if [ "$DEBUG_MODE" = true ] && [ ! -d "$TARGET_DRIVE" ]; then
    mkdir -p "$TARGET_DRIVE"
fi

# Determine OS-specific variables
if [[ "$OSTYPE" == "darwin"* ]]; then
    UNZIP="open -W"
    DISK_PREFIX="/dev/disk"
    RDISK_PREFIX="/dev/rdisk"
    MOUNT_CMD="diskutil mount"
    UMOUNT_CMD="diskutil unmountDisk"
else
    UNZIP="gunzip"
    DISK_PREFIX="/dev/sd"
    RDISK_PREFIX="/dev/sd"
    MOUNT_CMD="sudo mount"
    UMOUNT_CMD="sudo umount"
fi

# Function to download the Raspberry Pi OS image
download_os_image() {
    echo "Downloading the Raspberry Pi OS image..."
    if [ ! -f $OS_IMAGE ]; then
        OS_IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2022-01-28/$OS_IMAGE"
        curl -L $OS_IMAGE_URL -o $OS_IMAGE
        if [ $? -ne 0 ]; then
            echo "Failed to download OS image."
            exit 1
        fi
        echo "Download complete: $OS_IMAGE"
        $UNZIP $OS_IMAGE
    else
        echo "OS image already downloaded."
    fi
}

# Function to detect and validate the SD card device
detect_and_validate_sd_card() {
    echo "Detecting SD card device..."
    disks_before=$(ls ${DISK_PREFIX}*)

    echo "Please insert the SD card and press Enter..."
    read -p ""

    disks_after=$(ls ${DISK_PREFIX}*)

    new_disks=$(comm -13 <(echo "$disks_before") <(echo "$disks_after"))
    SDCARD=""
    for disk in $new_disks; do
        if [[ $disk == *disk* || $disk == *sd* ]]; then
            SDCARD=$disk
            break
        fi
    done

    if [ -z "$SDCARD" ]; then
        echo "No new device detected. Please ensure the SD card is inserted correctly."
        exit 1
    fi

    if [[ ! -e $SDCARD ]]; then
        echo "Error: Device $SDCARD does not exist."
        exit 1
    fi
    
    system_mounts=$(mount | grep "^${DISK_PREFIX}" | awk '{print $1}')
    for mount_point in $system_mounts; do
        if [[ $mount_point == *disk0* || $mount_point == *sda* ]]; then
            echo "Error: Device $SDCARD is a system disk."
            exit 1
        fi
    done
    
    echo "Detected and validated SD card device: $SDCARD"
}

# Function to unmount all partitions of the SD card
unmount_sd_card() {
    echo "Unmounting all partitions of the SD card..."
    partitions=$(ls ${DISK_PREFIX}* | grep -E "${DISK_PREFIX}[0-9]")
    echo ${partitions}
    if $UMOUNT_CMD $SDCARD; then
        echo "Unmounted $SDCARD successfully."
    else
        echo "Failed to unmount $SDCARD Trying again..."
        if ! $UMOUNT_CMD force $SDCARD; then
            echo "Error: Unable to unmount $SDCARD"
            exit 1
        fi
    fi
}

write_os_image() {
    echo "Writing OS image to SD card..."
    if [ "$DEBUG_MODE" = true ]; then
        echo "Debug mode: Skipping writing OS image to SD card."
    else
        if sudo dd if=$OS_IMAGE of=$RDISK_PREFIX${SDCARD##*/} bs=4m status=progress conv=sync; then
            echo "OS image written to SD card."
        else
            echo "Error writing OS image to SD card."
            exit 1
        fi
    fi
}

# Functions to write setup
# Function to create wpa_supplicant.conf
create_wpa_supplicant() {
    echo "Creating wpa_supplicant.conf..."
    sudo bash -c "cat <<EOF > $1/wpa_supplicant.conf
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

# Function to create the setup script
create_setup_script() {
    echo "Creating setup script..."
    sudo bash -c "cat <<'EOF' > $1/setup.sh
#!/bin/bash

# Update package list and upgrade all packages
sudo apt-get update && sudo apt-get upgrade -y

# Ensure rfkill is installed and unblock Wi-Fi
sudo apt-get install -y rfkill
sudo rfkill unblock all

# Create a new user and enable SSH
sudo useradd -m -s /bin/bash $NEW_USER
echo "$NEW_USER:$NEW_PASS" | sudo chpasswd
sudo usermod -aG sudo $NEW_USER
sudo systemctl enable ssh
sudo systemctl start ssh

# Install Git and pi_video_looper
sudo apt-get install -y git
git clone https://github.com/adafruit/pi_video_looper.git /home/pi/pi_video_looper
cd /home/pi/pi_video_looper
sudo ./install.sh

# Indicate successful completion
touch /boot/setup_complete

# Remove this script after setup
if [ -f /boot/setup_complete ]; then
    rm -- \"$0\"
fi
EOF"
    if [ $? -ne 0 ]; then
        echo "Failed to create setup script."
        exit 1
    fi
}

# Function to create the first boot script
create_firstboot_script() {
    echo "Creating first boot script..."
    sudo bash -c "cat <<'EOF' > $1/firstboot.sh
#!/bin/bash

# Check for network connection
while ! ping -c 1 google.com &>/dev/null; do
    echo "Waiting for network connection..."
    sleep 5
done

# Run the setup script
bash /boot/setup.sh
EOF"
    if [ $? -ne 0 ]; then
        echo "Failed to create first boot script."
        exit 1
    fi
}

# Function to update rc.local to run the first boot script
update_rc_local() {
    echo "Updating rc.local to run the first boot script..."
    sudo bash -c "cat <<'EOF' >> $1/rc.local
# Run firstboot script on first boot
if [ -f /boot/firstboot.sh ]; then
    bash /boot/firstboot.sh
fi
EOF"
    if [ $? -ne 0 ]; then
        echo "Failed to update rc.local."
        exit 1
    fi
}

# Main script execution
echo "Starting main script execution..."
download_os_image

if [ -z "$1" ]; then
    detect_and_validate_sd_card
else
    SDCARD=$1
    detect_and_validate_sd_card
fi

# SD card needs to be unmounted to write to drive
if [ "$DEBUG_MODE" = false ]; then
    unmount_sd_card
fi

# Write the image to SD card
write_os_image

# Mount the boot partition
if [ "$DEBUG_MODE" = true ]; then
    MOUNT_POINT="$TARGET_DRIVE"
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
        BOOT_PARTITION="${SDCARD}s1"
        $MOUNT_CMD $BOOT_PARTITION
        MOUNT_POINT="/Volumes/boot"
    else
        sudo mount /dev/${SDCARD}1 /mnt/sdcard
        MOUNT_POINT="/mnt/sdcard"
    fi
fi

# Create wpa_supplicant.conf
create_wpa_supplicant $MOUNT_POINT

# Create and copy the setup script to the SD card
create_setup_script $MOUNT_POINT

# Create and copy the first boot script to the SD card
create_firstboot_script $MOUNT_POINT

# Update rc.local to run the first boot script
update_rc_local $MOUNT_POINT

# Unmount the SD card
if [ "$DEBUG_MODE" = false ]; then
    echo "Unmounting the SD card..."
    if $UMOUNT_CMD $SDCARD; then
        echo "Unmounted SD card successfully."
    else
        echo "Failed to unmount SD card. Please manually unmount it."
        exit 1
    fi
else
    echo "Debug mode: Skipping unmounting of SD card."
fi

echo "SD card is ready. Insert it into your Raspberry Pi and power it on."
