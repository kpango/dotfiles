#!/usr/bin/zsh

stty stop undef
stty start undef

setopt no_global_rcs
if [ -x /usr/libexec/path_helper ]; then
    PATH=""
    eval "$(/usr/libexec/path_helper -s)"
fi

# 環境変数
export LANG=en_US.UTF-8
export MANLANG=ja_JP.UTF-8
export LC_TIME=en_US.UTF-8

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export SHELL=$(which zsh)

export CPUCORES="$(getconf _NPROCESSORS_ONLN)"
export TERMCMD="urxvtc -e $SHELL"

#プログラミング環境構築
export XDG_CONFIG_HOME=$HOME/.config
export NVIM_HOME=$XDG_CONFIG_HOME/nvim
export XDG_DATA_HOME=$NVIM_HOME/log
export NVIM_LOG_FILE_PATH=$XDG_DATA_HOME
export NVIM_TUI_ENABLE_TRUE_COLOR=1

#GO
export GOPATH=/go
export CGO_ENABLED=1
export GO111MODULE=on
export GOBIN=$GOPATH/bin
export GO15VENDOREXPERIMENT=1
export NVIM_GO_LOG_FILE=$XDG_DATA_HOME/go
export CGO_CFLAGS="-g -Ofast -march=native"
export CGO_CPPFLAGS="-g -Ofast -march=native"
export CGO_CXXFLAGS="-g -Ofast -march=native"
export CGO_FFLAGS="-g -Ofast -march=native"
export CGO_LDFLAGS="-g -Ofast -march=native"

export GCLOUD_PATH="/google-cloud-sdk"

export PYTHON_CONFIGURE_OPTS="--enable-shared"

if type nvim >/dev/null 2>&1; then
    export VIM=$(which nvim)
    export VIMRUNTIME=/usr/share/nvim/runtime
else
    export VIM=$(which vim)
    export VIMRUNTIME=/usr/share/vim/vim*
fi

export EDITOR=$VIM
export VISUAL=$VIM
export PAGER=$(which less)
export SUDO_EDITOR=$EDITOR

if type go >/dev/null 2>&1; then
    export GOROOT="$(go env GOROOT)"
    export GOOS="$(go env GOOS)"
    export GOARCH="$(go env GOARCH)"
fi

export TERM="tmux-256color"
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/share/npm/bin:/usr/local/go/bin:/opt/local/bin:$GOBIN:/root/.cargo/bin:$GCLOUD_PATH/bin:$PATH"

export ZPLUG_HOME=$HOME/.zplug

if [ -e $ZPLUG_HOME/repos/zsh-users/zsh-completions ]; then
    fpath=($ZPLUG_HOME/repos/zsh-users/zsh-completions/src $fpath)
fi

if type zplug >/dev/null 2>&1; then
    if zplug check junegunn/fzf; then
        # export FZF_DEFAULT_COMMAND='rg --files --hidden --smartcase --glob "!.git/*"'
        export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
        export FZF_DEFAULT_OPTS='--height 40% --reverse --border'
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

########################################
#Zplug Settings
if [[ -f ~/.zplug/init.zsh ]]; then
    source "$HOME/.zplug/init.zsh"

    zplug "junegunn/fzf", as:command, use:bin/fzf-tmux
    zplug "junegunn/fzf-bin", as:command, from:gh-r, rename-to:fzf
    zplug "zchee/go-zsh-completions"
    zplug "zsh-users/zsh-autosuggestions"
    zplug "zsh-users/zsh-completions", as:plugin, use:"src"
    zplug "zsh-users/zsh-history-substring-search"
    zplug "zsh-users/zsh-syntax-highlighting", defer:2
    zplug "superbrothers/zsh-kubectl-prompt", as:plugin, from:github, use:"kubectl.zsh"
    zplug "greymd/tmux-xpanes"
    zplug "felixr/docker-zsh-completion"
    # zplug "superbrothers/zsh-kubectl-prompt", as:plugin, from:github, use:"kubectl.zsh"

    if ! zplug check --verbose; then
        zplug install
    fi

    zplug load
