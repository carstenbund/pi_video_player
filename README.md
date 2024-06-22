# Raspberry Pi Video Player Setup

This repository contains a script to set up a Raspberry Pi as a video player. The script downloads the latest Raspberry Pi OS image, writes it to an SD card, configures Wi-Fi, installs necessary software, and sets up Samba for file sharing.

## Prerequisites

- macOS
- An SD card
- An SD card reader

## Instructions

1. Clone this repository:

    ```bash
    git clone https://github.com/<your-username>/raspberry-pi-video-player-setup.git
    cd raspberry-pi-video-player-setup
    ```

2. Make the setup script executable:

    ```bash
    chmod +x setup.sh
    ```

3. Run the setup script:

    ```bash
    ./setup.sh
    ```

4. Follow the on-screen instructions to complete the setup.

5. Insert the prepared SD card into your Raspberry Pi and power it on.

The Raspberry Pi will automatically configure itself and set up a video player with Samba file sharing.

## Configuration

Edit the `setup.sh` script to set your Wi-Fi credentials:

```bash
SSID="Your_SSID"
PSK="Your_Password"


