#!/usr/bin/env zsh

# Determine DOTFILES_DIR
export GIT_USER=${GIT_USER:-kpango}
if [ -z "$DOTFILES_DIR" ]; then
	DOTFILE_URL="github.com/$GIT_USER/dotfiles"
	if [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
		export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
	elif (($+commands[ghq])); then
		export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
	else
		export DOTFILES_DIR="$HOME/dotfiles"
	fi
fi

for config_file in "$DOTFILES_DIR/zsh"/*.zsh(N); do
	source "$config_file"
done

(
	unalias -m '*' 2>/dev/null
	for config_file in "$DOTFILES_DIR/zsh"/*.zsh(N); do
		if [[ -f "$config_file" && (! -f "$config_file.zwc" || "$config_file" -nt "$config_file.zwc") ]]; then
			zcompile "$config_file" 2>/dev/null
		fi
	done
	if [[ -f "$HOME/.zshrc" && (! -f "$HOME/.zshrc.zwc" || "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc") ]]; then
		zcompile "$HOME/.zshrc" 2>/dev/null
	fi
	if [[ -f "$HOME/.zcompdump" && (! -f "$HOME/.zcompdump.zwc" || "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc") ]]; then
		zcompile "$HOME/.zcompdump" 2>/dev/null
	fi
) &|
