[1mdiff --git i/coc-settings.json w/coc-settings.json[m
[1mindex b6e52b8..e994ca6 100644[m
[1m--- i/coc-settings.json[m
[1m+++ w/coc-settings.json[m
[36m@@ -2,24 +2,49 @@[m
   "languageserver": {[m
     "golang": {[m
       "command": "bingo",[m
[31m-      "args": ["--golist-duration", "0", "--format-style", "goimports", "--cache-style", "on-demand", "-mode", "stdio", "--diagnostics-style=instant"],[m
[31m-      "rootPatterns": ["go.mod", ".vim/", ".git/", ".hg/"],[m
[31m-      "filetypes": ["go"][m
[32m+[m[32m      "args": [[m
[32m+[m[32m        "--golist-duration",[m
[32m+[m[32m        "0",[m
[32m+[m[32m        "--format-style",[m
[32m+[m[32m        "goimports",[m
[32m+[m[32m        "--cache-style",[m
[32m+[m[32m        "on-demand",[m
[32m+[m[32m        "-mode",[m
[32m+[m[32m        "stdio",[m
[32m+[m[32m        "--diagnostics-style=instant"[m
[32m+[m[32m      ],[m
[32m+[m[32m      "rootPatterns": [[m
[32m+[m[32m        "go.mod",[m
[32m+[m[32m        ".vim/",[m
[32m+[m[32m        ".git/",[m
[32m+[m[32m        ".hg/"[m
[32m+[m[32m      ],[m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "go"[m
[32m+[m[32m      ][m
     },[m
     "nix": {[m
       "command": "nix-lsp",[m
[31m-      "filetypes": ["nix"],[m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "nix"[m
[32m+[m[32m      ],[m
       "args": [][m
     },[m
     "dockerfile": {[m
       "command": "docker-langserver",[m
[31m-      "filetypes": ["dockerfile"],[m
[31m-      "args": ["--stdio"][m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "dockerfile"[m
[32m+[m[32m      ],[m
[32m+[m[32m      "args": [[m
[32m+[m[32m        "--stdio"[m
[32m+[m[32m      ][m
     },[m
     "dart": {[m
       "command": "dart_language_server",[m
       "args": [],[m
[31m-      "filetypes": ["dart"],[m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "dart"[m
[32m+[m[32m      ],[m
       "initializationOptions": {},[m
       "settings": {[m
         "dart": {[m
[36m@@ -30,18 +55,22 @@[m
     },[m
     "python": {[m
       "command": "pyls",[m
[31m-      "filetypes": ["python"],[m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "python"[m
[32m+[m[32m      ],[m
       "args": [][m
     },[m
[31m-    "clangd": {[m
[31m-      "command": "clangd",[m
[31m-      "rootPatterns": ["compile_flags.txt", "compile_commands.json", ".vim/", ".git/", ".hg/"],[m
[31m-      "filetypes": ["c", "cpp", "objc", "objcpp"][m
[31m-    },[m
     "efm": {[m
       "command": "efm-langserver",[m
[31m-      "args": ["-c", "$HOME/.config/nvim/efm-lsp-conf.yaml"],[m
[31m-      "filetypes": ["vim", "eruby", "markdown"][m
[32m+[m[32m      "args": [[m
[32m+[m[32m        "-c",[m
[32m+[m[32m        "$HOME/.config/nvim/efm-lsp-conf.yaml"[m
[32m+[m[32m      ],[m
[32m+[m[32m      "filetypes": [[m
[32m+[m[32m        "vim",[m
[32m+[m[32m        "eruby",[m
[32m+[m[32m        "markdown"[m
[32m+[m[32m      ][m
     }[m
   }[m
 }[m
