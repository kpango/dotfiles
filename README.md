# dotfiles
----
kpango's dotfiles
Fullstack Develop Environment in Docker

## Description

- neovim (https://neovim.io)
  - vim-plug (https://github.com/junegunn/vim-plug)
  - vim-lsp (https://github.com/prabirshrestha/vim-lsp)
  - python3 deoplete dependency
  - language
    - Go
    - Rust
    - Nim
    - Python
    - C / C++
    - Ruby
    - JavaScript
    - HTML CSS
- zsh
  - zplug (https://github.com/zplug/zplug)
- tmux
- git
  - gitconfig
  - gitignore
  - gitattributes

## Requirements
- ghq
- make
- docker
- bash/zsh

## Install
```shell
# I recommend use ghq instead of git command
git config --global ghq.root $HOME/go/src
ghq get kpango/dotfiles
cd $HOME/go/src/github.com/kpango/dotfiles
make $SHELL
```

## Contribution
1. Fork it ( http://github.com/kpango/dotfiles/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create new Pull Request

## Author

[kpango](https://github.com/kpango)
