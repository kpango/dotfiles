#!/bin/sh

rm -rf "$HOME/.zshrc";
cp "./zshrc" "$HOME/.zshrc";
rm -rf "$HOME/.config"
mkdir -p "$HOME/.config/nvim/tmp"
mkdir -p "$HOME/.config/nvim/colors"
mkdir -p "$HOME/.config/nvim/plugged"
cp "./init.vim" "$HOME/.config/nvim/"
cp "./monokai.vim" "$HOME/.config/nvim/colors/"
mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.back"
cp "./tmux.conf" "$HOME/.tmux.conf"
cp "./tmux-status-line" "$HOME/.tmux-status-line"
mv "$HOME/.eslintrc" "$HOME/.eslintrc.back"
cp "./eslintrc" "$HOME/.eslintrc"
mv "$HOME/.esformatter" "$HOME/.esformatter.back"
cp "./esformatter" "$HOME/.esformatter"
mv "$HOME/.gitignore" "$HOME/.gitignore.back"
cp "./gitignore" "$HOME/.gitignore"
mv "$HOME/.gitattributes" "$HOME/.gitattributes.back"
cp "./gitattributes" "$HOME/.gitattributes"
mv "$HOME/.gitconfig" "$HOME/.gitconfig.back"
cp "./gitconfig" "$HOME/.gitconfig"

sed -i -e "s/\"PASSWORD\"/\"$1\"/g" "$HOME/.zshrc"

echo "$1" | sudo -S mkdir -p /usr/local/bin
echo "$1" | sudo -S mkdir -p /usr/local/etc
echo "$1" | sudo -S mkdir -p /usr/local/opt

echo "$1" | sudo -S chmod -R 777 /usr/local

reload_anyenv() {
    export PROGRAMMING=$HOME/Documents/Programming;
    export GOPATH=$PROGRAMMING/go;
    export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/X11/bin:/usr/local/git/bin:/opt/local/bin:$HOME/.cabal/bin:$GOPATH/bin:$JAVA_HOME/bin:$JRE_HOME:$PATH;
    if [ -d "$HOME/.anyenv" ] ; then
        export PATH="$HOME/.anyenv/bin:$PATH"
        if type anyenv >/dev/null 2>&1; then
            eval "$(anyenv init - --no-rehash)"
        fi
    fi
}

if type nvim > /dev/null 2>&1; then
    echo 'neovim found'
else
    if [ "$(uname)" = 'Darwin' ]; then
        OS='Mac'
        if ! type brew > /dev/null 2>&1; then
            ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)";
            export HOMEBREW_CASK_OPTS="--appdir=/Applications"
            brew update
            brew upgrade --all
            brew cleanup
        fi

        if ! type zsh > /dev/null 2>&1; then
            brew install zsh --HEAD
        fi

        if ! type go > /dev/null 2>&1; then
            brew install go
        fi

    elif [ "$(expr substr $(uname -s) 1 5)" = 'Linux' ]; then
        OS="Linux"
        if   [ -e /etc/debian_version ] || [ -e /etc/debian_release ]; then
            echo "$1" | sudo -S add-apt-repository ppa:neovim-ppa/unstable
            echo "$1" | sudo -S apt-get update
            echo "$1" | sudo -S apt-get install xclip xsel
        else
            echo "$1" | sudo -S yum -y install epel-release.noarch
            echo "$1" | sudo -S yum -y install git libtool autoconf automake cmake gcc gcc-c++ make pkgconfig unzip ctags
            echo "$1" | sudo -S yum -y groupinstall "Development Tools"
            echo "$1" | sudo -S yum -y install readline readline-devel zlib zlib-devel bzip2 bzip2-devel sqlite sqlite-devel openssl openssl-devel 
            if ! type tmux > /dev/null 2>&1; then
                echo "$1" | sudo -S yum -y install tmux --enablerepo=rpmforge
            fi

        fi
        echo "$1" | sudo -S mkdir -p /usr/local/bin
        echo "$1" | sudo -S mkdir -p /usr/local/etc
        echo "$1" | sudo -S mkdir -p /usr/local/opt

        echo "$1" | sudo -S chmod -R 777 /usr/local

        if ! type zsh > /dev/null 2>&1; then
            wget http://downloads.sourceforge.net/project/zsh/zsh/5.2/zsh-5.2.tar.gz
            tar xzvf zsh-5.2.tar.gz
            cd zsh-5.2 || exit
            ./configure --prefix="$HOME/local" --enable-multibyte --enable-locale
            echo "$1" | sudo -S make
            echo "$1" | sudo -S make install
        fi

        if ! type go > /dev/null 2>&1; then
            wget https://storage.googleapis.com/golang/go1.8.linux-amd64.tar.gz
            tar xvzf ./go1.8.linux-amd64.tar.gz
            mv go /usr/local/go
            rm -rf ./go1.8.linux-amd64.tar.gz
        fi
    else
        echo "Your platform ($(uname -a)) is not supported."
        exit 1
    fi

    if ! type nvim > /dev/null 2>&1; then
        echo "$1" | sudo -S rm -rf /usr/local/bin/nvim
        echo "$1" | sudo -S rm -rf /usr/local/share/nvim
        cd "$HOME" || exit
        git clone https://github.com/neovim/neovim
        cd neovim || exit
        rm -r build/
        make clean
        make CMAKE_BUILD_TYPE=RelWithDebInfo
        echo "$1" | sudo -S make install
        cd ../ || exit
        rm -rf neovim
    fi

