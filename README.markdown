pstrano
===================

pstrano is a capistrano like deployment and automation tool specifically for Windows and Powershell. I have borrowed heavily from psake (http://github.com/JamesKovacs/psake) for the initial structure of the module. The task system has been changed to support before and after syntax instead of -depends.

This tool is very much considered Alpha status.

Setup Instructions
--------------------
 In order to use this file and do a deployment you need to:
	1. Make sure you have power shell installed on your development pc and all remote servers
	2. Make sure winrm is configured on each remote server (winrm quickconfig)
		a. If quickconfig fails, the following commands will configure winrm
			1. sc config "WinRM" start= auto
			2. net start WinRM
			3. winrm create winrm/config/listener?Address=*+Transport=HTTP
			4. netsh advfirewall firewall add portopening TCP 80 "Windows Remote Management"
	3. Clone the pstrano module into your Modules directory (\Documents and Settings\<username>\My Documents\WindowsPowerShell\Modules) 
		git://github.com/tclem/pstrano.git
	4. Edit your PowerShell Profile to import this module by including these lines:
		Import-Module pstrano -Force
		Set-Alias pstrano Invoke-pstrano
	5. Do some pstrano deployment action:
		pstrano setup
		pstrano deploy

		
 First time setup notes:
--------------------
 1. Right now, this command needs to be run manually to let snap sync listen on http :8080
 		"netsh http add urlacl url=http://+:8080/ user=BDS\tclem"
 		Ref: http://msdn.microsoft.com/en-us/library/ms733768.aspx


 Setting up TrustedHosts for cross domain deployment: 
 --------------------
 1. The TrustedHosts config setting needs to be set in order to enable WinRM communication between the client and 
    and the server. This setting needs to be set on both the client and the server. More information 
    regarding this setting can be found here: http://msdn.microsoft.com/en-us/library/aa384372(VS.85).aspx

    To enable trusted hosts use the following command:
			winrm set winrm/config/client @{TrustedHosts="*"}
	
    To reiterate, this command needs to be executed on both the client and the server. In the example above setting 
    TrustedHosts="*" is probably not a good idea from a security perspective. Specific host
    names or IP Addresses should be entered here. 

    If you get the following error, you will need to run the command from the windows command prompt: 
			Error: Invalid use of command line. Type "winrm -?" for help. 

		