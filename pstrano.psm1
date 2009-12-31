#Requires -Version 2.0

#-- Private Module Variables (Listed here for quick reference)
[string]$script:originalDirectory
[string]$script:formatTaskNameString
[string]$script:currentTaskName
[string]$script:defaultEnvironment
[hashtable]$script:environments
[hashtable]$script:tasks
[scriptblock]$script:taskSetupScriptBlock
[scriptblock]$script:taskTearDownScriptBlock
[system.collections.queue]$script:includes 
[system.collections.stack]$script:executedTasks
[system.collections.stack]$script:callStack

[hashtable]$script:roles

#-- Public Module Variables -- The pstrano hashtable variable is initialized in the invoke-pstrano function
$script:pstrano = @{}
Export-ModuleMember -Variable "pstrano","roles"

#-- Private Module Functions
function ExecuteTask 
{
	param([string]$taskName)
	
	Assert (![string]::IsNullOrEmpty($taskName)) "Task name should not be null or empty string"
	
	$taskKey = $taskName.Tolower()
	
	Assert ($script:tasks.Contains($taskKey)) "task [$taskName] does not exist"

	if ($script:executedTasks.Contains($taskKey)) 
	{ 
		return 
	}
  
  	Assert (!$script:callStack.Contains($taskKey)) "Error: Circular reference found for task, $taskName"

	$script:callStack.Push($taskKey)
  
	$task = $script:tasks.$taskKey
	
	$taskName = $task.Name
	
	$precondition_is_valid = if ($task.Precondition -ne $null) {& $task.Precondition} else {$true}
	
	if (!$precondition_is_valid) 
	{
		"Precondition was false not executing $name"		
	}
	else
	{
		#------------- TEC new ---------------------
		
		# Run all before tasks
		foreach($childTask in $task.BeforeTasks) {
			ExecuteTask $childTask
		}
		
		$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()	
		# Run the task
		if ($task.Action -ne $null) {
				
			try {
				$script:currentTaskName = $taskName									
				if ($script:taskSetupScriptBlock -ne $null) {
					& $script:taskSetupScriptBlock
				}
				if ($task.PreAction -ne $null) {
					& $task.PreAction
				}
				
				$script:formatTaskNameString -f $taskName
				& $task.Action
				
				if ($task.PostAction -ne $null) {
					& $task.PostAction
				}
				if ($script:taskTearDownScriptBlock -ne $null) {
					& $script:taskTearDownScriptBlock
				}
			}
			catch{
				if ($task.ContinueOnError) {
					"-"*70
					"Error in Task [$taskName] $_"
					"-"*70
					continue
				} 
				else {
					throw $_
				}
			}
		}
		$stopwatch.stop()
		$task.Duration = $stopwatch.Elapsed
		"$taskName finished in " + $task.Duration |Format-Wide
		
		# Run all after tasks
		foreach($childTask in $task.AfterTasks) {
			ExecuteTask $childTask
		}
		
		#------------- TEC new ---------------------
	
		if ($task.Postcondition -ne $null) 
		{			
			Assert (& $task.Postcondition) "Error: Postcondition failed for $taskName"
		} 		
	}
	
	$poppedTaskKey = $script:callStack.Pop()
	
	Assert ($poppedTaskKey -eq $taskKey) "Error: CallStack was corrupt. Expected $taskKey, but got $poppedTaskKey."

	$script:executedTasks.Push($taskKey)
}

function Configure_Environment 
{
	#if any error occurs in a PS function then "stop" processing immediately
	#	this does not effect any external programs that return a non-zero exit code 
	$global:ErrorActionPreference = "Stop"
}

function Cleanup-Environment 
{
	Set-Location $script:originalDirectory
	$global:ErrorActionPreference = $originalErrorActionPreference
}

