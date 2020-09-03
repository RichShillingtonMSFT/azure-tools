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
    .\Get-AzureRMOrphanedObjects.ps1 -FileSaveLocation 'C:\Temp' -AllSubscriptions
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
$Environments = Get-AzureRmEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

#region Connect to Azure
try
{
    Connect-AzureRmAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

If ($AllSubscriptions)
{
    $Subscriptions = Get-AzureRmSubscription | Where-Object {$_.Name -ne "Access to Azure Active Directory"}
}
else
{
    $Subscriptions = Get-AzureRmSubscription | Where-Object {$_.Name -ne "Access to Azure Active Directory"}
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
    Select-AzureRmSubscription $Subscription | Out-Null
    Write-Verbose "Checking Subscription $($Subscription.Name)"

    # Get Azure RM Disks That Are Not Managed
    Write-Verbose 'Getting Azure RM Disks That Are Not Attached To A VM. Please Wait..'
    $AzureRMDisks = Get-AzureRmDisk | Where-Object {$_.ManagedBy -eq $null}
    if ($AzureRMDisks.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzureRMDisks.Count) Disks That Are Not Managed."
        foreach ($AzureRMDisk in $AzureRMDisks)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzureRMDisk.Type)
            $NewRow.ResourceGroupName = $($AzureRMDisk.ResourceGroupName)
            $NewRow.ResourceName = $($AzureRMDisk.Name)
            $NewRow.CreationTime = $($AzureRMDisk.TimeCreated)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Disks That Are Not Managed.'
    }

    # Get Azure RM Public IP Addresses That Are Not In Use
    Write-Verbose 'Getting Azure RM Public IP Addresses That Are Not In Use. Please Wait..'
    $AzureRMPublicIPAddresses = Get-AzureRmPublicIpAddress | Where-Object {$_.IpConfiguration -eq $null}
    if ($AzureRMPublicIPAddresses.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzureRMPublicIPAddresses.Count) Public IP Addresses That Are Not In Use."
        foreach ($AzureRMPublicIPAddress in $AzureRMPublicIPAddresses)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzureRMPublicIPAddress.Type)
            $NewRow.ResourceGroupName = $($AzureRMPublicIPAddress.ResourceGroupName)
            $NewRow.ResourceName = $($AzureRMPublicIPAddress.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Public IP Addresses'
    }

    # Get Azure RM Network Interfaces That Are Not In Use
    Write-Verbose 'Getting Azure RM Network Interfaces That Are Not In Use. Please Wait..'
    $AzureRMNetworkInterfaces = Get-AzureRmNetworkInterface |  Where-Object {$_.VirtualMachine -eq $null}
    if ($AzureRMNetworkInterfaces.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzureRMNetworkInterfaces.Count) Network Interfaces That Are Not In Use."
        foreach ($AzureRMNetworkInterface in $AzureRMNetworkInterfaces)
        {
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzureRMNetworkInterface.Type)
            $NewRow.ResourceGroupName = $($AzureRMNetworkInterface.ResourceGroupName)
            $NewRow.ResourceName = $($AzureRMNetworkInterface.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Network Interfaces'
    }

    # Get Azure RM Network Security Groups That Are Not In Use
    Write-Verbose 'Getting Azure RM Network Security Groups That Are Not In Use. Please Wait..'
    $AzureRMNetworkSecurityGroups = Get-AzureRmNetworkSecurityGroup | Where-Object {$_.subnets.id -eq $null -and $_.networkinterfaces.id -eq $null}
    if ($AzureRMNetworkSecurityGroups.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzureRMNetworkSecurityGroups.Count) Network Security Groups That Are Not In Use."
        foreach ($AzureRMNetworkSecurityGroup in $AzureRMNetworkSecurityGroups)
        {
            $NewRow = $DataTable.NewRow()
            $NewRow.ResourceType = $($AzureRMNetworkSecurityGroup.Type)
            $NewRow.ResourceGroupName = $($AzureRMNetworkSecurityGroup.ResourceGroupName)
            $NewRow.ResourceName = $($AzureRMNetworkSecurityGroup.Name)
            $NewRow.Subscription = ($Subscription.Name)
            $DataTable.Rows.Add($NewRow)
            $OrphanedObjectsCount ++
        }
    }
    else
    {
        Write-Verbose 'I Have Not Found Any Unused Network Security Groups.'
    }

    # Get Azure RM Virtual Machines That Are Powered Off
    Write-Verbose 'Getting Azure RM Virtual Machines That Are Powered Off. Please Wait..'
    $AzureRMVirtualMachines = Get-AzureRmVM -Status | Where-Object {$_.PowerState -eq "VM deallocated"}
    if ($AzureRMVirtualMachines.Count -ge '1')
    {
        Write-Warning "I Have Found $($AzureRMVirtualMachines.Count) Virtual Machines That Are Powered Off." 
        foreach ($AzureRMVirtualMachine in $AzureRMVirtualMachines)
        {
            Write-Verbose "Getting Virtual Machine Information for $($AzureRMVirtualMachine.Name)"
            $AzureRMVMInfo = Get-AzureRmVM -Name $AzureRMVirtualMachine.Name -ResourceGroupName $AzureRMVirtualMachine.ResourceGroupName -DisplayHint Expand
        
            $NewRow = $DataTable.NewRow() 
            $NewRow.ResourceType = $($AzureRMVMInfo.Type)
            $NewRow.ResourceGroupName = $($AzureRMVirtualMachine.ResourceGroupName)
            $NewRow.ResourceName = $($AzureRMVirtualMachine.Name)
            $NewRow.VMSize = $($AzureRMVMInfo.HardwareProfile.VmSize)
            $NewRow.VMOperatingSystem = $($AzureRMVMInfo.StorageProfile.ImageReference.Sku)
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
    $CSVFileName = 'AzureRMOrphanedObjectsReport ' + $(Get-Date -f yyyy-MM-dd) + '.csv'
    $DataTable | Export-Csv "$FileSaveLocation\$CSVFileName" -NoTypeInformation
    Write-Output "I have Found $OrphanedObjectsCount Orphaned Objects. Please See $FileSaveLocation\$CSVFileName For More Details"
}

if ($OrphanedObjectsCount -eq '0')
{
    Write-Output "I Have Found $OrphanedObjectsCount Orphaned Objects In Your Azure Subscription!"
    Write-Output "You Have Done A Fantastic Job Keeping This Subscription Clean. Keep Up The Good Work!"
}

Write-Verbose 'Script processing complete.'