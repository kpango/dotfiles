.PHONY: help

help:
	@printf "Usage: make <target> [VAR=value ...]\n\n"
	@printf "Variables:\n"
	@printf "  MODE              link|copy (default: link)\n"
	@printf "  NIX_HOST_NAME     NixOS host (default: tr)\n"
	@printf "  NIX_TEST_HOSTS    space-separated list of hosts for nix/test/eval\n"
	@printf "  NIX_DOCKER_IMAGE  container image used when nix is not installed\n\n"
	@awk -v GITFILES="$$(git -C "$(ROOTDIR)" ls-files 2>/dev/null | tr '\n' ':')" \
	'BEGIN { \
	    n = split(GITFILES, _f, ":"); \
	    for (i = 1; i <= n; i++) gf[_f[i]] = 1; \
	    desc = ""; prev = ""; sect = ""; hdr = 0; skip = 0; \
	} \
	{ \
	    if (FILENAME != prev) { \
	        prev = FILENAME; desc = ""; hdr = 0; \
	        sect = FILENAME; \
	        gsub(/.*\//, "", sect); \
	        gsub(/\.mk$$/, "", sect); \
	        skip = (sect == "variables" || substr(FILENAME, length(FILENAME) - 1) != "mk"); \
	    } \
	} \
	skip { desc = ""; next } \
	/^## / { \
	    l = substr($$0, 4); \
	    desc = (desc == "") ? l : desc " " l; \
	    next; \
	} \
	/^[a-zA-Z_0-9][a-zA-Z_0-9%:\\/-]*:/ { \
	    if (desc != "") { \
	        cmd = $$1; sub(/:.*/, "", cmd); \
	        if (index(cmd, "%") > 0 && match(desc, /\([^)]+%[^)]*\)/) > 0) { \
	            pat = substr(desc, RSTART + 1, RLENGTH - 2); \
	            pre = substr(pat, 1, index(pat, "%") - 1); \
	            suf = substr(pat, index(pat, "%") + 1); \
	            delete av; m = 0; \
	            for (f in gf) { \
	                if (substr(f, 1, length(pre)) == pre) { \
	                    r = substr(f, length(pre) + 1); \
	                    if (suf == "") { \
	                        sub(/\/.*/, "", r); \
	                        if (r != "") av[r] = 1; \
	                    } else { \
	                        ix = index(r, suf); \
	                        if (ix > 0) { nm = substr(r, 1, ix - 1); if (nm != "" && index(nm, "/") == 0) av[nm] = 1; } \
	                    } \
	                } \
	            } \
	            al = ""; split("", aa); \
	            for (v in av) aa[++m] = v; \
	            for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) if (aa[i] > aa[j]) { t = aa[i]; aa[i] = aa[j]; aa[j] = t; } \
	            for (i = 1; i <= m; i++) al = al (al == "" ? "" : ", ") aa[i]; \
	            if (al != "") sub(/\([^)]+%[^)]*\)/, "(Available: " al ")", desc); \
	        } \
	        if (!hdr) { printf "\n\033[34;01m[%s]\033[0m\n", sect; hdr = 1; } \
	        printf "  \033[32;01m%-38s\033[0m %s\n", cmd, desc; \
	    } \
	    desc = ""; next; \
	} \
	{ desc = "" }' \
	$(MAKELISTS)
	@printf "\n"