#borrowed from Jeffrey Snover http://blogs.msdn.com/powershell/archive/2006/12/07/resolve-error.aspx
function Resolve-Error($ErrorRecord=$Error[0]) 
{	
	"ErrorRecord"
	$ErrorRecord | Format-List * -Force | Out-String -Stream | ? {$_}
	""
	"ErrorRecord.InvocationInfo"
	$ErrorRecord.InvocationInfo | Format-List * | Out-String -Stream | ? {$_}
	""
	"Exception"
	$Exception = $ErrorRecord.Exception
	for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException)) 
	{
		"$i" * 70
		$Exception | Format-List * -Force | Out-String -Stream | ? {$_}
		""
	}
}

function Write-Documentation 
{
	$list = New-Object System.Collections.ArrayList
	foreach($key in $script:tasks.Keys) 
	{
		if($key -eq "default") 
		{
		  continue
		}
		$task = $script:tasks.$key
		$content = "" | Select-Object Name, Description
		$content.Name = $task.Name        
		$content.Description = $task.Description
		$index = $list.Add($content)
	}

	$list | Sort 'Name' | Format-Table -Auto 
}

function Write-TaskTimeSummary
{
	#"-"*70
	#"Build Time Report"
	#"-"*70	
	$list = @()
	while ($script:executedTasks.Count -gt 0) 
	{
		$taskKey = $script:executedTasks.Pop()
		$task = $script:tasks.$taskKey
		if($taskKey -eq "default") 
		{
		  continue
		}    
		$list += "" | Select-Object @{Name="Task";Expression={$task.Name}}, @{Name="Duration";Expression={$task.Duration}}
	}
	[Array]::Reverse($list)
	$list += "" | Select-Object @{Name="Task";Expression={"Total:"}}, @{Name="Duration";Expression={$stopwatch.Elapsed}}
	$list | Format-Table -Auto | Out-String -Stream | ? {$_}  # using "Out-String -Stream" to filter out the blank line that Format-Table prepends 
}

function Load_DefaultEnvironment
{
	param([string]$name = $null)

	if($name -ne $null -and $name -ne ''){
		$script:defaultEnvironment = $name
	}
	
	Assert ($script:defaultEnvironment -ne $null) "Error: You must specify an environment or use the default switch in your script like this: environment 'production' -default"
	
	. (Resolve-Path $script:environments.$script:defaultEnvironment)
	
	"-"*70
	"Beginning deployment to $script:defaultEnvironment"
	"-"*70
}

#-- Public Module Functions
function Assert
{
<#
.SYNOPSIS 
Helper function for "Design by Contract" assertion checking. 
    
.DESCRIPTION
This is a helper function that makes the code less noisy by eliminating many of the "if" statements
that are normally required to verify assumptions in the code.
    
.PARAMETER conditionToCheck 
The boolean condition to evaluate	
Required
    
.PARAMETER failureMessage
The error message used for the exception if the conditionToCheck parameter is false
Required 
    
.EXAMPLE
Assert $false "This always throws an exception"
    
This example always throws an exception
    
.EXAMPLE
Assert ( ($i % 2) -eq 0 ) "%i is not an even number"  	

This exmaple may throw an exception if $i is not an even number
     
.LINK	
Invoke-pstrano
Task
Include
FormatTaskName
TaskSetup
TaskTearDown
    
.NOTES
It might be necessary to wrap the condition with paranthesis to force PS to evaluate the condition 
so that a boolean value is calculated and passed into the 'conditionToCheck' parameter.

Example:
    Assert 1 -eq 2 "1 doesn't equal 2"
   
PS will pass 1 into the condtionToCheck variable and PS will look for a parameter called "eq" and 
throw an exception with the following message "A parameter cannot be found that matches parameter name 'eq'"

The solution is to wrap the condition in () so that PS will evaluate it first.

    Assert (1 -eq 2) "1 doesn't equal 2"
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	
	param(
	  [Parameter(Position=0,Mandatory=1)]$conditionToCheck,
	  [Parameter(Position=1,Mandatory=1)]$failureMessage
	)
	if (!$conditionToCheck) { throw $failureMessage }
}

