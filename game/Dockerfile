# syntax=docker/dockerfile:1
FROM ubuntu:24.04

LABEL maintainer="kpango <kpango@vdaas.org>" \
      description="Isolated Steam and Proton environment for Ace Combat 7"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute,display,video

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Enable 32-bit architecture (required by Steam runtime and 32-bit Wine/DXVK components)
# Install base utilities, locales, Steam, Vulkan/OpenGL, and audio libraries
# hadolint ignore=DL3008
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        curl \
        dbus-x11 \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        gamemode \
        gosu \
        libasound2t64:i386 \
        libasound2-plugins:i386 \
        libgl1-mesa-dri:amd64 \
        libgl1-mesa-dri:i386 \
        libgl1:amd64 \
        libgl1:i386 \
        libglib2.0-0t64:amd64 \
        libglib2.0-0t64:i386 \
        libgtk-3-0t64:amd64 \
        libgtk-3-0t64:i386 \
        libpulse0:amd64 \
        libpulse0:i386 \
        libudev1:amd64 \
        libudev1:i386 \
        libvulkan1:amd64 \
        libvulkan1:i386 \
        locales \
        mangohud \
        mesa-vulkan-drivers:amd64 \
        mesa-vulkan-drivers:i386 \
        pciutils \
        pulseaudio-utils \
        vulkan-tools \
        zenity \
    && locale-gen en_US.UTF-8 \
    && echo steam steam/question select "I AGREE" | debconf-set-selections \
    && echo steam steam/license note "" | debconf-set-selections \
    && apt-get install --no-install-recommends -y steam-installer \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default working directory
WORKDIR /home/steam

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["steam"]
