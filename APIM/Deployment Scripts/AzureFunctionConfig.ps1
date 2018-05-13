#Requires -Version 5
#Requires -Module AzureRM.Resources
#Requires -Module AzureRM.Websites
<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
				
		File:		AzureFunctionConfig.ps1
		
		Purpose:	Deployment Automation Script
		
		Version: 	1.0.0.2 - 2nd November 2017 - Release Deployment Team
		==============================================================================================

	.SYNOPSIS
		Deployment Automation Script
	
	.DESCRIPTION
		Deployment Automation Script
		
		Deployment steps of the script are outlined below.
		1) <TBA>
	
	
	.PARAMETER ResourceGroupName
		Specify the ResourceGroup Name parameter.
        Example: -ResourceGroupName ""

	.PARAMETER ParamFilePath
		Specify the location of Parameter File Path parameter. 
        Example: -ParamFilePath "C:\Repos\APIM\"
        
    .PARAMETER LogicAppParamFilePath
		Specify the location of Logic App Parameter File Path parameter.
        Example: -LogicAppParamFilePath "C:\Repos\APIM\"
        
    .PARAMETER Environment
		Specify the environment name parameter, like dev, prod, uat.  
        Example: -Environment "dev"    
			
	.EXAMPLE
		Default:
        C:\PS> AzureFunctionConfig.ps1 `
            -ResourceGroupName <"ResourceGroupName"> `
            -ParamFilePath <"ParamFilePath"> `
            -LogicAppParamFilePath <"LogicAppParamFilePath"> `
            -Environment <"environment">			
#>

#region - Variables

param
(
	[Parameter(Mandatory = $true)]
	[string]$ResourceGroupName = "{Name of the resource group}",
	[Parameter(Mandatory = $true)]
	[string]$ParamFilePath = "{file path of APIM arm template parameters to get values like function name, }",
	[Parameter(Mandatory = $true)]
	[string]$LogicAppParamFilePath = "{file path of logic app arm template parameters to get values like service bus & queue name}",
	[Parameter(Mandatory = $true)]
	[string]$Environment = "{environment name to identify parameter file}"
)

Add-Type -AssemblyName System.Web

#endregion

#region - Functions

<#
 ==============================================================================================	 
	Script Functions
		New-SaSToken							- Creates new SASToken		
 ==============================================================================================	
#>
function New-SaSToken
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $True, Position = 1)]
		[String]$ResourceUri,
		[parameter(Mandatory = $True, Position = 2)]
		[String]$KeyName,
		[parameter(Mandatory = $True, Position = 3)]
		[String]$Key
	)
	
$sinceEpoch = (Get-Date).ToUniversalTime().AddYears(2) - ([datetime]'1/1/1970')

$expiry = [System.Convert]::ToString([int]($sinceEpoch.TotalSeconds))
 
$encodedResourceUri = [System.Web.HttpUtility]::UrlEncode($ResourceUri)
 
$stringToSign = $encodedResourceUri + "`n" + $expiry
$stringToSignBytes = [System.Text.Encoding]::UTF8.GetBytes($stringToSign)
$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
$hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
$hashOfStringToSign = $hmac.ComputeHash($stringToSignBytes)
$signature = [System.Convert]::ToBase64String($hashOfStringToSign)
$encodedSignature = [System.Web.HttpUtility]::UrlEncode($signature)
 
$sasToken = "SharedAccessSignature sr=$encodedResourceUri&sig=$encodedSignature&se=$expiry&skn=$KeyName"
 
return $sasToken
}

#endregion

#region - Control Routine


[string]$ClientId = "{client id of spn}"
[string]$resourceAppIdURI = "{app id uri of spn}"
[string]$TenantId = "{tenant id of azure ad}"
[string]$ClientKey = "{clint secret of the spn}"
$secpasswd = ConvertTo-SecureString $ClientKey -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($ClientId, $secpasswd)
Login-AzureRmAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds -SubscriptionId "{subscription id}"


$ParametersFile = "$ParamFilePath" + "APIMDeploy.parameters.$Environment.json"
$fileParameters = Get-Content -Path $ParametersFile -Raw | ConvertFrom-JSON
if (-not $fileParameters)
{
	throw "ERROR: Unable to retrieve AIS Template parameters file. Terminating the script unsuccessfully."
}

$siteName = $fileParameters.parameters.functionapp_name.value

