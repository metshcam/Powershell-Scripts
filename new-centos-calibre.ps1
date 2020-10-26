####
## HyperV + CentOS Server Automation
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
$vmrole = "calibre"
$machinename = "$ostype" + "-" + "$vmrole"
$vmdiskname = "centos-diff"

## HyperV Machine and Disk locations
## 
$vmlocation = "C:\hyperv\machines\"
$vmdiskloc = "C:\hyperv\disks\"

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

$vmIP = (Get-VM -Name $vmname.Name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0]
$vmSSHPort = "22"

do {
    Write-Host "Waiting..."
    Start-Sleep -Seconds 3
  } until(Test-NetConnection $vmIP -Port $vmSSHPort | Where-Object { $_.TcpTestSucceeded } )

Write-Host "

$vmIP is up and running on port $vmSSHPort

Attempting to connect to server over port $vmSSHPort...

"
Pause

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

## Scan for and accept ssh rsa key for new machine
##
$sshlocation = $env:USERPROFILE + '\.ssh\known_hosts'

Write-Host "

Location of SSH hosts file is:  $sshlocation

"

Pause

ssh-keyscan.exe -t rsa $vmIP >> $sshlocation

## Use guest services to startup script to virtual machine
## File must exist in path with .PS1 file
## Note on CreateFullPath: can only create one folder deep.
##
$sourcepath = (Get-Location).Path
$startupscript = "startup-calibre.sh"

Copy-VMFile -Name $vmname.Name -SourcePath $sourcepath\$startupscript -DestinationPath '/root/hyperv/' -CreateFullPath -FileSource Host

## Remove ability to copy from HyperV to VM
##
Disable-VMIntegrationService -VMName $vmname.Name -Name 'Guest Service Interface'
