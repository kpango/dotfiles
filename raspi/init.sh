#!/bin/sh

swapoff --all
rm -rf /var/swap
pacman-key --init
pacman-key --populate archlinuxarm
