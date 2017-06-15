﻿param($installPath, $toolsPath, $package)

function Add-ProjectDirectoryIfNotExist($DirPath)
{	
	$project = Get-Project
    $projectPath = Split-Path $project.FileName -Parent
    $fullPathToNewDire ="$projectPath\$DirPath"
    if((Test-Path $fullPathToNewDire) -ne $true){
        [void](New-Item -ItemType Directory -Force -Path  $fullPathToNewDire)
        $outRoot = ($DirPath -split "\\")[0]
        if([string]::IsNullOrWhiteSpace($outRoot) -ne $true)
        {
            [void]$project.ProjectItems.AddFromDirectory("$projectPath\$outRoot")
        }
    }
    $fullPathToNewDire
}

function Add-FileToProject{
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true)]$Files)
	begin{
		$project = Get-Project
	}
    process{
        foreach($file in $Files)
        {
            $path = if($file -is [System.String]){$file}else{$file.FullName}
            $projectItem = $project.ProjectItems.AddFromFile($path)
            $projectItem.Properties["CopyToOutputDirectory"].Value = 2
        }
    }
}

function New-TempDirectory{
    $tempDirectoryPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()) 
    [System.IO.Directory]::CreateDirectory($tempDirectoryPath) | Out-Null  
    $tempDirectoryPath
}

function Get-VersionsFromGoogleapis{
	param($BaseUrl, $DriverName, $Platform="win32")
    $p = Invoke-WebRequest "$BaseUrl/?prefix=" -Headers @{"Accept-Encoding"="gzip"}
    $o = [xml]$p.Content 
    ($o.ListBucketResult.Contents) |? { $_.Key -like "*$DriverName*" }  |% {
		$parts =  $_.Key -split "/"; 
		if(($parts.Length -eq 2)  -and ($parts[1].EndsWith(".zip")))
		{
			$versionParts =  $parts[0] -split "\."
			$major = $versionParts[0] -replace "[^\d]",""
			$minor = $versionParts[1] -replace "[^\d]",""
            $elementPlatform = ($parts[1] -split "[_\.]")[1]
			[PsCustomObject](@{VersionNumber= [int]$major*100 +[int]$minor  ; File= "$BaseUrl/$($_.Key)"; Version= $parts[0]; Platform=$elementPlatform} )
		}
    }|? { ([string]::IsNullOrWhiteSpace($Platform) -eq $true) -or ($_.Platform -eq "$Platform")} | Sort-Object -Property VersionNumber
}

function Download-FromGoogleapis{
    param($BaseUrl, $DriverName, $DestinationPath, $Platform="win32")
    $allVersions = Get-VersionsFromGoogleapis -BaseUrl $BaseUrl -DriverName $DriverName -Platform $Platform
	$newestFile = $allVersions | Sort-Object -Property VersionNumber | Select-Object -Last 1	
    $tempDir = New-TempDirectory
    $driverTmpPath = "$tempDir\$DriverName.zip"
    Start-BitsTransfer -Source $newestFile.File -Destination $driverTmpPath    
    Expand-Archive -Path $driverTmpPath -DestinationPath $DestinationPath -Force
    Add-FileToProject -Files "$DestinationPath\$DriverName.exe"
    Remove-Item -Path $driverTmpPath -Force -Recurse    
}

function New-DriversDirectory{
    Add-ProjectDirectoryIfNotExist -DirPath "Drivers"
}

function Get-ChromeDriverVersions{
	[CmdletBinding()]
    param([string]$Platform)
    Get-VersionsFromGoogleapis -BaseUrl "http://chromedriver.storage.googleapis.com" -DriverName "chromedriver" -Platform $Platform | Sort-Object -Descending VersionNumber, Platform | Select-Object -Property @{n="Driver";e={"Chrome"}}, Version, Platform 
}


function Create-Parameters{
    param([scriptblock]$Params)
    $runtimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$parameters = . $Params
	foreach($parameter in $parameters)
	{Ge
		$runtimeParameterDictionary.Add($parameter.Name, $parameter)
	}    
    $runtimeParameterDictionary
}

function New-Parameter{
    param($Name, $Position, $ValidateSet, $Mandatory=$false)
    $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $parameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $parameterAttribute.Mandatory = $Mandatory
    $parameterAttribute.Position = $Position
    $attributeCollection.Add($parameterAttribute)   
    $validateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $ValidateSet
    $attributeCollection.Add($validateSetAttribute)
    New-Object System.Management.Automation.RuntimeDefinedParameter($Name, [string], $attributeCollection)
}