else
    rm -rf $ZPLUG_HOME
    git clone https://github.com/zplug/zplug $ZPLUG_HOME
    source "$HOME/.zshrc"
    return 0
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
export PROMPT_COMMAND='hcmd=$(history 1); hcmd="${hcmd# *[0-9]*  }"; if [[ ${hcmd%% *} == "cd" ]]; then pwd=$OLDPWD; else pwd=$PWD; fi; hcmd=$(echo -e "cd $pwd && $hcmd"); history -s "$hcmd"'

# プロンプト
PROMPT="%F{045}%/ $ %f"
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
zstyle ':completion:*:default' list-prompt '%S%M matches%s'
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*:descriptions' format ' %F{yellow}-- %d --%f'
zstyle ':completion:*:functions' ignored-patterns '(_*|pre(cmd|exec)|prompt_*)'
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

########################################
# vcs_info
autoload -Uz vcs_info
autoload -Uz add-zsh-hook

zstyle ':vcs_info:*' formats '(%s)-[%b]'
zstyle ':vcs_info:*' actionformats '%F{red}(%s)-[%b|%a]%f'

_update_vcs_info_msg() {
    LANG=en_US.UTF-8
    # RPROMPT="%F{green}${vcs_info_msg_0_} %{$fg[blue]%}($ZSH_KUBECTL_PROMPT)%{$reset_color%} %F{gray}[%D{%Y-%m-%d %H:%M:%S}]"
    RPROMPT="%F{046}${vcs_info_msg_0_} %F{102}[%D{%Y-%m-%d %H:%M:%S}]"
}
add-zsh-hook precmd _update_vcs_info_msg

########################################
# オプション
setopt auto_cd         # ディレクトリ名だけでcdする
setopt auto_list       # 補完候補を一覧表示
setopt auto_menu       # 補完候補が複数あるときに自動的に一覧表示する
setopt auto_param_keys # カッコの対応などを自動的に補完
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
bindkey '^R' history-incremental-pattern-search-backward

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
    alias dls='docker ps'
    alias dsh='docker run -it '
    [ -f $HOME/.aliases ] && source $HOME/.aliases
fi

alias open="xdg-open"