function Task
{
<#
.SYNOPSIS
Defines a build task to be executed by pstrano 
	
.DESCRIPTION
This function creates a 'task' object that will be used by the pstrano engine to execute a build task.
Note: There must be at least one task called 'default' in the build script 
	
.PARAMETER Name 
The name of the task	
Required
	
.PARAMETER Action 
A scriptblock containing the statements to execute
Optional 

.PARAMETER PreAction
A scriptblock to be executed before the 'Action' scriptblock.
Note: This parameter is ignored if the 'Action' scriptblock is not defined.
Optional 

.PARAMETER PostAction 
A scriptblock to be executed after the 'Action' scriptblock.
Note: This parameter is ignored if the 'Action' scriptblock is not defined.
Optional 

.PARAMETER Precondition 
A scriptblock that is executed to determine if the task is executed or skipped.
This scriptblock should return $true or $false
Optional

.PARAMETER Postcondition
A scriptblock that is executed to determine if the task completed its job correctly.
An exception is thrown if the scriptblock returns $false.	
Optional

.PARAMETER ContinueOnError
If this switch parameter is set then the task will not cause the build to fail when an exception is thrown

.PARAMETER Description
A description of the task.

.EXAMPLE
A sample build script is shown below:

task default -depends Test

task Test -depends Compile, Clean { 
  "This is a test"
} 	

task Compile -depends Clean {
	"Compile"
}

task Clean {
	"Clean"
}

The 'default' task is required and should not contain an 'Action' parameter.
It uses the 'depends' parameter to specify that 'Test' is a dependency

The 'Test' task uses the 'depends' parameter to specify that 'Compile' and 'Clean' are dependencies
The 'Compile' task depends on the 'Clean' task.

Note: 
The 'Action' parameter is defaulted to the script block following the 'Clean' task. 

The equivalent 'Test' task is shown below:

task Test -depends Compile, Clean -Action { 
  $testMessage
}

The output for the above sample build script is shown below:
Executing task, Clean...
Clean
Executing task, Compile...
Compile
Executing task, Test...
This is a test

Build Succeeded!

----------------------------------------------------------------------
Build Time Report
----------------------------------------------------------------------
Name    Duration
----    --------
Clean   00:00:00.0065614
Compile 00:00:00.0133268
Test    00:00:00.0225964
Total:  00:00:00.0782496

.LINK	
Invoke-pstrano    
Include
FormatTaskName
TaskSetup
TaskTearDown
Assert
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
		[Parameter(Position=0,Mandatory=1)]
		[string]$name = $null, 
		[Parameter(Position=1,Mandatory=0)]
		[scriptblock]$action = $null, 
		[Parameter(Position=2,Mandatory=0)]
		[scriptblock]$preaction = $null,
		[Parameter(Position=3,Mandatory=0)]
		[scriptblock]$postaction = $null,
		[Parameter(Position=4,Mandatory=0)]
		[scriptblock]$precondition = $null,
		[Parameter(Position=5,Mandatory=0)]
		[scriptblock]$postcondition = $null,
		[Parameter(Position=6,Mandatory=0)]
		[switch]$continueOnError = $false, 
		[Parameter(Position=7,Mandatory=0)]
		[string]$description = $null		
		)
		
	$newTask = @{
		Name = $name
		PreAction = $preaction
		Action = $action
		PostAction = $postaction
		Precondition = $precondition
		Postcondition = $postcondition
		ContinueOnError = $continueOnError
		Description = $description
		Duration = 0
		BeforeTasks = @()
		AfterTasks = @()
	}
	
	$taskKey = $name.ToLower()
	$script:tasks.$taskKey = $newTask
	
	# todo: consider allowing this (just overwrite current task, this should allow overriding our core behavior)
	#Assert (!$script:tasks.ContainsKey($taskKey)) "Error: Task, $name, has already been defined."
}

function Role
{
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$name = $null,
	[Parameter(Position=1,Mandatory=1)]
	[string[]]$hosts = @()
	)
	Write-Verbose "Adding role '$name' for hosts: $hosts"
	$roleKey = $name.ToLower()
	if(!$script:roles.ContainsKey($roleKey)){
		$script:roles.$roleKey = @()
	}
	$script:roles.$roleKey += $hosts
}

