# This is for deploying services to azure
# Generally you don't need to edit this file
# Use deploy.ps1 for your custom project settings instead
include 'config\deploy_azure.ps1'

$s = Get-PSSnapin AzureManagementToolsSnapIn
if($s -eq $null){
	Add-PSSnapin AzureManagementToolsSnapIn
}

$script:service = $null
$script:sub = $null
$script:cert = $null
$script:package = $null
$script:config = $null
$script:label = (date).ToString('hh:mm:ss MM/dd/yyyy')

setup{
	Assert ($service -ne $null) "Failed: You must specify a value for service."
	Assert ($sub -ne $null) "Failed: You must specify a value for sub. This is your azure subscriptionId"
	Assert ($cert -ne $null) "Failed: You must specify a value for cert. This is your azure certificate. Use Get-Item cert:\CurrentUser\My\<thumbprintinuppercase>"
	Assert ($package -ne $null) "Failed: You must specify a value for package. This is your azure deployment package"
	Assert ($config -ne $null) "Failed: You must specify a value for config. This is your azure deployment configuration"
	
	Write-Host "ServiceName =  $service"
	Write-Host "SubscriptionID =  $sub"
	Write-Host "Certificate = "  $cert.Subject
	Write-Host "Package =  $package"
	Write-Host "Config =  $config"
	Write-Host "label =  $label"
	
}

teardown{
}

task Deploy{
}

task CheckStagingStatus{
	Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging
}

task CreateStagingDeployment{

	# create the new deployment
	New-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging -package $package -configuration $config -label $label |
	Get-OperationStatus –WaitToComplete
}
task UpgradeStagingDeployment{

	# upgrade the staging deployment
	Get-HostedService -serviceName $service -subscriptionId $sub -certificate $cert |
	Get-Deployment -slot staging |
	Set-Deployment -package $package -label $label |
	Get-OperationStatus –WaitToComplete
}
task RunStagingDeployment{

	# set the status to running
	Get-HostedService -serviceName $service -subscriptionId $sub -certificate $cert |
	Get-Deployment -slot staging |
	Set-DeploymentStatus running |
	Get-OperationStatus –WaitToComplete
}
task SwapSlots{

	# swap the staging and production slots
	Get-HostedService -serviceName $service -subscriptionId $sub -certificate $cert |
	Get-Deployment -slot staging |
	Move-Deployment |
	Get-OperationStatus –WaitToComple
}

