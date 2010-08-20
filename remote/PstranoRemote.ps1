#Functions that need to be available in the remote environment
function CheckCreatePath {
	param($path)
	
	if(!(Test-Path $path)){
		Print ("Creating {0}" -f $path) Magenta
		[void](md $path)
	}
	else{
		Print ("{0} exists" -f $path) -ForegroundColor Green
	}
}
		
function CheckFile{
	param($path)
	if(!(Test-Path $path)){
		Print ("$path does not exist! You must manually put this file on the remote filesystem for pstrano to work.") -ForegroundColor Red
	}
	else{
		Print ("{0} exists" -f $path) Green
	}
}
		
function Print{
	param(
		[string]$text, 
		[System.ConsoleColor]$ForegroundColor
	)
	Write-Host "[$host_name]# " -ForegroundColor DarkGray -NoNewline
	if($ForegroundColor -eq $null){
		Write-Host $text -ForegroundColor DarkGray 
	}
	else{
		Write-Host $text -ForegroundColor $ForegroundColor 
	}
}
		
function WriteHostName {
	param([string]$text)
	Write-Host ("[{0}]# $text" -f (hostname)) -ForegroundColor DarkGray -NoNewline
}
		
function UnZip{
	param([string]$file, [string]$name = 'UnPack')
	
	$shell=new-object -com shell.application
	$CurrentLocation= get-location 
	$CurrentLocation = Join-Path $CurrentLocation $name
	if(Test-Path $CurrentLocation){ rm $CurrentLocation -Force -Recurse }
	mkdir $CurrentLocation -Force
	$Location=$shell.namespace($CurrentLocation)
	$ZipFiles = get-childitem $file
	foreach ($ZipFile in $ZipFiles){
		$ZipFolder = $shell.namespace($ZipFile.fullname)
		$Location.CopyHere($ZipFolder.Items())
	}
}
		
function InstallService{
	param(
		[string]$asm,
		[string]$name,
		[string]$user = $null
	)
	
	$env = $vars["environment"]
	$asm = (Join-Path $deploy_dir_current $asm)
	
	[void](StopService $name)
	
	$util = $vars["install_util"]
	Print "$util /servicename=$name /environment=$env /LogToConsole=true $asm"
	
	& $util "/LogToConsole=true","/environment=$env", "/servicename=$name", $asm
	
	# set service user
	#if($user -ne $null){
		#$cred = $host.ui.PromptForCredential("Snap Sync", "Please enter the user name and password that the snap sync service will run under.", $user, "UserName")
		# this works too!
		#$cred = Get-Credential $u 
		#$n = $vars["service_name"]
		$s = gwmi win32_service -filter "name='$name'"
		$s.Change($null, $null, $null, $null, $null, $null, $vars["service_user"].UserName, $vars["service_user"].GetNetworkCredential().Password, $null, $null, $null)
	#}
	
	# Start up the service
	StartService $name
}
		
function UnInstallService{
	param(
		[string]$asm,
		[string]$name
	)
	
	$asm = (Join-Path $deploy_dir_current $asm)

	if(StopService $name){
		$util = $vars["install_util"]
		Print "$util /u /LogToConsole=true $asm"
		& $util "/u", "/LogToConsole=true", $asm
	}
}
		
function StartService{
	param(
	[Parameter(Mandatory=$true)]
	[string]$name
	)
				
	$s = Get-Service "$name*"
	if($s -ne $null){
		if( $s.Status -ne "Running" ){
			Print "Starting service '$name'."
			$s.Start();
		}
		else{
			Print "Service '$name' is already running."
		}
	}
	else{
		Print "Service '$name' does not exists."
	}
}
		
function Assert{
	param(
	[Parameter(Position=0,Mandatory=1)]$conditionToCheck,
	[Parameter(Position=1,Mandatory=1)]$failureMessage
	)
	if (!$conditionToCheck) { throw $failureMessage }
}
		
function StopService{
	param([string]$name)
	
	$s = Get-Service "$name*"
	if($s -ne $null){
		if( $s.Status -eq "Running" ){
			Print "Stopping service '$name'."
			$s.Stop();
		}
		else{
			Print "Service '$name' is not running."
		}
		return $true
	}
	else{
		Print "Service '$name' does not exists."
	}
	return $false
}
		
function Get-WebFile2 {
	param( 
		$url = (Read-Host "The URL to download"),
		$fileName = $null
	)
	if($fileName -and !(Split-Path $fileName)) {
		$fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
	} 
	
	$client = New-Object Net.WebClient
	$client.Credentials = $vars["download_user"]
	$client.DownloadFile($url, $fileName)
	
	if($fileName){
		ls $fileName
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
