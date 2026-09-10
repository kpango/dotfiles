# Garuda Sway-WM CheatSheet

 = Super Key

# common operations

 Return _term_ (`ghostty`)
 q _quit_ (kill focused window)
 p _show activities_
 d _show app menu (i3 like)_ (`wofi`)
 Shift d _show app menu (mac like)_ (`...`)
 Shift e _show power menu_ (lock/suspend/logout/reboot/shutdown)
 Shift c _reload config files_ (`sway reload`)
 f1 _lock screen_ (`swaylock`)

# screenshot

            PrintSrc    *full screenshot*
     Shift  PrintSrc    *screenshot options*

# application shortcuts

 n _file manager_ (`thunar`)
 o _browser_ (`firedragon`)

# container layout

 b _split horizontally_ (on next open)
 v _split vertically_ (on next open)
 s _layout stacked_
 w _layout tabbed_
 e _toggle split_ (?)
 f _toggle fullscreen_
 Shift Space _toggle tiling/floating mode_
 Space _toggle tiling/floating focus_ (`focus mode_toggle`?)
 a _focus parent container_

 left mouse button _move floating window_
 right mouse button _resize floating window_

# window focus and location

 h / Left _focus left_
 j / Down _focus down_
 k / Up _focus up_
 l / Right _focus right_
 Shift h / Left _move left_
 Shift j / Down _move down_
 Shift k / Up _move up_
 Shift l / Right _move right_

# window size

 r _toggle resize mode_
h / Left
j / Down
k / Up
l / Right
Return / Escape _return to default mode_

# scratchpad

 Minus _cycle scratchpad_
 Shift Minus _move scratchpad_

# workspaces

 1 .. 0 _switch to workspace 1 .. 10_
 Shift 1 .. 0 _move container to workspace 1 .. 10_

# multimedia keys

- may not work for every keyboard
- may need to hold down the function (`fn`) key

# notes

- _Sway_ is documented through man pages unlike i3.
  To get a overview of what to expect you can read `man 5 sway`.
  The pages are then spilt into topics - some the important ones
  are listed at the bottom of the document.
- _Waybar_ is also documented through man pages - `man 5 waybar`.

- User configuration files are in `~/.config/`.
- Sway configuration files are in `~/.config/sway/config.d/`.
  `~/.config/sway/config` only includes the files in `config.d`.
  The file structure is spilt for easier use, where filenames refer
  to the part they play - for example `output` for output devices.
- Similarly, Waybar configuration is in `~/.config/waybar`.
