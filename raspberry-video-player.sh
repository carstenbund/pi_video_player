#!/bin/bash

# Source the configuration file for Wi-Fi credentials and new user details
CONFIG_FILE="config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
else
    echo "Configuration file '$CONFIG_FILE' not found. Please create it with your Wi-Fi credentials and new user details."
    exit 1
fi

# Function to download the Raspberry Pi OS image for macOS
download_os_image_macos() {
    if [ ! -f "2022-01-28-raspios-bullseye-arm64-lite.img" ]; then
        echo "Downloading the Raspberry Pi OS image..."
        OS_IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2022-01-28/2022-01-28-raspios-bullseye-arm64-lite.zip"
        OS_IMAGE="2022-01-28-raspios-bullseye-arm64-lite.zip"
        curl -L $OS_IMAGE_URL -o $OS_IMAGE
        echo "Download complete: $OS_IMAGE"
        unzip $OS_IMAGE
    else
        echo "OS image already downloaded."
    fi
    OS_IMAGE="2022-01-28-raspios-bullseye-arm64-lite.img"
}

# Function to download the latest Raspberry Pi OS image for Linux
download_os_image_linux() {
    if [ ! -f "raspios_latest.img" ]; then
        echo "Downloading the latest Raspberry Pi OS image..."
        OS_IMAGE_URL=$(curl -s https://downloads.raspberrypi.org/raspios_lite_armhf_latest | grep -o 'https://.*\.img\.xz')
        OS_IMAGE="raspios_latest.img.xz"
        curl -L $OS_IMAGE_URL -o $OS_IMAGE
        echo "Download complete: $OS_IMAGE"
        
        # Check if xz-utils or tar is available
        if command -v unxz &> /dev/null; then
            unxz $OS_IMAGE
        elif command -v tar &> /dev/null; then
            tar -xf $OS_IMAGE
        else
            echo "Neither unxz nor tar is available to decompress the image."
            exit 1
        fi
    else
        echo "OS image already downloaded."
    fi
    OS_IMAGE="raspios_latest.img"
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
    
    # Ensure the device is not a system disk
    system_mounts=$(mount | grep '^/dev/disk' | awk '{print $3}')
    for mount_point in $system_mounts; do
        if [[ $mount_point == "/System" ]]; then
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
        echo "Failed to unmount $SDCARD Trying again..."
        if ! diskutil unmountDisk force $SDCARD; then
            echo "Error: Unable to unmount $SDCARD"
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
}

# Function to create the setup script
create_setup_script() {
    echo "Creating setup script..."
    sudo bash -c "cat <<'EOF' > /Volumes/boot/setup.sh
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

# Install VLC media player
sudo apt-get install -y vlc

# Install Samba for file sharing
sudo apt-get install -y samba samba-common-bin

# Configure Samba
sudo smbpasswd -a pi <<EOT
raspberry
raspberry
EOT

sudo bash -c 'cat <<EOT >> /etc/samba/smb.conf

[Videos]
   path = /home/pi/Videos
   browseable = yes
   writeable = yes
   only guest = no
   create mask = 0777
   directory mask = 0777
   public = yes
EOT'

# Configure Samba for network discovery using nmbd and avahi (Bonjour)
sudo apt-get install -y avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

# Restart Samba service
sudo systemctl restart smbd nmbd

# Create a directory for videos
mkdir -p ~/Videos

# Copy the script to play videos on startup
cat <<'EOT' > ~/play_video.sh
#!/bin/bash
cvlc --fullscreen --loop ~/Videos/*
EOT

chmod +x ~/play_video.sh

# Add the play video script to crontab to run at startup
(crontab -l ; echo "@reboot /home/pi/play_video.sh") | crontab -

echo "Setup complete. The system will play videos from the Videos directory on startup."
EOF"
}

# Function to create the first boot script
create_firstboot_script() {
    echo "Creating first boot script..."
    sudo bash -c "cat <<'EOF' > /Volumes/boot/firstboot.sh
#!/bin/bash

# Check for network connection
while ! ping -c 1 google.com &>/dev/null; do
    echo "Waiting for network connection..."
    sleep 5
done

# Run the setup script
bash /boot/setup.sh

# Indicate successful completion
touch /boot/setup_complete

# Remove this script after first boot
if [ -f /boot/setup_complete ]; then
    rm -- \"$0\"
fi
EOF"
}

# Function to update rc.local to run the first boot script
update_rc_local() {
    echo "Updating rc.local to run the first boot script..."
    sudo bash -c "cat <<'EOF' >> /Volumes/boot/rc.local
# Run firstboot script on first boot
if [ -f /boot/firstboot.sh ]; then
    bash /boot/firstboot.sh
fi
EOF"
}

# Main script execution
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
diskutil mount $BOOT_PARTITION

# Create wpa_supplicant.conf
create_wpa_supplicant

# Create and copy the setup script to the SD card
create_setup_script

# Create and copy the first boot script to the SD card
create_firstboot_script

# Update rc.local to run the first boot script
update_rc_local

# Unmount the SD card
if diskutil unmountDisk $SDCARD; then
    echo "Unmounted SD card successfully."
else
    echo "Failed to unmount SD card. Please manually unmount it."
    exit 1
fi

echo "SD card is ready. Insert it into your Raspberry Pi and power it on."
