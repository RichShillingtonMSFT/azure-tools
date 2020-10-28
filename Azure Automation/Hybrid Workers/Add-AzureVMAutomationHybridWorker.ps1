<#
.SYNOPSIS
    Script to add an Azure VM as a Azure Automation Hybrid Worker

.DESCRIPTION
    This script is used to add an Azure VM as a Azure Automation Hybrid Worker.
    You must run this on the VM to be used as a Hybrid Worker.
    You must have an Automation Account and Log Analytics Workspace already created.
    You must be an owner of the Automation Account, Log Analytics Workspace and the VM where this is being run.
    This requires an elevated PowerShell session.
    The script will perform the following actions:
        Turn off Internet Explorer Enhanced Security.
        Install all required AZ Modules.
        Connect to Azure and prompt you for the environment and location.
        Ensure that AzureAutomation, ChangeTracking, Updates, AgentHealthAssessment Operational Insights Intelligence Packs are enabled.
        Install the Microsoft Monitoring Agent Extension on the VM.
        Add the new Hybrid Worker to the Automation Account in the group specified.

.PARAMETER LogAnalyticsResourceGroupName
    Specify the Log Analytics Resource Group Name.
    Example Prod-LA-RG

.PARAMETER LogAnalyticsWorkspaceName
    Specify the Log Analytics Workspace Name.
    Example Prod-LA-WS

.PARAMETER AzureAutomationAccountResourceGroupName
    Specify the Automation Account Resource Group Name.
    Example Azure-Automation-RG

.PARAMETER AutomationAccountName
    Specify the Automation Account Name. 
    Example Prod-AzureAutomation-Acct

.PARAMETER HybridWorkerGroupName
    Specify the Hybrid Workers Group Name. 
    Example Tier1-Workers

.PARAMETER HybridWorkerResourceGroupName
    Specify the Hybrid Workers Resource Group. 
    Example Azure-Automation-Workers-RG

