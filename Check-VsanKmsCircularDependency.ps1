<#==========================================================================
Script Name: Check-VsanKmsCircularDependency.ps1
Created on: 2/26/2018 
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================

.DESCRIPTION
This script will look to see if a KMS Server is running on the same Encrypted 
vSAN Datastore that it is providing Key Management Services for.

Tested on vSAN 6.6 and PowerCLI 6.5.4
The KMS Server Applicances must have VMware Tools installed for this to work properly
** Powershell on MacOS will throw an error when performing KMS Host lookups
** Resolve this issue with adding KMS entries in the hosts file

.SYNTAX
Check-VsanKmsCircularDependency.ps1 -ClusterName <ClusterName>

#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory=$True)]
  [String]$ClusterName
)


# Get the Cluster 
$Cluster = Get-Cluster -Name $ClusterName

# Get the Cluster Configuration 
$ClusterConfig = Get-VsanClusterConfiguration -Cluster $Cluster

# Get the vSAN Cluster Configuration
$VsanVcClusterConfig = Get-VsanView -Id "VsanVcClusterConfigSystem-vsan-cluster-config-system"

# Get Encryption State of $Cluster
$EncryptedVsan = $VsanVcClusterConfig.VsanClusterGetConfig($Cluster.ExtensionData.MoRef).DataEncryptionConfig

# If vSAN is enabled and it is Encrypted
If($Cluster.vSanEnabled -And $EncryptedVsan.EncryptionEnabled){

    # Get the vSAN Datastore 
    $vSANdatastore = $Cluster | Get-VMHost | Get-Datastore | Where-Object {$_.Type -eq "vsan"}

    # Get a list of VM IP Addresses - We'll grab them all, and compare them against each KMS Server entry
    $VMIpAddressList = Get-VM | Select-Object Name, @{N="IP";E={@($_.guest.IPaddress)}}

    # Add our currently assigned KMS Cluster to a variable
    $KmsCluster = $ClusterConfig.KmsCluster
    
    # Write the Profile (Cluster) Name of our vSAN Cluster's KMS Cluster
    Write-Host "Current KMS Cluster for "$Cluster.Name " " $KmsCluster.Name

    # Get a list of all of our KMS Cluster Hosts
    $KmsServerList = $KmsCluster | Get-KeyManagementServer

    # Go through each KMS Server in the KMS Cluster List and check against the VM IP Addresses on this Cluster
    Foreach ($KmsSvr in $KmsServerList) {

        # Write the Current KMS Server being checked
        Write-Host "Current KMS Server" $KmsSvr.Name
        Write-Host ""

        # Get the IP address of the KMS Server (this works for either FQDN or IP address)
        $KmsAddress = [System.Net.Dns]::GetHostAddresses([string]$KmsSvr.Address)


        # Compare the KMS Server's IP Address to the entire list of VM IP Addresses
        Foreach ($VMitem in $VMIpAddressList) {

            # Write-Host $VMitem.IP "" $VMitem.IPaddress
            If ($KmsAddress -eq $VMitem.IP){

                # Determine the datastore the VM is on
                $VMDatastore = Get-VM -Name $VMitem.Name | Get-Datastore

                # See if our KMS VM is running on the vSAN Datastore vs an alternate datastore
                If ($VMDatastore -eq $vSANdatastore) {

                    Write-Host "VM"$VMItem.Name"has the IP address"$VMItem.IP" matching $KmsSvr at $KmsAddress" -ForegroundColor Red
                    Write-Host "Is running in the "$Cluster.Name"Cluster" -ForegroundColor Red -NoNewline
                    Write-Host " and it is running on"$vSANdatastore.Name -ForegroundColor Red
                    Write-Host "It is suggested to immediately migrate VM"$VMItem.Name"to an alternate datastore and cluster" -ForegroundColor Red
                    Write-Host "Consult the KMS Vendor's documentation regarding virtual machine movement" -ForegroundColor Yellow
                    Write-Host ""
                    $CircularDependency = $CircularDependency + 1                    

                } else {
                    Write-Host "VM"$VMItem.Name"has the IP address"$VMItem.IP" matching $KmsSvr at $KmsAddress" -ForegroundColor Red
                    Write-Host "Is running in the "$Cluster.Name"Cluster" -ForegroundColor Red -NoNewline
                    Write-Host " but is not running on"$vSANdatastore.Name -ForegroundColor Green
                    Write-Host "It is suggested to migrate VM"$VMItem.Name"to an alternate cluster" -ForegroundColor Red
                    Write-Host "Consult the KMS Vendor's documentation regarding virtual machine movement" -ForegroundColor Yellow
                    Write-Host ""
                    $PotentialDependency = $PotentialDependency + 1
                }

            } 
        }
    }
    # If we haven't had any Circular / Potential Dependencies, indicate that it could not be determined whether a KMS Cluster for the vSAN Cluster is running on the cluster.
    If ($CircularDependency -lt 1 -and $PotentialDependency -lt 1) {
        Write-Host "The KMS Cluster for this Encrypted Cluster could not be determined to be running on this Encrypted Cluster." -ForegroundColor Yellow
        Write-Host "Please manually check to validate that the KMS Cluster for this Encrypted vSAN Cluster isn't running on this Encrypted Cluster" -ForegroundColor Yellow 
    }
} else {
    # Report that either vSAN or vSAN Encryption are not enabled.
    Write-Host "Cluster '$Cluster' either does not have vSAN enabled, or does not have vSAN Encryption enabled" -ForegroundColor Green 
}

