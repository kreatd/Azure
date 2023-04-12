#Set the variables 
$SubscriptionID = ""
$ResourceGroup = ""
$NetInter=""
$VNET = ""
$subnet= ""
$PrivateIP = ""

#You can ignore the publicIP variable if the VM does not have a public IP associated.
#$publicIP =Get-AzPublicIpAddress -Name <the public IP name> -ResourceGroupName  $ResourceGroup

#Log in to the subscription 
#Add-AzAccount
#Select-AzSubscription -SubscriptionId $SubscriptionId 

#Check whether the new IP address is available in the virtual network.
Get-AzVirtualNetwork -Name $VNET -ResourceGroupName $ResourceGroup | Test-AzPrivateIPAddressAvailability -IPAddress $PrivateIP

#Add/Change static IP. This process will change MAC address
$vnet = Get-AzVirtualNetwork -Name $VNET -ResourceGroupName $ResourceGroup

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnet -VirtualNetwork $vnet

$nic = Get-AzNetworkInterface -Name  $NetInter -ResourceGroupName  $ResourceGroup

#Remove the PublicIpAddress parameter if the VM does not have a public IP.
$nic | Set-AzNetworkInterfaceIpConfig -Name ipconfig1 -PrivateIpAddress $PrivateIP -Subnet $subnet -Primary

$nic | Set-AzNetworkInterface