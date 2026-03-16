#!/bin/bash
#Daniel Kreatsoulas
# port information#!/bin/bash

# Capture the netstat output
netstatOutput=$(netstat -anop)
#netstatOutput=$(netstat -anop | grep udp)
#echo "test"
# Process each line of the netstat output
while IFS= read -r line; do
    # Split the line into fields
    fields=($line)
    protocol=${fields[0]}
    localAddress=${fields[3]}
    foreignAddress=${fields[4]}
    #state=${fields[5]}
    #pid=$(echo ${fields[6]} | cut -d'/' -f1)

    # Filter out unwanted foreign addresses and check the state
    if [[ ! $foreignAddress =~ ^\:\:1 ]] && [[ ! $foreignAddress =~ ^\:\: ]] && [[ ! $foreignAddress =~ ^10\.245 ]] && [[ ! $foreignAddress =~ ^192\.168 ]] && [[ ! $foreignAddress =~ ^127\.0 ]] && [[ $state == "ESTABLISHED" ]]; then
    #if [[ $state == "ESTABLISHED" ]]; then
    
        # Extract the foreign IP without the port number
        foreignIP=$(echo $foreignAddress | sed 's/:.*//')

        # Resolve the FQDN
        fqdn=$(getent hosts $foreignIP | awk '{ print $2 }')
        if [[ -z "$fqdn" ]]; then
            fqdn="N/A"
        fi

        # Output the results in a structured format
        #echo "Protocol: $protocol"
        echo "LocalAddress: $localAddress"
        echo "ForeignAddress: $foreignAddress"
        echo "FQDN: $fqdn"
       # echo "State: $state"
        #echo "PID: $pid"
        #echo
    fi
done <<< "$netstatOutput"

