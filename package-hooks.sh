#!/bin/sh
# XBPS runs this inside the target root after installation or removal.
case "$1" in
    post)
        if [ -x usr/bin/update-desktop-database ] && [ -d usr/share/applications ]; then
            usr/bin/update-desktop-database usr/share/applications || exit 1
        fi
        if [ -x usr/bin/gtk-update-icon-cache ] && [ -d usr/share/icons/hicolor ]; then
            usr/bin/gtk-update-icon-cache -q -f -t usr/share/icons/hicolor || exit 1
        fi
        if [ -x usr/bin/update-mime-database ] && [ -d usr/share/mime ]; then
            usr/bin/update-mime-database usr/share/mime || exit 1
        fi
        ;;
esac
exit 0
