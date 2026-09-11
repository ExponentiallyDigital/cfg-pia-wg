#!/bin/bash
#
# Parse vpnc_clientlist NVRAM string into indexed entries with field labels.
#
# Usage:
#   ./read-vpnc_clientlist.sh  # Reads from `nvram get vpnc_clientlist`
#   cat vpnc_clientlist.txt | ./read-vpnc_clientlist.sh
#   echo 'pia-aus_melbourne>WireGuard>...' | ./read-vpnc_clientlist.sh
#   ./read-vpnc_clientlist.sh 'pia-aus_melbourne>WireGuard>...'

if [ -n "$1" ]; then
    input="$1"
elif [ ! -t 0 ]; then
    input=$(cat)
else
    input=$(nvram get vpnc_clientlist 2>/dev/null)
fi

if [ -z "$input" ]; then
    exit 0
fi

printf "%s\n" "$input" | awk '
BEGIN {
    FS = ">"
    RS = "<"
    labels[1] = "descr ----"
    labels[2] = "protocol -"
    labels[3] = "slot -----"
    labels[4] = "username -"
    labels[5] = "pwd ------"
    labels[6] = "state ----"
    labels[7] = "vpnc_idx -"
    labels[8] = "region ---"
    labels[9] = "con type -"
    labels[10] = "tunnel --"
    labels[11] = "wan_idx -"
    labels[12] = "source --"
}
{
    gsub(/[\r\n]+$/, "")
    if (length($0) == 0) next

    if (count > 0) print ""
    count++

    for (i = 1; i <= NF; i++) {
        lbl = (i in labels) ? labels[i] : "unknown"
        tag = "[" i " " lbl "]"
        tabs = (length(tag) < 8) ? "\t\t" : "\t"
        print tag tabs $i
    }
}
END {
    if (count > 0) print ""
}
'