fi

chsh -s "$(which zsh)"

if type anyenv > /dev/null 2>&1; then
    echo "anyenv found"
else
    # anyenv install
    git clone https://github.com/riywo/anyenv "$HOME/.anyenv"
    mkdir -p "$HOME/.anyenv/plugins"
    git clone https://github.com/znz/anyenv-update.git "$HOME/.anyenv/plugins/anyenv-update"
    git clone git://github.com/aereal/anyenv-exec.git "$HOME/.anyenv/plugins/anyenv-exe"
    git clone https://github.com/znz/anyenv-git.git "$HOME/.anyenv/plugins/anyenv-git"
    anyenv update
    anyenv git gc
    anyenv exec --version
fi

reload_anyenv
"$HOME/.anyenv/bin/anyenv" install -l

if type pip3 > /dev/null 2>&1; then
    echo 'pip3 found'
else
    if ! type pyenv > /dev/null 2>&1; then
    "$HOME/.anyenv/bin/anyenv" install pyenv

    mkdir -p "$HOME/.anyenv/envs/pyenv/plugins"
    git clone git://github.com/yyuu/pyenv-virtualenv.git "$HOME/.anyenv/envs/pyenv/plugins/pyenv-virtualenv"
    git clone https://github.com/yyuu/pyenv-pip-rehash.git "$HOME/.anyenv/envs/pyenv/plugins/pyenv-pip-rehash"

    reload_anyenv
    fi

    if ! type python3 > /dev/null 2>&1; then
    PYTHON_CONFIGURE_OPTS="--enable-framewok" "$HOME/.anyenv/envs/pyenv/bin/pyenv" install 2.7.13
    PYTHON_CONFIGURE_OPTS="--enable-framewok" "$HOME/.anyenv/envs/pyenv/bin/pyenv" install 3.6.0
    "$HOME/.anyenv/envs/pyenv/bin/pyenv" global 2.7.13 3.6.0

    reload_anyenv
    fi

    "$HOME/.anyenv/envs/pyenv/shims/pip" install --upgrade pip;
    "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade pip;
    "$HOME/.anyenv/envs/pyenv/shims/pip3" install --upgrade pip;
    "$HOME/.anyenv/envs/pyenv/shims/pip" install --upgrade sexpdata websocket-client neovim vim-vint;
    "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade sexpdata websocket-client neovim vim-vint;
    "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade sexpdata websocket-client neovim vim-vint;
fi

if type gem > /dev/null 2>&1; then
    echo 'gem found'
else
    if ! type rbenv > /dev/null 2>&1; then
    "$HOME/.anyenv/bin/anyenv" install rbenv
    fi

    if ! type ruby > /dev/null 2>&1; then
    $HOME/.anyenv/envs/rbenv/bin/rbenv install 2.5.0-dev
    $HOME/.anyenv/envs/rbenv/bin/rbenv global 2.5.0-dev
    echo "$1" | sudo -S rm -rf /usr/bin/ruby
    echo "$1" | sudo -S rm -rf /usr/bin/gem
    echo "$1" | sudo -S ln -sfv $HOME/.anyenv/envs/rbenv/shims/ruby /usr/bin/ruby
    echo "$1" | sudo -S ln -sfv $HOME/.anyenv/envs/rbenv/shims/gem /usr/bin/gem
    reload_anyenv
    echo "$1" | sudo -S chmod -R 755 $HOME/.anyenv/envs/rbenv/versions
    reload_anyenv
    fi

    $HOME/.anyenv/envs/rbenv/shims/gem install neovim --no-rdoc --no-ri
fi

mkdir -p ~/.config/nvim/plugged/vim-plug
git clone https://github.com/junegunn/vim-plug.git ~/.config/nvim/plugged/vim-plug/autoload

nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall
wget -P "$HOME/.config/nvim/plugged/nvim-go/syntax/" https://raw.githubusercontent.com/fatih/vim-go/master/syntax/go.vim
