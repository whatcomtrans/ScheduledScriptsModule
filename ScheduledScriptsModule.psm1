<#
This cmdlet reviews the contents of the ScheduledScripts folder and either creates or updates scheduled jobs.

Credentials are required.

Jobs are named every[CamelCaseEvery]-[scriptName]

#>
function Update-ScheduledJobToRunCASScriptEvery {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="all")]
	Param(
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [System.IO.FileInfo] $ScriptsRootPath,
        [Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String] $Every,
        [Parameter(Mandatory=$false,Position=2,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Define options
        $options = New-ScheduledJobOption -RunElevated:$true -DoNotAllowDemandStart:$false -HideInTaskScheduler:$false -MultipleInstancePolicy IgnoreNew

        #Setup credentials
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }
	}
	Process {
        #ScriptsRootPath default
        if (!$ScriptsRootPath) {
            $ScriptsRootPath = "$CommonAdministrativeShellPath\ScheduledScripts"
        }

        $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
        if ($Every) {
            #Process a specific Every folder
            #Verify trigger exists, if not throw error, otherwise, load
            if (!(Test-Path "$ScriptsRootPath\trigger_every$($Every).ps1")) {
                throw "No Triger defined for every $Every"
            } else {
                $trigger = . "$ScriptsRootPath\trigger_every$($Every).ps1"
            }

            #Verify path to folder exists, if not, create it
            if (!(Test-Path "$ScriptsRootPath\every$Every")) {
                New-item -Path "$ScriptsRootPath\every$Every" -ItemType Directory
            }
            
            #Get the scripts that currently exist in the folder
            if ($ScriptName) {
                #Only process a specfic script
                $currentScripts = Get-ChildItem -Path "$ScriptsRootPath\every$Every" -Filter "$($ScriptName).ps1"
            } else {
                #Get all of the scripts
                $currentScripts = Get-ChildItem -Path "$ScriptsRootPath\every$Every" -Filter "*.ps1"
            }

            #Get the currently registered jobs
            if ($ScriptName) {
                $currentJobs = Get-ScheduledJob | where Name -eq "every$($Every)-$ScriptName"
            } else {
                $currentJobs = Get-ScheduledJob | where Name -Like "every$($Every)*"
            }

            #Determine which ones need to be Registered and which ones need to be Unregistered
            $ToRegister = @()
            $ToUnregister = @()

            forEach($currentScript in $currentScripts) {
                if (($currentJobs | where Name -eq "every$($Every)-$($currentScript.Name.Replace('.ps1', ''))").Count -eq 1) {
                    #Has matching job, no change
                } else {
                    #New script file, Register job
                    $ToRegister += $currentScript
                }
            }

            forEach($currentJob in $currentJobs) {
                $jobScriptName = $currentJob.Name.Split("-")[1]
                if (($currentScripts | where Name -like "$($jobScriptName)*").Count -eq 1) {
                    #Has matching script file, no change
                } else {
                    #Script file is now missing, Unregister job
                    $ToUnregister += $currentJob
                }
            }

            #Process ToRegister and ToUnregister
            forEach ($file in $ToRegister) {
                $initScript = '$CommonAdministrativeShellPath = "' + $CommonAdministrativeShellPath + '"; '  + 'Import-Module "$($CommonAdministrativeShellPath)\Modules\Modulets" -Verbose;'
                # . (Load-CAS -local -CASPath '$($CommonAdministrativeShellPath)' -NoCredentials);"
                $initScriptBlock = [Scriptblock]::Create($initScript)
                #Write-Output "FilePath $($file.FullName)"
                #Write-Output "every$($Every)-$($file.Name.Replace('.ps1', ''))"
                Register-ScheduledJob -FilePath $file.FullName -Name "every$($Every)-$($file.Name.Replace('.ps1', ''))" -Trigger $trigger -ScheduledJobOption $options -InitializationScript $initScriptBlock -Credential $cred # -Authentication Credssp
            }

            forEach ($ScheduledJob in $ToUnregister) {
                Disable-ScheduledJob $ScheduledJob
                Start-Sleep -Seconds 10
                Unregister-ScheduledJob $ScheduledJob
            }
        } else {
            #Update all of them
            #Iterate over all of the every folders and call this cmdlet with that specific folder
            $folders = Get-ChildItem -Path "$ScriptsRootPath" -Filter "every*" -Directory
            forEach($folder in $folders) {
                $folderName = $folder.Name.Replace("every", "")
                Update-ScheduledJobToRunCASScriptEvery -Every $folderName -Credentials $cred -ScriptsRootPath $ScriptsRootPath
            }
        }
	}
}

function Get-ScheduledScriptJob {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="name")]
	Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]    
        [String] $Every,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="id")]
        [Int] $Id,
		[Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
		[String]$ComputerName,
	    [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
                if(-Not ($_ | Test-Path) ){
                    throw "File or folder does not exist"
                }
                if(-Not ($_ | Test-Path -PathType Leaf) ){
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if($_ -notmatch "(\.xml)"){
                    throw "The file specified in the path argument must be of type xml"
                }
                return $true 
        })]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Setup credentials for connecting to ComputerName
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }

        #Establish session
        $session = New-PSSession -ComputerName $ComputerName -Credential $cred
	}
	Process {
        if (!$Id) {
            $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
            $filterStr = "every$($Every)-$($ScriptName)*"
            Invoke-Command -Session $session -ScriptBlock {param($filter); Get-ScheduledJob | Where-Object Name -like $filter} -Args $filterStr
        } else {
            Invoke-Command -Session $session -ScriptBlock {param($intId); Get-ScheduledJob -Id $intId} -Args $Id
        }
	}
	End {
        #Put end here
        Disconnect-PSSession -Session $session | Out-Null
	}
}

