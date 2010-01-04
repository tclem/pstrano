include 'config\deploy.ps1'

set application $null 			-Option AllScope
set deploy_to 	$null 			-Option AllScope
set deploy_via  remote_cache 	-Option AllScope	
set scm 		'git' 			-Option AllScope
set repository 	$null 			-Option AllScope
set scm_command '\Program Files\Git\bin\git' -Option AllScope
set http_source $null 			-Option AllScope

setup {
	CheckVars
	Write-Host ("Connecting to {0} host(s): " -f $roles.web.count) -NoNewline
	$roles.web | %{ "$_, " | Write-Host -NoNewline  }
	Write-Host
	$sessions = New-PSSession $roles.web
	SetupRemoteFunctions
}

teardown {
	$sessions | Remove-PSSession
}

task Setup {
	Invoke-Command $sessions {
		CheckCreatePath $deploy_dir
		CheckCreatePath ( Join-Path $deploy_dir '\releases')
		CheckCreatePath ( Join-Path $deploy_dir '\shared')
	}
} -description "Sets up each of the web server roles" 

task Check {
	Invoke-Command $sessions {
		param($d_via)
		
		if($d_via -eq 'remote_cache'){
			Assert(Test-Path $scm_cmd) "Failed: Cannot find scm exe (scm_command) here: $scm_cmd"
		}
		
		
	} -ArgumentList $deploy_via
} -description "Checks server dependencies and such"

task Deploy {
} -description "Deploys your project"

task DeployViaRemoteCache {
	Invoke-Command $sessions {
		# get the latest code from the scm
		WriteHostName
		$cached_copy = Join-Path $deploy_dir '\shared\cached-copy'
		if(!(Test-Path $cached_copy)){
			# clone the repo
			(& $scm_cmd clone $repo "$cached_copy") | Write-Host -ForegroundColor DarkGreen
		}
		else{
			# pull the repo
			cd $cached_copy 
			(& $scm_cmd pull) | Write-Host -ForegroundColor DarkGreen
		}
	}
} -description "Deploys your project via remote cache" -precondition { return ($deploy_via -eq 'remote_cache')}

task DeployViaHttp {
	Invoke-Command $sessions {
		$shared_dir = Join-Path $deploy_dir '\shared'
		cd $shared_dir
		
		WriteHostName 'Downloading '
		(Get-WebFile $http_download_url 'package.zip') | Write-Host -ForegroundColor DarkGray
		
		WriteHostName 'Extracted package to '
		($cached_copy = UnZip 'package.zip') | Write-Host -ForegroundColor DarkGray
		
		# bits doesn't work over pssession :(
#		Import-Module BitsTransfer
#		Start-BitsTransfer $bits_package (Join-Path $deploy_dir 'package.zip')
	}
} -description "Deploys your project via BITS" -precondition { return ($deploy_via -eq 'http')}

task UpdateRelease {
	Invoke-Command $sessions {
		# the release directory
		$release_dir = Join-Path $deploy_dir "\releases\$release_time_stamp"
		
		# copy over the latest-greatest
		Copy-Item $cached_copy $release_dir -Recurse
		WriteHostName
		Write-Host ("Copied the latest cached version to {0}" -f $release_dir) -ForegroundColor Magenta
	}
}

task SymLink {
	Invoke-Command $sessions {
		$current_symlnk = (Join-Path $deploy_dir '\current.lnk')
		$shell = New-Object -COM WScript.Shell
		$shortcut = $shell.CreateShortcut($current_symlnk)
		$shortcut.TargetPath = Resolve-Path $release_dir
		$shortcut.Save()
		WriteHostName
		Write-Host ("Created Symlink {0}" -f $current_symlnk) -ForegroundColor Magenta
	}
} -description "Creates the final symlink to the just released version"


task Restart{
	#todo: restart iis or windows services
}

# Task ordering 
after Deploy -do DeployViaRemoteCache, DeployViaHttp, UpdateRelease
after UpdateRelease -do SymLink

task Rollback {
	Invoke-Command $sessions {
		# find the current version
		$current = Get-ChildItem $deploy_dir current.lnk
		$shell = New-Object -COM WScript.Shell
		$shortcut = $shell.CreateShortcut($current.fullname)
		$current_release = Split-Path $shortcut.TargetPath -Leaf
		"Current release is {0}" -f $current_release
		
		# find the previous version
		$releases_dir = Join-Path $deploy_dir 'releases'
		$prev_release = Get-ChildItem $releases_dir | where {$_.Name -lt $current_release} | sort Name -Descending | select -First 1
		if ($prev_release -eq $null) { throw "Failed: Nothing to rollback to" }
		"Previous release is {0}" -f $prev_release
		
		# do the rollback
		$shortcut.TargetPath = Resolve-Path (Join-Path $deploy_dir "releases\$prev_release")
		$shortcut.Save()
	}
} -description "Rollsback to the previous deployment"

