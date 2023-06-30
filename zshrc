#!/usr/bin/zsh

if type tmux >/dev/null 2>&1; then
    if [ -z $TMUX ]; then
        echo "welcome to tmux"
        USER=$(whoami)
        HOST=$(hostname)
        TMUX_SOCK=/tmp/tmux.sock
        if [ -z "$SSH_CLIENT" ] || [ -z "$SSH_TTY" ]; then
            echo "starting tmux for ssh $SSH_TTY from $SSH_CLIENT"
            TMUX_SOCK=/tmp/tmux-ssh-$(echo $SSH_CLIENT | awk '{print $1}').sock
        fi
        TMUX_TMPDIR=/tmp
        if [[ ! -f $TMUX_SOCK ]]; then
            if [ -f /.dockerenv ]; then
                group=$(id -g)
                sudo chown -R $USER:$group /var/run/docker.sock
            fi
            echo "creating new tmux session"
            TMUX_TMPDIR=/tmp tmux -S $TMUX_SOCK -2 new-session -n$USER -s$USER@$HOST && echo "created new tmux session"
        else
            ID="$(tmux -S /tmp/tmux.sock ls | grep attached | cut -d: -f1)" # get the id of a deattached session
            echo "attaching tmux session $ID"
            TMUX_TMPDIR=/tmp tmux -S $TMUX_SOCK -2 attach-session -t "$ID" && echo "attached tmux session $ID"
        fi
    fi
fi