if type xsel >/dev/null 2>&1; then
    alias pbcopy="xsel --clipboard --input"
    alias pbpaste="xsel --clipboard --output"
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
    gfr() {
        git fetch --prune
        git reset --hard origin/$(tb)
        git branch -r --merged master | grep -v -e master -e develop | sed -e 's% *origin/%%' | xargs -I% git push --delete origin %
        git fetch --prune
        git reset --hard origin/$(tb)
        git branch --merged master | grep -vE '^\*|master$|develop$' | xargs -I % git branch -d %
    }
    alias gfr=gfr
    gfrs() {
        gfr
        git submodule foreach git pull origin master
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
    alias gedit="$EDITOR $HOME/.gitconfig"
    git-remote-add-merge() {
        git remote add upstream $1
        git fetch upstream
        git merge upstream/master
    }
    alias grfa=git-remote-add-merge
    git-remote-merge() {
        git fetch upstream
        git merge upstream/master
    }
    alias grf=git-remote-merge
fi

if type rg >/dev/null 2>&1; then
    alias grep=rg
fi

if type go >/dev/null 2>&1; then
    go-get() {
        rm -rf $GOPATH/src/$1
        go get -u -f -v -fix $1
        go install $1
    }

    goup() {
        mv $GOPATH/src/github.com/kpango \
            $GOPATH/src/github.com/azamasu \
            $GOPATH/src/github.com/parheliondb \
            $GOPATH/src/github.com/yahoojapan \
            $GOPATH/src/github.com/vdaas \
            $HOME/
        rm -rf "$GOPATH/bin" "$GOPATH/pkg" "$GOPATH/cache" \
            "$GOPATH/src/github.com" \
            "$GOPATH/src/golang.org" \
            "$GOPATH/src/google.golang.org" \
            "$GOPATH/src/gopkg.in" \
            "$GOPATH/src/code.cloudfoundry.org" \
            "$GOPATH/src/sourcegraph.com" \
            "$GOPATH/src/honnef.co" \
            "$GOPATH/src/sigs.k8s.io"

        go get -u \
            github.com/cweill/gotests/... \
            github.com/davidrjenni/reftools/cmd/fillstruct \
            github.com/derekparker/delve/cmd/dlv \
            github.com/dominikh/go-tools/cmd/keyify \
            github.com/fatih/gomodifytags \
            github.com/fatih/motion \
            github.com/gohugoio/hugo \
            github.com/golang/dep/... \
            github.com/golangci/golangci-lint/cmd/golangci-lint \
            github.com/josharian/impl \
            github.com/jstemmer/gotags \
            github.com/kisielk/errcheck \
            github.com/klauspost/asmfmt/cmd/asmfmt \
            github.com/koron/iferr \
            github.com/mattn/efm-langserver/cmd/efm-langserver \
            github.com/motemen/ghq \
            github.com/motemen/go-iferr/cmd/goiferr \
            github.com/nsf/gocode \
            github.com/orisano/dlayer \
            github.com/orisano/minid \
            github.com/pwaller/goimports-update-ignore \
            github.com/rogpeppe/godef \
            github.com/sugyan/ttygif \
            github.com/uber/go-torch \
            github.com/wagoodman/dive \
            github.com/zmb3/gogetdoc \
            golang.org/x/lint/golint \
            golang.org/x/tools/cmd/goimports \
            golang.org/x/tools/cmd/gopls \
            golang.org/x/tools/cmd/gorename \
            golang.org/x/tools/cmd/guru \
            google.golang.org/grpc \
            honnef.co/go/tools/cmd/keyify \
            sigs.k8s.io/kustomize \
            sourcegraph.com/sqs/goreturns &&
            git clone https://github.com/saibing/bingo.git &&
            cd bingo &&
            GO111MODULE=on go install &&
            git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph &&
            cp /tmp/FlameGraph/flamegraph.pl /go/bin/ &&
            cp /tmp/FlameGraph/stackcollapse.pl /go/bin/ &&
            cp /tmp/FlameGraph/stackcollapse-go.pl /go/bin/

        wait

        rm -rf "$GOPATH/pkg" "$GOPATH/cache" \
            "$GOPATH/src/github.com" \
            "$GOPATH/src/golang.org" \
            "$GOPATH/src/google.golang.org" \
            "$GOPATH/src/gopkg.in" \
            "$GOPATH/src/code.cloudfoundry.org" \
            "$GOPATH/src/sourcegraph.com" \
            "$GOPATH/src/honnef.co" \
            "$GOPATH/src/sigs.k8s.io"

        mkdir -p $GOPATH/src/github.com
        mv $HOME/kpango \
            $HOME/azamasu \
            $HOME/parheliondb \
            $HOME/yahoojapan \
            $HOME/vdaas \
            $GOPATH/src/github.com/

        $VIM main.go +GoInstall +GoInstallBinaries +GoUpdateBinaries +qall

        gocode set autobuild true
        gocode set lib-path $GOPATH/pkg/$GOOS\_$GOARCH/
        gocode set propose-builtins true
        gocode set unimported-packages true
    }

    cover() {
        t=$(mktemp -t cover)
        go test $COVERFLAGS -coverprofile=$t $@ && go tool cover -func=$t && unlink $t
    }
    cover-web() {
        t=$(mktemp -t cover)
        go test $COVERFLAGS -coverprofile=$t $@ && go tool cover -html=$t && unlink $t
    }

    alias goui=goimports-update-ignore
    alias goup=goup

    gobg-build() {
        while true; do
            if [ ! $(git -C $PWD diff --name-only HEAD | wc -l) -eq 0 ]; then
                go build
                ./${PWD##*/}
            fi
            sleep 2
        done
    }
    alias gobg-build=gobg-build

    go-bench() {
        if [ $# -eq 2 ]; then
            go test -count=$1 -run=NONE -bench $2 -benchmem
        else
            go test -count=$1 -run=NONE -bench . -benchmem
        fi
    }
    alias gobench=go-bench
    go-pprof-out() {
        go test -count=10 -run=NONE -bench=. -benchmem -o pprof/test.bin -cpuprofile pprof/cpu.out -memprofile pprof/mem.out
    }
    alias gprofout=go-pprof-out

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

if type exa >/dev/null 2>&1; then
    alias ll='exa -l'
    alias la='exa -aghHliS'
    alias lla='exa -aghHliSm'
    alias tree='exa -T'
    alias ls='exa -G'
    alias lg='la | rg'
else
    alias ll='ls -la'
    alias la='ls -la'
    alias lg='ls -a | rg'
fi

alias mkcd=mkcd
alias ..='\cd ../'
alias ...='\cd ../../'
alias ....='\cd ../../../'
alias ,,='\cd ../'
alias ,,,='\cd ../../'
alias ,,,,='\cd ../../../'

if type fzf >/dev/null 2>&1; then
    if type fzf-tmux >/dev/null 2>&1; then
        if type fd >/dev/null 2>&1; then
            alias s='mkcd $(fd -a -H -t d . | fzf-tmux +m)'
            alias vf='vim $(fd -a -H -t f . | fzf-tmux +m)'
        fi
        if type rg >/dev/null 2>&1; then
            fbr() {
                git branch --all | rg -v HEAD | fzf-tmux +m | sed -e "s/.* //" -e "s#remotes/[^/]*/##" | xargs git checkout
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
    alias sshinit="rm -rf $HOME/.ssh/known_hosts;rm -rf $HOME/.ssh/master_kpango@192.168.2.*;chmod 600 $HOME/.ssh/config"
fi

if type rails >/dev/null 2>&1; then
    alias railskill="kill -9 $(ps aux | grep rails | awk '{print $2}')"
fi

if type tar >/dev/null 2>&1; then
    alias tarzip="tar Jcvf"
    alias tarunzip="tar Jxvf"
fi

if type ranger>/dev/null 2>&1; then
    rng() {
        if [ -n "$RANGER_LEVEL" ]; then
            \ranger $@
        else
            echo "other ranger process already running"
        fi
    }
    alias ranger=rng
    alias rng=rng
fi

alias f="open ."
alias ks="ls "
alias l="ls "
alias rm='rm -rf'
alias find='find'

if type tmux >/dev/null 2>&1; then
    alias tmls='\tmux list-sessions'
    alias tmlc='\tmux list-clients'
    alias tkill='\tmux kill-server'
    alias tmkl='\tmux kill-session'
    alias tmaw='\tmux main-horizontal'
    alias tmuxa='\tmux -2 a -t'
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
        time (zsh -i -c exit)
    done
}
alias zstime=zstime

alias zedit="$EDITOR $HOME/.zshrc"

alias zsback="cp $HOME/.zshrc $HOME/.zshrc.back"

greptext() {
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

chword() {
    if [ $# -eq 3 ]; then
        if type rg >/dev/null 2>&1; then
            rg -l $2 $1 | xargs -t -P $CPUCORES sed -i "" -E "s/$2/$3/g"
        elif type jvgrep >/dev/null 2>&1; then
            jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$' -l -r |
                xargs -t -P $CPUCORES sed -i "" -e "s/$2/$3/g"
        else
            find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
                -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES sed -i "" -e "s/$2/$3/g"
        fi
    elif [ $# -eq 4 ]; then
        if type rg >/dev/null 2>&1; then
            rg -l $2 $1 | xargs -t -P $CPUCORES sed -i "" -E "s$4$2$4$3$4g"
        elif type jvgrep >/dev/null 2>&1; then
            jvgrep -I -R $2 $1 --exclude '(^|\/)\.zsh_history$|(^|\/)\.z$|(^|\/)\.cache|\.emlx$|\.mbox$|\.tar*|(^|\/)\.glide|(^|\/)\.stack|(^|\/)\.anyenv|(^|\/)\.gradle|(^|\/)vendor|(^|\/)Application\ Support|(^|\/)\.cargo|(^|\/)\.config|(^|\/)com\.apple\.|(^|\/)\.idea|(^|\/)\.zplug|(^|\/)\.nimble|(^|\/)build|(^|\/)node_modules|(^|\/)\.git$|(^|\/)\.svn$|(^|\/)\.hg$|\.o$|\.obj$|\.a$|\.exe~?$|(^|\/)tags$' -l -r |
                xargs -t -P $CPUCORES sed -i "" -e "s$4$2$4$3$4g"
        else
            find $1 -type d \( -name 'vendor' -o -name '.git' -o -name '.svn' -o -name 'build' -o -name '*.mbox' -o -name '.idea' -o -name '.cache' -o -name 'Application\ Support' \) \
                -prune -o -type f \( -name '.zsh_history' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '*.a' -o -name '*.out' -o -name '*.pdf' -o -name '*.swp' -o -name '*.bak' -o -name '*.back' -o -name '*.bac' -o -name '*.class' -o -name '*.bin' -o -name '.z' -o -name '*.dat' -o -name '*.plist' -o -name '*.db' -o -name '*.webhistory' \) \
                -prune -o -type f -print0 | xargs -0 -P $CPUCORES grep -rnwe $2 | xargs -t -P $CPUCORES sed -i "" -e "s$4$2$4$3$4g"
        fi
    else
        echo "Not enough arguments"
    fi
}
alias chword=chword

if type bat >/dev/null 2>&1; then
    alias cat=bat
fi

alias :q=exit

alias 600='chmod -R 600'
alias 644='chmod -R 644'
alias 655='chmod -R 655'
alias 755='chmod -R 755'
alias 777='chmod -R 777'

if type nvim >/dev/null 2>&1; then
    alias nvup="nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall"
    nvim-init() {
        rm -rf "$HOME/.config/gocode"
        rm -rf "$HOME/.config/nvim/autoload"
        rm -rf "$HOME/.config/nvim/ftplugin"
        rm -rf "$HOME/.config/nvim/log"
        rm -rf "$HOME/.config/nvim/plugged"
        nvup
        rm "$HOME/.nvimlog"
        rm "$HOME/.viminfo"
    }
    alias vedit="$EDITOR $HOME/.config/nvim/init.vim"
    alias nvinit="nvim-init"
    alias vback="cp $HOME/.config/nvim/init.vim $HOME/.config/nvim/init.vim.back"
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

if type thefuck >/dev/null 2>&1; then
    eval $(thefuck --alias --enable-experimental-instant-mode)
fi

if type kubectl >/dev/null 2>&1; then
    kubectl() {
        local kubectl="$(whence -p kubectl 2>/dev/null)"
        [ -z "$_lazy_kubectl_completion" ] && {
            source <("$kubectl" completion zsh)
            complete -o default -F __start_kubectl k
            _lazy_kubectl_completion=1
        }
        "$kubectl" "$@"
    }
    alias kubectl=kubectl
    alias k=kubectl
    alias kpall="k get pods --all-namespaces -o wide"
    alias ksall="k get svc --all-namespaces -o wide"
    alias kiall="k get ingress --all-namespaces -o wide"
    alias knall="k get namespace -o wide"
    alias kdall="k get deployment --all-namespaces -o wide"
    # source <(kubectl completion zsh);
fi

if type nmcli >/dev/null 2>&1; then
    nmcliwifi() {
        if [ $# -eq 2 ]; then
            nmcli d
            nmcli radio wifi
            nmcli device wifi list
            sudo nmcli c add type wifi ifname $(nmcli d | grep wifi | head -1 | awk '{print $1}') con-name $1 ssid $1
            sudo nmcli c mod $1 connection.autoconnect yes
            sudo nmcli c mod $1 wifi-sec.key-mgmt wpa-psk
            sudo nmcli c mod $1 wifi-sec.psk-flags 0
            sudo nmcli c mod $1 wifi-sec.psk $2
            nmcli c up $1
        else
            echo "invalid argument, SSID and PSK is required"
        fi
    }
fi

# [ tmux has-session >/dev/null 2>&1 ] && if [ -z "${TMUX}" ]; then
if type tmux >/dev/null 2>&1; then
    if [ -z $TMUX ]; then
        ID="$(tmux ls | grep -vm1 attached | cut -d: -f1)" # get the id of a deattached session
        if [[ -z $ID ]]; then # if not available create a new one
            tmux -2 new-session
            source-file ~/.tmux/new-session
        else
            tmux -2 attach-session -t "$ID" # if available attach to it
        fi
    fi
fi
