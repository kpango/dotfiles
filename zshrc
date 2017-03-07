#!/bin/zsh

if [ -z $DOTENV_LOADED ]; then
    setopt no_global_rcs
    if [ -x /usr/libexec/path_helper ]; then
        PATH=''
        eval "$(/usr/libexec/path_helper -s)"
    fi

    # 環境変数
    export LANG=en_US.UTF-8
    export MANLANG=ja_JP.UTF-8
    export LC_TIME=en_US.UTF-8

    if type nvim >/dev/null 2>&1; then
        export VIM=$(which nvim);
        export VIMRUNTIME=/usr/local/share/nvim/runtime;
    else
        export VIM=$(which vim);
        export VIMRUNTIME=/usr/share/vim/vim*;
    fi

    export EDITOR=$VIM;
    export VISUAL=$VIM;
    export PAGER=$(which less);
    export SUDO_EDITOR=$EDITOR;

    export PASSWORD="PASSWORD"

    [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

    export SHELL=$(which zsh)

    export CPUCORES="$(getconf _NPROCESSORS_ONLN)"

    #プログラミング環境構築
    export PROGRAMMING=$HOME/Documents/Programming;
    export XDG_CONFIG_HOME=$HOME/.config;
    export NVIM_HOME=$XDG_CONFIG_HOME/nvim;
    export XDG_DATA_HOME=$NVIM_HOME/log;
    export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME;
    export NVIM_PYTHON_LOG_LEVEL=WARNING;
    export NVIM_PYTHON_LOG_FILE=$NVIM_LOG_FILE_PATH/nvim.log;

    export LLVM_HOME=/usr/local/opt/llvm;

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

    if type composer >/dev/null 2>&1; then
        export COMPOSER_HOME="$HOME/.composer/vendor"
    fi

    export PHP_BUILD_CONFIGURE_OPTS="--with-openssl=/usr/local/opt/openssl"
    export PYTHON_CONFIGURE_OPTS="--enable-framework"

    #GO
    export GOPATH=$PROGRAMMING/go;
    export CGO_ENABLED=1;
    export GOBIN=$GOPATH/bin;
    export GO15VENDOREXPERIMENT=1;
    export NVIM_GO_LOG_FILE=$XDG_DATA_HOME/go;
    export CGO_CFLAGS="-g -Ofast -march=native"
    export CGO_CPPFLAGS="-g -Ofast -march=native"
    export CGO_CXXFLAGS="-g -Ofast -march=native"
    export CGO_FFLAGS="-g -Ofast -march=native"
    export CGO_LDFLAGS="-g -Ofast -march=native"

    #Nim
    export NIMPATH=/usr/local/bin/Nim;
    export NIMBLE_PATH=$HOME/.nimble;

    #ReactNative
    export REACT_EDITOR=$EDITOR;

    # Rust
    export RUST_SRC_PATH=/usr/local/src/rust/src;
    export RUST_BACKTRACE=1;
    export CARGO_HOME=$HOME/.cargo;

    #QT
    export QT_HOME=/usr/local/opt/qt;

    # IntelliJ
    export NVIM_LISTEN_ADDRESS="127.0.0.1:7650";

    # CoreUtil
    export MANPATH=/usr/local/opt/coreutils/libexec/gnuman:$MANPATH

    if [ -z $TMUX ]; then
        export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/X11/bin:/usr/local/git/bin:/usr/local/go/bin:/opt/local/bin:$HOME/.cabal/bin:$HOME/.local/bin:$LLVM_HOME/bin:$GOBIN:$COMPOSER_HOME/bin:$JAVA_HOME/bin:$JRE_HOME:$NIMPATH/bin:$NIMBLE_PATH/bin:$CARGO_HOME:$CARGO_HOME/bin:$PATH";
        #anyenv init
        if [ -d "$HOME/.anyenv" ] ; then
            export PATH="$HOME/.anyenv/bin:$HOME/.anyenv/libexec:$PATH"
            eval "$(anyenv init - --no-rehash zsh)"
        fi
    fi

    #LLVM
    if type llvm >/dev/null 2>&1; then
        export C=$LLVM_HOME/bin/clang;
        export CC=$LLVM_HOME/bin/clang;
        export CPP=$LLVM_HOME/bin/clang++;
        export CXX=$LLVM_HOME/bin/clang++;
        export LD_LIBRARY_PATH=$(llvm-config --libdir):$LD_LIBRARY_PATH;
        export LIBRARY_PATH=$LLVM_HOME/lib;
        export LLVM_CONFIG_PATH=$LLVM_HOME/bin/llvm-config;

        #CLANG
        export CFLAGS=-I$LLVM_HOME/include:-I$QT_HOME/include:-I/usr/local/opt/openssl/include:$CFLAGS;
        export CPPFLAGS=$CFLAGS;
        export LDFLAGS=-L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS;
        export C_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$C_INCLUDE_PATH;
        export CPLUS_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$CPLUS_INCLUDE_PATH;
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
        export NODE_PATH=$(\npm root -g);
    fi

    if type vagrant > /dev/null 2>&1; then
        export VAGRANT_HOME=$HOME/Documents/vagrant;
    fi

    export HTTP_PROXY_HOST="HTTP_PROXY_HOST"
    export HTTP_PROXY_PORT="HTTP_PROXY_PORT"
    export HTTP_PROXY_PASSWORD="PASSWORD"
    export HTTPS_PROXY_HOST=$HTTP_PROXY_HOST
    export HTTPS_PROXY_PORT="HTTPS_PROXY_PORT"

    if type zplug > /dev/null 2>&1; then
        if zplug check junegunn/fzf; then
            export FZF_DEFAULT_COMMAND='rg --files --hidden --smartcase --glob "!.git/*"'
        fi

        if zplug check b4b4r07/enhancd; then
            export ENHANCD_FILTER=fzf-tmux
            export ENHANCD_COMMAND=ccd
            export ENHANCD_FILTER=fzf:peco:gof
            export ENHANCD_DOT_SHOW_FULLPATH=1
        fi
    fi

    if [ ! -f "$HOME/.zshrc.zwc" -o "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" ]; then
        zcompile $HOME/.zshrc
    fi

    if [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
        zcompile $HOME/.zcompdump
    fi

    export DOTENV_LOADED=1
fi

########################################
#Zplug Settings
if [[ -f ~/.zplug/init.zsh ]]; then
    source "$HOME/.zplug/init.zsh";

    zplug "zchee/go-zsh-completions"
    zplug "junegunn/fzf-bin", as:command, from:gh-r, rename-to:fzf
    zplug "junegunn/fzf", as:command, use:bin/fzf-tmux
    zplug "rupa/z", use:z.sh
    zplug "supercrabtree/k"
    zplug "zsh-users/zsh-autosuggestions"
    zplug "zsh-users/zsh-completions"
    zplug "zsh-users/zsh-history-substring-search"
    zplug "zsh-users/zsh-syntax-highlighting", defer:2
    zplug "soimort/translate-shell", at:stable, as:command, use:"build/*", hook-build:"make build &> /dev/null"

    if ! zplug check --verbose; then
        zplug install
    fi

    zplug load
else
    rm -rf $ZPLUG_HOME
    git clone https://github.com/zplug/zplug $ZPLUG_HOME
    source "$HOME/.zshrc"
fi

if ! [ -z $TMUX ]||[ -z $ZSH_LOADED ]; then

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

    _update_vcs_info_msg() {
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
    setopt correct
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
    bindkey -e
    bindkey '^R' history-incremental-pattern-search-backward

    fzf-z-search (){
        which fzf z > /dev/null
        if [ $? -ne 0 ]; then
            echo "Please install fzf and z"
            return 1
        fi
        local res=$(z | sort -rn | cut -c 12- | fzf)
        if [ -n "$res" ]; then
            BUFFER+="$res"
            zle accept-line
        else
            return 1
        fi
    }
    zle -N fzf-z-search
    bindkey '^s' fzf-z-search

    if type go >/dev/null 2>&1; then

        go-get(){
            cd $GOPATH/src/$1
            git fetch
            git reset --hard origin/master
            git submodule foreach git pull origin master
            cd -
            go get -u $1
        }

        go-update(){
            go-get github.com/Masterminds/glide &
            go-get github.com/aarzilli/gdlv &
            go-get github.com/alecthomas/gometalinter &
            go-get github.com/concourse/fly &
            go-get github.com/constabulary/gb/... &
            go-get github.com/cweill/gotests/... &
            go-get github.com/derekparker/delve/cmd/dlv &
            go-get github.com/garyburd/go-explorer/src/getool &
            go-get github.com/golang/dep/... &
            go-get github.com/golang/lint/golint &
            go-get github.com/gopherjs/gopherjs &
            go-get github.com/haya14busa/gosum/cmd/gosumcheck &
            go-get github.com/haya14busa/goverage &
            go-get github.com/haya14busa/reviewdog/cmd/reviewdog &
            go-get github.com/jstemmer/gotags &
            go-get github.com/kardianos/govendor &
            go-get github.com/kisielk/gotool &
            go-get github.com/mattn/files &
            go-get github.com/mattn/jvgrep &
            go-get github.com/motemen/ghq &
            go-get github.com/motemen/go-iferr/cmd/goiferr &
            go-get github.com/motemen/gofind/cmd/gofind &
            go-get github.com/nsf/gocode &
            go-get github.com/onsi/ginkgo/ginkgo &
            go-get github.com/peco/peco/cmd/peco &
            go-get github.com/pwaller/goimports-update-ignore &
            go-get github.com/rogpeppe/godef &
            go-get github.com/valyala/quicktemplate/... &
            go-get github.com/zmb3/gogetdoc &
            go-get golang.org/x/tools/cmd/cover &
            go-get golang.org/x/tools/cmd/godoc &
            go-get golang.org/x/tools/cmd/goimports &
            go-get golang.org/x/tools/cmd/gorename &
            go-get golang.org/x/tools/cmd/guru &
            go-get golang.org/x/tools/cmd/present &
            go-get google.golang.org/grpc &
            go-get sourcegraph.com/sqs/goreturns &

            wait

            gocode set autobuild true
            gocode set lib-path $GOPATH/pkg/$GOOS\_$GOARCH/
            gocode set propose-builtins true
        }

        cover () {
            t=$(mktemp -t cover)
            go test $COVERFLAGS -coverprofile=$t $@ && go tool cover -func=$t && unlink $t
        }
        cover-web() {
            t=$(mktemp -t cover)
            go test $COVERFLAGS -coverprofile=$t $@ && go tool cover -html=$t && unlink $t
        }

        alias goui=goimports-update-ignore
        alias go-update=go-update
        alias goup="rm -rf $GOPATH/bin;rm -rf $GOPATH/pkg;go-update;$VIM +GoInstall +GoInstallBinaries +GoUpdateBinaries +qall"
    fi

    mkcd() {
        if [[ -d $1 ]]; then
            \cd $1
        else
            printf "Confirm to Make Directory? $1 [y/N]: "
            if read -q; then
                echo; \mkdir -p $1 && \cd $1
            fi
        fi
    }

    if type git >/dev/null 2>&1; then
        alias gco="git checkout"
        alias gsta="git status"
        alias gcom="git commit -m"
        alias gdiff="git diff"
        alias gbra="git branch"
        gitthisrepo(){
            git symbolic-ref --short HEAD|tr -d "\n"
        }
        alias tb=gitthisrepo
        alias gfr="git fetch;git reset --hard origin/master"
        gitpull(){
            git pull --rebase origin $(tb)
        }
        alias gpull=gitpull
        alias gpush="git push origin"
        gitcompush(){
            git add -A;
            git commit -m $1;
            git push -u origin $2;
        }
        alias gitcompush=gitcompush
        gcp(){
            gitcompush $1 "$(tb)";
        }
        alias gcp=gcp
        alias gfix="gcp fix"
        alias gedit="$EDITOR $HOME/.gitconfig"
    fi

    if type rustc >/dev/null 2>&1; then
        rust_run() {
            rustc $1
            local binary=$(basename $1 .rs)
            ./$binary
        }
        alias rust="rustc -O"
        alias rrun="rust_run"
    fi

    # sudo の後のコマンドでエイリアスを有効にする
    alias sudo="echo $PASSWORD | sudo -S "

    # エイリアス
    alias cp='cp -r'
    alias ln="sudo ln -Fsnfiv"
    alias mv='mv -i'

    if type axel >/dev/null 2>&1; then
        alias wget='axel -a -n 10'
    else
        alias wget='wget --no-cookies --no-check-certificate --no-dns-cache -4'
    fi

    alias mkdir='mkdir -p'
    alias gtrans='trans -b -e google'

    # グローバルエイリアス
    alias -g L='| less'
    alias -g G='| grep'

    if type zplug >/dev/null 2>&1; then
        if zplug check supercrabtree/k; then
            alias ll='k --no-vcs'
            alias la='k -a --no-vcs'
            alias lla='k -a'
        fi
    fi

    if type anyenv >/dev/null 2>&1; then
        alias anyenvup="anyenv update;anyenv git gc --aggressive;anyenv git prune;"
    fi

    if type nim >/dev/null 2>&1; then
        alias nimup="\cd $NIMPATH;git -C $NIMPATH pull;nim c $NIMPATH/koch;$NIMPATH/koch boot -d:release;\cd $HOME"
    fi

    if type apm >/dev/null 2>&1; then
        alias atomup="sudo apm update;sudo apm upgrade;sudo apm rebuild;sudo apm clean"
    fi

    alias gemup="sudo chmod -R 777 $HOME/.anyenv/envs/rbenv/versions/;sudo chmod -R 777 /Library/Ruby/;gem update --system;gem update"
    alias haskellup="stack upgrade;stack update;cabal update"
    alias npmup="npm update -g npm;npm update -g;npm upgrade -g"
    alias pipup="sudo chown -R $(whoami) $HOME/.anyenv/envs/pyenv/versions/$(python -V 2>&1 >/dev/null | sed -e 's/Python\ //g')/lib/python2.7/site-packages;pip install --upgrade pip;pip freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip install -U --upgrade"
    alias pip2up="sudo chown -R $(whoami) $HOME/.anyenv/envs/pyenv/versions/$(python -V 2>&1 >/dev/null | sed -e 's/Python\ //g')/lib/python2.7/site-packages;pip2 install --upgrade pip;pip2 freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip2 install -U --upgrade"
    alias pip3up="sudo chown -R $(whoami) $HOME/.anyenv/envs/pyenv/versions/$(python3 -V 2>&1 >/dev/null | sed -e 's/Python\ //g')/lib/python3.7/site-packages;pip3 install --upgrade pip;pip3 freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -P $CPUCORES pip3 install -U --upgrade"

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
    alias cdc='mkcd $HOME/Documents/Programming/C'
    alias cdpl='mkcd $HOME/Documents/Programming/perl'
    alias cdrs='mkcd $HOME/Documents/Programming/rust/src'
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

    if type tmux >/dev/null 2>&1; then
        alias aliastx='alias | grep tmux'
        alias tmls='\tmux list-sessions'
        alias tmlc='\tmux list-clients'
        alias tkill='\tmux kill-server'
        alias tmkl='\tmux kill-session'
        alias tmaw='\tmux main-horizontal'
        alias tmuxa='\tmux -2 a -t'
    fi

    if type javac >/dev/null 2>&1; then
        alias javad="\javac -d64 -Dfile.encoding=UTF8"
        alias javacd="\javac -d64 -J-Dfile.encoding=UTF8"
    fi

    rsagen(){
        sudo -u $USER ssh-keygen -t rsa -b 4096 -P $1 -f $HOME/.ssh/id_rsa -C $USER
    }
    alias rsagen=rsagen

    alias sedit="$EDITOR $HOME/.ssh/config"
    alias sshinit="sudo rm -rf $HOME/.ssh/known_hosts;chmod 600 $HOME/.ssh/config"

    alias tedit="$EDITOR $HOME/.tmux.conf"

    zscompile(){
        for f in $(find $HOME -name "*.zsh"); do
            zcompile $f;
        done;
    }
    alias zscompile=zscompile

    zsup(){
        sudo rm -rf $HOME/.zcompd*;
        sudo rm -rf $HOME/.zplug/zcompd*;
        sudo rm $HOME/.zshrc.zwc;
        zplug update;
        zplug clean;
        zplug clear;
        zplug info;
        sudo rm -rf $HOME/.bashrc;
        sudo rm -rf $HOME/.fzf.bash;
        zscompile;
    }
    alias zsup=zsup

    zsinit(){
        sudo rm -rf $ZPLUG_HOME;
        sudo rm -rf $HOME/.zcompd*;
        sudo rm -rf $HOME/.zplug/zcompd*;
        sudo rm -rf $HOME/.zshrc.zwc;
    }
    alias zsinit=zsinit

    zstime(){
        for i in $(seq 1 $1); do
            time (zsh -i -c exit);
        done
    }
    alias zstime=zstime

    alias zedit="$EDITOR $HOME/.zshrc"

    greptext(){
        if [ $# -eq 2 ]; then
            if type rg >/dev/null 2>&1; then
                rg $2 $1
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$'
            else
                find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                    -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
                    -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 /dev/null
            fi
        else
            echo "Not enough arguments"
        fi
    }
    alias gt=greptext

   chword(){
        if [ $# -eq 3 ]; then
            if type rg >/dev/null 2>&1; then
                rg -l $2 $1 | xargs -t -P $CPUCORES sed -i "" -E "s/$2/$3/g";
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$' -l -r \
                    | xargs -t -P $CPUCORES sed -i "" -e "s/$2/$3/g";
            else
                find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                    -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
                    -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES sed -i "" -e "s/$2/$3/g";
            fi
        elif [ $# -eq 4 ]; then
            if type rg >/dev/null 2>&1; then
                rg -l $2 $1 | xargs -t -P $CPUCORES sed -i "" -E "s$4$2$4$3$4g";
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$' -l -r \
                    | xargs -t -P $CPUCORES sed -i "" -e "s$4$2$4$3$4g";
            else
                find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                    -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
                    -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES sed -i "" -e "s$4$2$4$3$4g";
            fi
        else
            echo "Not enough arguments"
        fi
    }
    alias chword=chword;

    alias :q=exit;

    alias 600='chmod -R 600'
    alias 644='chmod -R 644'
    alias 655='chmod -R 655'
    alias 755='chmod -R 755'
    alias 777='chmod -R 777'

    nvim-install(){
        sudo rm -rf $HOME/neovim
        sudo rm -rf /usr/local/bin/nvim
        sudo rm -rf /usr/local/share/nvim
        rm -rf "$HOME/.config/gocode";
        rm -rf "$HOME/.config/nvim/autoload";
        rm -rf "$HOME/.config/nvim/ftplugin";
        rm -rf "$HOME/.config/nvim/log";
        rm -rf "$HOME/.config/nvim/plugged";
        rm "$HOME/.nvimlog";
        rm "$HOME/.viminfo";
        cd $HOME
        git clone https://github.com/neovim/neovim
        cd neovim
        rm -r build/
        make clean
        make CMAKE_BUILD_TYPE=RelWithDebInfo
        sudo make install
        cd ../
        rm -rf neovim
        nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall;
        wget -P "$HOME/.config/nvim/plugged/nvim-go/syntax/" https://raw.githubusercontent.com/fatih/vim-go/master/syntax/go.vim;
        mv "$HOME/.config/nvim/plugged/nvim-go/bin/nvim-go-$GOOS-$GOARCH" "$HOME/.config/nvim/plugged/nvim-go/bin/nvim-go";
    }
    alias nvinstall=nvim-install

    if type nvim >/dev/null 2>&1; then
        alias nvup=nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall; 
        nvim-init(){
            rm -rf "$HOME/.config/gocode";
            rm -rf "$HOME/.config/nvim/autoload";
            rm -rf "$HOME/.config/nvim/ftplugin";
            rm -rf "$HOME/.config/nvim/log";
            rm -rf "$HOME/.config/nvim/plugged";
            nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall;
            rm "$HOME/.nvimlog";
            rm "$HOME/.viminfo";
            wget -P "$HOME/.config/nvim/plugged/nvim-go/syntax/" https://raw.githubusercontent.com/fatih/vim-go/master/syntax/go.vim;
            mv "$HOME/.config/nvim/plugged/nvim-go/bin/nvim-go-$GOOS-$GOARCH" "$HOME/.config/nvim/plugged/nvim-go/bin/nvim-go";
        }
        alias vedit="$EDITOR $HOME/.config/nvim/init.vim"
        alias nvinit="nvim-init";
    else
        alias vedit="$EDITOR $HOME/.vimrc"
    fi

    alias vi="$EDITOR"
    alias vim="$EDITOR"
    alias bim="$EDITOR"
    alias cim="$EDITOR"
    alias v="$EDITOR"
    alias vspdchk="rm -rf /tmp/starup.log && $EDITOR --startuptime /tmp/startup.log +q && less /tmp/startup.log"

    # OS 別の設定
    case ${OSTYPE} in
        darwin*)
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
                    sudo networksetup -setwebproxy Wi-Fi $HTTP_PROXY_HOST $HTTP_PROXY_PORT;
                    sudo networksetup -setwebproxystate Wi-Fi off
                elif [ $1 = "status" ]; then
                    echo $http_proxy;
                fi
                ssh ci "echo $HTTP_PROXY_PASSWORD | sudo -S systemctl $1 proxy"
            }

            dns(){
                if [ $1 = "start" ]; then
                    sudo networksetup -setdnsservers Wi-Fi  106.186.17.181 129.250.35.250 129.250.35.251 8.8.8.8 8.8.4.4
                elif [ $1 = "stop" ]; then
                    sudo networksetup -setdnsservers Wi-Fi Empty
                elif [ $1 = "status" ]; then
                    networksetup -getdnsservers Wi-Fi
                fi
            }

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

            clean(){
                sudo update_dyld_shared_cache -force
                sudo kextcache -system-caches
                sudo kextcache -system-prelinked-kernel

                sudo rm -rf $HOME/Library/Developer/Xcode/DerivedData
                sudo rm -rf $HOME/Library/Developer/Xcode/Archives
                sudo rm -rf $HOME/Library/Caches

                sudo purge
                sudo du -sx /* &
                sudo mkdir /usr/local/etc/my.cnf.d
            }

            alias ls='ls -G -F'
            alias -g C='| pbcopy'
            xcodeUUIDFix(){
                sudo find -L $HOME/Library/Application\ Support/Developer/Shared/Xcode/Plug-ins -name Info.plist -maxdepth 3 | \
                    xargs -P $CPUCORES -I{} defaults write {} DVTPlugInCompatibilityUUIDs -array-add `defaults read /Applications/Xcode.app/Contents/Info DVTPlugInCompatibilityUUID`;
                sudo xcode-select --reset;
            }
            alias xcodeUUIDFix=xcodeUUIDFix
            alias proxy=proxy
            alias dns=dns
            alias dock=dock

            alias clean=clean

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
                alias brew="env PATH=${PATH//$HOME\/.anyenv\/envs\/*\/shims:/} brew";
                alias brew-cask-update=brewcaskup
                alias brewup="brew upgrade;\cd $(brew --repo) && git fetch && git reset --hard origin/master && brew update && \cd -;brew-cask-update;brew prune;brew doctor";

                alias update="sudo chown -R $(whoami) /usr/local;anyenvup;brewup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;pip install vim-vint --force-reinstall;nimup;atomup;nvinstall;zsup;rm $HOME/.lesshst;rm $HOME/.mysql_history;clean;";
            else
                alias update="sudo chown -R $(whoami) /usr/local;anyenvup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;nimup;atomup;nvinstall;zsup"
            fi
            findfile(){
                sudo mdfind -onlyin $1 "kMDItemFSName == '$2'c && (kMDItemSupportFileType == MDSystemFile || kMDItemSupportFileType != MDSystemFile || kMDItemFSInvisible == *)"
            }
            ;;
        linux*)
            findfile(){
                sudo find $1 -name $2
            }
            alias ls='ls -F --color=auto'
            alias -g C='| xsel --input --clipboard'
            alias update="sudo chown -R $(whoami) /usr/local;anyenvup;goup;gemup;haskellup;npmup;pipup;pip2up;pip3up;nimup;nvinit;zsup"
            ;;
    esac
    alias findfile=findfile

    case ${OSTYPE} in
        darwin*)
            eval "$(rbenv init - --no-rehash zsh)";
            eval "$(pyenv init - --no-rehash zsh)"
            ;;
        linux*)
            ;;
    esac

    export TERM="xterm-256color";

    export ZSH_LOADED=1;
fi

if [[ $SHLVL = 1 && -z $TMUX ]]; then
    tmux -2 new-session
fi
