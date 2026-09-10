#!/bin/sh
set -eu

focused_app_id=$(swaymsg -t get_tree | python3 -c "
import json, sys
def find_focused(node):
    if node.get('focused'):
        return node
    for n in node.get('nodes', []) + node.get('floating_nodes', []):
        r = find_focused(n)
        if r:
            return r
tree = json.load(sys.stdin)
node = find_focused(tree)
print(node.get('app_id', '') if node else '')
")

if [ "$focused_app_id" = "com.mitchellh.ghostty" ]; then
    is_floating=$(swaymsg -t get_tree | python3 -c "
import json, sys
def find_focused(node):
    if node.get('focused'):
        return node
    for n in node.get('nodes', []) + node.get('floating_nodes', []):
        r = find_focused(n)
        if r:
            return r
tree = json.load(sys.stdin)
node = find_focused(tree)
print(node.get('type', '') if node else '')
")
    if [ "$is_floating" = "floating_con" ]; then
        swaymsg 'floating disable'
    else
        swaymsg 'floating enable; resize set 100ppt 100ppt; move position 0 0'
    fi
else
    swaymsg 'fullscreen toggle'
fi
