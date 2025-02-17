#!/usr/bin/env zsh

# Determine CPU type
CPUTYPE=${CPUTYPE:-$(uname -m)}

# Set alias for tmux on ARM-based Macs
[[ ${OSTYPE} == "darwin"* && ${CPUTYPE} == "arm"* ]] && alias tmux=/opt/homebrew/bin/tmux

# Check if tmux is installed
if type tmux >/dev/null 2>&1; then
    # If not inside a tmux session
    if [ -z $TMUX ]; then
        echo "welcome to tmux"
        USER="$(whoami)"
        HOST="$(hostname)"
        TMUX_TMPDIR_PREFIX="/tmp/tmux-sockets"
        TMUX_TMPDIR="$TMUX_TMPDIR_PREFIX/$HOST"
        export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
        TPM_PATH="$TMUX_PLUGIN_MANAGER_PATH/tpm"
        if [ ! -d $TPM_PATH ]; then
            git clone --depth 1 --recursive https://github.com/tmux-plugins/tpm $TPM_PATH
        fi
        # If connected via SSH
        if [ ! -z "$SSH_CLIENT" ]; then
            SSH_IP="${SSH_CLIENT%% *}"
            TMUX_TMPDIR="$TMUX_TMPDIR_PREFIX/ssh-from-$SSH_IP"
            echo "starting tmux for ssh $SSH_TTY from $SSH_CLIENT"
        fi
        export TMUX_TMPDIR=$TMUX_TMPDIR
        # Create tmux temp directory if it doesn't exist
        if mkdir -p $TMUX_TMPDIR; then
            echo "Successfully created tmux temp directory on $TMUX_TMPDIR."
        else
            echo "Failed to create tmux temp directory on $TMUX_TMPDIR."
            exit 1 # Exit if failed to create directory
        fi
        TMUX_SESSIONS=$(tmux ls 2>/dev/null) # Check for existing tmux sessions on the specified socket directory
        if [ $? -ne 0 ]; then                # Check for error from tmux command
            if [ -f /.dockerenv ]; then      # Docker specific settings
                group=$(id -g)
                # Ensure the user has access to the Docker socket
                sudo chown -R $USER:$group /var/run/docker.sock
            fi
            echo "creating new tmux session at $TMUX_TMPDIR"
            if TMUX_TMPDIR=$TMUX_TMPDIR tmux -2 new-session -n$USER -s$USER@$HOST; then
                echo "created new tmux session for $TMUX_TMPDIR:$USER@$HOST"
            else
                echo "failed to create new tmux session for $TMUX_TMPDIR:$USER@$HOST"
                exit 1 # Exit if failed to create tmux session
            fi
        else
            SESSION_NAME="$(tmux ls | cut -d: -f1 | head -n 1)" # get the name of a session
            if [ -z "$SESSION_NAME" ]; then
                echo "No sessions found in $USER@$HOST, global tmux ls = $(tmux ls)"
                exit 1 # Exit if no sessions found
            fi
            echo "attaching tmux session $SESSION_NAME at $TMUX_TMPDIR"
            # Attach to an existing tmux session
            if TMUX_TMPDIR=$TMUX_TMPDIR tmux -2 attach-session -t "$SESSION_NAME"; then
                echo "attached tmux session $SESSION_NAME"
            else
                echo "failed to attach tmux session for $SESSION_NAME"
                exit 1 # Exit if failed to attach tmux session
            fi
        fi
        exit
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
    export GIT_USER=kpango

    if [[ ${OSTYPE} == "darwin"* && ${CPUTYPE} == "arm"* ]]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi

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
        if [ -d /usr/local/lib/google-cloud-sdk ]; then
            export GCLOUD_PATH="/usr/lib/google-cloud-sdk"
        fi
        export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    fi

    if type php >/dev/null 2>&1; then
        export PHP_BUILD_CONFIGURE_OPTS="--with-openssl=/usr/local/opt/openssl"
    fi

    if type python3 >/dev/null 2>&1; then
        export PYTHON_CONFIGURE_OPTS="--enable-shared"
        export PYTHONIOENCODING="utf-8"
    fi

    if type nvim >/dev/null 2>&1; then
        export VIM=$(which nvim)
        case ${OSTYPE} in
        darwin*)
            if [ -d /opt/homebrew/Cellar/neovim/*/share/nvim/runtime ]; then
                export VIMRUNTIME="/opt/homebrew/Cellar/neovim/*/share/nvim/runtime"
            fi
            ;;
        linux*)
            if [ -d /usr/share/nvim/runtime ]; then
                export VIMRUNTIME="/usr/share/nvim/runtime"
            fi
            ;;
        esac
        export NVIM_HOME=$XDG_CONFIG_HOME/nvim
        export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME/log
        export NVIM_TUI_ENABLE_TRUE_COLOR=1
        export NVIM_PYTHON_LOG_LEVEL=WARNING
        export NVIM_PYTHON_LOG_FILE=$NVIM_LOG_FILE_PATH/nvim.log
    elif type vim >/dev/null 2>&1; then
        export VIM=$(which vim)
        case ${OSTYPE} in
        darwin*)
            if [ -d /opt/homebrew/Cellar/neovim/*/share/nvim/runtime ]; then
                export VIMRUNTIME="/opt/homebrew/Cellar/neovim/*/share/nvim/runtime"
            fi
            ;;
        linux*)
            if [ -d /usr/share/nvim/runtime ]; then
                export VIMRUNTIME="/usr/share/nvim/runtime"
            fi
            ;;
        esac
    else
        export VIM=$(which vi)
    fi

    export EDITOR=$VIM
    export VISUAL=$EDITOR
    export PAGER=$(which less)
    export SUDO_EDITOR=$EDITOR

    #ReactNative
    export REACT_EDITOR=$EDITOR

    export LD_LIBRARY_PATH=/lib:/usr/local/lib:${GCLOUD_PATH}/lib:/opt/containerd/lib:/opt/cuda/lib:${LD_LIBRARY_PATH}

    if [ -d "/usr/local/lib/rust" ]; then
        export RUST_HOME="/usr/local/lib/rust"
    fi
    export CARGO_HOME=$RUST_HOME/cargo
    export RUSTUP_HOME=$RUST_HOME/rustup

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
        export GOPRIVATE="*.yahoo.co.jp,github.com/vdaas/vald,github.com/vdaas/vald/apis,github.com/vdaas/vald-client-go"
        export NVIM_GO_LOG_FILE=$XDG_DATA_HOME/go
        # export CGO_LDFLAGS="-g -flto -march=native -fno-plt -Wl,-Ofast,--sort-common,--as-needed,-z,relro,-z,now -fdata-sections -ffunction-sections -Wl,--gc-sections -fvisibility=hidden"
        # export CGO_CFLAGS=$CGO_LDFLAGS
    fi

    if type clang >/dev/null 2>&1; then
        export CC=$(which clang)
        export CXX=$(which clang++)
        export CPP="$CXX -E"
        export LD=/usr/bin/ldd
        if type llvm-config >/dev/null 2>&1; then
            export LD_LIBRARY_PATH=$(llvm-config --libdir):$LD_LIBRARY_PATH
            export LLVM_CONFIG_PATH=$(which llvm-config)
        else
            export LD_LIBRARY_PATH=/usr/lib/clang/*/lib:$LD_LIBRARY_PATH
        fi
        # export LDFLAGS="-g -flto -march=native -fno-plt -Wl,-Ofast,--sort-common,--as-needed,-z,relro,-z,now -fdata-sections -ffunction-sections -Wl,--gc-sections -fvisibility=hidden -L$LLVM_HOME/lib:-L$QT_HOME/lib:-L/usr/local/opt/openssl/lib:-L/usr/local/opt/bison/lib:$LDFLAGS"
        # export FFLAGS=$LDFLAGS
        #CLANG
        export CFLAGS=-I$LLVM_HOME/include:-I$QT_HOME/include:-I/usr/local/opt/openssl/include:$CFLAGS
        export CPPFLAGS=$CFLAGS
        export C_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$C_INCLUDE_PATH
        export CPLUS_INCLUDE_PATH=$LLVM_HOME/include:$QT_HOME/include:$CPLUS_INCLUDE_PATH
    fi

    DOTFILE_URL="github.com/$GIT_USER/dotfiles"
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
    export LIBRARY_PATH=/lib:/usr/local/lib:${GCLOUD_PATH}/lib:/opt/containerd/lib:/opt/cuda/lib:${LD_LIBRARY_PATH}

    export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/local/go/bin:/opt/local/bin:$GOBIN:$HOME/.local/bin:$CARGO_HOME/bin:$GCLOUD_PATH/bin:/usr/lib/docker/cli-plugins/:$PATH"

    if type deno >/dev/null 2>&1; then
        export PATH="$(which deno):$PATH"
    fi

    if [ -d "$HOME/.rd/bin" ]; then
        export PATH="$HOME/.rd/bin:$PATH"
    fi

    # for teleplesence disabling send analytics data anonymously
    export SCOUT_DISABLE=1

    export DOTENV_LOADED=1
fi

if type gpg >/dev/null 2>&1; then
    export GPG_TTY=$(tty)
    # export PINENTRY_USER_DATA="USE_CURSES=1"
fi

if [ ! -f "$HOME/.zshrc.zwc" -o "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" ]; then
    zcompile $HOME/.zshrc
fi

if [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
    zcompile $HOME/.zcompdump
fi

if [ -z $ZSH_LOADED ]; then
    if type sheldon >/dev/null 2>&1; then
        [ -z "$_lazy_sheldon" ] && {
            eval "$(sheldon source)"
            _lazy_sheldon=1
        }
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

    ########################################
    # オプション
    setopt auto_cd         # ディレクトリ名だけでcdする
    setopt auto_list       # 補完候補を一覧表示
    setopt auto_menu       # 補完候補が複数あるときに自動的に一覧表示する
    setopt auto_param_keys # カッコの対応などを自動的に補完
    setopt auto_param_slash
    setopt auto_pushd # cd したら自動的にpushdする
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
        BUFFER=$(history -n -r 1 |
            awk 'length($0) > 2' |
            rg -v "^...$" |
            rg -v "^....$" |
            rg -v "^.....$" |
            rg -v "^......$" |
            rg -v "^exit$" |
            uniq -u |
            fzf-tmux --no-sort +m --query "$LBUFFER" --prompt="History > ")
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
        # General Git aliases
        alias gco="git checkout"
        alias gsta="git status"
        alias gcom="git commit -m"
        alias gdiff="git diff"
        alias gbra="git branch"

        # Get current repository branch name
        gitthisrepo() {
            git symbolic-ref --short HEAD | tr -d "\n"
        }
        alias tb=gitthisrepo

        # Get default branch name
        gitdefaultbranch() {
            git remote show origin | grep 'HEAD' | cut -d':' -f2 | sed -e 's/^ *//g' -e 's/ *$//g'
        }
        alias gitdb=gitdefaultbranch

        # Check for merged branches that can be removed
        gitremovalcheck() {
            local db=$(gitdb)
            git branch -r --merged "$db" | grep -v -e "$db" -e develop -e release | sed -E 's% *origin/%%'
            git branch --merged "$db" | grep -vE '^\*|master$|develop$|main$'
        }
        alias grc=gitremovalcheck

        # Common function for fetch, reset, and cleanup
        git_fetch_reset() {
            local tb=$(tb)
            local db=$(gitdb)
            git fetch --prune
            git reset --hard origin/$tb || { echo "Failed to reset"; return 1; }
            git branch -r --merged $db | grep -v -e $db -e develop -e release | sed -E 's% *origin/%%' | xargs -I% git push --delete origin % || { echo "Failed to delete merged branches"; return 1; }
            git fetch --prune
            git reset --hard origin/$tb || { echo "Failed to reset"; return 1; }
            git branch --merged $db | grep -vE '^\*|master$|develop$|main$' | xargs -I % git branch -d % || { echo "Failed to delete local branches"; return 1; }
        }

        # Fetch, reset, and clean up branches
        gfr() {
            git_fetch_reset
        }
        alias gfr=gfr

        # Fetch, reset, and update submodules
        gfrs() {
            gfr && git submodule foreach git pull origin "$(gitdb)" || { echo "Failed to update submodules"; return 1; }
        }
        alias gfrs=gfrs

        # Pull with rebase
        gitpull() {
            git pull --rebase origin "$(tb)" || { echo "Failed to pull with rebase"; return 1; }
        }
        alias gpull=gitpull

        # Push to current branch
        gpush() {
            git push -u origin "$(tb)" || { echo "Failed to push to origin"; return 1; }
        }
        alias gpush=gpush

        # Commit, signoff, and push
        gitcompush() {
            git add -A
            git commit --signoff -m "$1"
            git push -u origin "$2"
        }
        alias gitcompush=gitcompush

        # Commit, signoff, and push to current branch
        gcp() {
            gitcompush "$1" "$(tb)"
        }
        alias gcp=gcp
        alias gfix="gcp fix"

        # Commit, signoff, and force push with lease
        gitcompushf() {
            git add -A
            git commit --signoff -m "$1"
            git push --force-with-lease --set-upstream origin "$2"
        }
        alias gitcompushf=gitcompushf

        # Commit, signoff, and force push to current branch
        gcpf() {
            gitcompushf "$1" "$(tb)"
        }
        alias gcpf=gcpf

        # Amend last commit and force push
        gfp() {
            git add -A || { echo "Failed to stage changes"; return 1; }
            git commit --signoff --amend || { echo "Failed to amend commit"; return 1; }
            git push --force-with-lease || { echo "Failed to force push"; return 1; }
        }
        alias gfp=gfp

        # Rebase and squash changes
        grs() {
            if [ $# -eq 1 ] || [ $# -eq 2 ]; then
                local branch="$(tb)"
                git checkout "$1" || { echo "Failed to checkout branch $1"; return 1; }
                gfr
                git checkout -b tmp || { echo "Failed to create tmp branch"; return 1; }
                git merge --squash "$branch"
                if [ $# -eq 2 ]; then
                    git checkout "$2" . || { echo "Failed to checkout files from $2"; return 1; }
                fi

                git branch -D "$branch" || { echo "Failed to delete branch $branch"; return 1; }
                git branch -m "$branch" || { echo "Failed to rename branch"; return 1; }
            else
                echo "invalid argument, rebase branch name required"
                return 1
            fi
        }
        alias grs=grs

        # Rebase, squash, and push changes
        grsp() {
            if [ $# -eq 1 ] || [ $# -eq 2 ]; then
                local message="$(git log remotes/origin/$1..$branch --reverse --pretty=%s)"
                grs "$@"
                gcpf $message
            else
                echo "invalid argument, rebase branch name required"
                return 1
            fi
        }
        alias grsp=grsp

        # Edit Git config
        alias gedit="vim $HOME/.gitconfig"


        # Fetch and merge from upstream
        git-remote-merge() {
            git fetch upstream || { echo "Failed to fetch from upstream"; return 1; }
            git merge upstream/$(gitdb) || { echo "Failed to merge upstream branch"; return 1; }
        }
        alias grf=git-remote-merge
        # Add and merge remote repository
        git-remote-add-merge() {
            git remote add upstream "$1" || { echo "Failed to add remote upstream"; return 1; }
            grf
        }
        alias grfa=git-remote-add-merge
    fi

    if type rg >/dev/null 2>&1; then
        alias grep=rg
        if type curl >/dev/null 2>&1; then
            listdomains() {
                if [ $# -eq 1 ]; then
                    curl -fs $1 |
                        rg -Po '.*?//\K.*?(?=/)' |
                        rg -v "@" |
                        rg -v "\+" |
                        sort | uniq
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
    elif type erd >/dev/null 2>&1; then
        alias ks='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
        alias l='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
        alias ll='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
        alias la='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --color force --level 1'
        alias lla='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --no-git --color force --level 2'
        alias tree='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --no-git --color force'
        alias ls='erd -H -d logical -I --level 1 --sort rsize -y inverted --dir-order first'
        alias lg='erd -H -d logical -I -l --group --octal --time-format iso --sort rsize -y inverted --dir-order first --threads 32 --hidden --color force --level 1 | rg'
    elif type eza >/dev/null 2>&1; then
        alias ks="eza -G"
        alias l="eza -G "
        alias ll='eza -l'
        alias la='eza -aghHliS'
        alias lla='eza -aghHliSm'
        alias tree='eza -T'
        alias ls='eza -G'
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
        sshperm() {
            sudo chown -R $(id -u):$(id -g) $HOME/.ssh
            find $HOME/.ssh -type d -print | xargs sudo chmod 700
            find $HOME/.ssh -type f -print | xargs sudo chmod 600
        }
        rsagen() {
            ssh-keygen -t rsa -b 4096 -P $1 -f $HOME/.ssh/id_rsa -C $USER
            sshperm
        }
        alias rsagen=rsagen
        ecdsagen() {
            ssh-keygen -t ecdsa -b 521 -P $1 -f $HOME/.ssh/id_ecdsa -C $USER
            sshperm
        }
        alias ecdsagen=ecdsagen

        edgen() {
            ssh-keygen -t ed25519 -P $1 -f $HOME/.ssh/id_ed -C $USER
            sshperm
        }
        alias edgen=edgen
        alias sedit="vim $HOME/.ssh/config"
        sshls() {
            rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*"
        }
        alias sshls=sshls
        sshinit() {
            rm -rf $HOME/.ssh/known_hosts \
                $HOME/.ssh/master_$GIT_USER@192.168.2.* \
                /tmp/ssh-.*.sock
            sshperm
        }
        alias sshinit=sshinit
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
        if [ -f /.dockerenv ]; then
            tmux unbind C-b
            tmux set -g prefix C-w
            tmux bind C-w send-prefix
        else
            case ${OSTYPE} in
            darwin*)
                tmux unbind C-b
                tmux set -g prefix C-g
                tmux bind C-g send-prefix
                ;;
            linux*)
                tmux bind C-b send-prefix
                ;;
            esac
        fi
    fi
    alias tedit="vim $HOME/.tmux.conf"

    zscompile() {
        for f in $(find $HOME -name "*.zsh"); do
            zcompile $f
        done
    }
    alias zscompile=zscompile

    zsup() {
        rm -rf $HOME/.zcompd*
        rm $HOME/.zshrc.zwc
        # update sheldon package here
        rm -rf $HOME/.bashrc
        rm -rf $HOME/.fzf.bash
        zscompile
    }
    alias zsup=zsup

    zsinit() {
        rm -rf $HOME/.zcompd*
        rm -rf $HOME/.zshrc.zwc
    }
    alias zsinit=zsinit

    zstime() {
        for i in $(seq 1 $1); do
            time $(zsh -i -c exit)
        done
    }
    alias zstime=zstime

    if { [ -L "$HOME/.zshrc" ] || [ -f "/.dockerenv" ]; } && [ -f "$DOTFILES_DIR/zshrc" ]; then
        alias zedit="vim $DOTFILES_DIR/zshrc"
    else
        alias zedit="vim $HOME/.zshrc"
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
    chperm() {
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
            elif type ug >/dev/null 2>&1; then
                cd $1 && ug -l $2 | xargs -t -P $CPUCORES \sed -i -E "s/$2/$3/g" && cd -
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
                rg --multiline -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g"
            elif type ug >/dev/null 2>&1; then
                cd $1 && ug -l $2 $1 | xargs -t -P $CPUCORES \sed -i -E "s$4$2$4$3$4g" && cd -
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
        neovim() {
            local neovim="$(whence -p nvim 2>/dev/null)"
            if type pass >/dev/null 2>&1; then
	        if pass show neovim; then
                    "$neovim" "$@"
                else
                    echo "failed to load openai key"
                    exit 1 # Exit if failed to create tmux session
                fi
            else
                "$neovim" "$@"
            fi
        }
        alias nvim=neovim
        alias vim=neovim
        alias vi=neovim
        alias bim=neovim
        alias cim=neovim
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
        alias nvinit="nvim-init"
        alias vake="nvim Makefile"
        alias vback="cp $HOME/.config/nvim/init.lua $HOME/.config/nvim/init.lua.back"
        alias vedit="nvim $HOME/.config/nvim/"
        alias vocker="nvim Dockerfile"
        alias vrestore="cp $HOME/.config/nvim/init.lua.back $HOME/.config/nvim/init.lua"
        alias vspdchk="rm -rf /tmp/starup.log && nvim --startuptime /tmp/startup.log +q && less /tmp/startup.log"
        alias wedit="nvim $HOME/.config/sway/config"
        alias xedit="nvim $HOME/.Xdefaults"
    else
        alias vedit="$EDITOR $HOME/.vimrc"
        alias vi="$EDITOR"
        alias vim="$EDITOR"
        alias bim="$EDITOR"
        alias cim="$EDITOR"
        alias vspdchk="rm -rf /tmp/starup.log && $EDITOR --startuptime /tmp/startup.log +q && less /tmp/startup.log"
        alias xedit="$EDITOR $HOME/.Xdefaults"
        alias wedit="$EDITOR $HOME/.config/sway/config"
    fi

    if type kubectl >/dev/null 2>&1; then
        kubectl() {
            local kubectl="$(whence -p kubectl 2>/dev/null)"
            if type kubecolor >/dev/null 2>&1; then
                local kubectl="$(whence -p kubecolor 2>/dev/null)"
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
                SSID=$1
                PSK=$2

                SECURITY=$(nmcli -f SSID,SECURITY dev wifi | grep "$SSID" | awk '{print $2}')
                KEY_MGMT="wpa-psk"
                if [[ "$SECURITY" == *"WPA3"* ]]; then
                    KEY_MGMT="sae"
                elif [[ "$SECURITY" == *"WPA2"* ]]; then
                    KEY_MGMT="wpa-psk"
                fi
                sudo nmcli c delete "$SSID"
                nmcli d
                nmcli r wifi
                nmcli d wifi list
                IFNAME=$(nmcli d | grep wifi | head -1 | awk '{print $1}')
                sudo nmcli c add type wifi ifname "$IFNAME" con-name "$SSID" ssid "$SSID" -- \
                    connection.autoconnect yes \
                    ipv4.method auto \
                    802-11-wireless.ssid "$SSID" \
                    802-11-wireless-security.key-mgmt "$KEY_MGMT" \
                    802-11-wireless-security.psk-flags 0 \
                    802-11-wireless-security.psk "$PSK"
                sudo nmcli c up "$SSID"
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
        ciscovpn() {
            osascript $DOTFILES_DIR/macos/AnyConnect.scpt
        }
        alias ciscovpn=ciscovpn
    fi

    if type fwupdmgr >/dev/null 2>&1; then
        fup() {
            sudo systemctl reload dbus.service
            sudo systemctl restart fwupd.service
            sudo lsusb
            sudo fwupdtool get-devices
            sudo fwupdtool clear-history
            sudo fwupdtool clear-offline
            sudo fwupdtool refresh --force
            sudo fwupdtool get-updates --force
            sudo fwupdtool get-upgrades --force
            sudo fwupdtool update
        }
        alias fup=fup
    fi

    update_git_repo() {
        local repo_dir=$1
        if [ -d "$repo_dir" ]; then
            pushd "$repo_dir" >/dev/null || return
            #if git diff-index --quiet HEAD -- && [ -z "$(git status --porcelain | grep '^[^ ]')" ]; then
            if git diff-index --quiet HEAD -- && [ -z "$(git diff --ignore-space-change --ignore-blank-lines --diff-filter=MARC)" ]; then
                echo "No local changes in $repo_dir, pulling latest changes from origin..."
                gfrs
            else
                echo "Local changes detected in $repo_dir, not pulling from origin. Here are the changes:"
                git status
                git diff --name-only
                echo "Detailed changes:"
                git diff
            fi
            popd >/dev/null || return
        else
            echo "Directory $repo_dir does not exist." >&2
        fi
    }

    update_multiple_git_repos() {
        local repos=("$@")
        for repo in "${repos[@]}"; do
            update_git_repo "$repo"
        done
    }

    kpangoup() {
        update_multiple_git_repos \
            "$GOPATH/src/github.com/kpango/dotfiles" \
            "$GOPATH/src/github.com/kpango/pass" \
            "$GOPATH/src/github.com/kpango/wallpapers" \
            "$GOPATH/src/github.com/vdaas/vald" \
            "$GOPATH/src/github.com/vdaas/vald-client-go"
    }
    alias kpangoup=kpangoup

    if type brew >/dev/null 2>&1; then
        brewup() {
            kpangoup
            cd $(brew --prefix)/Homebrew
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
    elif type pacman >/dev/null 2>&1; then
        GCC=$(which gcc)
        GXX=$(which g++)
        GCPP="$GCC -E"
        run_command() {
            if ! "$@"; then
                echo "Failed to execute the command: $@"
                return 1
            fi
            echo "Command executed successfully: $@"
        }

        try_package_manager() {
            local manager=$1
            shift
            if type $manager >/dev/null 2>&1; then
                echo "Trying with $manager..."
                if run_command $manager "$@"; then
                    return 0
                fi
                echo "$manager failed, trying to ignore unnecessary packages."
                if run_command $manager "$@" --ignore mozc --ignore fcitx5-mozc-ut; then
                    return 0
                fi
                echo "$manager with ignoreing unnecessary package failed, trying with gcc/g++ environment variables set."
                if CC=$GCC CXX=$GXX CPP=$GCPP run_command $manager "$@"; then
                    return 0
                fi
                echo "$manager with gcc/g++ environment variables failed, trying to ignore unnecessary packages."
                if CC=$GCC CXX=$GXX CPP=$GCPP run_command $manager "$@" --ignore mozc --ignore fcitx5-mozc-ut; then
                    return 0
                fi
                echo "$manager failed."
            else
                echo "$manager is not installed."
            fi
            return 1
        }

        kacman() {
            if try_package_manager paru "$@"; then return 0; fi
            if try_package_manager pakku "$@"; then return 0; fi
            if try_package_manager yay "$@"; then return 0; fi
            if try_package_manager "sudo pacman" "$@"; then return 0; fi
            echo "Failed to execute the command with option '$@' with all package managers."
            return 1
        }
        kacclean() {
            sudo chmod -R 777 $HOME/.config/gcloud
            sudo chown -R $USER $HOME/.config/gcloud
            sudo rm -rf $HOME/.cache/* \
                $HOME/.config/gcloud/config_sentinel \
                $HOME/.config/gcloud/logs/* \
                /tmp/makepkg/* \
                /var/lib/pacman/db.l* \
                /usr/share/man/man5/gemfile* \
                /var/cache/pacman/pkg \
                /var/lib/pacman/sync/*
            sudo mkdir -p /var/cache/pacman/pkg
            kacman -Scc --noconfirm
            sudo pacman -Qtdq | xargs -r kacman -Rsucnd --noconfirm
            sudo rm -rf /var/lib/pacman/db.lck
            sudo paccache -ruk0
        }
        archback() {
            family_name=$(cat /sys/devices/virtual/dmi/id/product_family)
            echo $family_name
            kacman -Sy
            if [[ $family_name =~ "P1" ]]; then
                echo "backup ThinkPad P1 Gen 2 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_p1.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_p1.list
                pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_p1.list
                pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_p1.list
            elif [[ $family_name =~ "5th" ]]; then
                echo "backup ThinkPad X1 Carbon Gen 5 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_nc.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_nc.list
                pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_nc.list
                pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_nc.list
            elif [[ $family_name =~ "X1" ]]; then
                echo "backup ThinkPad X1 Carbon Gen 9 packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur.list
                pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg.list
                pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur.list
            else
                echo "backup packages"
                sudo chmod -R 777 $DOTFILES_DIR/arch/pkg_desk.list
                sudo chmod -R 777 $DOTFILES_DIR/arch/aur_desk.list
                pacman -Qqen | sort -n >$DOTFILES_DIR/arch/pkg_desk.list
                pacman -Qqem | sort -n >$DOTFILES_DIR/arch/aur_desk.list
            fi
            kacclean
        }
        alias archback=archback

        archup() {
            kpangoup
            sudo chown 0 /etc/sudoers.d/$USER
            sudo chmod -R 700 $HOME/.gnupg
            sudo chmod -R 600 $HOME/.gnupg/*
            run_command sync &&
                sudo sysctl -w vm.drop_caches=3 &&
                sudo swapoff -a &&
                sudo swapon -a &&
                printf '\n%s\n' 'RAM-cache and Swap were cleared.' &&
                free
            sudo su -c "chown 0 /etc/sudoers.d/$USER"
            kacclean
            if type gpgconf >/dev/null 2>&1; then
                sudo gpgconf --kill all
            fi
            if [ $# -eq 1 ]; then
                sudo chown -R $USER $HOME/.gnupg
                touch $HOME/.gnupg/dirmngr_ldapservers.conf
                sudo chmod 700 $HOME/.gnupg/crls.d/
                if type dirmgr >/dev/null 2>&1; then
                    sudo dirmngr </dev/null
                fi
                if type pacman-key >/dev/null 2>&1; then
                    sudo pacman-key --init
                    sudo pacman-key --populate archlinux
                    sudo pacman-key --refresh-keys
                fi
            elif type pacman-key >/dev/null 2>&1; then
                sudo pacman-key --populate archlinux
            fi
            sudo pacman-db-upgrade
            kacclean
            if type rate-mirrors >/dev/null 2>&1; then
                sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
                TMPFILE="$(mktemp)"
                rate-mirrors \
                    --allow-root \
                    --disable-comments \
                    --disable-comments-in-file \
                    --entry-country JP \
                    --concurrency $CPUCORES \
                    --save="$TMPFILE" \
                    arch --max-delay=21600
                if [[ $(wc -l <$TMPFILE) -lt 5 ]]; then
                    echo "Failed to get new mirrorlist from rate-mirrors"
                    sudo rm -rf $TMPFILE
                    sudo rm -rf /etc/pacman.d/mirrorlist
                    sudo mv /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist
                else
                    echo "Successfully got new mirrorlist from rate-mirrors"
                    sudo rm -rf /etc/pacman.d/mirrorlist
                    sudo mv $TMPFILE /etc/pacman.d/mirrorlist
                    sudo chmod 755 /etc/pacman.d/mirrorlist
                    sudo chown root:root /etc/pacman.d/mirrorlist
                    sudo rm -f /etc/pacman.d/mirrorlist.backup
                fi
                kacman -Syy
                if type milcheck >/dev/null 2>&1; then
                    sudo milcheck
                fi
            fi
            kacman -Syyu --noconfirm --skipreview --removemake --cleanafter --useask --combinedupgrade --batchinstall --sudoloop
            kacclean
            sudo bootctl update
            sudo mkinitcpio -p linux-zen
            sudo journalctl --vacuum-time=2weeks
            run_command sync &&
                sudo sysctl -w vm.drop_caches=3 &&
                sudo swapoff -a &&
                sudo swapon -a &&
                printf '\n%s\n' 'RAM-cache and Swap were cleared.' &&
                sudo fsck -AR -a &&
                sudo journalctl --vacuum-time=2weeks &&
                systemd-analyze &&
                sensors &&
                free
        }
        alias archup=archup
        alias up=archup

        if type reboot >/dev/null 2>&1; then
            reboot() {
                if [ $# -eq 1 ]; then
                    archup keyref
                else
                    archup
                fi
                fup
                archback
                sudo reboot && exit
            }
            alias reboot=reboot
        fi

        if type shutdown >/dev/null 2>&1; then
            shutdown() {
                if [ $# -eq 1 ]; then
                    archup keyref
                else
                    archup
                fi
                fup
                archback
                sudo shutdown now && exit
            }
            alias shutdown=shutdown
        fi
    elif type apt-get >/dev/null 2>&1; then
        aptup() {
            kpangoup
            sudo du -sh /var/cache/apt/archives
            sudo rm -rf /var/cache/apt /var/lib/apt/lists/*
            sudo mkdir -p /var/cache/apt/archives/partial
            sudo apt-key adv --refresh-keys --keyserver keyserver.ubuntu.com
            sudo apt-key list | awk -F"/" '/expired:/{print $2}' | xargs -I {} sudo apt-key del {}
            echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
            echo 'APT::Install-Recommends "false";' >/etc/apt/apt.conf.d/no-install-recommends
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y clean
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y update
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y clean
            sudo dpkg-reconfigure -f noninteractive tzdata
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge
            sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoclean --purge
            sudo du -sh /var/cache/apt/archives
            sudo rm -rf /var/cache/apt /var/lib/apt/lists/*
            sudo mkdir -p /var/cache/apt/archives/partial
            sudo update-alternatives --set cc $CC
            sudo update-alternatives --set c++ $CXX
            sudo systemctl daemon-reload
        }
        alias aptup=aptup
        alias up=aptup
    fi

    if type gpg >/dev/null 2>&1; then
        backup_dir=$HOME/gpgbackup
        gpgbackup() {
            sudo rm -rf $backup_dir
            mkdir -p $backup_dir
            gpg -a --export $1 >$backup_dir/$GIT_USER-public.key
            gpg -a --export-secret-keys $1 >$backup_dir/$GIT_USER-secret.key
            gpg --export-ownertrust >$backup_dir/$GIT_USER-ownertrust.txt
            sudo chmod -R 777 $backup_dir
            sudo chown -R $USER $backup_dir
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
            gpg --import $backup_dir/$GIT_USER-secret.key
            gpg --import-ownertrust $backup_dir/$GIT_USER-ownertrust.txt
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
        checkcountry() {
            if [ $# -eq 1 ]; then
                echo "$TRACECMD $TRACE_ARGS $1"
                sudo $TRACECMD $TRACE_ARGS $1 |
                    rg -wo -e '[0-9]+(\.[0-9]+){3}' |
                    xargs -I {} whois {} |
                    rg -i country |
                    awk '{print $(NF)}' |
                    sort | uniq
            else
                echo "invalid argument, Domain or IP is required"
            fi
        }
        alias ccnt=checkcountry
    fi

    if type wakeonlan >/dev/null 2>&1; then
        alias p1up="wakeonlan -p 9 -i 10.0.0.255 48:2a:e3:8c:80:90"
        alias trup="wakeonlan -p 9 -i 10.0.0.255 f0:2f:74:d4:37:35"
    fi

    if type tailscale >/dev/null 2>&1; then
        if type ubnt-systool >/dev/null 2>&1; then
            export PATH=/usr/lib/unifi/bin:/usr/share/sensible-utils/bin:/usr/share/ubios-udapi-server/ips/bin:/usr/share/ubios-udapi-server/utm/bin:/usr/share/unifi-core/bin:$PATH
            alias tailup="sudo tailscale up --ssh --reset --advertise-exit-node --advertise-routes=10.0.0.0/24,10.0.1.0/29 --stateful-filtering"
        else
            alias tailup="sudo tailscale up --ssh --reset --accept-routes --stateful-filtering"
        fi
    fi

    if [ -d "$GOPATH/src/github.com/vdaas/vald" ]; then
        valdmanifest() {
            make files
            make helm/schema/all
            make helm/schema/crd/all
            make k8s/manifest/update
            make k8s/manifest/helm-operator/update
            make helm/docs/vald
            make helm/docs/vald-helm-operator
        }
        alias valdmanifest=valdmanifest
        valdup() {
            cd "$GOPATH/src/github.com/vdaas/vald"
            sudo chmod -R 777 $CARGO_HOME
            sudo chmod -R 777 $RUSTUP_HOME
            sudo chown -R $USER $CARGO_HOME
            sudo chown -R $USER $RUSTUP_HOME
            valdmanifest
            make -k update
            make format
            chword $GOPATH/src/github.com/vdaas/vald "interface\{\}" "any"
        }
        alias valdup=valdup
        valddep() {
            cd "$GOPATH/src/github.com/vdaas/vald"
            rm -rf go.mod go.sum &&
                cp hack/go.mod.default go.mod &&
                GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy
            rm -rf hack/go.mod.default2 &&
                cat hack/go.mod.default | head -n 5 >>hack/go.mod.default2 &&
                cat go.sum | awk '{printf "\t%s => %s upgrade\n", $1, $1}' |
                sort -n | uniq | sort -n >>hack/go.mod.default2 &&
                echo ")" >>hack/go.mod.default2
            rm -rf hack/go.mod.default3
            cat hack/go.mod.default | head -n 5 >>hack/go.mod.default3
            cat hack/go.mod.default | rg k8s >>hack/go.mod.default3
            cat hack/go.mod.default | rg opentelemetry >>hack/go.mod.default3
            cat hack/go.mod.default | rg containerd >>hack/go.mod.default3
            echo ")" >>hack/go.mod.default3
            rm -rf /tmp/go.mod /tmp/go.sum &&
                mv go.mod go.sum /tmp &&
                cp hack/go.mod.default3 go.mod &&
                GOPRIVATE=github.com/vdaas/vald,github.com/vdaas/vald/apis go mod tidy &&
                rm -rf hack/go.mod.default3 &&
                cat hack/go.mod.default | head -n 5 >>hack/go.mod.default3 &&
                cat go.sum | awk '{printf "\t%s => %s upgrade\n", $1, $1}' |
                sort -n | uniq | sort -n >>hack/go.mod.default3 &&
                echo ")" >>hack/go.mod.default3 &&
                rm -rf go.mod go.sum &&
                mv /tmp/go.mod /tmp/go.sum .
            vim -d hack/go.mod.default hack/go.mod.default2
            vim -d hack/go.mod.default hack/go.mod.default3
            cd -
        }
        alias valddep=valddep
    fi
    export ZSH_LOADED=1
fi