function After
{
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$task = $null,
	[Parameter(Position=1,Mandatory=1)]
	[string[]]$do = $null
	)
	
	$taskKey = $task.ToLower()
	Assert ($script:tasks.Contains($taskKey)) "Cannot add task [$do] after task [$task] because task [$task] does not exist"
	$t = $script:tasks.$taskKey
	foreach($taskToDo in $do){
		$doTaskKey = $taskToDo.ToLower()
		Assert ($script:tasks.Contains($doTaskKey)) "Cannot add task [$taskToDo] after task [$task] because task [$taskToDo] does not exist"
		$t.AfterTasks += $doTaskKey
	}
}

function Before
{
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$task = $null,
	[Parameter(Position=1,Mandatory=1)]
	[string[]]$do = $null
	)
	
	$taskKey = $task.ToLower()
	Assert ($script:tasks.Contains($taskKey)) "Cannot add task [$do] before task [$task] because task [$task] does not exist"
	$t = $script:tasks.$taskKey
	foreach($taskToDo in $do){
		$doTaskKey = $taskToDo.ToLower()
		Assert ($script:tasks.Contains($doTaskKey)) "Cannot add task [$taskToDo] before task [$task] because task [$taskToDo] does not exist"
		$t.BeforeTasks += $doTaskKey
	}
}

function Environment
{
	[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$name = $null,
	[Parameter(Position=1,Mandatory=0)]
	[switch]$default = $false
	)

	$scriptPath = (Split-Path -parent $MyInvocation.ScriptName)
	$path = Join-Path $scriptPath "deploy\$name.ps1"
	$script:environments.$name += $path
	
#	. (Resolve-Path $path)
	
	if($default){
		$script:defaultEnvironment = $name
	}
}

function Include
{
<#
.SYNOPSIS
Include the functions or code of another powershell script file into the current build script's scope

.DESCRIPTION
A build script may declare an "includes" function which allows you to define
a file containing powershell code to be included and added to the scope of 
the currently running build script.

.PARAMETER fileNamePathToInclude 
A string containing the path and name of the powershell file to include
Required

.EXAMPLE
A sample build script is shown below:

Include ".\build_utils.ps1"

Task default -depends Test

Task Test -depends Compile, Clean { 
}

Task Compile -depends Clean { 
}

Task Clean { 
}

 
.LINK	
Invoke-pstrano    
Task
FormatTaskName
TaskSetup
TaskTearDown
Assert	

.NOTES
You can have more than 1 "Include" function defined in the script
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$fileNamePathToInclude
	)
	if(!(test-path $fileNamePathToInclude)){
		$scriptPath = (Split-Path -parent $MyInvocation.ScriptName)
		$fileNamePathToInclude = Join-Path $scriptPath $fileNamePathToInclude
	}
	
	Assert (test-path $fileNamePathToInclude) "Error: Unable to include $fileNamePathToInclude. File not found."
	$script:includes.Enqueue((Resolve-Path $fileNamePathToInclude));
}

function FormatTaskName 
{
<#
.SYNOPSIS
Allows you to define a format mask that will be used when pstrano displays
the task name

.DESCRIPTION
Allows you to define a format mask that will be used when pstrano displays
the task name.  The default is "Executing task, {0}..."

.PARAMETER format 
A string containing the format mask to use, it should contain a placeholder ({0})
that will be used to substitute the task name.
Required

.EXAMPLE
A sample build script is shown below:

FormatTaskName "[Task: {0}]"

Task default -depends Test

Task Test -depends Compile, Clean { 
}

Task Compile -depends Clean { 
}

Task Clean { 
}
	
You should get the following output:
------------------------------------

[Task: Clean]
[Task: Compile]
[Task: Test]

Build Succeeded

----------------------------------------------------------------------
Build Time Report
----------------------------------------------------------------------
Name    Duration
----    --------
Clean   00:00:00.0043477
Compile 00:00:00.0102130
Test    00:00:00.0182858
Total:  00:00:00.0698071
 
.LINK	
Invoke-pstrano    
Include
Task
TaskSetup
TaskTearDown
Assert	
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[string]$format
	)
	$script:formatTaskNameString = $format
}

