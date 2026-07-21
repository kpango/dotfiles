# Ghostty Deployment Design

## Overview

Ensure that all necessary Ghostty files, specifically themes and shaders, are properly deployed to the host machine via the existing Makefile mechanisms in the `dotfiles` repository.

## Architecture & Data Flow

- The deployment logic is handled by `Makefile.d/install.mk`.
- The `DOTFILES_MAP` variable dictates which files and directories are copied or symlinked from the repository to the user's home directory.
- `ghostty.conf` is currently mapped to `.config/ghostty/config`.
- `ghostty/themes` and `ghostty/shaders` exist in the repository but are absent from the map.

## Implementation Details

Modify `Makefile.d/install.mk` to include the following lines in the `DOTFILES_MAP` definition:

```makefile
ghostty/themes .config/ghostty/themes
ghostty/shaders .config/ghostty/shaders
```

## Error Handling & Testing

- **Testing Strategy:** Run `make dotfiles/install` after modification and verify that the `.config/ghostty/themes` and `.config/ghostty/shaders` directories are correctly symlinked to the source directories in the repository.
- No new edge cases are expected since this relies on the battle-tested dotfiles deployment script.