.EXAMPLE
    .\Add-AzureVMAutomationHybridWorker -LogAnalyticsResourceGroupName 'Prod-LA-RG' `
        -LogAnalyticsWorkspaceName 'Prod-LA-WS' `
        -AzureAutomationAccountResourceGroupName 'Azure-Automation-RG' `
        -AutomationAccountName 'Prod-AzureAutomation-Acct' `
        -HybridWorkerGroupName 'Tier1-Workers' `
        -HybridWorkerResourceGroupName 'Azure-Automation-Workers-RG'
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
Param
(
    # Log Analytics Resource Group Name
    [Parameter(Mandatory=$true,HelpMessage="Specify the Log Analytics Resource Group Name. Example Prod-LA-RG")]
    [String] $LogAnalyticsResourceGroupName,

    # Log Analytics Workspace Name
    [Parameter(Mandatory=$true,HelpMessage="Specify the Log Analytics Workspace Name. Example Prod-LA-WS")]
    [String] $LogAnalyticsWorkspaceName,

    # Automation Account Resource Group Name
    [Parameter(Mandatory=$true,HelpMessage="Specify the Automation Account Resource Group Name. Example Azure-Automation-RG")]
    [String] $AzureAutomationAccountResourceGroupName,

    # Automation Account Name
    [Parameter(Mandatory=$true,HelpMessage="Specify the Automation Account Name. Example Prod-AzureAutomation-Acct")]
    [String] $AutomationAccountName,

    # Hybrid Workers Group Name
    [Parameter(Mandatory=$true,HelpMessage="Specify the Hybrid Workers Group Name. Example Tier1-Workers")]
    [String] $HybridWorkerGroupName,

    # Hybrid Workers Resource Group
    [Parameter(Mandatory=$true,HelpMessage="Specify the Hybrid Workers Resource Group. Example Azure-Automation-Workers-RG")]
    [String] $HybridWorkerResourceGroupName
)

# Stop the script if any errors occur
$ErrorActionPreference = "Stop"
$VerbosePreference = 'Continue'

# Turn off Internet Explorer Enhanced Security
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
Stop-Process -Name Explorer

# Add and update modules on the Automation account
Write-Output "Importing necessary modules..."

# Create a list of the modules necessary to register a hybrid worker
$AzModule = @{"Name" = "Az"; "Version" = ""}
$Modules = @($AzModule)

# Import or Install modules
foreach ($Module in $Modules)
{

    $ModuleName = $Module.Name

    # Find the module version
    if ([string]::IsNullOrEmpty($Module.Version))
    {
        # Find the latest module version if a version wasn't provided
        $ModuleVersion = (Find-Module -Name $ModuleName).Version
    } 
    else 
    {
        $ModuleVersion = $Module.Version
    }

    # Check if the required module is already installed
    $CurrentModule = Get-Module -Name $ModuleName -ListAvailable | Where-Object "Version" -eq $ModuleVersion

    if (!$CurrentModule) 
    {
        $null = Install-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force
        Write-Output "Successfully installed version $ModuleVersion of $ModuleName..."
    } 
    else 
    {
        Write-Output "Required version $ModuleVersion of $ModuleName is installed..."
    }
}

#region Connect To Azure
# Enviornment Selection
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

try
{
    Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}

try 
{
    $Subscriptions = Get-AzSubscription
    if ($Subscriptions.Count -gt '1')
    {
        $Subscription = $Subscriptions | Out-GridView -Title "Please Select a Subscription." -PassThru
        Set-AzContext $Subscription
    }
}
catch
{
    Write-Error -Message $_.Exception
    break
}

# Location Selection
$Locations = Get-AzLocation
$Location = ($Locations | Out-GridView -Title "Please Select a location." -PassThru).Location
#endregion

# Get Azure Automation Primary Key and Endpoint
$AutomationInfo = Get-AzAutomationRegistrationInfo -ResourceGroupName $AzureAutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName
$AutomationPrimaryKey = $AutomationInfo.PrimaryKey
$AutomationEndpoint = $AutomationInfo.Endpoint

# Get the primary key for the OMS workspace
$Workspace = Get-AzOperationalInsightsWorkspace -Name $LogAnalyticsWorkspaceName -ResourceGroupName $LogAnalyticsResourceGroupName  -ErrorAction Stop
$WorkspaceSharedKeys = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $LogAnalyticsResourceGroupName -Name $LogAnalyticsWorkspaceName -WarningAction SilentlyContinue

# Activate the Log Analytics Solutions in the workspace
$IntelligencePacks = @(
'AzureAutomation'
'ChangeTracking'
'Updates'
'AgentHealthAssessment'
)

foreach ($IntelligencePack in $IntelligencePacks)
{
   if ((Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $LogAnalyticsResourceGroupName -WorkspaceName $LogAnalyticsWorkspaceName -WarningAction SilentlyContinue | Where-Object {$_.Name -eq $IntelligencePack}).Enabled -eq $false)
   {
        Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $LogAnalyticsResourceGroupName -WorkspaceName $LogAnalyticsWorkspaceName -IntelligencePackName "$IntelligencePack" -Enabled $true -Verbose
   }
}

# Install Microsoft Monitoring Agent

$PublicSettings = @{"workspaceId" = $($Workspace.CustomerId)}
$ProtectedSettings = @{"workspaceKey" = $($WorkspaceSharedKeys.PrimarySharedKey)}

try
{
    Get-AzVMExtension -Name "MicrosoftMonitoringAgent" `
        -ResourceGroupName "$HybridWorkerResourceGroupName" `
        -VMName "$ENV:COMPUTERNAME"
}
catch
{
    Write-Output "Microsoft Monitoring Agent was not found. Installing...."

    Set-AzVMExtension -ExtensionName "MicrosoftMonitoringAgent" `
        -ResourceGroupName "$HybridWorkerResourceGroupName" `
        -VMName "$ENV:COMPUTERNAME" `
        -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
        -ExtensionType "MicrosoftMonitoringAgent" `
        -TypeHandlerVersion 1.0 `
        -Settings $PublicSettings `
        -ProtectedSettings $ProtectedSettings `
        -Location $Location
}

# Import Hybrid Automation Module
try
{
    Set-Location "$env:ProgramFiles\Microsoft Monitoring Agent\Agent\AzureAutomation" -ErrorAction Stop
    $version = (Get-ChildItem | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
    Set-Location "$version\HybridRegistration"
    Import-Module (Resolve-Path('HybridRegistration.psd1'))
}
catch
{
   Write-Host "Azure Automation Agent is not installed correctly. Please try again."
   break
}

# Add Hybrid Worker to Group
Add-HybridRunbookWorker -Name $HybridWorkerGroupName -EndPoint $AutomationEndpoint -Token $AutomationPrimaryKey