function TaskSetup 
{
<#
.SYNOPSIS
Adds a scriptblock that will be executed before each task

.DESCRIPTION
This function will accept a scriptblock that will be executed before each
task in the build script.  

.PARAMETER include 
A scriptblock to execute
Required

.EXAMPLE
A sample build script is shown below:

Task default -depends Test

Task Test -depends Compile, Clean { 
}
	
Task Compile -depends Clean { 
}
	
Task Clean { 
}

TaskSetup {
	"Running 'TaskSetup' for task $script:currentTaskName"
}

You should get the following output:
------------------------------------

Running 'TaskSetup' for task Clean
Executing task, Clean...
Running 'TaskSetup' for task Compile
Executing task, Compile...
Running 'TaskSetup' for task Test
Executing task, Test...

Build Succeeded

----------------------------------------------------------------------
Build Time Report
----------------------------------------------------------------------
Name    Duration
----    --------
Clean   00:00:00.0054018
Compile 00:00:00.0123085
Test    00:00:00.0236915
Total:  00:00:00.0739437
 
.LINK	
Invoke-pstrano    
Include
Task
FormatTaskName
TaskTearDown
Assert	
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[scriptblock]$setup
	)
	$script:taskSetupScriptBlock = $setup
}

function TaskTearDown 
{
<#
.SYNOPSIS
Adds a scriptblock that will be executed after each task

.DESCRIPTION
This function will accept a scriptblock that will be executed after each
task in the build script.  

.PARAMETER include 
A scriptblock to execute
Required

.EXAMPLE
A sample build script is shown below:

Task default -depends Test

Task Test -depends Compile, Clean { 
}
	
Task Compile -depends Clean { 
}
	
Task Clean { 
}

TaskTearDown {
	"Running 'TaskTearDown' for task $script:currentTaskName"
}

You should get the following output:
------------------------------------

Executing task, Clean...
Running 'TaskTearDown' for task Clean
Executing task, Compile...
Running 'TaskTearDown' for task Compile
Executing task, Test...
Running 'TaskTearDown' for task Test

Build Succeeded

----------------------------------------------------------------------
Build Time Report
----------------------------------------------------------------------
Name    Duration
----    --------
Clean   00:00:00.0064555
Compile 00:00:00.0218902
Test    00:00:00.0309151
Total:  00:00:00.0858301
 
.LINK	
Invoke-pstrano    
Include
Task
FormatTaskName
TaskSetup
Assert	
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	param(
	[Parameter(Position=0,Mandatory=1)]
	[scriptblock]$teardown)
	$script:taskTearDownScriptBlock = $teardown
}

