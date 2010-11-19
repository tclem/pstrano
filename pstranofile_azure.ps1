# This is for deploying services to azure
# Generally you don't need to edit this file
# Use deploy.ps1 for your custom project settings instead
include 'config\deploy_azure.ps1'

$s = Get-PSSnapin | ? { $_.Name -like "Azure*" }
if($s -eq $null){
	Add-PSSnapin AzureManagementToolsSnapIn
}

[hashtable]$script:vars = @{}

#Default Settings
$service = $null
$storage_service = $null
$sub = $null
$cert = $null
$package = $null
$config = $null
$prod_config = $null
$label = (date).ToString('hh:mm:ss MM/dd/yyyy')

setup{
	$storage_service = $service = $vars["service"]
	if($vars["storage_service"] -ne $null){
		$storage_service = $vars["storage_service"]
	}
	$sub = $vars["sub"]
	$cert = $vars["cert"]
	$package = $vars["package"]
	$config = $vars["staging_config"]
	$prod_config = $vars["production_config"]

	Assert ($service -ne $null) "Failed: You must specify a value for service."
	Assert ($sub -ne $null) "Failed: You must specify a value for sub. This is your azure subscriptionId."
	Assert ($cert -ne $null) "Failed: You must specify a value for cert. This is your azure certificate. Use Get-Item cert:\CurrentUser\My\<thumbprintinuppercase>"
	Assert ($package -ne $null) "Failed: You must specify a value for package. This is the local path to your azure deployment package."
	Assert ($config -ne $null) "Failed: You must specify a value for staging_config. This is the local path to your azure deployment configuration file(*.cscfg)."
	Assert ($prod_config -ne $null) "Failed: You must specify a value for production_config. This is the local path to your azure deployment configuration file(*.cscfg)."
	
	Write-Host "ServiceName =  $service"
	Write-Host "SubscriptionID =  $sub"
	Write-Host "Certificate = "  $cert.Subject
	Write-Host "Package =  $package"
	Write-Host "Staging Config =  $config"
	Write-Host "Production Config =  $prod_config"
	Write-Host "label =  $label"
}

teardown{
}

task Deploy{
	$d = Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging
	if($d.Status) {
		"Updating deployment"
		Get-HostedService -serviceName $service -subscriptionId $sub -certificate $cert |
		Get-Deployment -slot staging |
		Set-Deployment -package $package -label $label |
		Get-OperationStatus –WaitToComplete
	} else {
		"Creating new deployment"
		New-Deployment -serviceName $service -StorageServiceName $storage_service -subscriptionId $sub -certificate $cert -slot staging -package $package -configuration $config -label $label |
		Get-OperationStatus –WaitToComplete
	}
}

task CheckStagingStatus{
	Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging
}

task CheckProductionStatus{
	Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot production
}

task UpdateStagingConfig {
	if((Test-Path "$config~")){
		rm -Force "$config~"
	}
	
	$d = Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging
	(Get-Content $config) | 
	% {$_ -replace "{staging_guid}", $d.DeploymentId} |
	Set-Content "$config~"
	
	$d | 
	Set-DeploymentConfiguration -Configuration "$config~" | 
	Get-OperationStatus –WaitToComplete
}

task CreateStagingDeployment{

	# create the new deployment
	New-Deployment -serviceName $service -StorageServiceName $storage_service -subscriptionId $sub -certificate $cert -slot staging -package $package -configuration $config -label $label |
	Get-OperationStatus –WaitToComplete
}
task UpgradeStagingDeployment{

	# upgrade the staging deployment
	Get-HostedService -serviceName $service -subscriptionId $sub -certificate $cert |
	Get-Deployment -slot staging |
	Set-Deployment -package $package -StorageServiceName $storage_service -label $label |
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
	
	$d = Get-Deployment -serviceName $service -subscriptionId $sub -certificate $cert -slot staging
	
	# make sure we upload our production configuration
	"Updating staging slot to use production configuration ($prod_config)"
	$d |
	Set-DeploymentConfiguration -Configuration $prod_config | 
	Get-OperationStatus –WaitToComplete

	# swap the staging and production slots
	"Swapping production and staging"
	$d |
	Move-Deployment |
	Get-OperationStatus –WaitToComplete
}

