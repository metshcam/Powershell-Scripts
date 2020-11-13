####
## HyperV - Deploy CentOS Server
## Build a differencing disk, based on a Centos 8 base install.
####

Set-Location $PSScriptRoot

## Must have an existing Centos8 .VHDX parent disk
## Must have an existing HyperV Virtual Network (e.g. vBridge)
## Virtual machine must be built on a working environment e.g. dhcp/dns
## 
$vmparentdisk = "centos8.2-base-parent.vhdx"
$vmswitchname = "vBridge"

## Virtual machine details
## 
$ostype = "centos"
$vmrole = "workstation"
$machinename = "$ostype" + "-" + "$vmrole"
$vmdiskname = "centos-diff"

## HyperV Machine and Disk locations
## 
$vmlocation = "E:\hyperv\machines\"
$vmdiskloc = "E:\hyperv\disks\"

## Parent disk must exist
##
if (!(Test-Path -Path $vmdiskloc$vmparentdisk)){
    Write-Host $vmparentdisk "does not exist.  Quitting."
    Pause
    Break
}

## Check if diff+role exists
##
$vmdisk_chk = "$vmdiskloc$vmdiskname" + "-" + $vmrole + ".vhdx"

if (Test-Path -Path $vmdisk_chk){
    Write-Host $vmdisk_chk "already exists.  Quitting."
    Pause
    Break
}

## Differencing disk details
## Initial size should match or be larger than parent disk
##
$vmdiskparams = @{
    ParentPath = "$vmdiskloc$vmparentdisk";
    Path = "$vmdiskloc$vmdiskname" + "-" + $vmrole + ".vhdx";
    SizeBytes = 40GB;
}

Write-Host "About to create differencing disk with following parameters..."
Write-Host @vmdiskparams

## Remove pause when done testing
##
Pause

## Create new differencing virtual disk
##
New-VHD @vmdiskparams -Differencing

## Assign the current disk to assign to the virtual machine
##
$vhdpath = (Get-ChildItem -Path $vmdiskloc$vmdiskname* -Filter *$vmrole*)

## Virtual machine parameters (hyperv)
##
$vmparams = @{
    Name = $machinename;
    MemoryStartupBytes = 2048MB; 
    Path = $vmlocation;
    BootDevice = "VHD";
    SwitchName = $vmswitchname;
    VHDPath = $vhdpath;
    Generation = "2";
}

## Make sure virtual machine doesn't currently exist
##
$vm_chk = $machinename

if (Get-VM -Name $vm_chk -ErrorAction SilentlyContinue) {
    Write-Host $vm_chk "already exists.  Quitting."
    Pause
    Break    
}

## Create virtual machine and attach new differencing disk
##
$vmdiskpath = "$vmdiskloc$vmdiskname" + "-" + $vmrole + ".vhdx"

Write-Host "About to create VM at ..." $vmparams.Path "with the following paramaters..."
Write-Host @vmparams

## Remove pause when done testing
##
Pause

## If differencing disk currently exists, create virtual machine
##
if (Test-Path -Path $vmdiskpath){
    Write-Host $vmdiskpath "exists.  Here we goooo..."
    New-VM @vmparams
}

## Change VM properties for linux and no checkpoints
## Change properties according to your environment
##
$vmname = Get-VM -Name *$vmrole
Set-VM -Name $vmname.Name -CheckpointType Disabled -AutomaticCheckpointsEnabled $false -MemoryMinimumBytes 512MB -MemoryMaximumBytes 2048MB
Set-VMFirmware -VMName $vmname.Name -EnableSecureBoot Off

## Enable guest services on VM
## The parent disk must have the hyperv kernel module
## loaded.  Centos8 has it enabled by default.
##
Enable-VMIntegrationService -VMName $vmname.Name -Name 'Guest Service Interface'

## Start virtual machine, and wait for SSH service to respond
## 
Get-VM -Name $vmname.Name | Start-VM

## Wait for machine to start up before it receives an IP from your DHCP server
## Adjust according to your network environment
##
Start-Sleep -Seconds 20

## This should be your virtual machine's primary IPv4 address
## These variables may require changes based on your own network configuration
##
$vmIP = (Get-VM -Name $vmname.Name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0]
$vmSSHPort = "22"

do {
    Write-Host "Waiting for SSH on port $vmSSHPort ... on $vmIP"
    Start-Sleep -Seconds 3
  } until(Test-NetConnection $vmIP -Port $vmSSHPort | Where-Object { $_.TcpTestSucceeded } )

Write-Host "$vmIP is up and running on port $vmSSHPort"

## Needs OpenSSH installed
## Powershell: Add-WindowsCapability -Online -Name OpenSSH.Client*
##
$sshclient = Get-WindowsCapability -Online -Name 'OpenSSH.Client*'

if (!($sshclient.State -eq 'Installed')){
    Write-Host "
    You are about to install OpenSSH (Windows Feature).
    CTRL+C to exit.
    "
    Pause
    Add-WindowsCapability -Online -Name OpenSSH.Client*
}

## Bug: 
## known_hosts file corrupted by ssh-keyscan.exe
## non-ascii characters
## use ssh.exe method instead
#ssh-keyscan.exe -t rsa $vmIP >> $sshlocation

## Prepare ssh current user RSA public key
## Copy to virtual machine using guest services
## note: RSA key should already exist after installing OpenSSH
##
$sshpublocation = $env:USERPROFILE + '\.ssh\id_rsa.pub'

Copy-Item -Path $sshpublocation -Destination $PSScriptRoot\provisioning_files\authorized_keys

## Use HyperV integrated guest services to copy SSH authorized_keys to VM
## Root user gains access to the host's public key
##
Copy-VMFile -Name $vmname.Name -SourcePath $PSScriptRoot\provisioning_files\authorized_keys -DestinationPath '/root/.ssh/' -CreateFullPath -FileSource Host
Copy-VMFile -Name $vmname.Name -SourcePath $PSScriptRoot\provisioning_files\startup.sh -DestinationPath '/root/hyperv/' -CreateFullPath -FileSource Host

## Remove authorized_keys file and disable guest services
##
Remove-Item -Path $PSScriptRoot\provisioning_files\authorized_keys -Force
Disable-VMIntegrationService -VMName $vmname.Name -Name 'Guest Service Interface'

## Connect over SSH and run startup script that was copied with Copy-VMFile
## Auto-accepts ssh key certificate into known_hosts
##
ssh.exe -oStrictHostKeyChecking=no root@$vmIP "sh -c 'cd /root/hyperv; nohup ./startup.sh > /dev/null 2>&1 &'"