function Invoke-pstrano 
{
<#
.SYNOPSIS
Runs a pstrano build script.

.DESCRIPTION
This function runs a pstrano build script 

.PARAMETER BuildFile 
The pstrano build script to execute (default: default.ps1).	

.PARAMETER TaskList 
A comma-separated list of task names to execute

.PARAMETER Framework 
The version of the .NET framework you want to build
Possible values: '1.0', '1.1', '2.0', '3.0',  '3.5'
Default = '3.5'

.PARAMETER Docs 
Prints a list of tasks and their descriptions	
	
.EXAMPLE
Invoke-pstrano 
	
Runs the 'default' task in the 'default.ps1' build script in the current directory

.EXAMPLE
Invoke-pstrano '.\build.ps1'

Runs the 'default' task in the '.build.ps1' build script

.EXAMPLE
Invoke-pstrano '.\build.ps1' Tests,Package

Runs the 'Tests' and 'Package' tasks in the '.build.ps1' build script

.EXAMPLE
Invoke-pstrano '.\build.ps1' -docs

Prints a report of all the tasks and their descriptions and exits
	
.OUTPUTS
    If there is an exception and '$pstrano.use_exit_on_error' -eq $true
	then runs exit(1) to set the DOS lastexitcode variable 
	otherwise set the '$pstrano.build_success variable' to $true or $false depending
	on whether an exception was thrown

.LINK
Task
Include
FormatTaskName
TaskSetup
TaskTearDown
Assert	
#>
[CmdletBinding(
    SupportsShouldProcess=$False,
    SupportsTransactions=$False, 
    ConfirmImpact="None",
    DefaultParameterSetName="")]
	
	param(
		[Parameter(Position=0,Mandatory=0)]
		[string[]]$taskList = @(),
		[Parameter(Position=1,Mandatory=0)]
		[string]$environment = $null,
		[Parameter(Position=2,Mandatory=0)]
	  	[string]$scriptFile = 'pstranofile.ps1',
		[Parameter(Position=3,Mandatory=0)]
	  	[switch]$explain = $false	  
	)

	Begin 
	{	
		$script:pstrano.build_success = $false
		$script:pstrano.use_exit_on_error = $false
		$script:pstrano.log_error = $false
		$script:pstrano.deploy_script_file = $null
		
		$script:formatTaskNameString = "Executing task, {0}..."
		$script:taskSetupScriptBlock = $null
		$script:taskTearDownScriptBlock = $null
		$script:executedTasks = New-Object System.Collections.Stack
		$script:callStack = New-Object System.Collections.Stack
		$script:originalDirectory = Get-Location	
		$originalErrorActionPreference = $global:ErrorActionPreference
		
		$script:tasks = @{}
		$script:roles = @{}
		$script:environments = @{}
		$script:defaultEnvironment = $null
		$script:includes = New-Object System.Collections.Queue	
	}
	
	Process 
	{	
		try 
		{
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

			# Execute the build file to set up the tasks and defaults
			Assert (test-path $scriptFile) "Error: Could not find the deployment script file, $scriptFile."
			
			$script:pstrano.deploy_script_file = dir $scriptFile
			set-location $script:pstrano.deploy_script_file.Directory
			. $script:pstrano.deploy_script_file.FullName
						
			if ($explain) 
			{
				Write-Documentation
				Cleanup-Environment				
				return								
			}

			Configure_Environment

			# N.B. The initial dot (.) indicates that variables initialized/modified
			#      in the propertyBlock are available in the parent scope.
			while ($script:includes.Count -gt 0) 
			{
				$includeBlock = $script:includes.Dequeue()
				. $includeBlock
			}
			
			Load_DefaultEnvironment $environment

			# Execute the list of tasks
			if($taskList.Length -ne 0) 
			{
				foreach($task in $taskList) 
				{
					ExecuteTask $task
				}
			}  
			else 
			{
				throw 'Error: You must specify a task to run. Run Invoke-pstrano -docs to see a list of available tasks'
			}

			$stopwatch.Stop()
			
			"`nDeploy Succeeded!`n" 
			"-"*70
			
			Write-TaskTimeSummary		
			
			$script:pstrano.build_success = $true
		} 
		catch 
		{	
			#Append detailed exception to log file
			if ($script:pstrano.log_error)
			{
				$errorLogFile = "pstrano-error-log-{0}.log" -f ([DateTime]::Now.ToString("yyyyMMdd"))
				"-" * 70 >> $errorLogFile
				"{0}: An Error Occurred. See Error Details Below: " -f [DateTime]::Now >>$errorLogFile
				"-" * 70 >> $errorLogFile
				Resolve-Error $_ >> $errorLogFile
			}
			
            $scriptFileName = Split-Path $scriptFile -leaf
            if (test-path $scriptFile) { $scriptFileName = $script:pstrano.deploy_script_file.Name }		
			Write-Host -foregroundcolor Red ($scriptFileName + ":" + $_)				
			
			if ($script:pstrano.use_exit_on_error) 
			{ 
				exit(1)				
			} 
			else 
			{
				$script:pstrano.build_success = $false
			}
		}
	} #Process
	
	End 
	{
		# Clear out any global variables
		Cleanup-Environment
	}
}

Export-ModuleMember -Function "Invoke-pstrano","Task","Include","FormatTaskName","TaskSetup","TaskTearDown","Assert","Role","After","Before"