$LogicAppParamFile = "$LogicAppParamFilePath" + "WorkflowsDeploy.parameters.$Environment.json"
$LogicAppParameters = Get-Content -Path $LogicAppParamFile -Raw | ConvertFrom-JSON
if (-not $LogicAppParameters)
{
	throw "ERROR: Unable to retrieve AIS Template parameters file. Terminating the script unsuccessfully."
}

$serviceBusNamespace = $LogicAppParameters.parameters.serviceBusNamespaceName.value
Write-Output $serviceBusNamespace

$serviceBusQueueName = $LogicAppParameters.parameters.serviceBusQueueName.value
Write-Output $serviceBusQueueName

$queueName = $serviceBusQueueName
$senderKeyName = 'RootManageSharedAccessKey'
$op = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName
$displayop = $op | Select-Object -First 1 -Wait
Write-Output $displayop

$outputs = ($op | Select-Object -First 1 -Wait).Outputs

$serviceBusKey = $outputs.sharedAccessPolicyPrimaryKey.Value.ToString()
Write-Output $serviceBusKey

$senderKey = $serviceBusKey

$resourceUri = "https://$serviceBusNamespace.servicebus.windows.net/$queueName"

$senderSasToken = New-SaSToken -ResourceUri $resourceUri -KeyName $senderKeyName -Key $senderKey

Write-Host ("##vso[task.setvariable variable=ServiceBusSasToken;]$senderSasToken")
Write-Host "DynamicVariable: $env:ServiceBusSasToken"

$Parameters = @{
	ResourceGroupName	  = $ResourceGroupName
	Name				  = $siteName
}
$webApp = Get-AzureRMWebApp @Parameters

$appSettingList = $webApp.SiteConfig.AppSettings
($appSettingList | Where-Object { $PSItem.Name -eq "ServiceBusQueue" }).Value = "{service bus queue name}/messages?timeout=60"
($appSettingList | Where-Object { $PSItem.Name -eq "HeaderContentType" }).Value = "application/atom+xml"
($appSettingList | Where-Object { $PSItem.Name -eq "ServiceBusAccesskey" }).Value = $senderSasToken
($appSettingList | Where-Object { $PSItem.Name -eq "ServieBusBaseUrl" }).Value = "https://$($serviceBusNamespace).servicebus.windows.net/"

#$table = new-object System.Collections.Hashtable # Use literal initializer, @{{}}, for creating a hashtable as they are case-insensitive by default
$table = @{ }
for ($i = 0; $i -lt $appSettingList.count; $i++)
{
	$table.Add($appSettingList[$i].Name, $appSettingList[$i].Value)
}
Write-Output $table

$Parameters = @{
	Name				  = $siteName
	ResourceGroupName	  = $ResourceGroupName
	AppSettings		      = $table
}
Set-AzureRmWebApp @Parameters

$FunctionAppName = $siteName

$content = Get-AzureRmWebAppPublishingProfile -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -OutputFile creds.xml -Format WebDeploy
$username = Select-Xml -Content $content -XPath "//publishProfile[@publishMethod='MSDeploy']/@userName"
$password = Select-Xml -Content $content -XPath "//publishProfile[@publishMethod='MSDeploy']/@userPWD"
$accessToken = "Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))
$FunctionAppNameLower = $FunctionAppName.ToLower()
$masterApiUrl = "https://$FunctionAppNameLower.scm.azurewebsites.net/api/functions/admin/masterkey"
$masterKeyResult = Invoke-RestMethod -Uri $masterApiUrl -Headers @{ "Authorization" = $accessToken; "If-Match" = "*" }
$masterKey = $masterKeyResult.Masterkey
Write-Output ($masterKey)

$functionApiUrl = "https://$FunctionAppName.azurewebsites.net/admin/host/keys?code=$masterKey"
$functionApiResult = Invoke-WebRequest -UseBasicParsing -Uri $functionApiUrl
$keysCode = $functionApiResult.Content | ConvertFrom-Json
$functionKey = $keysCode.Keys[0].Value

Write-Output ("https://{0}.azurewebsites.net/api/JsonRequestValidation?code={1}" -f $FunctionAppName, $functionKey)

$functionTriggerUrl = "https://$($FunctionAppName).azurewebsites.net/api/JsonRequestValidation?code=$($functionKey)"

Write-Host ("##vso[task.setvariable variable=FunctionEndpoint;]$functionTriggerUrl")
Write-Host "DynamicVariable: $env:FunctionEndpoint"

#endregion