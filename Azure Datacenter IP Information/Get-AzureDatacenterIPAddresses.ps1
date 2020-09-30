<#
.SYNOPSIS
    Gather Azure Datacenter IP Endpoint Information

.DESCRIPTION
    This script will download the Azure Datacenter IP List files
    It will then prompt you to select a single region or multiple regions
    You can then select a single or multiple services
    The script will then parse the JSON files and collect the relevant IP address information
    Finally this will export the IPv4 & IPv6 data to text files

.PARAMETER OutputPath
    Specify the output path for the exported files. Example: C:\Exports

.PARAMETER IncludeGlobal
    Only exports selected regions and does not include global or non-region specific items.

.EXAMPLE
    .\Get-AzureDatacenterIPAddresses.ps1 -OutputPath 'C:\Exports' -IncludeGlobal

#>[CmdletBinding()]
Param
(
    # Specify the output path for the exported files
    [Parameter(Mandatory=$false,HelpMessage="Specify the output path for the exported files. Example: C:\Exports")]
    [String]$OutputPath = 'C:\Temp\Exports',

    # Only exports selected regions and does not include global or non-region specific items
    [Switch]$IncludeGlobal
)

$URLs = @(
@{Environment = 'AzureCloud';URL = 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519'}
@{Environment = 'USGovernment'; URL = 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=57063'}
)

$TempFileStore = New-Item -Name IPJSONFiles -ItemType Directory -Path $env:TEMP -Force

$Regions = @()
$Services = @()
$ContentVariableList = @()
$AzureServicesSelected = @()

foreach ($URL in $URLs)
{
    $WebRequest = Invoke-WebRequest $($URL.URL) -UseBasicParsing
    $DownloadURL = ($WebRequest.Links | Where-Object {$_.href -like "*.json*"}).href | Select-Object -First 1
    $FileName = $DownloadURL.Split('/') | Select-Object -Last 1
    Invoke-WebRequest -UseBasicParsing -Uri $DownloadURL -OutFile "$($TempFileStore.FullName)\$FileName"
    New-Variable -Name "$($URL.Environment)IPData" -Force
    Get-Content "$($TempFileStore.FullName)\$FileName" | ConvertFrom-Json -OutVariable "$($URL.Environment)IPData"
    $ContentVariableList += "$($URL.Environment)IPData"
}

foreach ($ContentVariable in $ContentVariableList)
{
    $AzureIPData = Get-Variable -Name $ContentVariable
    $RegionInfo = $AzureIPData.value.values.properties | Where-Object {($_.region) -and ($Regions -notcontains $_.region)} | Select-Object region,regionid -Unique
    
    foreach ($Region in $RegionInfo)
    {
        $Regions += New-Object PSObject -Property ([ordered]@{Region=$($Region.region);RegionId=$($Region.regionId)})
    }
}

$RegionsToUse = $Regions | Out-GridView -Title "Please select which regions to include." -PassThru

foreach ($ContentVariable in $ContentVariableList)
{
    $AzureIPData = Get-Variable -Name $ContentVariable
    if ($IncludeGlobal)
    { 
        $Services += $AzureIPData.value.values.properties | Where-Object {($RegionsToUse.RegionId -contains $_.regionId) -or ($_.regionId -eq '0')}
    }
    else
    {
        $Services += $AzureIPData.value.values.properties | Where-Object {$RegionsToUse.RegionId -contains $_.regionId}
    }
}

$ServicesToUse = $Services | Where-Object {$_.systemService} | Select-Object systemService -Unique | Out-GridView -Title "Please select which services to include." -PassThru

foreach ($Service in $Services | Where-Object {($ServicesToUse.systemService -ccontains $_.systemService) -or (!$_.systemService)})
{
    $AzureServicesSelected += $Service
}

$IPv4Pattern = "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}"
$IPv6Pattern = "(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"
$IPv6Addresses = $AzureServicesSelected.addressPrefixes | Select-String -Pattern $IPv6Pattern | Select-Object -Unique
$IPv4Addresses = $AzureServicesSelected.addressPrefixes | Select-String -Pattern $IPv4Pattern | Select-Object -Unique

if (!(Test-Path $OutputPath))
{
    New-Item -Path $OutputPath -ItemType Directory
}

$IPv6Addresses | Out-File -FilePath "$OutputPath\AzureIPv6Addresses.txt"
$IPv4Addresses | Out-File -FilePath "$OutputPath\AzureIPv4Addresses.txt"

Remove-Item $TempFileStore -Force -Recurse