function Get-ScheduledScriptJobInstance {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="name")]
	Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]    
        [String] $Every,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="id")]
        [Int] $Id,
		[Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
		[String]$ComputerName,
	    [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
                if(-Not ($_ | Test-Path) ){
                    throw "File or folder does not exist"
                }
                if(-Not ($_ | Test-Path -PathType Leaf) ){
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if($_ -notmatch "(\.xml)"){
                    throw "The file specified in the path argument must be of type xml"
                }
                return $true 
        })]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Setup credentials for connecting to ComputerName
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }

        #Establish session
        $session = New-PSSession -ComputerName $ComputerName -Credential $cred
	}
	Process {
        if (!$Id) {
            $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
            $filterStr = "every$($Every)-$($ScriptName)*"
            Invoke-Command -Session $session -ScriptBlock {param($filter); Get-Job | Where-Object Name -like $filter} -Args $filterStr
        } else {
            Invoke-Command -Session $session -ScriptBlock {param($intId); Get-Job -Id $intId} -Args $Id
        }
	}
	End {
        #Put end here
        Disconnect-PSSession -Session $session | Out-Null
	}
}

function Receive-ScheduledScriptJobInstance {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="name")]
	Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]    
        [String] $Every,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="id")]
        [Int] $Id,
		[Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
		[String]$ComputerName,
	    [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
                if(-Not ($_ | Test-Path) ){
                    throw "File or folder does not exist"
                }
                if(-Not ($_ | Test-Path -PathType Leaf) ){
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if($_ -notmatch "(\.xml)"){
                    throw "The file specified in the path argument must be of type xml"
                }
                return $true 
        })]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Setup credentials for connecting to ComputerName
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }

        #Establish session
        $session = New-PSSession -ComputerName $ComputerName -Credential $cred
	}
	Process {
        if (!$Id) {
            $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
            $filterStr = "every$($Every)-$($ScriptName)*"
            Invoke-Command -Session $session -ScriptBlock {param($filter); Receive-Job -Keep | Where-Object Name -like $filter} -Args $filterStr
        } else {
            Invoke-Command -Session $session -ScriptBlock {param($intId); Receive-Job -Id $intId -Keep} -Args $Id
        }
	}
	End {
        #Put end here
        Disconnect-PSSession -Session $session | Out-Null
	}
}

function Disable-ScheduledScriptJob {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="name")]
	Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]    
        [String] $Every,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="id")]
        [Int] $Id,
		[Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
		[String]$ComputerName,
	    [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
                if(-Not ($_ | Test-Path) ){
                    throw "File or folder does not exist"
                }
                if(-Not ($_ | Test-Path -PathType Leaf) ){
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if($_ -notmatch "(\.xml)"){
                    throw "The file specified in the path argument must be of type xml"
                }
                return $true 
        })]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Setup credentials for connecting to ComputerName
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }

        #Establish session
        $session = New-PSSession -ComputerName $ComputerName -Credential $cred
	}
	Process {
        if (!$Id) {
            $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
            $filterStr = "every$($Every)-$($ScriptName)*"
            Invoke-Command -Session $session -ScriptBlock {param($filter); Get-ScheduledJob | Where-Object Name -like $filter | Disable-ScheduledJob} -Args $filterStr
        } else {
            Invoke-Command -Session $session -ScriptBlock {param($intId); Disable-ScheduledJob -Id $intId} -Args $Id
        }
	}
	End {
        #Put end here
        Disconnect-PSSession -Session $session | Out-Null
	}
}

function Enable-ScheduledScriptJob {
	[CmdletBinding(SupportsShouldProcess=$false,DefaultParameterSetName="name")]
	Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]    
        [String] $Every,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="name")]
        [String] $ScriptName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName="id")]
        [Int] $Id,
		[Parameter(Mandatory=$true,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
		[String]$ComputerName,
	    [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [PSCredential] $Credentials,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false,ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({
                if(-Not ($_ | Test-Path) ){
                    throw "File or folder does not exist"
                }
                if(-Not ($_ | Test-Path -PathType Leaf) ){
                    throw "The Path argument must be a file. Folder paths are not allowed."
                }
                if($_ -notmatch "(\.xml)"){
                    throw "The file specified in the path argument must be of type xml"
                }
                return $true 
        })]
        [System.IO.FileInfo] $CredentialsPath
	)
	Begin {
        #Setup credentials for connecting to ComputerName
        [PSCredential] $cred = $null
        If ($CredentialsPath) {
            $cred = Import-PSCredential $CredentialsPath
        }

        If ($Credentials) {
            $cred = $Credentials
        }
        If ($cred -eq $null) {
            throw "Must supply credentials either by providing a PSCredentials object to parameter Credentials or by providing parameter CredentialsPath with a path to an encoded XML file that can be imported using Import-PSCredential"
        }

        #Establish session
        $session = New-PSSession -ComputerName $ComputerName -Credential $cred
	}
	Process {
        if (!$Id) {
            $Every = (Get-Culture).TextInfo.ToTitleCase($Every)
            $filterStr = "every$($Every)-$($ScriptName)*"
            Invoke-Command -Session $session -ScriptBlock {param($filter); Get-ScheduledJob | Where-Object Name -like $filter | Enable-ScheduledJob} -Args $filterStr
        } else {
            Invoke-Command -Session $session -ScriptBlock {param($intId); Enable-ScheduledJob -Id $intId} -Args $Id
        }
	}
	End {
        #Put end here
        Disconnect-PSSession -Session $session | Out-Null
	}
}

Export-ModuleMember -Function *