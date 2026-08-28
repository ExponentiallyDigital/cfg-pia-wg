#!/bin/bash
#
# take an input and split into arrays by ">" and "<" and print each entry with an index
#
# example usage: cat vpnc_clientlist.txt | ./scripts/read-vpnc_clientlist.sh
# example usage: echo 'pia-aus_melbourne>WireGuard>5>>pwd1>1>5>>>0>0>Web<pia-aus>WireGuard>4>>pwd2>1>6>>>0>0>Web' | ./scripts/read-vpnc_clientlist.sh

input=$(cat)

# Split by ">"
IFS='>' read -ra parts <<< "$input"

entry_index=1
first_array=true

for part in "${parts[@]}"; do
    if [[ "$part" == *"<"* ]]; then
        # Split at "<"
        before="${part%<*}"
        after="${part#*<}"
        
        # Print the "before" part as the last entry of current array
        echo "[$entry_index] $before"
        ((entry_index++))
        
        # Blank line between arrays and reset counter
        if [[ "$first_array" == false ]]; then
            echo
        fi
        entry_index=1
        first_array=false
        
        # Print the "after" part as first entry of new array
        echo "[$entry_index] $after"
        ((entry_index++))
    else
        # Regular field - print even if empty
        echo "[$entry_index] $part"
        ((entry_index++))
    fi
done

echo  # trailing blank line