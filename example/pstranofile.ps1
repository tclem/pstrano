include 'config\deploy.ps1'

set application $null -Option AllScope
set deploy_to 	$null -Option AllScope
set scm 		'git' -Option AllScope
set scm_command '\Program Files\Git\bin\git' -Option AllScope
set repository 	$null -Option AllScope

setup {
	CheckVars
	Write-Host ("Connecting to {0} host(s)" -f $roles.web.count) $roles.web
	$sessions = New-PSSession $roles.web
	SetupRemoteFunctions
}

teardown {
	$sessions | Remove-PSSession
}

task Setup `
	-description "Sets up each of the web server roles" 
{
	Invoke-Command $sessions {
		param($deploy_dir)
		
		CheckCreatePath $deploy_dir
		CheckCreatePath ( Join-Path $deploy_dir '\releases')
		CheckCreatePath ( Join-Path $deploy_dir '\shared')
	} -ArgumentList $deploy_to
} 

task Check `
	-description "Checks server dependencies and such"
{
	# todo
} 

task Deploy `
	 -description "Deploys your project"
{
	Invoke-Command $sessions {
		param($deploy_dir, $scm_cmd, $repo)
	
		# get the latest code from the scm
		$cached_copy = Join-Path $deploy_dir '\shared\cached-copy'
		if(!(Test-Path $cached_copy)){
			# clone the repo
			& $scm_cmd clone $repo "$cached_copy"
		}
		else{
			# pull the repo
			cd $cached_copy 
			(& $scm_cmd pull) | Write-Host -ForegroundColor DarkGreen
		}
	
		# the release directory
		$release_dir = Join-Path $deploy_dir ("\releases\{0}" -f ([DateTime]::Now.ToString("yyyyMMddhhmmss")))
		
		# copy over the latest-greatest
		Copy-Item $cached_copy $release_dir -Recurse
		Write-Host ("Copied the latest cached version to {0}" -f $release_dir) -ForegroundColor Magenta
		
	} -ArgumentList $deploy_to, $scm_command, $repository
}

task Update `
	-description "Copies the latest code and updates the symlink" `
{

}

#task UpdateCode{
#}
#
#task FinializeUpdate{
#}
#

task SymLink `
	-description "Creates the final symlink to the just released version"
{
	Invoke-Command $sessions {
		param($deploy_dir)
		
		$current_symlnk = (Join-Path $deploy_dir '\current.lnk')
		$shell = New-Object -COM WScript.Shell
		$shortcut = $shell.CreateShortcut($current_symlnk)
		$shortcut.TargetPath = Resolve-Path $release_dir
		$shortcut.Save()
		Write-Host ("Created Symlink {0}" -f $current_symlnk) -ForegroundColor Magenta
		
	} -ArgumentList $deploy_to
}

#
#task Restart{
#}
#
task Rollback{
#	Invoke-Command $sessions {
#		param($deploy_dir)
#		
#		$current = Get-ChildItem $deploy_dir current.lnk
#		$shell = New-Object -COM WScript.Shell
#		$shortcut = $shell.CreateShortcut($current.fullname)
#		$current_release = Split-Path $shortcut.TargetPath -Leaf
#		"Current release is {0}" -f $current_release
#		
#		$releases_dir = Join-Path $deploy_dir 'releases'
#		$prev_release = Get-ChildItem $releases_dir | where {$_.Name -lt $current_release} | sort Name | select -First 1
#		if ($prev_release -eq $null) { throw "Failed: Nothing to rollback to" }
#		"Previous release is {0}" -f $prev_release
#		
#		# todo: actually rollback
#		
#	} -ArgumentList $deploy_to
}

after Deploy -do SymLink

function CheckVars
{
	Assert $roles.ContainsKey('web') "Failed: No servers defined for the web role"
	Assert ($deploy_to -ne $null) "Failed: deploy_to has not been set"
	Assert ($scm -eq 'git') "Failed: The only support scm is git right now"
	Assert ($scm_command -ne $null) "Failed: You must specify the scm_command"
	Assert ($repository -ne $null) "Failed: You must specify the repository"
}

function SetupRemoteFunctions
{
	Invoke-Command $sessions {
		function CheckCreatePath
		{
			param($path)
			
			if(!(Test-Path $path)){
				Write-Host ("Creating {0}" -f $path) -ForegroundColor Magenta
				[void](md $path)
			}
			else{
				Write-Host ("{0} exists" -f $path) -ForegroundColor Green
			}
		}
	}
}

# it would be nice if we could do something like this
#namespace Deploy {
#	task SubTask{
#	}
#}


