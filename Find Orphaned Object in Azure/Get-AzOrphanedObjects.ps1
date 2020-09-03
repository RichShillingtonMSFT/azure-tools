<#
.SYNOPSIS
    Script to find orphaned object in Azure

.DESCRIPTION
    This script will look for object not in use in Azure and export the list to a CSV File
    It will find Public IPs, NICs, NSGs, Powered Off VMs & Disks

.PARAMETER FileSaveLocation
    Specify the output location for the CSV File
    Example: 'C:\Temp'
    Default location is \UserProfile\Documents\

.EXAMPLE
    .\Get-AzOrphanedObjects.ps1 -FileSaveLocation 'C:\Temp' -AllSubscriptions
#>
[CmdletBinding()]
param
(
	# Specify the output location for the CSV File
	[Parameter(Mandatory=$false,HelpMessage="Specify the output location for the CSV File. Example C:\Temp")]
    [String]$FileSaveLocation = "$env:USERPROFILE\Documents\",
    
    # If this is true, this script will go through all the subscriptions you have access to
    [Switch]$AllSubscriptions
)

# Set verbose preference
$VerbosePreference = 'Continue'

# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

If ($AllSubscriptions)
{
    $Subscriptions = Get-AzSubscription | Where-Object {$_.Name -ne "Access to Azure Active Directory"}
}
else
{
    $Subscriptions = Get-AzSubscription | Where-Object {$_.Name -ne "Access to Azure Active Directory"}
    if ($Subscriptions.Count -gt '1')
    {
        $Subscriptions = $Subscriptions | Out-GridView -Title "Please Select the Subscriptions to scan." -PassThru
    }
}

# Set Counter For Orphaned Objects
[Int]$OrphanedObjectsCount = '0'

# Create Data Table Structure
Write-Output 'Creating DataTable Structure'
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("ResourceType","string") | Out-Null
$DataTable.Columns.Add("ResourceGroupName","string") | Out-Null
$DataTable.Columns.Add("ResourceName","string") | Out-Null
$DataTable.Columns.Add("CreationTime","DateTime") | Out-Null
$DataTable.Columns.Add("VMSize","string") | Out-Null
$DataTable.Columns.Add("VMOperatingSystem","string") | Out-Null
$DataTable.Columns.Add("Subscription","string") | Out-Null

foreach ($Subscription in $Subscriptions)
{
    Set-AzContext $Subscription | Out-Null
    Write-Verbose "Checking Subscription $($Subscription.Name)"

    # Get Azure Disks That Are Not Managed
    Write-Verbose 'Getting Azure Disks That Are Not Attached To A VM. Please Wait..'
    $AzDisks = Get-AzDisk | Where-Object {$_.ManagedBy -eq $null}
    if ($AzDisks.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzDisks.Count) Disks That Are Not Managed."
        foreach ($AzDisk in $AzDisks)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzDisk.Type)
            $NewRow.ResourceGroupName = $($AzDisk.ResourceGroupName)
            $NewRow.ResourceName = $($AzDisk.Name)
            $NewRow.CreationTime = $($AzDisk.TimeCreated)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Disks That Are Not Managed.'
    }

    # Get Azure Public IP Addresses That Are Not In Use
    Write-Verbose 'Getting Azure Public IP Addresses That Are Not In Use. Please Wait..'
    $AzPublicIPAddresses = Get-AzPublicIpAddress | Where-Object {$_.IpConfiguration -eq $null}
    if ($AzPublicIPAddresses.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzPublicIPAddresses.Count) Public IP Addresses That Are Not In Use."
        foreach ($AzPublicIPAddress in $AzPublicIPAddresses)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzPublicIPAddress.Type)
            $NewRow.ResourceGroupName = $($AzPublicIPAddress.ResourceGroupName)
            $NewRow.ResourceName = $($AzPublicIPAddress.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Public IP Addresses'
    }

    # Get Azure Network Interfaces That Are Not In Use
    Write-Verbose 'Getting Azure Network Interfaces That Are Not In Use. Please Wait..'
    $AzNetworkInterfaces = Get-AzNetworkInterface |  Where-Object {$_.VirtualMachine -eq $null}
    if ($AzNetworkInterfaces.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzNetworkInterfaces.Count) Network Interfaces That Are Not In Use."
        foreach ($AzNetworkInterface in $AzNetworkInterfaces)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzNetworkInterface.Type)
            $NewRow.ResourceGroupName = $($AzNetworkInterface.ResourceGroupName)
            $NewRow.ResourceName = $($AzNetworkInterface.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Network Interfaces'
    }

    # Get Azure Network Security Groups That Are Not In Use
    Write-Verbose 'Getting Azure Network Security Groups That Are Not In Use. Please Wait..'
    $AzNetworkSecurityGroups = Get-AzNetworkSecurityGroup | Where-Object {$_.subnets.id -eq $null -and $_.networkinterfaces.id -eq $null}
    if ($AzNetworkSecurityGroups.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzNetworkSecurityGroups.Count) Network Security Groups That Are Not In Use."
        foreach ($AzNetworkSecurityGroup in $AzNetworkSecurityGroups)
        {
            $NewRow = $DataTable.NewRow()
            $NewRow.ResourceType = $($AzNetworkSecurityGroup.Type)
            $NewRow.ResourceGroupName = $($AzNetworkSecurityGroup.ResourceGroupName)
            $NewRow.ResourceName = $($AzNetworkSecurityGroup.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Network Security Groups.'
    }

    # Get Azure Virtual Machines That Are Powered Off
    Write-Verbose 'Getting Azure Virtual Machines That Are Powered Off. Please Wait..'
    $AzVirtualMachines = Get-AzVM -Status | Where-Object {$_.PowerState -eq "VM deallocated"}
    if ($AzVirtualMachines.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzVirtualMachines.Count) Virtual Machines That Are Powered Off." 
        foreach ($AzVirtualMachine in $AzVirtualMachines)
        {
            Write-Verbose "Getting Virtual Machine Information for $($AzVirtualMachine.Name)"
            $AzVMInfo = Get-AzVM -Name $AzVirtualMachine.Name -ResourceGroupName $AzVirtualMachine.ResourceGroupName -DisplayHint Expand
        
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzVMInfo.Type)
            $NewRow.ResourceGroupName = $($AzVirtualMachine.ResourceGroupName)
            $NewRow.ResourceName = $($AzVirtualMachine.Name)
            $NewRow.VMSize = $($AzVMInfo.HardwareProfile.VmSize)
            $NewRow.VMOperatingSystem = $($AzVMInfo.StorageProfile.ImageReference.Sku)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Virtual Machines That Are Powered Off.'
    }
}

if ($OrphanedObjectsCount -ge '1')
{
    # Export the results to CSV file
    $CSVFileName = 'AzOrphanedObjectsReport ' + $(Get-Date -f yyyy-MM-dd) + '.csv'
    $DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
    Write-Output "I have Found $OrphanedObjectsCount Orphaned Objects. Please See $FileSaveLocation\$CSVFileName For More Details"
}

if ($OrphanedObjectsCount -eq '0')
{
    Write-Output "I Have Found $OrphanedObjectsCount Orphaned Objects In Your Azure Subscription!"
    Write-Output "You Have Done A Fantastic Job Keeping This Subscription Clean. Keep Up The Good Work!"
}

Write-Verbose 'Script processing complete.'