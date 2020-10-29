####
## HyperV - Deploy CentOS Server
## Build a differencing disk, based on a Centos 8 base install.
####

## Must have an existing Centos8 .VHDX parent disk
## Must have an existing HyperV Virtual Network (e.g. vBridge)
##
$vmparentdisk = "centos8.2-base-parent.vhdx"
$vmswitchname = "vBridge"

Set-Location $PSScriptRoot

## Virtual machine details
## 
$ostype = "centos"
$vmrole = "insurgencyserver"
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

## Check if diff exists
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

Write-Host "About to create disk with following parameters..."
Write-Host @vmdiskparams

Pause

New-VHD @vmdiskparams -Differencing

## Assign the current disk to assign to the virtual machine
##
$vhdpath = (Get-ChildItem -Path $vmdiskloc$vmdiskname* -Filter *$vmrole*)

## Virtual machine parametere (hyperv)
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

## Make sure VM doesn't already exist
##
$vm_chk = $machinename

if (Get-VM -Name $vm_chk -ErrorAction SilentlyContinue) {
    
    Write-Host $vm_chk "already exists.  Quitting."
    Pause
    Break    
}

## Create virtual machine and use new disk
##
$vmdiskpath = "$vmdiskloc$vmdiskname" + "-" + $vmrole + ".vhdx"

Write-Host "About to create VM at ..." $vmparams.Path "with the following paramaters..."
Write-Host @vmparams

Pause

## If diff disk exists, create vm
##
if (Test-Path -Path $vmdiskpath){
    Write-Host $vmdiskpath "exists.  Here we goooo..."
    New-VM @vmparams
}

## Change VM properties for linux and no checkpoints
##
$vmname = Get-VM -Name *$vmrole
Set-VM -Name $vmname.Name -CheckpointType Disabled -AutomaticCheckpointsEnabled $false -MemoryMinimumBytes 512MB -MemoryMaximumBytes 2048MB
Set-VMFirmware -VMName $vmname.Name -EnableSecureBoot Off

## Enable guest services on VM
##
Enable-VMIntegrationService -VMName $vmname.Name -Name 'Guest Service Interface'

## Start VM
##
Get-VM -Name $vmname.Name | Start-VM

Start-Sleep -Seconds 20

## Wait for SSH to respond/listen on virtual machine
##
$vmIP = (Get-VM -Name $vmname.Name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0]
$vmSSHPort = "22"

do {
    Write-Host "Waiting for port $vmSSHPort ..."
    Start-Sleep -Seconds 3
  } until(Test-NetConnection $vmIP -Port $vmSSHPort | Where-Object { $_.TcpTestSucceeded } )

Write-Host "$vmIP is up and running on port $vmSSHPort"

## Needs OpenSSH installed
## Powershell: Add-WindowsCapability -Online -Name OpenSSH.Client*
##
$sshclient = Get-WindowsCapability -Online -Name 'OpenSSH.Client*'

if (!($sshclient.State -eq 'Installed')){
    Write-Host "
    You are about to install.
    CTRL+C to exit.
    "
    Pause
    Add-WindowsCapability -Online -Name OpenSSH.Client*
}

## Bug: 
## Check known_hosts file for non-ascii characters
## breaks known_hosts file
## use ssh command instead
#$sshlocation = $env:USERPROFILE + '\.ssh\known_hosts'
#ssh-keyscan.exe -t rsa $vmIP >> $sshlocation

## Prepare ssh rsa public key to copy over to virtual machine
## Should exist after installing OpenSSH
##
$sshpublocation = $env:USERPROFILE + '\.ssh\id_rsa.pub'

Copy-Item -Path $sshpublocation -Destination $PSScriptRoot\provisioning_files\authorized_keys

## Use HyperV intergrated guest services to copy SSH authorized_keys to VM
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
