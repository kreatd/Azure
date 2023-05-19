
  
$rgs = get-azresourcegroup

$resourceGroups= [System.Collections.ArrayList]::new()

foreach($rg in $rgs)
{
$marchTotal = Get-AzConsumptionUsageDetail -ResourceGroup $rg.resourcegroupname -StartDate 2023-03-01 -EndDate 2023-03-31 | Select-Object InstanceName, Currency, PretaxCost | Sort-Object -Property PretaxCost -Descending
$marchCostTotal = $marchTotal.pretaxcost | measure-object -sum

$lastYearTotal = Get-AzConsumptionUsageDetail -ResourceGroup $rg.resourcegroupname -StartDate 2022-04-01 -EndDate 2023-03-31 | Select-Object InstanceName, Currency, PretaxCost | Sort-Object -Property PretaxCost -Descending
$lastYearCostTotal = $lastYearTotal.pretaxcost | measure-object -sum

[void]$resourceGroups.Add([PSCustomObject]@{
    'ResourceGroupName' = $rg.resourcegroupname
    'LastYearCost' = $lastYearCostTotal.Sum
    'MarchCost' = $MarchCostTotal.Sum
})
}

$rgs = get-clipboard

$resourceGroups= [System.Collections.ArrayList]::new()

foreach($rg in $rgs)
{
    $marchTotal = Get-AzConsumptionUsageDetail -ResourceGroup $rg -StartDate 2023-03-01 -EndDate 2023-03-31 | Select-Object InstanceName, Currency, PretaxCost | Sort-Object -Property PretaxCost -Descending
    $marchCostTotal = $marchTotal.pretaxcost | measure-object -sum
    
    $lastYearTotal = Get-AzConsumptionUsageDetail -ResourceGroup $rg -StartDate 2022-04-01 -EndDate 2023-03-31 | Select-Object InstanceName, Currency, PretaxCost | Sort-Object -Property PretaxCost -Descending
    $lastYearCostTotal = $lastYearTotal.pretaxcost | measure-object -sum

[void]$resourceGroups.Add([PSCustomObject]@{
    'ResourceGroupName' = $rg
    'LastYearCost' = $lastYearCostTotal.Sum
    'MarchCost' = $MarchCostTotal.Sum
})
}

$rgs = get-clipboard


$resourceGroups= [System.Collections.ArrayList]::new()

foreach($rg in $rgs){
$out=@()
$resources=get-azresource -resourcegroupname $rg | select resourcetype
foreach($res in $resources){
    $out+=$res.resourcetype.split('/')[1].split(' ')
}
$out = $out | select -unique
[void]$resourceGroups.Add([PSCustomObject]@{
    'ResourceGroupName' = $rg
    'ResourceType' = $out -join ','
})
}
