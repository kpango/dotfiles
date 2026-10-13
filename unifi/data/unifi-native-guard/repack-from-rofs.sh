#!/bin/bash
# Rebuild a .deb from the pristine firmware lower layer (/mnt/.rofs) — like dpkg-repack
set -e
R=/mnt/.rofs; ADM=$R/var/lib/dpkg; OUT=${OUT:-$(dirname $0)/debs}; mkdir -p $OUT
for P in "$@"; do
  W=$(mktemp -d); mkdir -p $W/DEBIAN
  dpkg-query --admindir=$ADM -s "$P" | grep -vE '^(Status|Config-Version):' > $W/DEBIAN/control
  PFX=$ADM/info/$P; [ -e $PFX.list ] || PFX=$ADM/info/$P:arm64
  for s in preinst postinst prerm postrm conffiles triggers shlibs symbols templates config md5sums; do
    [ -e $PFX.$s ] && cp -a $PFX.$s $W/DEBIAN/$s
  done
  while IFS= read -r f; do
    [ "$f" = "/." ] && continue
    # usrmerge: top-level dir symlinks (/lib -> usr/lib) must stay out of the package
    top=/$(echo "$f" | cut -d/ -f2); if [ -L "$R$top" ]; then f="/usr$f"; [ "$f" = "/usr$top" ] && continue; fi
    if [ -d "$R$f" ] && [ ! -L "$R$f" ]; then mkdir -p "$W$f"; chmod --reference="$R$f" "$W$f"
    elif [ -e "$R$f" ] || [ -L "$R$f" ]; then mkdir -p "$W$(dirname "$f")"; cp -a "$R$f" "$W$f"
    else :; fi
  done < $PFX.list
  dpkg-deb -Zgzip -b $W $OUT/ >/dev/null && echo "built $P"
  rm -rf $W
done
