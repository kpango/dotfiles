FROM golang:1.11-alpine AS go
FROM alpine:edge AS builder

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV HOME /root

ENV PYTHON_VERSION 2.7.15
ENV PYTHON3_VERSION 3.8-dev
ENV RUBY_VERSION 2.6.0-preview2
ENV NODE_VERSION v10.9.0

ENV RUST_SRC_PATH /usr/local/src/rust/src
ENV RUST_BACKTRACE 1
ENV CARGO_HOME $HOME/.cargo

ENV XDG_CONFIG_HOME $HOME/.config
ENV NVIM_HOME $XDG_CONFIG_HOME/nvim
ENV XDG_DATA_HOME $NVIM_HOME/log
ENV NVIM_LOG_FILE_PATH $XDG_DATA_HOME
ENV NVIM_TUI_ENABLE_TRUE_COLOR 1
ENV NVIM_PYTHON_LOG_LEVEL WARNING
ENV NVIM_PYTHON_LOG_FILE $NVIM_LOG_FILE_PATH/nvim.log

COPY --from=go /usr/local/go/bin /usr/bin 

ENV GOPATH /go
ENV PATH $GOPATH/bin:$PATH

WORKDIR $HOME

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/community/ >> /etc/apk/repositories

RUN set -eux; \
    apk update \
    && apk upgrade \
    && apk add --no-cache \
    build-base \
    sudo \
    curl \
    gcc \
    git \
    bash \
    zsh \
    neovim \
    tmux \
    rust \
    cargo \
    perl \
    zlib-dev \
    libffi-dev \
    libressl-dev \
    readline-dev \
    linux-headers \
    && rm -rf /var/cache/apk/* /tmp/* /etc/apk/cache/* \
    && git config --global url."https://".insteadOf git://

ENV SHELL /bin/zsh

RUN sed -i -e "s/bin\/ash/bin\/zsh/" /etc/passwd

RUN git clone https://github.com/riywo/anyenv "$HOME/.anyenv"

WORKDIR $HOME/.anyenv/plugins
RUN git clone https://github.com/znz/anyenv-update.git "$HOME/.anyenv/plugins/anyenv-update" \
    && git clone git://github.com/aereal/anyenv-exec.git "$HOME/.anyenv/plugins/anyenv-exe" \
    && git clone https://github.com/znz/anyenv-git.git "$HOME/.anyenv/plugins/anyenv-git"

WORKDIR $HOME
RUN "$HOME/.anyenv/bin/anyenv" update \
    && "$HOME/.anyenv/bin/anyenv" git gc \
    && "$HOME/.anyenv/bin/anyenv" exec --version

ENV PATH $HOME/.anyenv/bin:$PATH

RUN zsh -c "eval $($HOME/.anyenv/bin/anyenv init - --no-rehash zsh)" \
    && git clone https://github.com/riywo/ndenv $HOME/.anyenv/envs/ndenv \
    && git clone https://github.com/riywo/node-build.git $HOME/.anyenv/envs/ndenv/plugins/node-build \
    && git clone https://github.com/pyenv/pyenv $HOME/.anyenv/envs/pyenv \
    && git clone git://github.com/yyuu/pyenv-virtualenv.git "$HOME/.anyenv/envs/pyenv/plugins/pyenv-virtualenv" \
    && git clone https://github.com/yyuu/pyenv-pip-rehash.git "$HOME/.anyenv/envs/pyenv/plugins/pyenv-pip-rehash" \
    && git clone https://github.com/rbenv/rbenv $HOME/.anyenv/envs/rbenv \
    && git clone https://github.com/sstephenson/ruby-build.git $HOME/.anyenv/envs/rbenv/plugins/ruby-build \
    && git clone git://github.com/tpope/rbenv-communal-gems.git $HOME/.anyenv/envs/rbenv/plugins/rbenv-communal-gems \
    && zsh -c "eval $($HOME/.anyenv/envs/ndenv/bin/ndenv init - --no-rehash zsh)" \
    && zsh -c "eval $($HOME/.anyenv/envs/pyenv/bin/pyenv init - --no-rehash zsh)" \
    && zsh -c "eval $($HOME/.anyenv/envs/rbenv/bin/rbenv init - --no-rehash zsh)" \
    && zsh -c "eval $($HOME/.anyenv/bin/anyenv init - --no-rehash zsh)"

ENV PATH $HOME/.anyenv/bin:$HOME/.anyenv/libexec:$PATH

ENV PYENV_ROOT $HOME/.anyenv/envs/pyenv
ENV PYTHON_CONFIGURE_OPTS --enable-shared
WORKDIR $HOME/.anyenv/envs/pyenv
RUN "$HOME/.anyenv/envs/pyenv/bin/pyenv" install $PYTHON_VERSION \
    && "$HOME/.anyenv/envs/pyenv/bin/pyenv" install $PYTHON3_VERSION \
    && "$HOME/.anyenv/envs/pyenv/bin/pyenv" global $PYTHON_VERSION $PYTHON3_VERSION \
    && "$HOME/.anyenv/envs/pyenv/shims/pip" install --upgrade pip \
    && "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade pip \
    && "$HOME/.anyenv/envs/pyenv/shims/pip3" install --upgrade pip \
    && "$HOME/.anyenv/envs/pyenv/shims/pip" install --upgrade sexpdata websocket-client neovim vim-vint \
    && "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade sexpdata websocket-client neovim vim-vint \
    && "$HOME/.anyenv/envs/pyenv/shims/pip2" install --upgrade sexpdata websocket-client neovim vim-vint

ENV RBENV_ROOT $HOME/.anyenv/envs/rbenv
WORKDIR $HOME/.anyenv/envs/rbenv
RUN $HOME/.anyenv/envs/rbenv/bin/rbenv install $RUBY_VERSION \
    && $HOME/.anyenv/envs/rbenv/bin/rbenv global $RUBY_VERSION \
    && ln -sfv $HOME/.anyenv/envs/rbenv/shims/ruby /usr/bin/ruby \
    && ln -sfv $HOME/.anyenv/envs/rbenv/shims/gem /usr/bin/gem \
    && $HOME/.anyenv/envs/rbenv/shims/gem install --no-rdoc --no-ri --no-document etc json rubocop neovim 

ENV NDENV_ROOT $HOME/.anyenv/envs/ndenv
WORKDIR $HOME/.anyenv/envs/ndenv
RUN $HOME/.anyenv/envs/ndenv/bin/ndenv install $NODE_VERSION \
    && $HOME/.anyenv/envs/ndenv/bin/ndenv global $NODE_VERSION \
    && $HOME/.anyenv/envs/ndenv/bin/ndenv versions

# RUN $HOME/.anyenv/envs/ndenv/shims/npm install -g less jsctags jshint htmlhint js-beautify eslint eslint_d babel-eslint eslint-config-airbnb eslint-plugin-import eslint-plugin-react eslint-plugin-jsx-a11y source-map-support webpack csslint stylelint pug-cli markdown-pdf

WORKDIR $HOME/.config/nvim/plugged/vim-plug
RUN git clone https://github.com/junegunn/vim-plug.git ~/.config/nvim/plugged/vim-plug/autoload

WORKDIR $HOME
RUN git clone https://github.com/kpango/dotfiles \
    && cp $HOME/dotfiles/arch/zshrc $HOME/.zshrc

WORKDIR $HOME/.config/nvim
RUN cp $HOME/dotfiles/init.vim .
WORKDIR $HOME/.config/nvim/colors
RUN cp $HOME/dotfiles/monokai.vim .
    

WORKDIR $HOME

RUN nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall

RUN zsh

ENV SHELL /bin/zsh
