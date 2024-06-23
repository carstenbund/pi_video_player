# Raspberry Pi Video Player Setup

This repository contains a script to set up a Raspberry Pi as a video player. The script downloads the latest Raspberry Pi OS image, writes it to an SD card, configures Wi-Fi, installs necessary software, and sets up Samba for file sharing.

## Prerequisites

- macOS
- A SD card
- A SD card reader

## Instructions

1. Clone this repository:

    ```bash
    git clone https://github.com/carstenbund/pi_video_player.git
    cd pi_video_player
    ```

2. Create a `config.sh` file with your Wi-Fi credentials:

    ```bash
    nano config.sh
    ```

    Add the following content:

    ```bash
    SSID="Your_SSID"
    PSK="Your_Password"
    NEW_USER="vplayer"
    NEW_PASS="vplayer"

    ```

3. Make the setup script executable:

    ```bash
    chmod +x setup.sh
    ```

4. Run the setup script:

    ```bash
    ./setup.sh
    ```

5. Insert the prepared SD card into your Raspberry Pi and power it on.

The Raspberry Pi will automatically configure itself and set up a video player with Samba file sharing.

## Quick Start

After creating the `config.sh` file, you can run the following command to execute the setup script in one go:

```bash
curl -s https://raw.githubusercontent.com/carstenbund/raspberry-pi-video-player-setup/main/pi_video_player.sh | bash