# Private Functions
function CheckVars
{
	Assert $roles.ContainsKey('web') "Failed: No servers defined for the web role"
	Assert ($deploy_to -ne $null) "Failed: deploy_to has not been set"
	Assert ($scm -eq 'git') "Failed: The only support scm is git right now"
	Assert ($scm_command -ne $null) "Failed: You must specify the scm_command"
	Assert ($repository -ne $null) "Failed: You must specify the repository"
	Assert ($deploy_via -ne $null) "Failed: You must specify a value for deploy_via"
	Assert (($deploy_via -eq 'remote_cache'), ($deploy_via -eq 'abcd')) "Failed: deploy_via is not set to one of the valid values"
}

function SetupRemoteFunctions
{
	Invoke-Command $sessions {
		param($d, $s, $r, $v, $source)
		
		$deploy_dir = $d
		$scm_cmd = $s
		$repo = $r
		$deploy_strategy = $v
		$http_download_url = $source
		$release_time_stamp = [DateTime]::Now.ToString("yyyyMMddhhmmss")
	
		function CheckCreatePath {
			param($path)
			
			WriteHostName
			if(!(Test-Path $path)){
				Write-Host ("Creating {0}" -f $path) -ForegroundColor Magenta
				[void](md $path)
			}
			else{
				Write-Host ("{0} exists" -f $path) -ForegroundColor Green
			}
		}
		
		function WriteHostName {
			param([string]$text)
			Write-Host ("[{0}]# $text" -f (hostname)) -ForegroundColor DarkGray -NoNewline
		}
		
		function UnZip{
			param([string]$file)
			
			$shell=new-object -com shell.application
			$CurrentLocation=get-location
			$CurrentPath=$CurrentLocation.path
			$Location=$shell.namespace($CurrentPath)
			$ZipFiles = get-childitem $file
			foreach ($ZipFile in $ZipFiles){
				$ZipFolder = $shell.namespace($ZipFile.fullname)
				$destPath = ($ZipFolder.Items() | select -First 1 ).Path
				$destPath = Join-Path $CurrentPath $destPath
				if(Test-Path $destPath){ rm $destPath -Recurse }
				$Location.CopyHere($ZipFolder.Items())
				return $destPath
			}
		}
		
		function Get-WebFile {
			param( 
				$url = (Read-Host "The URL to download"),
				$fileName = $null,
				[switch]$Passthru,
				[switch]$quiet
			)
			
			$req = [System.Net.HttpWebRequest]::Create($url);
			$res = $req.GetResponse();
			
			if($fileName -and !(Split-Path $fileName)) {
				$fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
			} 
			elseif((!$Passthru -and ($fileName -eq $null)) -or (($fileName -ne $null) -and (Test-Path -PathType "Container" $fileName)))
			{
				[string]$fileName = ([regex]'(?i)filename=(.*)$').Match( $res.Headers["Content-Disposition"] ).Groups[1].Value
				$fileName = $fileName.trim("\/""'")
				if(!$fileName) {
					$fileName = $res.ResponseUri.Segments[-1]
					$fileName = $fileName.trim("\/")
					if(!$fileName) { 
						$fileName = Read-Host "Please provide a file name"
					}
					$fileName = $fileName.trim("\/")
					if(!([IO.FileInfo]$fileName).Extension) {
						$fileName = $fileName + "." + $res.ContentType.Split(";")[0].Split("/")[1]
					}
				}
				$fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
			}
			if($Passthru) {
				$encoding = [System.Text.Encoding]::GetEncoding( $res.CharacterSet )
				[string]$output = ""
			}
			
			if($res.StatusCode -eq 200 -or $res.StatusCode -eq 'OpeningData') {
				[int]$goal = $res.ContentLength
				$reader = $res.GetResponseStream()
				if($fileName) {
					$writer = new-object System.IO.FileStream $fileName, "Create"
				}
				[byte[]]$buffer = new-object byte[] 4096
				[int]$total = [int]$count = 0
				do
				{
					$count = $reader.Read($buffer, 0, $buffer.Length);
					if($fileName) {
						$writer.Write($buffer, 0, $count);
					} 
					if($Passthru){
						$output += $encoding.GetString($buffer,0,$count)
					} elseif(!$quiet) {
						$total += $count
						if($goal -gt 0) {
						Write-Progress "Downloading $url" "Saving $total of $goal" -id 0 -percentComplete (($total/$goal)*100)
						} else {
						Write-Progress "Downloading $url" "Saving $total bytes..." -id 0
						}
					}
				} while ($count -gt 0)
				
				$reader.Close()
				if($fileName) {
					$writer.Flush()
					$writer.Close()
				}
				if($Passthru){
					$output
				}
			}
			$res.Close(); 
			if($fileName) {
				ls $fileName
			}
		}
		
	} -ArgumentList $deploy_to, $scm_command, $repository, $deploy_via, $http_source
}

# todo: it would be nice if we could do something like this
#namespace Deploy {
#	task SubTask{
#	}
#}


