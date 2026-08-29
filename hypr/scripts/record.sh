#!/bin/sh
mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
qs ipc call pill quickRecord "$mon"
