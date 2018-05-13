#Requires -Version 5
<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
		
		File:		deploymentScript.ps1
		
		Purpose:	Deployment Automation Script
		
		Version: 	1.0.0.2 - 2nd November 2017 - Release Deployment Team
		==============================================================================================	

	.SYNOPSIS
		Deployment Automation Script
	
	.DESCRIPTION
		Deployment Automation Script
		
		Deployment steps of the script are outlined below.
		1) <TBA>
		
	.PARAMETER PolicyFilePath
		Specify the Policy File Path parameter.
	
	.PARAMETER APIMPolicyFilePath
		Specify the APIM Policy File Path parameter.
	
	.PARAMETER APIMPolicyConfigFilePath
		Specify the APIM Policy Config File Path parameter.
	
	.PARAMETER ConfigurationFilePath
		Specify the Configuration File Path parameter.
	
	.PARAMETER Environment
		Specify the Environment parameter.
	
	.PARAMETER ClientId
		Specify the Client Id parameter.
	
	.PARAMETER resourceAppIdURI
		Specify the resource AppId URI parameter.
	
	.PARAMETER TenantId
		Specify the Tenant Id parameter.
	
	.PARAMETER ClientKey
		Specify the Client Key parameter.
	
	.PARAMETER NotificationFunctionBackend
		Specify the Notification Function Backend parameter.
	
	.EXAMPLE
		Default:
		C:\PS> deploymentScript.ps1 `
			-PolicyFilePath <"PolicyFilePath"> `
			-APIMPolicyFilePath <"APIMPolicyFilePath"> `
			-APIMPolicyConfigFilePath <"APIMPolicyConfigFilePath">
			-ConfigurationFilePath <"ConfigurationFilePath"> `
			-Environment <"Environment"> `
			-ClientId <"ClientId"> `
			-resourceAppIdURI <"resourceAppIdURI"> `
			-TenantId <"TenantId"> `
			-ClientKey <"ClientKey"> `
			-NotificationFunctionBackend <"NotificationFunctionBackend">
	
#>

#region - Variables

[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true)]
	[string]$PolicyFilePath = "C:\Source\Repos\Deployment Scripts\BasePolicies.wadl.xml",
	[Parameter(Mandatory = $true)]
	[string]$APIMPolicyFilePath = "C:\Source\Repos\\Deployment Scripts\APIMBasePolicies.wadl.xml",
	[Parameter(Mandatory = $true)]
	[string]$APIMPolicyConfigFilePath = "C:\Source\Repos\Deployment Scripts\APIMPolicyConfig.dev.json",
	[Parameter(Mandatory = $true)]
	[string]$ConfigurationFilePath = "C:Source\Repos\Deployment Scripts\DeploymentConfiguration\",
	[Parameter(Mandatory = $true)]
	[String]$Environment = "dev",
	[Parameter(Mandatory = $true)]
	[string]$ClientId = "",
	[Parameter(Mandatory = $true)]
	[string]$resourceAppIdURI = "",
	[Parameter(Mandatory = $true)]
	[string]$TenantId = "",
	[Parameter(Mandatory = $true)]
	[string]$ClientKey = "",
	[Parameter(Mandatory = $true)]
	[string]$NotificationFunctionBackend = "",
	[Parameter(Mandatory = $true)]
	[string]$SubscriptionID = ""
)

$deploymentConfigurationFile = "$ConfigurationFilePath" + "DeploymentConfig.$Environment.json"
$configurationParameters = Get-Content -Path $deploymentConfigurationFile -Raw | ConvertFrom-JSON

#endregion

#region - Control Routine


$secpasswd = ConvertTo-SecureString $ClientKey -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($ClientId, $secpasswd)
Login-AzureRmAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds -SubscriptionId $SubscriptionID


[string]$ResourceGroupName = $configurationParameters.DeploymentParameters.ResourceGroupName
[string]$APIMServiceName = $configurationParameters.DeploymentParameters.APIMServiceName
[string]$CRMAPIName = $configurationParameters.DeploymentParameters.CRMAPIName
[string]$CRMAPIPath = $configurationParameters.DeploymentParameters.CRMAPIPath
[string]$CRMProductTitle = $configurationParameters.DeploymentParameters.CRMProductTitle
[string]$GetTransactionsHistoryLogicAppName = $configurationParameters.DeploymentParameters.GetTransactionsHistoryLogicAppName
[string[]]$OriginUrls = $configurationParameters.DeploymentParameters.OriginUrls
[string]$GetPiiDataBackend = $configurationParameters.DeploymentParameters.GetPiiDataBackend
[string]$CRMProductAdminEmail = $configurationParameters.DeploymentParameters.CRMProductAdminEmail


$Parameters = @{
	ResourceGroupName					  = $ResourceGroupName
	APIMServiceName					      = $APIMServiceName
	ProductTitle						  = $CRMProductTitle
	APIName							      = $CRMAPIName
	APIPath							      = $CRMAPIPath
	PolicyFilePath					      = $PolicyFilePath
	GetTransactionsHistoryLogicAppName    = $GetTransactionsHistoryLogicAppName
	OriginUrls						      = $OriginUrls
	GetPiiDataBackend					  = $GetPiiDataBackend
	APIMPolicyFilePath				      = $APIMPolicyFilePath
	APIMPolicyConfigFilePath			  = $APIMPolicyConfigFilePath
	ProductAdminEmail					  = $CRMProductAdminEmail
	NotificationFunctionBackend		      = $NotificationFunctionBackend
}
.$PSScriptRoot\CreateCRMAPI.ps1 @Parameters

#endregion