function Install-ChromeDriver{
    [CmdletBinding()]
    param([string]$Platform)
    DynamicParam{
       Create-Parameters -Params {
            New-Parameter -Name "Version" -Position 1 -ValidateSet $(Get-ChromeDriverVersions -Platform $Platform | Select-Object -ExpandProperty VersionString)        
       }
    }
    process{
        $driversPath = New-DriversDirectory
        $version = $PsBoundParameters["Version"]
        Download-FromGoogleapis -BaseUrl "http://chromedriver.storage.googleapis.com" -DriverName "chromedriver" -Platform $Platform -DestinationPath $driversPath
    }
}

function Get-IEDriverVersions{
	param([string]$Platform)
	Get-VersionsFromGoogleapis -BaseUrl "http://selenium-release.storage.googleapis.com" -DriverName "IEDriverServer" -Platform $Platform | Sort-Object -Descending VersionNumber | Select-Object -Property @{n="Driver";e={"InternetExplorer"}}, Version, Platform
}

function Install-IEDriver{
    param([string]$Platform)
    $driversPath = New-DriversDirectory
    Download-FromGoogleapis -BaseUrl "http://selenium-release.storage.googleapis.com" -DriverName "IEDriverServer" -Platform $Platform -DestinationPath  $driversPath
}


function Get-PahntomJSDriverAvailabeFiles{
    param([string]$Platform)    
    $data = Invoke-RestMethod -Method Get -Uri https://api.bitbucket.org/2.0/repositories/ariya/phantomjs/downloads
    foreach($item in $data.values){ 
        if($item.name -match "phantomjs-([\d\.]+)-(.*?)\.(.*)")
        {
            $filePlatform = $Matches[2]
            if(([String]::IsNullOrWhiteSpace($Platform) -ne $true) -and ($Platform -ne $fileplatform))
            {
                continue
            }
            [PsCustomObject]@{Version=$Matches[1]; Url=$item.links.self.href; Platform=$filePlatform  ; }
        }
    }
}

function Get-PhantomJSDriverVersions{ 
    param([string]$Platform)    
    Get-PahntomJSDriverAvailabeFiles -Platform $Platform| Sort-Object Version -Descending | Select-Object -Property @{n="Driver";e={"Phantom"}}, Version, Platform
}

function Install-PhantomJSDriver{
    $newestPhantom = Get-PahntomJSDriverAvailabeFiles | Sort-Object -Property Version -Descending | Select-Object -First 1
    $tmpDir = New-TempDirectory    
    Invoke-RestMethod -Method Get -Uri $newestPhantom.Url -OutFile "$tmpDir\phantom.zip"    
    Expand-Archive -Path "$tmpDir\phantom.zip"  -DestinationPath $tmpDir
    $driversPath = New-DriversDirectory
    Get-ChildItem -Filter "phantomjs.exe" -Recurse -Path $tmpDir |  Copy-Item -Destination $driversPath -PassThru | Add-FileToProject
    Remove-Item $tmpDir -Force -Recurse
}


function Find-Matches{
    [CmdletBinding()]
    param(
            [Parameter(ValueFromPipeline=$true, Mandatory=$true)][string]$Text, 
            [string]$Pattern
        )
    process{
        foreach($t in $Text){
           [regex]::Matches($t, $Pattern) | Where-Object {$_.Length -gt 0}
        }        
    }    
}

function Get-EdgeDriverAvailableFiles {
    $page = Invoke-WebRequest -Uri https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/#downloads    
    $versions =  $page.Content | Find-Matches -Pattern "Version: (.*?) \| Edge version supported: (.*?) \|" |  ForEach-Object { @{Driver=$_.Groups[1].Value; Edge=$_.Groups[2].Value} }
    $page.Links |Where-Object {$_.innerText -like "*Release*"} |ForEach-Object { 
        foreach($v in $versions)
        {
            $releaseVersion = $_.innerText -replace "Release ",""
            if($v.Edge -like "*$($releaseVersion)*" )
            {
                [PsCustomObject]@{version = $v.Driver; path = $_.href } 
            }
        }
    }
}

