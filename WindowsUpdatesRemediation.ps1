<#
.SYNOPSIS
This script checks for pending Windows Update packages and performs actions based on the presence of stuck updates.

.DESCRIPTION
The script checks if there are pending Windows Update packages. If stuck updates are present, it proceeds to remove related registry entries and files to resolve the pending updates.

.PARAMETER
None required

.EXAMPLE
.\WindowsUpdateRemediation.ps1

.NOTES
Date Created: 2023-12-12
Author: Ditor Sahiti
#>

$pendingPackages = dism /online /get-packages /format:table | Select-String "Pending" | ForEach-Object { $_.ToString().Split('|')[0].Trim() }

# Check if $pendingPackages is not null
if ($pendingPackages -ne $null) {
    Write-Host "PendingPackages is present. Executing the script."

    # Define registry paths to check
    $registryPaths = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"

    # Loop through each registry path
    foreach ($path in $registryPaths) {
        # Check if the path exists
        if (Test-Path $path) {
            # Get all subkeys and values recursively
            $items = Get-ChildItem -Path $path -Recurse
            foreach ($item in $items) {
                # Check if the current item is a key
                if ($item.PSIsContainer) {
                    # Get all values in the key
                    $values = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
                    foreach ($valueName in $values.PSObject.Properties.Name) {
                        foreach ($package in $pendingPackages) {
                            # Check if the value name matches the package name
                            if ($valueName -like "*$package*") {
                                # Remove the value
                                Remove-ItemProperty -Path $item.PSPath -Name $valueName -Force -ErrorAction SilentlyContinue
                                Write-Host "Removed value $valueName in $($item.PSPath)" 
                            }
                        }
                    }

                    # Additional check for the key itself
                    foreach ($package in $pendingPackages) {
                        if ($item.Name -like "*$package*") {
                            # Remove the key
                            Remove-Item -Path $item.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Host "Removed key $($item.PSPath)" 
                        }
                    }
                }
            }
        }
        else {
            Write-Host "Path $path does not exist."
        }
    }


    # Define the paths for the registry keys
    $registryPaths = @(
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PendedSessionPackages",
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\SessionsPending"
    )

    # Function to modify ACLs, safely check and delete subkeys, then delete the main key
    function ModifyAndDeleteRegKey {
        param(
            [string]$regPath
        )

        try {
            $localMachineKey = [Microsoft.Win32.Registry]::LocalMachine
            $regKey = $localMachineKey.OpenSubKey($regPath, $true)

            if ($regKey -ne $null) {
                # Delete subkeys
                $subKeys = $regKey.GetSubKeyNames()
                foreach ($subKey in $subKeys) {
                    $subRegKeyPath = "$regPath\$subKey"
                    $localMachineKey.DeleteSubKeyTree($subRegKeyPath)
                    Write-Host "Successfully deleted subkey: $subRegKeyPath"
                }

                # Delete the main key
                 $localMachineKey.DeleteSubKeyTree($regPath)
                 Write-Host "Successfully deleted main registry key: $regPath"

                $regKey.Close()
            } else {
                Write-Host "Registry key does not exist or cannot be accessed: $regPath"
            }
        } catch {
            Write-Host "Failed to delete registry key: $regPath. Error: $_"
        }
    }

    # Process each registry path
    foreach ($path in $registryPaths) {
        ModifyAndDeleteRegKey -regPath $path
    }

    #Check for RebootPendingfilePath Key and remove it if present.
    $RebootPendingfilePath = "C:\Windows\Winsxs\Pending.xml"
    if (Test-Path $RebootPendingfilePath) {
        Remove-Item -Path $RebootPendingfilePath -Force
        Write-Host "File removed."
    } else {
        Write-Host "Pending.XML File does not exist, no action taken." -ForegroundColor green
    }

    # Get the list of software updates
    $UpdateList = Get-WmiObject -Namespace "root\ccm\clientsdk" -Class CCM_SoftwareUpdate

    #
    foreach ($Update in $UpdateList)
    {
        # Search for the CAB file in the ccmcache directory
        # We use a wildcard pattern to match any CAB file that contains the ArticleID
        $CABFilePaths = Get-ChildItem -Path C:\Windows\ccmcache\ -Filter "*$($Update.ArticleID)*.cab" -Recurse -ErrorAction SilentlyContinue
   
        foreach ($CABFilePath in $CABFilePaths)
        {
            if ($CABFilePath)
            {
                # Construct the DISM command
                Write-Host "Installing update: $($CABFilePath.Name)..."
                Write-Host "The installation process can take 15-30 minutes, depending on the size of a Cumulative Update. The progress can be tracked in C:\Windows\Logs\DISM\dism.log"

                $DISMCommand = "DISM /Add-Package /Online /PackagePath:`"$($CABFilePath.FullName)`" /Quiet /NoRestart"
                # Execute the DISM command to Install the Updates
                Invoke-Expression $DISMCommand
                Write-Host "Installed update: $($CABFilePath.Name)"
            }
            else
            {
                Write-Host "CAB file for update $($Update.ArticleID) not found."
            }
        }
    }

} else {
    write-Host "No Pending Windows Updates found. The script will not be executed."
}