if [ -z $DOTENV_LOADED ]; then
    if type fastfetch >/dev/null 2>&1; then
        fastfetch
    elif type neofetch >/dev/null 2>&1; then
        neofetch
    fi
    stty stop undef
    stty start undef

    setopt no_global_rcs
    if [ -x /usr/libexec/path_helper ]; then
        PATH=""
        [ -z "$_lazy_path_helper" ] && {
            eval "$(/usr/libexec/path_helper -s)"
            _lazy_path_helper=1
        }
    fi

    # environment var
    export CHARSET=UTF-8
    export LESSCHARSET=${CHARSET}
    export XLANGCCUS=en_US
    export XLANGCCJP=ja_JP
    export LANG=${XLANGCCUS}.${CHARSET}
    export LANGUAGE=${XLANGCCUS}:${XLANGCCJP}
    export LC_ADDRESS="${XLANGCCUS}.${CHARSET}"
    export LC_ALL=${XLANGCCUS}.${CHARSET}
    export LC_COLLATE="${XLANGCCUS}.${CHARSET}"
    export LC_CTYPE=${CHARSET}
    export LC_IDENTIFICATION="${XLANGCCUS}.${CHARSET}"
    export LC_MEASUREMENT="${XLANGCCUS}.${CHARSET}"
    export LC_MESSAGES="${XLANGCCUS}.${CHARSET}"
    export LC_MONETARY="${XLANGCCUS}.${CHARSET}"
    export LC_NAME="${XLANGCCUS}.${CHARSET}"
    export LC_NUMERIC="${XLANGCCUS}.${CHARSET}"
    export LC_PAPER="${XLANGCCUS}.${CHARSET}"
    export LC_TELEPHONE="${XLANGCCUS}.${CHARSET}"
    export LC_TIME=${XLANGCCJP}.${CHARSET}
    export MANLANG=${XLANGCCJP}.${CHARSET}


    [ -z "$_lazy_fzf_zsh" ] && {
        [ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh
        _lazy_fzf_zsh=1
    }

    export SHELL=$(which zsh)
    export USER=$(whoami)

    if type nproc >/dev/null 2>&1; then
        export CPUCORES="$(nproc)"
    else
        export CPUCORES="$(getconf _NPROCESSORS_ONLN)"
    fi

    if type alacritty >/dev/null 2>&1; then
        export TERMCMD="WINIT_UNIX_BACKEND=x11 alacritty -e $SHELL -c tmux -S /tmp/tmux.sock -q has-session  && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$HOST"
    elif type urxvtc >/dev/null 2>&1; then
        export TERMCMD="urxvtc -e $SHELL -c tmux -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$HOST"
    fi

    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.data

    if type gcloud >/dev/null 2>&1; then
        export GCLOUD_PATH="/usr/lib/google-cloud-sdk"
        export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    fi

    if type php >/dev/null 2>&1; then
        export PHP_BUILD_CONFIGURE_OPTS="--with-openssl=/usr/local/opt/openssl"
    fi

    if type python3 >/dev/null 2>&1; then
        export PYTHON_CONFIGURE_OPTS="--enable-shared"
        export PYTHONIOENCODING="utf-8";
    fi

    if type nvim >/dev/null 2>&1; then
        export VIM=$(which nvim)
        export VIMRUNTIME=/usr/share/nvim/runtime
        export NVIM_HOME=$XDG_CONFIG_HOME/nvim
        export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME/log
        export NVIM_TUI_ENABLE_TRUE_COLOR=1
        export NVIM_PYTHON_LOG_LEVEL=WARNING;
        export NVIM_PYTHON_LOG_FILE=$NVIM_LOG_FILE_PATH/nvim.log;
        export NVIM_LISTEN_ADDRESS="127.0.0.1:7650";
    elif type vim >/dev/null 2>&1; then
        export VIM=$(which vim)
        export VIMRUNTIME=/usr/share/vim/vim*
    else
        export VIM=$(which vi)
    fi

    export EDITOR=$VIM
    export VISUAL=$VIM
    export PAGER=$(which less)
    export SUDO_EDITOR=$EDITOR

    #ReactNative
    export REACT_EDITOR=$EDITOR;

    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib64:${GCLOUD_PATH}/lib

    if type go >/dev/null 2>&1; then
        #GO
        export GOPATH=$HOME/go
        export GOROOT="$(go env GOROOT)"
        export GOOS="$(go env GOOS)"
        export GOARCH="$(go env GOARCH)"
        export CGO_ENABLED=1
        export GO111MODULE=on
        export GOBIN=$GOPATH/bin
        export GO15VENDOREXPERIMENT=1
        export GOPRIVATE="*.yahoo.co.jp"
        export NVIM_GO_LOG_FILE=$XDG_DATA_HOME/go
        # export GOFLAGS="-ldflags=\"-w\ -s\""
        export CGO_CFLAGS="-g -Ofast -march=native"
        export CGO_CPPFLAGS="-g -Ofast -march=native"
        export CGO_CXXFLAGS="-g -Ofast -march=native"
        export CGO_FFLAGS="-g -Ofast -march=native"
        export CGO_LDFLAGS="-g -Ofast -march=native"
    fi

    if type clang >/dev/null 2>&1; then
        export CC=$(which clang)
        export CPP=$(which clang++)
        export CXX=$CPP
        export LD=/usr/bin/ldd
        if type llvm-config >/dev/null 2>&1; then
            export LD_LIBRARY_PATH=$(llvm-config --libdir):$LD_LIBRARY_PATH;
            export LLVM_CONFIG_PATH=$(which llvm-config);
        else
            export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/clang/*/lib
        fi
        export CFLAGS="-g -Ofast -march=native -ffp-contract=fast"
        export CPPFLAGS="-g -Ofast -march=native -ffp-contract=fast"
        export CXXFLAGS="-g -Ofast -march=native -ffp-contract=fast"
        export FFLAGS="-g -Ofast -march=native -ffp-contract=fast"
        export LDFLAGS="-g -Ofast -march=native -ffp-contract=fast"
        #CLANG
        export CFLAGS=-I$LLVM_HOME/include:-I$QT_HOME/include:-I/usr/local/opt/openssl/include:$CFLAGS;
        export CPPFLAGS=$CFLAGS;
        export LDFLAGS=-L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS;
        export C_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$C_INCLUDE_PATH;
        export CPLUS_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$CPLUS_INCLUDE_PATH;
    fi

    DOTFILE_URL="github.com/kpango/dotfiles"
    if type ghq >/dev/null 2>&1; then
        export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
    elif [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
        export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
    else
        export DOTFILES_DIR="$HOME/dotfiles"
    fi

    if [ -z $TMUX ]; then
        export TERM="xterm-256color"
    else
        export TERM="tmux-256color"
    fi

    export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/local/go/bin:/opt/local/bin:$GOBIN:$HOME/.local/bin:$HOME/.cargo/bin:$GCLOUD_PATH/bin:/usr/lib/docker/cli-plugins/:$PATH"

    if type deno >/dev/null 2>&1; then
        export PATH="$(which deno):$PATH"
    fi

    export ZPLUG_HOME=$HOME/.zplug

    if [ -e $ZPLUG_HOME/repos/zsh-users/zsh-completions ]; then
        fpath=($ZPLUG_HOME/repos/zsh-users/zsh-completions/src $fpath)
    fi

    # for teleplesence disabling send analytics data anonymously
    export SCOUT_DISABLE=1

    export DOTENV_LOADED=1
fi

if type zplug >/dev/null 2>&1; then
    if zplug check junegunn/fzf; then
        export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --smartcase --glob "!.git/*"'
        export FZF_DEFAULT_OPTS='--height 40% --reverse --border'
    fi

    if zplug check b4b4r07/enhancd; then
        export ENHANCD_FILTER=fzf-tmux
        export ENHANCD_COMMAND=ccd
        export ENHANCD_FILTER=fzf:peco:gof
        export ENHANCD_DOT_SHOW_FULLPATH=1
    fi
fi

if type gpg >/dev/null 2>&1; then
    export GPG_TTY=$(tty)
fi

if [ ! -f "$HOME/.zshrc.zwc" -o "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" ]; then
    zcompile $HOME/.zshrc
fi

if [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
    zcompile $HOME/.zcompdump
fi

if [ -z $ZSH_LOADED ]; then
    ########################################
    #Zplug Settings
    if [[ ! -f $HOME/.zplug/init.zsh ]]; then
        rm -rf $ZPLUG_HOME
        git clone --depth 1 https://github.com/zplug/zplug $ZPLUG_HOME
    fi
    [ -z "$_lazy_zplug_zsh" ] && {
        [ -f "$HOME/.zplug/init.zsh" ] && source "$HOME/.zplug/init.zsh"
        _lazy_zplug_zsh=1
    }
    zplug "junegunn/fzf", as:command, use:bin/fzf-tmux
    zplug "zsh-users/zsh-autosuggestions"
    zplug "zsh-users/zsh-completions", as:plugin, use:"src"
    zplug "zsh-users/zsh-history-substring-search"
    zplug "auscompgeek/fast-syntax-highlighting", defer:2
    zplug "greymd/tmux-xpanes"
    if ! zplug check --verbose; then
        zplug install
    fi
    zplug load

    # 色を使用出来るようにする
    autoload -Uz colors
    colors

    # ヒストリの設定
    HISTFILE=$HOME/.zsh_history
    HISTSIZE=1000000
    SAVEHIST=1000000
    setopt APPEND_HISTORY
    setopt SHARE_HISTORY
    setopt hist_ignore_all_dups
    setopt hist_ignore_space
    setopt hist_reduce_blanks
    setopt hist_save_no_dups
    LISTMAX=1000
    WORDCHARS="$WORDCHARS|:"
    # export PROMPT_COMMAND='hcmd=$(history 1); hcmd="${hcmd# *[0-9]*  }"; if [[ ${hcmd%% *} == "cd" ]]; then pwd=$OLDPWD; else pwd=$PWD; fi; hcmd=$(echo -e "cd $pwd && $hcmd"); history -s "$hcmd"'

    # プロンプト
    # PROMPT="%F{045}%/ $ %f"
    # PS1="%{${fg[green]}%}%/#%{${reset_color}%} %"

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
    autoload -Uz compinit -C && compinit -C

    zstyle ':completion:*' format '%B%d%b'
    zstyle ':completion:*' group-name ''
    zstyle ':completion:*' ignore-parents parent pwd ..
    zstyle ':completion:*' keep-prefix
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
    zstyle ':completion:*' menu select
    zstyle ':completion:*' squeeze-slashes true
    zstyle ':completion:*' verbose yes
    zstyle ':completion:*:(nano|vim|nvim|vi|emacs|e):*' ignored-patterns '*.(wav|mp3|flac|ogg|mp4|avi|mkv|webm|iso|dmg|so|o|a|bin|exe|dll|pcap|7z|zip|tar|gz|bz2|rar|deb|pkg|gzip|pdf|mobi|epub|png|jpeg|jpg|gif)'
    zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
    zstyle ':completion:*:*:*:*:*' menu select
    zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters
    zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
    zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
    zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'expand'
    zstyle ':completion:*:corrections' format ' %F{green}-- %d (errors: %e) --%f'
    zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
    # zstyle ':completion:*:default' list-prompt '%S%M matches%s'
    zstyle ':completion:*:default' menu select=1
    zstyle ':completion:*:descriptions' format ' %F{yellow}-- %d --%f'
    # zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec)|prompt_*)'
    zstyle ':completion:*:history-words' list false
    zstyle ':completion:*:history-words' menu yes
    zstyle ':completion:*:history-words' remove-all-dups yes
    zstyle ':completion:*:history-words' stop yes
    zstyle ':completion:*:manuals' separate-sections true
    zstyle ':completion:*:manuals.(^1*)' insert-sections true
    zstyle ':completion:*:matches' group 'yes'
    zstyle ':completion:*:messages' format ' %F{purple} -- %d --%f'
    zstyle ':completion:*:options' auto-description '%d'
    zstyle ':completion:*:options' description 'yes'
    zstyle ':completion:*:processes' command 'ps x -o pid, s, args'
    zstyle ':completion:*:rm:*' file-patterns '*:all-files'
    zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin
    zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
    zstyle ':completion::complete:*' cache-path "${ZDOTDIR:-${HOME}}/.zcompcache"
    zstyle ':completion::complete:*' use-cache on
    # zstyle ':zsh-kubectl-prompt:' separator ' | ns: '
    # zstyle ':zsh-kubectl-prompt:' preprompt 'ctx: '
    # zstyle ':zsh-kubectl-prompt:' postprompt ''

    ########################################
    # vcs_info
    autoload -Uz vcs_info
    autoload -Uz add-zsh-hook

    zstyle ':vcs_info:*' formats '(%s)-[%b]'
    zstyle ':vcs_info:*' actionformats '%F{red}(%s)-[%b|%a]%f'

    precmd() {
        if [ ! -z $TMUX ]; then
            tmux refresh-client -S
        fi
    }
    _update_vcs_info_msg() {
        vcs_info
        # RPROMPT="%F{046}${vcs_info_msg_0_} %F{102}[%D{%Y-%m-%d %H:%M:%S}]"
        # RPROMPT="%F{green}${vcs_info_msg_0_} %{$fg[blue]%}($ZSH_KUBECTL_PROMPT)%{$reset_color%} %F{gray}[%D{%Y-%m-%d %H:%M:%S}]"
    }
    add-zsh-hook precmd _update_vcs_info_msg

    if type starship >/dev/null 2>&1; then
        [ -z "$_lazy_starship" ] && {
            eval "$(starship init zsh)"
            _lazy_starship=1
        }
    fi

    ########################################
    # オプション
    setopt auto_cd         # ディレクトリ名だけでcdする
    setopt auto_list       # 補完候補を一覧表示
    setopt auto_menu       # 補完候補が複数あるときに自動的に一覧表示する
    setopt auto_param_keys # カッコの対応などを自動的に補完
    setopt auto_param_slash
    setopt auto_pushd      # cd したら自動的にpushdする
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
    setopt notify            # バックグラウンドジョブの状態変化を即時報告
    setopt print_eight_bit   # 日本語ファイル名を表示可能にする
    setopt prompt_subst      # プロンプト定義内で変数置換やコマンド置換を扱う
    setopt pushd_ignore_dups # 重複したディレクトリを追加しない
    ########################################
    # ^R で履歴検索をするときに * でワイルドカードを使用出来るようにする
    bindkey -e
    select-history() {
        BUFFER=$(history -n -r 1 \
            | awk 'length($0) > 2' \
            | rg -v "^...$" \
            | rg -v "^....$" \
            | rg -v "^.....$" \
            | rg -v "^......$" \
            | rg -v "^exit$" \
            | uniq -u \
            | fzf-tmux --no-sort +m --query "$LBUFFER" --prompt="History > ")
        CURSOR=$#BUFFER
    }
    zle -N select-history
    bindkey '^r' select-history

    fzf-z-search() {
        local res=$(history -n 1 | tail -f | fzf)
        if [ -n "$res" ]; then
            BUFFER+="$res"
            zle accept-line
        else
            return 0
        fi
    }
    zle -N fzf-z-search
    bindkey '^s' fzf-z-search

    if type docker >/dev/null 2>&1; then
        export DOCKER_BUILDKIT=1
        export DOCKER_CLI_EXPERIMENTAL="enabled"
        alias dls='docker ps'
        alias dsh='docker run -it '
        [ -z "$_lazy_docker_aliases" ] && {
            [ -f $HOME/.aliases ] && source $HOME/.aliases
            _lazy_docker_aliases=1
        }
    fi

    if type octant >/dev/null 2>&1; then
        export OCTANT_LISTENER_ADDR="0.0.0.0:8900"
    fi

    if type xsel >/dev/null 2>&1; then
        alias pbcopy="xsel --clipboard --input"
        alias pbpaste="xsel --clipboard --output"
    else
        if type wl-copy >/dev/null 2>&1; then
            alias pbcopy="wl-copy"
        fi

        if type wl-paste >/dev/null 2>&1; then
            alias pbpaste="wl-paste"
        fi
    fi

    if type git >/dev/null 2>&1; then
        alias gco="git checkout"
        alias gsta="git status"
        alias gcom="git commit -m"
        alias gdiff="git diff"
        alias gbra="git branch"
        gitthisrepo() {
            git symbolic-ref --short HEAD | tr -d "\n"
        }
        alias tb=gitthisrepo
        gitdefaultbranch(){
            git remote show origin | grep 'HEAD' | cut -d':' -f2 | sed -e 's/^ *//g' -e 's/ *$//g'
        }
        alias gitdb=gitdefaultbranch
        gfr() {
            git fetch --prune
            git reset --hard origin/$(tb)
            git branch -r --merged $(gitdb) | grep -v -e $(gitdb) -e develop | \sed -E 's% *origin/%%' | xargs -I% git push --delete origin %
            git fetch --prune
            git reset --hard origin/$(tb)
            git branch --merged $(gitdb) | grep -vE '^\*|master$|develop$|main$' | xargs -I % git branch -d %
        }
        alias gfr=gfr
        gfrs() {
            gfr
            git submodule foreach git pull origin $(gitdb)
        }
        alias gfrs=gfrs
        gitpull() {
            git pull --rebase origin $(tb)
        }
        alias gpull=gitpull
        gpush() {
            git push -u origin $(tb)
        }
        alias gpush=gpush
        gitcompush() {
            git add -A
            git commit --signoff -m $1
            git push -u origin $2
        }
        alias gitcompush=gitcompush
        gcp() {
            gitcompush $1 "$(tb)"
        }
        alias gcp=gcp
        alias gfix="gcp fix"
        gitcompushf() {
            git add -A
            git commit --signoff -m $1
            git push --force-with-lease --set-upstream origin $2
        }
        alias gitcompushf=gitcompushf
        gcpf() {
            gitcompushf $1 "$(tb)"
        }
        alias gcpf=gcpf
        gfp() {
            git add -A
            git commit --signoff --amend
            git push --force-with-lease
        }
        alias gfp=gfp
        grsp() {
            if [ $# -eq 1 ]; then
                branch="$(tb)"
                msg="$(git log remotes/origin/$1..$branch --reverse --pretty=%s)"
                git checkout $1
                gfr
                git checkout -b tmp
                git merge --squash $branch
                git branch -D $branch
                git branch -m $branch
                gcpf $msg
            else
                echo "invalid argument, rebase branch name required"
            fi

        }
        alias grsp=grsp

        alias gedit="$EDITOR $HOME/.gitconfig"
        git-remote-add-merge() {
            git remote add upstream $1
            git fetch upstream
            git merge upstream/$(gitdb)
        }
        alias grfa=git-remote-add-merge
        git-remote-merge() {
            git fetch upstream
            git merge upstream/$(gitdb)
        }
        alias grf=git-remote-merge
    fi

    if type rg >/dev/null 2>&1; then
        alias grep=rg
        if type curl >/dev/null 2>&1; then
            listdomains(){
                if [ $# -eq 1 ]; then
                    curl -fs $1 \
                    | rg -Po '.*?//\K.*?(?=/)'\
                    | rg -v "@" \
                    | rg -v "\+"\
                    | sort | uniq
                else
                    echo "invalid argument, Domain or url is required"
                fi
            }
            alias lsdomain=listdomains
        fi
    fi

    # エイリアス
    alias cp='cp -r'
    alias mv='mv -i'

    if type axel >/dev/null 2>&1; then
        alias wget='axel -a -n 10'
    else
        alias wget='wget --no-cookies --no-check-certificate --no-dns-cache -4'
    fi

    alias mkdir='mkdir -p'

    if type trans >/dev/null 2>&1; then
        alias gtrans='trans -b -e google'
    fi

    # グローバルエイリアス
    alias -g L='| less'

    alias f="open ."
    alias rm='rm -rf'

    if type fd >/dev/null 2>&1; then
        alias find='fd'
    fi

    if type dutree >/dev/null 2>&1; then
        alias du='dutree'
    fi

    if type bat >/dev/null 2>&1; then
        alias cat='bat'
    fi

    if type hyperfine >/dev/null 2>&1; then
        alias time='hyperfine'
    fi

    if type procs >/dev/null 2>&1; then
        alias ps='procs'
    fi

    if type btm >/dev/null 2>&1; then
        alias top='btm'
        alias htop='btm'
    elif type htop >/dev/null 2>&1; then
        alias top=htop
    fi

    if type lsd >/dev/null 2>&1; then
        alias ks="lsd"
        alias l="lsd"
        alias ll='lsd -l'
        alias la='lsd -aAlLh'
        alias lla='lsd -aAlLhi'
        alias tree='lsd --tree --total-size --human-readable'
        alias ls='lsd'
        alias lg='lsd -aAlLh | rg'
    # elif type erd >/dev/null 2>&1; then
    #     alias ks="erd -G"
    #     alias l="exa -G "
    #     alias ll='exa -l'
    #     alias la='exa -aghHliS'
    #     alias lla='exa -aghHliSm'
    #     alias tree='exa -T'
    #     alias ls='exa -G'
    #     alias lg='la | rg'
    elif type exa >/dev/null 2>&1; then
        alias ks="exa -G"
        alias l="exa -G "
        alias ll='exa -l'
        alias la='exa -aghHliS'
        alias lla='exa -aghHliSm'
        alias tree='exa -T'
        alias ls='exa -G'
        alias lg='la | rg'
    else
        alias ks="ls "
        alias l="ls "
        alias ll='ls -la'
        alias la='ls -la'
        alias lg='ls -a | rg'
    fi

    mkcd() {
        if [[ -d $1 ]]; then
            \cd $1
        else
            printf "Confirm to Make Directory? $1 [y/N]: "
            if read -q; then
                echo
                \mkdir -p $1 && \cd $1
            fi
        fi
    }

    alias mkcd=mkcd
    alias dl="\cd $HOME/Downloads"
    alias dc="\cd $HOME/Documents"
    alias ..='\cd ../'
    alias ...='\cd ../../'
    alias ....='\cd ../../../'
    alias .....='\cd ../../../../'
    alias ......='\cd ../../../../../'
    alias ,,='\cd ../'
    alias ,,,='\cd ../../'
    alias ,,,,='\cd ../../../'
    alias ,,,,,='cd ../../../../'
    alias ,,,,,,='\cd ../../../../../'

    if type fzf >/dev/null 2>&1; then
        if type fzf-tmux >/dev/null 2>&1; then
            if type fd >/dev/null 2>&1; then
                alias s='mkcd $(fd -a -H -t d . | fzf-tmux +m)'
                alias vf='vim $(fd -a -H -t f . | fzf-tmux +m)'
            fi
            if type rg >/dev/null 2>&1; then
                fbr() {
                    git branch --all | rg -v HEAD | fzf-tmux +m | \sed -E "s/.* //" -e "s#remotes/[^/]*/##" | xargs git checkout
                }
                alias fbr=fbr
                sshf() {
                    ssh $(rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*" | fzf-tmux +m)
                }
                alias sshf=sshf
            fi
            if type ghq >/dev/null 2>&1; then
                alias g='mkcd $(ghq root)/$(ghq list | fzf-tmux +m)'
            fi
        fi
    fi

    if type ssh-keygen >/dev/null 2>&1; then
        rsagen() {
            ssh-keygen -t rsa -b 4096 -P $1 -f $HOME/.ssh/id_rsa -C $USER
        }
        alias rsagen=rsagen
        ecdsagen() {
            ssh-keygen -t ecdsa -b 521 -P $1 -f $HOME/.ssh/id_ecdsa -C $USER
        }
        alias ecdsagen=ecdsagen

        edgen() {
            ssh-keygen -t ed25519 -P $1 -f $HOME/.ssh/id_ed -C $USER
        }
        alias edgen=edgen
        alias sedit="$EDITOR $HOME/.ssh/config"
        sshls() {
            rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*"
        }
        alias sshls=sshls
        alias sshinit="rm -rf $HOME/.ssh/known_hosts;rm -rf $HOME/.ssh/master_kpango@192.168.2.*;sudo chmod -R 700 $HOME/.ssh;sudo chmod -R 600 $HOME/.ssh/*"
    fi

    if type rails >/dev/null 2>&1; then
        alias railskill="kill -9 $(ps aux | grep rails | awk '{print $2}')"
    fi

    if type tar >/dev/null 2>&1; then
        alias tarzip="\tar Jcvf"
        alias tarunzip="\tar Jxvf"
    fi

    if type duf >/dev/null 2>&1; then
        alias df='\duf'
    fi

    if type ranger >/dev/null 2>&1; then
        # rng() {
        #     if [ -z "$RANGER_LEVEL" ]; then
        #         \ranger $@
        #     else
        #         echo "other ranger process already running"
        #     fi
        # }
        # alias ranger=rng
        alias rng=ranger
    fi

    if type tmux >/dev/null 2>&1; then
        export TMUX_TMPDIR=/tmp
        alias tkill='\tmux -S /tmp/tmux.sock kill-server'
        alias tmls='\tmux -S /tmp/tmux.sock list-sessions'
        alias tmlc='\tmux -S /tmp/tmux.sock list-clients'
        alias tmkl='\tmux -S /tmp/tmux.sock kill-session'
        alias tmaw='\tmux -S /tmp/tmux.sock main-horizontal'
        alias tmuxa='\tmux -S /tmp/tmux.sock -2 a -t'

        if [ -f /.dockerenv ]; then
            tmux unbind C-b
            tmux set -g prefix C-w
        fi
    fi
    alias tedit="$EDITOR $HOME/.tmux.conf"

    zscompile() {
        for f in $(find $HOME -name "*.zsh"); do
            zcompile $f
        done
    }
    alias zscompile=zscompile

    zsup() {
        rm -rf $HOME/.zcompd*
        rm -rf $HOME/.zplug/zcompd*
        rm $HOME/.zshrc.zwc
        zplug update
        zplug clean
        zplug clear
        zplug info
        rm -rf $HOME/.bashrc
        rm -rf $HOME/.fzf.bash
        zscompile
    }
    alias zsup=zsup

    zsinit() {
        rm -rf $ZPLUG_HOME
        rm -rf $HOME/.zcompd*
        rm -rf $HOME/.zplug/zcompd*
        rm -rf $HOME/.zshrc.zwc
    }
    alias zsinit=zsinit

    zstime() {
        for i in $(seq 1 $1); do
            time $(zsh -i -c exit)
        done
    }
    alias zstime=zstime


    if { [ -L "$HOME/.zshrc" ] || [ -f "/.dockerenv" ] ;} && [ -f "$DOTFILES_DIR/zshrc" ]; then
        alias zedit="$EDITOR $DOTFILES_DIR/zshrc"
    else
        alias zedit="$EDITOR $HOME/.zshrc"
    fi

    alias zsback="cp $HOME/.zshrc $HOME/.zshrc.back"

    jvgrule='(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|\.schema.json&|\.svg$|(^|\/)tags$'

    greptext() {
        if [ $# -eq 2 ]; then
            if type rg >/dev/null 2>&1; then
                rg $2 $1
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude $jvgrule
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
    chperm(){
        if [ $# -eq 3 ]; then
            sudo chmod $1 $3
            sudo chown $2 $3
        elif [ $# -eq 4 ]; then
            sudo chmod -R $2 $4
            sudo chown -R $3 $4
        fi
    }
    chword() {
        if [ $# -eq 3 ]; then
            if type rg >/dev/null 2>&1; then
                rg --multiline -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude $jvgrule -l -r |
                    xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
            else
                find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                    -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' -o -name '*.schema.json' \) \
                    -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g"
            fi
        elif [ $# -eq 4 ]; then
            if type rg >/dev/null 2>&1; then
                rg -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
            elif type jvgrep >/dev/null 2>&1; then
                jvgrep -I -R $2 $1 --exclude $jvgrule -l -r |
                    xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
            else
                find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                    -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' -o -name '*.schema.json' \) \
                    -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
            fi
        else
            echo "Not enough arguments"
        fi
    }
    alias chword=chword

    alias :q=exit
    alias :wq=exit

    alias 600='chmod -R 600'
    alias 644='chmod -R 644'
    alias 655='chmod -R 655'
    alias 755='chmod -R 755'
    alias 777='chmod -R 777'

    if type nvim >/dev/null 2>&1; then
        alias nvup="nvim --headless -c 'UpdateRemotePlugins' -c 'PackerSync' -c 'PackerCompile'"
        nvim-init() {
            rm -rf "$HOME/.config/gocode"
            rm -rf "$HOME/.config/nvim/autoload"
            rm -rf "$HOME/.config/nvim/ftplugin"
            rm -rf "$HOME/.config/nvim/log"
            rm -rf "$HOME/.config/nvim/pack"
            nvup
            rm "$HOME/.nvimlog"
            rm "$HOME/.viminfo"
        }
        alias vedit="$EDITOR $HOME/.config/nvim/init.lua"
        alias nvinit="nvim-init"
        alias vback="cp $HOME/.config/nvim/init.lua $HOME/.config/nvim/init.lua.back"
        alias vrestore="cp $HOME/.config/nvim/init.lua.back $HOME/.config/nvim/init.lua"
        alias vake="$EDITOR Makefile"
        alias vocker="$EDITOR Dockerfile"
    else
        alias vedit="$EDITOR $HOME/.vimrc"
    fi

    alias vi="$EDITOR"
    alias vim="$EDITOR"
    alias bim="$EDITOR"
    alias cim="$EDITOR"
    alias v="$EDITOR"
    alias vspdchk="rm -rf /tmp/starup.log && $EDITOR --startuptime /tmp/startup.log +q && less /tmp/startup.log"
    alias xedit="$EDITOR $HOME/.Xdefaults"
    alias wedit="$EDITOR $HOME/.config/sway/config"
    # if type thefuck >/dev/null 2>&1; then
    #     eval $(thefuck --alias --enable-experimental-instant-mode)
    # fi

    if type kubectl >/dev/null 2>&1; then
        kubectl() {
            local kubectl="$(whence -p kubectl 2> /dev/null)"
            if type kubecolor >/dev/null 2>&1; then
                local kubectl="$(whence -p kubecolor 2> /dev/null)"
            fi
            [ -z "$_lazy_kubectl_completion" ] && {
                source <("$kubectl" completion zsh)
                complete -o default -F __start_kubectl k
                _lazy_kubectl_completion=1
            }
            "$kubectl" "$@"
        }
        alias k=kubectl
        alias kpall="k get pods --all-namespaces -o wide"
        alias ksall="k get svc --all-namespaces -o wide"
        alias kiall="k get ingress --all-namespaces -o wide"
        alias knall="k get namespace -o wide"
        alias kdall="k get deployment --all-namespaces -o wide"

        if type kind >/dev/null 2>&1; then
            kind() {
                local kind="$(whence -p kind 2>/dev/null)"
                [ -z "$_lazy_kind_completion" ] && {
                    source <("$kind" completion zsh)
                    _lazy_kind_completion=1
                }
                "$kind" "$@"
            }
            alias kind=kind
        fi

        if type k3d >/dev/null 2>&1; then
            k3d() {
                local k3d="$(whence -p k3d 2>/dev/null)"
                [ -z "$_lazy_k3d_completion" ] && {
                    source <("$k3d" completion zsh)
                    _lazy_k3d_completion=1
                }
                "$k3d" "$@"
            }
            alias k3d=k3d
        fi

        if type helm >/dev/null 2>&1; then
            helm() {
                local helm="$(whence -p helm 2>/dev/null)"
                [ -z "$_lazy_helm_completion" ] && {
                    source <("$helm" completion zsh)
                    _lazy_helm_completion=1
                }
                "$helm" "$@"
            }
            alias helm=helm
        fi

        if type skaffold >/dev/null 2>&1; then
            skaffold() {
                local skaffold="$(whence -p skaffold 2>/dev/null)"
                [ -z "$_lazy_skaffold_completion" ] && {
                    source <("$skaffold" completion zsh)
                    _lazy_skaffold_completion=1
                }
                "$skaffold" "$@"
            }
            alias skaffold=skaffold
        fi

        if type linkerd >/dev/null 2>&1; then
            linkerd() {
                local linkerd="$(whence -p linkerd 2>/dev/null)"
                [ -z "$_lazy_linkerd_completion" ] && {
                    source <("$linkerd" completion zsh)
                    _lazy_linkerd_completion=1
                }
                "$linkerd" "$@"
            }
            alias linkerd=linkerd
        fi

        if type kustomize >/dev/null 2>&1; then
            kustomize() {
                local kustomize="$(whence -p kustomize 2>/dev/null)"
                [ -z "$_lazy_kustomize_completion" ] && {
                    source <("$kustomize" completion zsh)
                    _lazy_kustomize_completion=1
                }
                "$kustomize" "$@"
            }
            alias kustomize=kustomize
        fi
    fi

    if type nmcli >/dev/null 2>&1; then
        nmcliwifie() {
            if [ $# -eq 3 ]; then
                sudo nmcli c delete $1
                nmcli d
                nmcli r wifi
                nmcli d wifi list
                sudo nmcli c add type wifi ifname $(nmcli d | grep wifi | head -1 | awk '{print $1}') con-name $1 ssid $1 -- \
                    connection.autoconnect yes \
                    ipv4.method auto \
                    802-11-wireless.ssid $1 \
                    802-11-wireless-security.key-mgmt wpa-eap \
                    802-1x.eap peap \
                    802-1x.anonymous-identity $2 \
                    802-1x.identity $2 \
                    802-1x.password $3 \
                    802-1x.phase2-auth mschapv2
                sudo nmcli c up $1
            else
                echo "invalid argument, SSID and PSK is required"
            fi
        }
        alias nmcliwifie=nmcliwifie
        nmcliwifi() {
            if [ $# -eq 2 ]; then
                sudo nmcli c delete $1
                nmcli d
                nmcli r wifi
                nmcli d wifi list
                sudo nmcli c add type wifi ifname $(nmcli d | grep wifi | head -1 | awk '{print $1}') con-name $1 ssid $1 -- \
                    connection.autoconnect yes \
                    ipv4.method auto \
                    802-11-wireless.ssid $1 \
                    802-11-wireless-security.key-mgmt wpa-psk \
                    802-11-wireless-security.psk-flags 0 \
                    802-11-wireless-security.psk $2
                sudo nmcli c up $1
            else
                echo "invalid argument, SSID and PSK is required"
            fi
        }
        alias nmcliwifi=nmcliwifi
        nmclr() {
            if [ $# -eq 1 ]; then
                nmcli d
                nmcli r wifi
                nmcli d wifi list
                nmcli c show
                sudo nmcli c down $1
                sudo nmcli r wifi off
                sudo nmcli r wifi on
                sudo nmcli c up $1
            else
                echo "invalid argument, SSID and PSK is required"
            fi
        }
        alias nmclr=nmclr
    fi

    if type xdg-open >/dev/null 2>&1; then
        alias open=xdg-open
    fi

    if type compton >/dev/null 2>&1; then
        comprestart() {
            sudo pkill compton
            compton --config $HOME/.config/compton/compton.conf --xrender-sync-fence -cb
        }
        alias comprestart=comprestart
    fi

    if type osascript >/dev/null 2>&1; then
        ciscovpn(){
            osascript $DOTFILES_DIR/macos/AnyConnect.scpt
        }
        alias ciscovpn=ciscovpn
    fi

    if type fwupdmgr >/dev/null 2>&1; then
        fup(){
            sudo systemctl reload dbus.service
            sudo systemctl restart fwupd.service
            sudo lsusb
            sudo fwupdmgr get-devices
            sudo fwupdmgr clear-history
            sudo fwupdmgr clear-offline
            sudo fwupdmgr refresh --force
            sudo fwupdmgr get-updates --force
            sudo fwupdmgr get-upgrades --force
            sudo fwupdmgr update
        }
        alias fup=fup
    fi


    if type brew >/dev/null 2>&1; then
        brewup() {
            cd `brew --prefix`/Homebrew
            gfr
            git config --local pull.ff only
            git fetch origin
            git reset --hard origin/master
            cd -
            brew cleanup
            brew update
            brew upgrade
            brew cleanup
            brew doctor
            softwareupdate --all --install --force
            sudo pmset -a hibernatemode 0
            sudo rm -rf /private/var/vm/sleepimage
            sudo touch /private/var/vm/sleepimage
            sudo chmod 000 /private/var/vm/sleepimage
            # sudo pmset -a hibernatemode 3
            # sudo rm /private/var/vm/sleepimage
            sudo rm -rf /System/Library/Speech/Voices/*
            sudo rm -rf /private/var/log/*
            sudo rm -rf /private/var/folders/
            sudo rm -rf /usr/share/emacs/
            sudo rm -rf /private/var/tmp/TM*
            sudo rm -rf $HOME/Library/Caches/*
            sudo rm -rf /private/tmp/junk
            purge
        }
        alias brewup=brewup
        alias up=brewup
    elif type paru >/dev/null 2>&1; then
        archback() {
            family_name=$(cat /sys/devices/virtual/dmi/id/product_family)
            echo $family_name
            if [[ $family_name =~ "P1" ]]; then
                echo "backup ThinkPad P1 Gen 2 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_p1.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_p1.list
                pacman -Qqen > $DOTFILES_DIR/arch/pkg_p1.list
                pacman -Qqem > $DOTFILES_DIR/arch/aur_p1.list
            elif [[ $family_name =~ "5th" ]]; then
                echo "backup ThinkPad X1 Carbon Gen 5 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_nc.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_nc.list
                pacman -Qqen > $DOTFILES_DIR/arch/pkg_nc.list
                pacman -Qqem > $DOTFILES_DIR/arch/aur_nc.list
            elif [[ $family_name =~ "X1" ]]; then
                echo "backup ThinkPad X1 Carbon Gen 9 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur.list
                pacman -Qqen > $DOTFILES_DIR/arch/pkg.list
                pacman -Qqem > $DOTFILES_DIR/arch/aur.list
            else
                echo "backup packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_desk.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_desk.list
                pacman -Qqen > $DOTFILES_DIR/arch/pkg_desk.list
                pacman -Qqem > $DOTFILES_DIR/arch/aur_desk.list
            fi
        }
        alias archback=archback
        archup() {
            sudo chown 0 /etc/sudoers.d/kpango
            sudo chmod -R 700 $HOME/.gnupg
            sudo chmod -R 600 $HOME/.gnupg/*
            sync \
            && sudo sysctl -w vm.drop_caches=3 \
                && sudo swapoff -a \
                && sudo swapon -a \
                && printf '\n%s\n' 'RAM-cache and Swap were cleared.' \
                && free
            sudo su -c "chown 0 /etc/sudoers.d/kpango"
            sudo chmod -R 777 $HOME/.config/gcloud
            sudo chown -R $(whoami) $HOME/.config/gcloud
            sudo rm -rf /var/lib/pacman/db.l* \
                /var/lib/pacman/sync/* \
                $HOME/.config/gcloud/logs/* \
                $HOME/.config/gcloud/config_sentinel \
                $HOME/.cache/* \
                /tmp/makepkg/* \
                /usr/share/man/man5/gemfile* \
                /var/cache/pacman/pkg
            sudo mkdir -p /var/cache/pacman/pkg
            sudo gpgconf --kill all
            # sudo pacman-key --init
            sudo pacman-key --populate archlinux
            # sudo pacman-key --refresh-keys
            sudo pacman-db-upgrade
            sudo pacman -Scc --noconfirm
            sudo pacman -Rsucnd --noconfirm $(sudo pacman -Qtdq)
            if type scaramanga >/dev/null 2>&1; then
                sudo scaramanga > mirrorlist
                sudo rm -rf /etc/pacman.d/mirrorlist
                sudo mv mirrorlist /etc/pacman.d/mirrorlist
                sudo chmod 755 /etc/pacman.d/mirrorlist
                sudo chown root:root /etc/pacman.d/mirrorlist
                paru -Syy
                if type milcheck >/dev/null 2>&1; then
                    sudo milcheck
                fi
            fi
            sudo rm -rf /var/lib/pacman/db.l* \
                /var/lib/pacman/sync/* \
                $HOME/.config/gcloud/logs/* \
                $HOME/.config/gcloud/config_sentinel \
                $HOME/.cache/* \
                /tmp/makepkg/* \
                /usr/share/man/man5/gemfile* \
                /var/cache/pacman/pkg
            sudo mkdir -p /var/cache/pacman/pkg
            sudo pacman-db-upgrade
            paru -Syyu --noconfirm --skipreview --removemake --cleanafter --useask --combinedupgrade --batchinstall --sudoloop
            sudo rm -rf /var/lib/pacman/db.l*
            sudo chmod -R 777 $HOME/.config/gcloud
            sudo chown -R $(whoami) $HOME/.config/gcloud
            sudo rm -rf /var/lib/pacman/db.l* \
                /var/lib/pacman/sync/* \
                $HOME/.config/gcloud/logs/* \
                $HOME/.config/gcloud/config_sentinel \
                $HOME/.cache/* \
                /tmp/makepkg/* \
                /var/cache/pacman/pkg
            sudo mkdir -p /var/cache/pacman/pkg
            sudo pacman -Scc --noconfirm
            sudo pacman -Rsucnd --noconfirm $(sudo pacman -Qtdq)
            sudo rm -rf /var/lib/pacman/db.lck
            sudo paccache -ruk0
            CC=$(which gcc) CXX=$(which g++) CPP="$CC -E" \
                paru -Syyu --noconfirm --skipreview --removemake --cleanafter --useask --combinedupgrade --batchinstall --sudoloop
            sudo rm -rf /var/lib/pacman/db.l*
            sudo chmod -R 777 $HOME/.config/gcloud
            sudo chown -R $(whoami) $HOME/.config/gcloud
            sudo rm -rf /var/lib/pacman/db.l* \
                $HOME/.config/gcloud/logs/* \
                $HOME/.config/gcloud/config_sentinel \
                $HOME/.cache/* \
                /tmp/makepkg/* \
                /var/cache/pacman/pkg
            sudo mkdir -p /var/cache/pacman/pkg
            sudo pacman -Scc --noconfirm
            sudo pacman -Rns --noconfirm $(sudo pacman -Qtdq)
            sudo rm -rf /var/lib/pacman/db.lck
            sudo paccache -ruk0
            sudo bootctl update
            sudo mkinitcpio -p linux-zen
            sudo journalctl --vacuum-time=2weeks
            sync \
            && sudo sysctl -w vm.drop_caches=3 \
                && sudo swapoff -a \
                && sudo swapon -a \
                && printf '\n%s\n' 'RAM-cache and Swap were cleared.' \
                && free
        }
        alias archup=archup
        alias up=archup

        if type reboot >/dev/null 2>&1; then
            reboot() {
                archup
                fup
                archback
                sudo reboot && exit
            }
            alias reboot=reboot
        fi

        if type shutdown >/dev/null 2>&1; then
            shutdown() {
                archup
                fup
                archback
                sudo shutdown now && exit
            }
            alias shutdown=shutdown
        fi
    elif type apt >/dev/null 2>&1; then
        aptup(){
          sudo du -sh /var/cache/apt/archives
          sudo rm -rf /var/cache/apt
          sudo mkdir -p /var/cache/apt/archives/partial
          sudo DEBIAN_FRONTEND=noninteractive apt -y clean
          sudo DEBIAN_FRONTEND=noninteractive apt -y autoremove
          sudo DEBIAN_FRONTEND=noninteractive apt -y update
          sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade
          sudo DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
          sudo DEBIAN_FRONTEND=noninteractive apt -y clean
          sudo dpkg-reconfigure -f noninteractive tzdata
          sudo DEBIAN_FRONTEND=noninteractive apt -y autoremove --purge
          sudo du -sh /var/cache/apt/archives
          sudo rm -rf /var/cache/apt
          sudo mkdir -p /var/cache/apt/archives/partial
          sudo update-alternatives --set cc $CC
          sudo update-alternatives --set c++ $CXX
        }
        alias aptup=aptup
        alias up=aptup
    fi

    if type gpg >/dev/null 2>&1; then
        backup_dir=$HOME/gpgbackup
        gpgbackup() {
            sudo rm -rf $backup_dir
            mkdir -p $backup_dir
            gpg -a --export $1 > $backup_dir/kpango-public.key
            gpg -a --export-secret-keys $1 > $backup_dir/kpango-secret.key
            gpg --export-ownertrust > $backup_dir/kpango-ownertrust.txt
            sudo chmod -R 777 $backup_dir
            sudo chown -R $(USER) $backup_dir
            if type tar >/dev/null 2>&1; then
                sudo tar Jcvf $HOME/Downloads/gpgbackup.tar.gz $backup_dir
                rm -rf gpgbackup
            fi
        }
        alias gpgbu=gpgbackup

        gpgrestore() {
            if type tar >/dev/null 2>&1; then
                sudo tar Jxvf $HOME/Downloads/gpgbackup.tar.gz
            fi
            gpg --import $backup_dir/kpango-secret.key
            gpg --import-ownertrust $backup_dir/kpango-ownertrust.txt
        }
        alias gpgrs=gpgrestore
    fi

    if type bumblebeed >/dev/null 2>&1; then
        discrete() {
            killall Xorg
            modprobe nvidia_drm
            modprobe nvidia_modeset
            modprobe nvidia
            tee /proc/acpi/bbswitch <<<ON
            cp /etc/X11/xorg.conf.nvidia /etc/X11/xorg.conf
        }
        alias discrete=discrete
        integrated() {
            killall Xorg
            rmmod nvidia_drm
            rmmod nvidia_modeset
            rmmod nvidia
            tee /proc/acpi/bbswitch <<<OFF
            cp /etc/X11/xorg.conf.intel /etc/X11/xorg.conf
        }
        alias integrated=integrated
    fi

    if type direnv >/dev/null 2>&1; then
        eval "$(direnv hook zsh)"
    fi

    if type systemctl >/dev/null 2>&1; then
        alias checkkm="sudo systemctl status systemd-modules-load.service"
    fi

    if type vcs_info >/dev/null 2>&1; then
        vcs_info
    fi

    if type sway >/dev/null 2>&1; then
        export SWAYSOCK=/run/user/$(id -u)/sway-ipc.$(id -u).$(pgrep -x sway).sock
    fi

    if type chrome >/dev/null 2>&1; then
        alias chrome="chrome --audio-buffer-size=4096"
    fi

    if type whois >/dev/null 2>&1; then
        TRACECMD="traceroute"
        TRACE_ARGS=""
        if type mtr >/dev/null 2>&1; then
            TRACECMD="mtr"
            TRACE_ARGS="-wbc 4"
        fi
        checkcountry(){
            if [ $# -eq 1 ]; then
                echo "$TRACECMD $TRACE_ARGS $1"
                sudo $TRACECMD $TRACE_ARGS $1 \
                | rg -wo -e '[0-9]+(\.[0-9]+){3}' \
                | xargs -I {} whois {} \
                | rg -i country \
                | awk '{print $(NF)}' \
                | sort | uniq
            else
                echo "invalid argument, Domain or IP is required"
            fi
        }
        alias ccnt=checkcountry
    fi

    if [ -d "$GOPATH/src/github.com/vdaas/vald" ]; then
        valdup(){
            cd "$GOPATH/src/github.com/vdaas/vald"
            make helm/schema/vald
            make helm/schema/vald-helm-operator
            make helm/schema/crd/vald
            make helm/schema/crd/vald-helm-operator
            make k8s/manifest/update
            make k8s/manifest/helm-operator/update
            make helm/docs/vald
            make helm/docs/vald-helm-operator
            make update
        }
        alias valdup=valdup
        valddep(){
            cd "$GOPATH/src/github.com/vdaas/vald"
            rm -rf go.mod go.sum \
                && cp hack/go.mod.default go.mod \
                && GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy
            rm -rf hack/go.mod.default2 \
                && cat hack/go.mod.default | head -n 5 >> hack/go.mod.default2 \
                && cat go.sum | awk '{printf "\t%s => %s latest\n", $1, $1}' \
                | sort -n | uniq | sort -n >> hack/go.mod.default2 \
                && echo ")" >> hack/go.mod.default2
            rm -rf hack/go.mod.default3
            cat hack/go.mod.default | head -n 5 >> hack/go.mod.default3
            cat hack/go.mod.default | rg k8s >> hack/go.mod.default3
            cat hack/go.mod.default | rg opentelemetry >> hack/go.mod.default3
            cat hack/go.mod.default | rg containerd >> hack/go.mod.default3
            echo ")" >> hack/go.mod.default3
            rm -rf /tmp/go.mod /tmp/go.sum \
                && mv go.mod go.sum /tmp \
                && cp hack/go.mod.default3 go.mod \
                && GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy \
                && rm -rf hack/go.mod.default3 \
                && cat hack/go.mod.default | head -n 5 >> hack/go.mod.default3 \
                && cat go.sum | awk '{printf "\t%s => %s latest\n", $1, $1}' \
                | sort -n | uniq | sort -n >> hack/go.mod.default3 \
                && echo ")" >> hack/go.mod.default3 \
                && rm -rf go.mod go.sum \
                && mv /tmp/go.mod /tmp/go.sum .
            $EDITOR -d hack/go.mod.default hack/go.mod.default2
            $EDITOR -d hack/go.mod.default hack/go.mod.default3
            cd -
        }
        alias valddep=valddep
    fi
    export ZSH_LOADED=1;
fi
