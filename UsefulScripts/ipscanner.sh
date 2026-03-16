#!/bin/bash
#Daniel Kreatsoulas
# port information#!/bin/bash

netstatOutput=$(netstat -anop)

while IFS= read -r line; do
    # Split the line into fields
    fields=($line)
    protocol=${fields[0]}
    localAddress=${fields[3]}
    foreignAddress=${fields[4]}
    state=${fields[5]}
    #if [[ ! $foreignAddress =~ ^\:\:1 ]] && [[ ! $foreignAddress =~ ^\:\: ]] && [[ ! $foreignAddress =~ ^10\.245 ]] && [[ ! $foreignAddress =~ ^192\.168 ]] && [[ ! $foreignAddress =~ ^127\.0 ]] && [[ $state == "ESTABLISHED" ]]; then
    if [[ ! $foreignAddress =~ ^\:\:1 ]] && [[ ! $foreignAddress =~ ^\:\: ]] && [[ ! $foreignAddress =~ ^192\.168 ]] && [[ ! $foreignAddress =~ ^127\.0 ]] && [[ $state == "ESTABLISHED" ]]; then
        foreignIP=$(echo $foreignAddress | cut -d':' -f1)
        foreignPort=$(echo $foreignAddress | cut -d':' -f2)
    
        fqdn=$(getent hosts $foreignIP | awk '{ print $2 }')
        if [[ -n $fqdn ]]; then

            ncResult=$(nc -zv $foreignIP $foreignPort 2>&1 | grep Connected)
            if [[ -n $ncResult ]]; then
                echo "Protocol: $protocol"
                echo "LocalAddress: $localAddress"
                echo "ForeignAddress: $foreignAddress"
                echo "Connection Status: $ncResult"
                echo "FQDN: $fqdn"
                #echo "State $state"
            else
                echo "Protocol: $protocol"
                echo "LocalAddress: $localAddress"
                echo "ForeignAddress: $foreignAddress"
                echo "Connection Status: Failed to Connect"
                echo "FQDN: $fqdn"
                #echo "State $state"
            fi
        fi
    fi

done <<< "$netstatOutput"