function Get-EdgeDriverVersions{
    Get-EdgeDriverAvailableFiles | Sort-Object version -Descending | Select-Object -Property @{n="Driver";e={"Edge"}}, version, @{n="Platform";e={"windows"}}
}

function Install-EdgeDriver{    
    $newestEdge = Get-EdgeDriverAvailableFiles | Sort-Object version -Descending | Select-Object -First 1
    $tmpDir = New-TempDirectory
    Start-BitsTransfer -Source $newestEdge.path -Destination $tmpDir
    $driversPath = New-DriversDirectory
    Get-ChildItem $tmpDir | Copy-Item -Destination $driversPath -PassThru | Add-FileToProject
    Remove-Item $tmpDir -Force -Recurse   
}

function Get-OperaDriverAvailableFiles{
     param([string]$Platform)    
     $relases = Invoke-RestMethod -Method Get -Uri https://api.github.com/repos/operasoftware/operachromiumdriver/releases
     foreach($release in $relases)     
     {        
        $version = $release.name
        foreach($asset in $release.assets)
        {            
            $nameParts = $asset.name -split "[_\.]"
            if($nameParts.length -eq 3)
            {
                $filePlatform = $nameParts[1]
                if(([String]::IsNullOrWhiteSpace($Platform) -ne $true) -and ($Platform -ne $filePlatform))
                {
                    continue
                }
                [pscustomobject](@{Version = $version; Platform=$nameParts[1]; Url=$asset.browser_download_url })
            }
        }
    }
}

function Get-OperaDriverVersions{
    param([string]$Platform)    
    Get-OperaDriverAvailableFiles -Platform $Platform | Select-Object -Property @{n="Driver";e={"Opera"}}, Version, Platform
}

function Install-OperaDriver{
    param([string]$Platform)    
    $windowsEdition = Get-OperaDriverAvailableFiles |? {$_.Platform -like "*$Platform*"} | Select-Object -First 1
    $tmpDir = New-TempDirectory
    Invoke-RestMethod -Method Get -Uri $windowsEdition.Url -OutFile "$tmpDir\opera.zip"
    Expand-Archive -Path "$tmpDir\opera.zip" -DestinationPath $tmpDir
    $driversPath = New-DriversDirectory
    Copy-Item "$tmpDir\operadriver.exe" -Destination $driversPath -PassThru | Add-FileToProject
    Remove-Item -Path $tmpDir -Force -Recurse
}

function Install-SeleniumWebDriver{
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true)][ValidateSet("Chrome","PhantomJs","InternetExplorer","Edge","Firefox", "Opera")][string]$Browser,
    [ValidateSet("win32","win64")]$Platform="win32"
    )	
    switch($Browser)
    {
        "Chrome" {Install-ChromeDriver -Platform $Platform; break}
        "PhantomJs" {Install-PhantomJSDriver; break}
        "InternetExplorer" {Install-IEDriver -Platform $Platform; break}
        "Edge" {Install-EdgeDriver; break}
        "Firefox" {Write-Host "No need to download anything. Selenium support Firefox out of the box."; break}
        "Opera" {Install-OperaDriver -Platform $Platform; break}
        default {"Unsupported browser type. Please select browser from the follwing list: Chrome, PhantomJs, InternetExplorer, Edge, Firefox, Opera"}    
    }
}

function Get-SeleniumWebDriverVersions{
	[CmdletBinding()]
    param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)][ValidateSet("Chrome","PhantomJs","InternetExplorer","Edge","Firefox", "Opera")][string]$Browser,
    [ValidateSet("win32","win64")]$Platform
    )
    process{
        foreach($currentBrowser in $Browser)
        {
            switch($currentBrowser)
            {
                "Chrome" {Get-ChromeDriverVersions -Platform $Platform; break}
                "PhantomJs" {Get-PhantomJSDriverVersions -Platform $Platform; break}
                "InternetExplorer" {Get-IEDriverVersions -Platform $Platform; break}
                "Edge" {Get-EdgeDriverVersions; break}
                "Firefox" {Write-Host "No need to download anything. Selenium support Firefox out of the box."; break}
                "Opera" {Get-OperaDriverVersions -Platform $Platform; break}
                default {"Unsupported browser type. Please select browser from the follwing list: Chrome, PhantomJs, InternetExplorer, Edge, Firefox, Opera"}    
            }
        }    
    }		
}

Export-ModuleMember -Function Install-SeleniumWebDriver, Get-SeleniumWebDriverVersions