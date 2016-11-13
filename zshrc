#!/bin/zsh

if [ -z $DOTENV_LOADED ]; then
    setopt no_global_rcs
    if [ -x /usr/libexec/path_helper ]; then
        eval "$(/usr/libexec/path_helper -s)"
    fi

    # 環境変数
    export LANG=en_US.UTF-8
    export MANLANG=ja_JP.UTF-8
    export LC_TIME=en_US.UTF-8

    export PASSWORD="your password"

    [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh 
    if type nvim >/dev/null 2>&1; then
        export EDITOR=$(which nvim)
    else
        export EDITOR=$(which vim)
    fi

    export SHELL=$(which zsh)

    export CPUCORES="$(getconf _NPROCESSORS_ONLN)"

    #プログラミング環境構築
    export PROGRAMMING=$HOME/Documents/Programming;
    export XDG_CONFIG_HOME=$HOME/.config;
    export NVIM_HOME=$XDG_CONFIG_HOME/nvim;
    export XDG_DATA_HOME=$NVIM_HOME/log;
    export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME;

    #LLVM
    export LLVM_HOME=/usr/local/opt/llvm;
    export C=$LLVM_HOME/bin/clang;
    export CXX=$LLVM_HOME/bin/clang++;
    export LIBRARY_PATH=$LLVM_HOME/lib;
    export LLVM_CONFIG_PATH=$LLVM_HOME/bin/llvm-config;

    #CLANG
    export CFLAGS=-I$LLVM_HOME/include:-I$QT_HOME/include:-I/usr/local/opt/openssl/include:$CFLAGS;
    export CPPFLAGS=$CFLAGS;
    export LDFLAGS=-L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS;
    export C_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$C_INCLUDE_PATH;
    export CPLUS_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$CPLUS_INCLUDE_PATH;

    #JAVA
    if type java >/dev/null 2>&1; then
        export JDK_HOME=/Library/Java/JavaVirtualMachines/jdk$(java -version 2>&1 >/dev/null | grep 'java version' | sed -e 's/java\ version\ \"//g' -e 's/\"//g').jdk;
        export STUDIO_JDK=$JDK_HOME;
        export JAVA_HOME=$JDK_HOME/Contents/Home;
        export JRE_HOME=$JAVA_HOME/jre/bin;
        export ANDROID_HOME=/usr/local/opt/android-sdk;
        if type jetty >/dev/null 2>&1; then
            export JETTY_HOME=/usr/local/opt/jetty;
        fi
    fi

    export PHP_BUILD_CONFIGURE_OPTS="--with-openssl=/usr/local/opt/openssl"

    #GO
    export GOPATH=$PROGRAMMING/go;
    export GOBIN=$GOPATH/bin;
    export GO15VENDOREXPERIMENT=1;
    export NVIM_GO_LOG_FILE=$XDG_DATA_HOME/go;

    #Nim
    export NIMPATH=/usr/local/bin/Nim;

    #ReactNative
    export REACT_EDITOR=$EDITOR;

    # Rust
    export RUST_SRC_PATH=/usr/local/Cellar/rust/HEAD/src;
    export CARGO_HOME=$HOME/.cargo/bin;

    #QT
    export QT_HOME=/usr/local/opt/qt;

    # IntelliJ
    export NVIM_LISTEN_ADDRESS="127.0.0.1:7650";

    # CoreUtil
    export MANPATH=/usr/local/opt/coreutils/libexec/gnuman:$MANPATH

    if [ -z $TMUX ]; then
        export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/X11/bin:/usr/local/git/bin:/opt/local/bin:$HOME/.cabal/bin:$HOME/.local/bin:$LLVM_HOME/bin:$GOBIN:$JAVA_HOME/bin:$JRE_HOME:$NIMPATH/bin:$CARGO_HOME:$CARGO_HOME/bin:$PATH";
        #anyenv init
        if [ -d "$HOME/.anyenv" ] ; then
            export PATH="$HOME/.anyenv/bin:$PATH"
            if type anyenv >/dev/null 2>&1; then
                eval "$(anyenv init - --no-rehash)"
            fi
        fi
    fi

    if type ndenv > /dev/null 2>&1; then
        export NODE_BIN="$(ndenv prefix)/bin"
        export PATH="$NODE_BIN:$PATH"
    fi

    if type go >/dev/null 2>&1; then
        export GOROOT="$(go env GOROOT)";
        export GOOS="$(go env GOOS)";
        export GOARCH="$(go env GOARCH)";
    fi

    export ZPLUG_HOME=$HOME/.zplug;

    if [ -e $ZPLUG_HOME/repos/zsh-users/zsh-completions ]; then
        fpath=($ZPLUG_HOME/repos/zsh-users/zsh-completions/src $fpath)
    fi

    #Node
    if type npm >/dev/null 2>&1; then
        export NODE_PATH=$(npm root -g);
    fi

    if type vagrant > /dev/null 2>&1; then
        export VAGRANT_HOME=$HOME/Documents/vagrant;
    fi

    export HTTP_PROXY_HOST="proxy host"
    export HTTP_PROXY_PORT="http port"
    export HTTP_PROXY_PASSWORD="proxy passowrd"
    export HTTPS_PROXY_HOST="proxy host"
    export HTTPS_PROXY_PORT="https port"

    export DOTENV_LOADED=1
fi

if [ ! -f "$HOME/.zshrc.zwc" -o "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" ]; then
    zcompile $HOME/.zshrc
fi

if [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
    zcompile $HOME/.zcompdump
fi

########################################
#Zplug Settings
source "$HOME/.zplug/init.zsh";
if ! type zplug >/dev/null 2>&1; then
    rm -rf $ZPLUG_HOME
    git clone https://github.com/zplug/zplug $ZPLUG_HOME
    source "$HOME/.zshrc"
else
    zplug "zplug/zplug"
    zplug "Tarrasch/zsh-colors"
    zplug "ascii-soup/zsh-url-highlighter"
    zplug "b4b4r07/enhancd", use:enhancd.sh
    zplug "b4b4r07/zspec", as:command, use:bin/zspec
    zplug "chrissicool/zsh-256color"
    zplug "junegunn/fzf", as:command, use:bin/fzf-tmux
    zplug "mollifier/anyframe"
    zplug "mollifier/cd-gitroot"
    zplug "oknowton/zsh-dwim"
    zplug "rupa/z", use:z.sh
    zplug "supercrabtree/k"
    zplug "zsh-users/zsh-autosuggestions"
    zplug "zsh-users/zsh-completions"
    zplug "zsh-users/zsh-history-substring-search"
    zplug "zsh-users/zsh-syntax-highlighting", nice:10

    if zplug check b4b4r07/enhancd; then
        export ENHANCD_FILTER=fzf-tmux
        export ENHANCD_COMMAND=ccd
        export ENHANCD_FILTER=fzf:peco:gof
        export ENHANCD_DOT_SHOW_FULLPATH=1
    fi

    if zplug check supercrabtree/k; then
        alias ll='k --no-vcs'
        alias la='k -a --no-vcs'
        alias lla='k -a'
    fi

    if ! zplug check --verbose; then
        zplug install
    fi
    zplug load --verbose
    alias zsup="zcompinit;rm $HOME/.zshrc.zwc;zplug update;zplug clean;zplug clear;zplug status;zplug info;rm $HOME/.bashrc;rm $HOME/.fzf.bash;"
fi

# 色を使用出来るようにする
autoload -Uz colors
colors

# ヒストリの設定
HISTFILE=$HOME/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_save_no_dups
setopt share_history
LISTMAX=1000
WORDCHARS="$WORDCHARS|:"
# プロンプト
PROMPT="%{${fg[cyan]}%}%/#%{${reset_color}%} %"

# 単語の区切り文字を指定する
autoload -Uz select-word-style
select-word-style default
# ここで指定した文字は単語区切りとみなされる
# / も区切りと扱うので、^W でディレクトリ１つ分を削除できる
zstyle ':zle:*' word-chars " /=;@:{},|"
zstyle ':zle:*' word-style unspecified

########################################
# 補完
# 補完機能を有効にする
autoload -Uz compinit -C
compinit -C

zstyle ':completion:*' format '%B%d%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' ignore-parents parent pwd ..
zstyle ':completion:*' keep-prefix
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' menu select
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*:processes' command 'ps x -o pid, s, args'
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin

########################################
# vcs_info
autoload -Uz vcs_info
autoload -Uz add-zsh-hook

zstyle ':vcs_info:*' formats '%F{green}(%s)-[%b]%f'
zstyle ':vcs_info:*' actionformats '%F{red}(%s)-[%b|%a]%f'

function _update_vcs_info_msg() {
    LANG=en_US.UTF-8 vcs_info
    RPROMPT="${vcs_info_msg_0_}"
}
add-zsh-hook precmd _update_vcs_info_msg


########################################
# オプション
setopt auto_cd              # ディレクトリ名だけでcdする
setopt auto_list            # 補完候補を一覧表示
setopt auto_menu            # 補完候補が複数あるときに自動的に一覧表示する
setopt auto_param_keys      # カッコの対応などを自動的に補完
setopt auto_pushd           # cd したら自動的にpushdする
# setopt correct
setopt extended_glob
setopt ignore_eof
setopt interactive_comments # '#' 以降をコメントとして扱う
setopt list_packed          # 補完候補を詰めて表示
setopt list_types           # 補完候補一覧でファイルの種別をマーク表示
setopt magic_equal_subst    # = の後はパス名として補完する
setopt no_beep              # beep を無効にする
setopt no_flow_control      # フローコントロールを無効にする
setopt noautoremoveslash    # 最後のスラッシュを自動的に削除しない
setopt nonomatch
setopt notify               # バックグラウンドジョブの状態変化を即時報告
setopt print_eight_bit      # 日本語ファイル名を表示可能にする
setopt prompt_subst         # プロンプト定義内で変数置換やコマンド置換を扱う
setopt pushd_ignore_dups    # 重複したディレクトリを追加しない
########################################
# ^R で履歴検索をするときに * でワイルドカードを使用出来るようにする
bindkey '^R' history-incremental-pattern-search-backward

########################################
# エイリアス
alias cdu='cd-gitroot'
alias cp='cp -r'
alias ln="sudo ln -Fsnfiv"
alias mv='mv -i'
alias wget='wget --no-cookies --no-check-certificate --no-dns-cache -4'
alias mkdir='mkdir -p'

# sudo の後のコマンドでエイリアスを有効にする
alias sudo="echo $PASSWORD | sudo -S "

# グローバルエイリアス
alias -g L='| less'
alias -g G='| grep'

if type anyenv >/dev/null 2>&1; then
    alias anyenvup="anyenv update;anyenv git gc --aggressive;anyenv git prune;"
fi

if type nim >/dev/null 2>&1; then
    alias nimup="\cd $NIMPATH;git -C $NIMPATH pull;nim c $NIMPATH/koch;$NIMPATH/koch boot -d:release;\cd $HOME"
fi

go-update(){

    go get -u github.com/Masterminds/glide
    go get -u github.com/alecthomas/gometalinter
    go get -u github.com/constabulary/gb/...
    go get -u github.com/cweill/gotests/...
    go get -u github.com/garyburd/go-explorer/src/getool
    go get -u github.com/golang/lint/golint
    go get -u github.com/jstemmer/gotags
    go get -u github.com/kisielk/gotool
    go get -u github.com/mattn/files
    go get -u github.com/mattn/jvgrep
    go get -u github.com/motemen/go-iferr/cmd/goiferr
    go get -u github.com/nsf/gocode
    go get -u github.com/peco/peco/cmd/peco
    go get -u github.com/rogpeppe/godef
    go get -u github.com/zmb3/gogetdoc
    go get -u golang.org/x/tools/cmd/cover
    go get -u golang.org/x/tools/cmd/godoc
    go get -u golang.org/x/tools/cmd/goimports
    go get -u golang.org/x/tools/cmd/gorename
    go get -u sourcegraph.com/sqs/goreturns

    go install github.com/Masterminds/glide
    go install github.com/alecthomas/gometalinter
    go install github.com/constabulary/gb/...
    go install github.com/cweill/gotests
    go install github.com/garyburd/go-explorer/src/getool
    go install github.com/golang/lint/golint
    go install github.com/jstemmer/gotags
    go install github.com/kisielk/gotool
    go install github.com/mattn/jvgrep
    go install github.com/motemen/go-iferr/cmd/goiferr
    go install github.com/nsf/gocode
    go install github.com/peco/peco/cmd/peco
    go install github.com/rogpeppe/godef
    go install github.com/zmb3/gogetdoc
    go install golang.org/x/tools/cmd/cover
    go install golang.org/x/tools/cmd/godoc
    go install golang.org/x/tools/cmd/goimports
    go install golang.org/x/tools/cmd/gorename
    go install sourcegraph.com/sqs/goreturns

    $GOPATH/bin/gocode set autobuild true
    $GOPATH/bin/gocode set lib-path $GOPATH/pkg/darwin_amd64/
    $GOPATH/bin/gocode set propose-builtins true
}

if type go >/dev/null 2>&1; then
    alias goup="rm -rf $GOPATH/bin;rm -rf $GOPATH/pkg;go-update;nvim +GoInstall +GoInstallBinaries +GoUpdateBinaries +qall"
fi

if type apm >/dev/null 2>&1; then
    alias atomup="sudo apm update;sudo apm upgrade;sudo apm rebuild;sudo apm clean"
fi

alias gemup="sudo chmod -R 777 $HOME/.anyenv/envs/rbenv/versions/;sudo chmod -R 777 /Library/Ruby/;gem update --system;gem update"
alias haskellup="stack upgrade;stack update;cabal update"
alias npmup="npm update -g npm;npm update -g;npm upgrade -g"
alias pipup="pip install --upgrade pip;pip freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip install -U --upgrade"
alias pip2up="pip2 install --upgrade pip;pip2 freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip2 install -U --upgrade"
alias pip3up="pip3 install --upgrade pip;pip3 freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip3 install -U --upgrade"

mkcd() {
    if [[ -d $1 ]]; then
        \cd $1
    else
        printf "Confirm to Make Directory? $1 [y/N]: "
        if read -q; then
            echo; sudo \mkdir -p $1 && \cd $1
        fi
    fi
}

alias mkcd=mkcd
alias ..='\cd ../'
alias ...='\cd ../../'
alias ....='\cd ../../../'
alias ,,='\cd ../'
alias ,,,='\cd ../../'
alias ,,,,='\cd ../../../'
alias cdlc='mkcd /usr/local/'
alias cddl='mkcd $HOME/Downloads'
alias cddc='mkcd $HOME/Documents'
alias cdmd='mkcd $HOME/Documents/Programming/Markdown/'
alias cdpg='mkcd $HOME/Documents/Programming/'
alias cdpy='mkcd $HOME/Documents/Programming/Python'
alias cdrb='mkcd $HOME/Documents/Programming/Ruby'
alias cdph='mkcd $HOME/Documents/Programming/PHP'
alias cdjava='mkcd $HOME/Documents/Programming/Java'
alias cdjavaee='mkcd $HOME/Documents/Programming/JavaEE'
alias cdjavafx='mkcd $HOME/Documents/Programming/JavaFX'
alias cdgo='mkcd $HOME/Documents/Programming/go/src'
alias cdex='mkcd $HOME/Documents/Programming/elixir'
alias cdjs='mkcd $HOME/Documents/Programming/JavaScript'
alias cdnode='mkcd $HOME/Documents/Programming/Node'
alias cdsh='mkcd $HOME/Documents/Programming/shells'
alias cdnim='mkcd $HOME/Documents/Programming/Nim'
alias cdv='mkcd $HOME/Documents/vagrant'
alias cdvf='mkcd $HOME/Documents/vagrant/ForceVM'
alias cdcent='mkcd $HOME/Documents/vagrant/CentOS7'
alias cdarch='mkcd $HOME/Documents/vagrant/ArchLinux'

if type rails >/dev/null 2>&1; then
    alias railskill="kill -9 `ps aux | grep rails | awk '{print $2}'`"
fi

alias tarzip="tar Jcvf"
alias tarunzip="tar Jxvf"
alias f="open ."
alias ks="ls "
alias rm='sudo rm -rf'
alias find='sudo find'
alias grep='grep --color=auto'
alias lg='la | grep'

if type git >/dev/null 2>&1; then
    alias gco="git checkout"
    alias gsta="git status"
    alias gcom="git commit -m"
    alias gdiff="git diff"
    alias gbra="git branch"
    alias gpull="git pull origin"
    alias gpush="git push origin"
    gitcompush(){
        git add -A;
        git commit -m $1;
        git push -u origin $2;
    }
    alias gcp=gitcompush
    alias gfix="gcp fix master"
fi

if type tmux >/dev/null 2>&1; then
    alias aliastx='alias | grep tmux'
    alias tmls='\tmux list-sessions'
    alias tmlc='\tmux list-clients'
    alias killtmux='\tmux kill-server'
    alias tmkl='\tmux kill-session'
    alias tmaw='\tmux main-horizontal'
    alias tmuxa='\tmux -2 a -t'
fi

if type nvim >/dev/null 2>&1; then
    alias vi='nvim'
    alias vim="nvim"
    alias cim="nvim"
    alias bim="nvim"
    alias v="nvim"
    alias vedit="nvim $HOME/.config/nvim/init.vim"
    alias vspdchk="rm -rf /tmp/starup.log && nvim --startuptime /tmp/startup.log +q && less /tmp/startup.log"
    alias nvup="nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall;rm $HOME/.nvimlog;rm $HOME/.viminfo"
fi

if type rustc >/dev/null 2>&1; then
    alias rust="rustc -O"
fi

if type javac >/dev/null 2>&1; then
    alias javad="\javac -d64 -Dfile.encoding=UTF8"
    alias javacd="\javac -d64 -J-Dfile.encoding=UTF8"
fi

rsagen(){
    sudo -u $USER ssh-keygen -t rsa -b 4096 -P $1 -f $HOME/.ssh/id_rsa -C $USER
}

alias rsagen=rsagen

alias sedit="nvim $HOME/.ssh/config"
alias sshinit="sudo rm -rf $HOME/.ssh/known_hosts;chmod 600 $HOME/.ssh/config"

alias zedit="nvim $HOME/.zshrc"
alias zcompinit="sudo rm -rf $HOME/.zcompd*;sudo rm -rf $HOME/.zplug/zcompd*;"
alias zsinit="zcompinit;sudo rm -rf $HOME/.zplug;sudo rm -rf $HOME/.zshrc.zwc;zsup"

findfile(){
    sudo find $1 -name $2
}

alias findfile=findfile

greptext(){
    if type jvgrep >/dev/null 2>&1; then
        if [ $# -eq 3 ] && [ $3 = "-f" ]; then
            jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)Application\ Support|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$'
        else
            jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$'
        fi
    else
        find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
        -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
        -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 /dev/null
    fi
}

alias greptext=greptext

chword(){
    if [ $# -eq 3 ]; then
        jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$' -l -r \
        | xargs -t -P $CPUCORES sed -i "" -e "s/$2/$3/g";
    else
        echo "Not enough arguments"
    fi
}

alias chword=chword;

alias :q=exit

########################################
# OS 別の設定
case ${OSTYPE} in
    darwin*)
        #Mac用の設定
        alias ls='ls -G -F'
        alias -g C='| pbcopy'
        alias xcodeUUIDFix='sudo find -L $HOME/Library/Application\ Support/Developer/Shared/Xcode/Plug-ins -name Info.plist -maxdepth 3 | xargs -P $CPUCORES -I{} defaults write {} DVTPlugInCompatibilityUUIDs -array-add `defaults read /Applications/Xcode.app/Contents/Info DVTPlugInCompatibilityUUID`;sudo xcode-select --reset'
        proxy(){
            if [ $1 = "start" ]; then
                export http_proxy="http://$HTTP_PROXY_HOST:$HTTP_PROXY_PORT";
                export HTTP_PROXY="http://$HTTP_PROXY_HOST:$HTTP_PROXY_PORT";
                sudo networksetup -setwebproxy Wi-Fi $HTTP_PROXY_HOST $HTTP_PROXY_PORT;
                sudo networksetup -setwebproxystate Wi-Fi on;
            elif [ $1 = "stop" ]; then
                export http_proxy="";
                export HTTP_PROXY="";
                unset http_proxy;
                unset HTTP_PROXY;
                sudo networksetup -setwebproxystate Wi-Fi off
            elif [ $1 = "status" ]; then
                echo $http_proxy;
            fi

            ssh ci "echo $HTTP_PROXY_PASSWORD | sudo -S systemctl $1 proxy"
        }
        alias proxy=proxy
        
        dns(){
            if [ $1 = "start" ]; then
                sudo networksetup -setdnsservers Wi-Fi  106.186.17.181 129.250.35.250 129.250.35.251 8.8.8.8 8.8.4.4
            elif [ $1 = "stop" ]; then
                sudo networksetup -setdnsservers Wi-Fi Empty
            elif [ $1 = "status" ]; then
                networksetup -getdnsservers Wi-Fi
            fi
        }
        alias dns=dns

        dock(){
            if [ $1 = "l" ] || [ $1 = "left" ];then
                defaults write com.apple.dock orientation -string left
            elif [ $1 = "r" ] || [ $1 = "right" ];then
                defaults write com.apple.dock orientation -string right
            else
                defaults write com.apple.dock orientation -string bottom
            fi

            killall Dock
        }
        alias dock=dock

        if type brew >/dev/null 2>&1; then
            if [ -z $OSXENV_LOADED ]; then
                export CLICOLOR=1
                export HOMEBREW_GITHUB_API_TOKEN="Please Insert Your GitHub API Token"
                export HOMEBREW_EDITOR=$EDITOR
                export HOMEBREW_MAKE_JOBS=6
                export HOMEBREW_CASK_OPTS="--appdir=/Applications"
                export CFLAGS="-I$(xcrun --show-sdk-path)/usr/include:$CFLAGS"
                export OSXENV_LOADED=1
            fi
            alias brew="env PATH=${PATH//$HOME\/.anyenv\/envs\/*\/shims:/} brew";
            alias brewup="brew upgrade;\cd $(brew --repo) && git fetch && git reset --hard origin/master && brew update && \cd -;brew-cask-update;brew prune;brew doctor";

            brewcaskup(){
                brew untap caskroom/homebrew-cask;
                rm -rf $(brew --prefix)/Library/Taps/phinze-cask;
                rm $(brew --prefix)/Library/Formula/brew-cask.rb;
                rm -rf $(brew --prefix)/Library/Taps/caskroom;
                brew uninstall --force brew-cask;
                brew update;
                brew cask update;
                brew cleanup;
                brew cask cleanup;
            }
            alias brew-cask-update=brewcaskup

            alias update="sudo chown -R $(whoami) /usr/local;anyenvup;brewup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;nimup;atomup;nvup;zsup;rm $HOME/.lesshst;rm $HOME/.mysql_history;";
        else
            alias update="sudo chown -R $(whoami) /usr/local;anyenvup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;nimup;atomup;nvup;zsup"

        fi
        ;;
    linux*)
        #Linux用の設定
        alias ls='ls -F --color=auto'
        alias -g C='| xsel --input --clipboard'
        alias update="sudo chown -R $(whoami) /usr/local;anyenvup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;nimup;nvup;zsup"
        ;;
esac
