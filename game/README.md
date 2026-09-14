# Steam & Ace Combat 7 in Docker (dotfiles/game)

Isolated, containerized Steam & Proton environment optimized for **ACE COMBAT™ 7: SKIES UNKNOWN (AppID: 502500)** on Arch Linux / Wayland (Sway) with NVIDIA GPU passthrough and PipeWire / PulseAudio support.

---

## 1. DeepResearch: ProtonDB Findings for ACE COMBAT 7

### Compatibility Tier: Platinum
* **Verdict**: Runs near-flawlessly out of the box with modern Proton (Proton 8/9, Experimental, or GE-Proton).
* **Multiplayer / Cutscene Status**:
  * **Cutscenes**: Bandai Namco uses Windows Media Foundation (`mfplat`) for in-game video cutscenes. Standard Proton 8/9 has built-in support, but **GE-Proton** (Proton-GE) provides the most robust video decoding via bundled GStreamer plugins.
  * **Stuttering**: UE4 texture streaming and shader compilation can cause initial hitching or multiplayer frame drops. This is mitigated by:
    1. Enabling **DXVK Graphics Pipeline Library (GPL)** (default on modern NVIDIA 535+ drivers).
    2. Capping framerate to **60 FPS** (`MANGOHUD_CONFIG="fps_limit=60,no_display" mangohud %command%` or UE4 `t.MaxFPS=60`).
    3. Setting DXVK async compilation in `dxvk.conf`.
  * **Controllers & HOTAS**:
    * Standard gamepads (Xbox, PlayStation DualSense/DualShock) work out of the box via Steam Input.
    * Flight sticks (HOTAS) other than the officially branded models (HORI, Thrustmaster T.Flight Hotas 4) require setting **"Disable Steam Input"** in Steam game properties and mapping axes in `Input.ini`.

---

## 2. Architecture & Container Design

```
+-------------------------------------------------------------+
| Host (Arch Linux Zen Kernel / Sway Wayland / NVIDIA RTX)    |
|                                                             |
|  [Display]         [Audio]            [GPU]        [Input]  |
|  /tmp/.X11-unix/X0 /run/user/1000/    NVIDIA       /dev/    |
|  wayland-1         pulse/native       Container    input/   |
|                    pipewire-0         Toolkit      uinput   |
+--------+--------------+-----------------+------------+------+
         |              |                 |            |
+--------v--------------v-----------------v------------v------+
| Docker Container (Ubuntu 24.04 LTS + i386 Steam Runtime)    |
|                                                             |
|  UID:GID 1000:1000 (kpango)                                 |
|  - Mesa / NVIDIA Vulkan ICD (libvulkan1:i386 & amd64)       |
|  - PulseAudio / PipeWire audio bridge                       |
|  - MangoHud / GameMode integration                          |
|                                                             |
|  [Steam Client]                                             |
|        |                                                    |
|        +---> [GE-Proton / Proton Experimental]              |
|                    |                                        |
|                    +---> [Ace Combat 7: Skies Unknown]      |
|                                                             |
|  Mounted Volume: ~/.local/share/dotfiles-game/steam         |
|  (Persistent Steam library, games, prefixes, saves)         |
+-------------------------------------------------------------+
```

### Key Highlights
- **No Host Pollution**: No need to install `steam` or 32-bit multilib graphics drivers on the host Arch Linux OS.
- **NVIDIA GPU Acceleration**: Direct access via NVIDIA Container Toolkit (`--gpus all`), preserving hardware acceleration.
- **Wayland / Xwayland Hybrid**: Binds both `/tmp/.X11-unix` and Wayland runtime sockets.
- **Low Latency Audio**: Native UNIX socket pass-through for PipeWire / PulseAudio.
- **Gamepad / HOTAS**: Full pass-through of `/dev/input` and `/dev/uinput`.
- **Persistent Storage**: Steam game downloads, compatibility prefixes (`compatdata`), and save files reside in `~/.local/share/dotfiles-game/steam`.

---

## 3. Quick Start

### Build Container
```bash
make game/build
```

### Launch Steam Client
```bash
make game/run
```

### Launch ACE COMBAT 7 Directly
```bash
make game/ac7
```

---

## 4. Tuning & Optimization for ACE COMBAT 7

### Recommended Launch Options in Steam
Right-click **ACE COMBAT 7** in Steam -> **Properties** -> **General** -> **Launch Options**:
```text
MANGOHUD_CONFIG="fps_limit=60,no_display" mangohud %command%
```
*(If you want to view the MangoHud overlay, omit `no_display`)*.

### Recommended Proton Version
1. In Steam, right-click **ACE COMBAT 7** -> **Properties** -> **Compatibility**.
2. Check **Force the use of a specific Steam Play compatibility tool**.
3. Select **Proton Experimental** or **GE-Proton**.

### Applying Custom Configs (HOTAS / Engine)
The helper script `game/scripts/ac7-tuning.sh` automatically copies optimized `dxvk.conf`, `Engine.ini`, and `Input.ini` into the game prefix:
```bash
make game/tune
```
