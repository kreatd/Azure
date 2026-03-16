# Daniel Kreatsoulas
# gather port information
$netstatOutput = netstat -ano # | Select-String "TCP"
$netstatOutput | ForEach-Object {
    $fields = $_ -split "\s+"
    $foreignAddress = $fields[3]
    $state = $fields[4]
    if ($foreignAddress -notmatch "^\[::1\]" -and $foreignAddress -notmatch "^\[::\]" -and $foreignAddress -notmatch "^10\.245" -and $foreignAddress -notmatch "^192\.168" -and $foreignAddress -notmatch "^127\.0" -and $state -eq "ESTABLISHED") {
         $foreignIP = $foreignAddress -replace ":\d+$", ""  # Remove the port number
        try {
            $fqdn = (Resolve-DnsName $foreignIP -ErrorAction SilentlyContinue).NameHost
            if($fqdn){
            $address_split = $ForeignAddress.split(":")[0]
            $port_split = $ForeignAddress.split(":")[1]
            $test_connection = test-netconnection -computer $address_split -port $port_split
            [PSCustomObject]@{
            Protocol      = $fields[1]
            LocalAddress  = $fields[2]
            ForeignAddress = $fields[3]
            FQDN            = $fqdn
            ConnectionSucceeded = $test_connection.TcpTestSucceeded
            #State          = $fields[4]
            #PID            = $fields[5]
            }
        }
        } catch {
            $fqdn = "N/A"
        }

    }
}

