Set-Location $PSScriptRoot

## Virtual machine details
##
$ostype = "centos"
$vmrole = "calibre"
$machinename = "$ostype" + "-" + "$vmrole"

## Virtual environment and locations
##
$vmlocation = "E:\hyperv\machines\"
$vmdiskloc = "E:\hyperv\disks\"

## Virtual switch name
##
$vmswitchname = "vBridge"

## Virtual disk details
##
$vmdiskname = "centos-diff"
$vmparentdisk = "centos8.2-base-parent.vhdx"

## Parent disk must exist
##
if (!(Test-Path -Path $vmdiskloc$vmparentdisk)){
    Write-Host $vmparentdisk "does not exist.  Quitting."
    Pause
    Break
}
else {
    Write-Host $vmparentdisk "exists.  Now checking if the new VM's disk already exists."
}

## Check if diff exists
##
$vmdisk_chk = "$vmdiskloc$vmdiskname" + "-" + $vmrole + ".vhdx"

if (Test-Path -Path $vmdisk_chk){
    Write-Host $vmdisk_chk "already exists.  Quitting."
    Pause
    Break
}
else {
    Write-Host $vmdisk_chk "does not exist.  Continuing."
}

## Differencing disk details
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
else {
    Write-Host $machinename "does not exist.  Moving forward now..."
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
$vmname = Get-VM -Name $machinename
Set-VM -Name $vmname.Name -CheckpointType Disabled -AutomaticCheckpointsEnabled $false -MemoryMinimumBytes 512MB -MemoryMaximumBytes 2048MB
Set-VMFirmware -VMName $vmname.Name -EnableSecureBoot Off

## Start VM
##
Get-VM -Name $machinename | Start-VM

## Wait 10 seconds to ensure VM is booted and ssh responding
Start-Sleep -Seconds 10

$vmIP = (Get-VM -Name $machinename | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0]
$vmPort = "22"

do {
    Write-Host "Waiting..."
    Start-Sleep -Seconds 3
  } until(Test-NetConnection $vmIP -Port $vmPort | Where-Object { $_.TcpTestSucceeded } )

Write-Host "
$vmIP is up and running on port $vmPort
Attempting to connect to server over port $vmPort...
"
Pause

## Accept ssh key into wsl2
##
##Start-Process "bash.exe" -ArgumentList "-c "
##ssh ("root@"+$vmIP)
