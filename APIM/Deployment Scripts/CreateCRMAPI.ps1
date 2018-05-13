#Requires -Version 5
#Requires -Module AzureRM.ApiManagement
<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
		
		File:		CreateCRMAPI.ps1
		
		Purpose:	Deployment Automation Script
		
		Version: 	1.0.0.2 - 2nd November 2017 - Release Deployment Team
		==============================================================================================

	.SYNOPSIS
		Deployment Automation Script for creating the API Operations
	
	.DESCRIPTION
		Deployment Automation Script for creating the API Operations
		
		Deployment steps of the script are outlined below.
		1) Create new ADP API Context
		2) Configure Operation - Get PII data
		3) Configure Operation - Get Transaction History
		4) Configure Operation - Get Order Status
		5) Add Policy to Product
	
	.PARAMETER ResourceGroupName
		Specify the Resource Group Name parameter.
			
	.PARAMETER APIMServiceName
		Specify the APIM Service Name parameter.
	
	.PARAMETER ProductTitle
		Specify the Product Title parameter.
	
	.PARAMETER APIName
		Specify the API Name parameter.
	
	.PARAMETER APIPath
		Specify the API Path parameter.
	
	.PARAMETER PolicyFilePath
		Specify the Policy File Path parameter.
	
	.PARAMETER GetTransactionsHistoryLogicAppName
		Specify the Get Transactions History LogicApp Name parameter.
	
	.PARAMETER OriginUrls
		Specify the Origin Urls parameter.
	
	.PARAMETER GetPiiDataBackend
		Specify the Get Pii Data Backend parameter.
	
	.PARAMETER APIMPolicyFilePath
		Specify the APIM Policy File Path parameter.
	
	.PARAMETER APIMPolicyConfigFilePath
		Specify the APIM Policy Config File Path parameter.
	
	.PARAMETER ProductAdminEmail
		Specify the Product Admin Email parameter.
	
	.PARAMETER NotificationFunctionBackend
		Specify the Notification Function Backend parameter.
		
	.EXAMPLE
		Default:
		C:\PS> CreateCRMAPI.ps1 `
			-ResourceGroupName <"ResourceGroupName"> `
			-APIMServiceName <"APIMServiceName"> `
			-ProductTitle <"ProductTitle"> `
			-APIName <"APIName"> `
			-APIPath <"APIPath"> `
			-PolicyFilePath <"PolicyFilePath"> `
			-GetTransactionsHistoryLogicAppName <"GetTransactionsHistoryLogicAppName"> `
			-OriginUrls <"OriginUrls","OriginUrls"> `
			-GetPiiDataBackend <"GetPiiDataBackend"> `
			-APIMPolicyFilePath <"APIMPolicyFilePath"> `
			-APIMPolicyConfigFilePath <"APIMPolicyConfigFilePath">
			-ProductAdminEmail <"ProductAdminEmail"> `
			-NotificationFunctionBackend <"NotificationFunctionBackend">
	
#>

#region - Variables

[CmdletBinding()]
param
(
	[Parameter(Mandatory = $true)]
	[string]$ResourceGroupName,
	[Parameter(Mandatory = $true)]
	[string]$APIMServiceName,
	[Parameter(Mandatory = $true)]
	[string]$ProductTitle,
	[Parameter(Mandatory = $true)]
	[string]$APIName,
	[Parameter(Mandatory = $true)]
	[string]$APIPath,
	[Parameter(Mandatory = $true)]
	[string]$PolicyFilePath,
	[Parameter(Mandatory = $true)]
	[string]$GetTransactionsHistoryLogicAppName,
	[Parameter(Mandatory = $true)]
	[string[]]$OriginUrls,
	[Parameter(Mandatory = $true)]
	[string]$GetPiiDataBackend,
	[Parameter(Mandatory = $true)]
	[string]$APIMPolicyFilePath,
	[Parameter(Mandatory = $true)]
	[string]$APIMPolicyConfigFilePath,
	[Parameter(Mandatory = $true)]
	[string]$ProductAdminEmail,
	[Parameter(Mandatory = $true)]
	[string]$NotificationFunctionBackend
)

#region - Run PowerShell pre-reqs
.$PSScriptRoot\UpdatePolicies.ps1
.$PSScriptRoot\SetAPIMPolicy.ps1
#endregion

#region - Control Routine

[string[]]$cacheparams
[string]$backendUrl

$logicappname
$pathprefix
$Protocol = "HTTPS"
$CRMServiceGroup = "CRMServiceGroup"
[bool]$EnableRetry = $true

#endregion

#region - Control Routine

#region - Create new ADP API Context
Write-Output "Getting API Context"
$Parameters = @{
	ResourceGroupName	  = $ResourceGroupName
	ServiceName		      = $APIMServiceName
}
$APIContext = New-AzureRmApiManagementContext @Parameters

Write-Output "Getting Product"
$Parameters = @{
	Context	      = $APIContext
	Title		  = $ProductTitle
}
$Product = Get-AzureRmApiManagementProduct @Parameters

Write-Output "Getting API"
$Parameters = @{
	Context	       = $APIContext
	Name		   = $APIName
}
$API = Get-AzureRmApiManagementApi @Parameters
if ($API -eq $null)
{
	#region - Create a new API
	Write-Output "Creating API"
	$Parameters = @{
		Context		      = $APIContext
		Name			  = $APIName
		Path			  = $APIPath
		Protocols		  = $Protocol
		ServiceUrl	      = $GetPiiDataBackend
	}
	$API = New-AzureRmApiManagementApi @Parameters
	
	Write-Output "Adding the new API to Product"
	$Parameters = @{
		ApiId    = $API.ApiId
		Context  = $APIContext
		ProductId = $Product.ProductId
	}
	Add-AzureRmApiManagementApiToProduct @Parameters
	
	Write-Output "Publishing the Product"
	$Parameters = @{
		ProductId    = $Product.ProductId
		Context	     = $APIContext
		State	     = 'Published'
	}
	Set-AzureRmApiManagementProduct @Parameters
	#endregion
}

$CacheHeader = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
$CacheHeader.Name = 'Cache-Control'
$CacheHeader.Type = 'string'
$CacheHeader.Values = @('no-cache')
$CacheHeader.DefaultValue = @('no-cache')

$user = Get-AzureRmApiManagementUser -Context $APIContext | Where-Object { $PSItem.Email -eq $ProductAdminEmail }
if ($user -eq $null)
{
	#region - Create new API User
	$Parameters = @{
		Context		    = $APIContext
		FirstName	    = "CRM"
		LastName	    = "ServiceAccount"
		Email		    = $ProductAdminEmail
		Password	    = "CRMServiceAccount"
	}
	$user = New-AzureRmApiManagementUser @Parameters
	#endregion
}

$Parameters = @{
	Context	      = $APIContext
	Name		  = $CRMServiceGroup
}
$UserGroup = Get-AzureRmApiManagementGroup @Parameters
if ($UserGroup -eq $null)
{
	#region - Create new API UserGroup
	$UserGroup = New-AzureRmApiManagementGroup @Parameters
	#endregion
}

$Parameters = @{
	Context	      = $APIContext
	GroupId	      = $UserGroup.GroupId
	UserId	      = $user.UserId
}
Add-AzureRmApiManagementUserToGroup @Parameters

$Parameters = @{
	Context	       = $APIContext
	GroupId	       = $UserGroup.GroupId
	ProductId	   = $Product.ProductId
}
Add-AzureRmApiManagementProductToGroup @Parameters

$Parameters = @{
	Context		    = $APIContext
	UserId		    = $user.UserId
	ProductId	    = $Product.ProductId
	Name		    = "CRMAccessKey"
}
New-AzureRmApiManagementSubscription @Parameters

CreateProductPolicy $APIName $APIMPolicyFilePath $APIMPolicyConfigFilePath
#endregion

#region - Operation - Get PII data

#region - Parameters for Operation - Get PII data
$GetPIIOperationName = "Get PII Data"
$GetPIIOperationURLTemplate = "/BigDataCustomer/getPIIData/{SampleId}"
$GetPIIOperationDescription = "This operation gets the PII Data based on `n<br />Required Parameter: SampleId(string)"
#endregion

#region - Check for the existance of Operation - Get PII data
Write-Output "Getting Operation: $GetPIIOperationName"
$Parameters = @{
	ApiId    = $API.ApiId
	Context  = $APIContext
}
$op = Get-AzureRmApiManagementOperation @Parameters

$opreq = $op | Where-Object { $PSItem.name -eq $GetPIIOperationName }
if ($opreq -ne $null)
{
	#region - Remove Operation
	$Parameters = @{
		ApiId    = $API.ApiId
		Context  = $APIContext
		OperationId = $opreq.OperationId
	}
	Remove-AzureRmApiManagementOperation @Parameters
	#endregion
}
    #-------If the operation does not exist, Create a new operation- Get PII data
    Write-Output "Creating Operation: $GetPIIOperationName"
    $Request = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementRequest
    
    $Request.Headers = @($CacheHeader)
    $SampleId = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
    $SampleId.Name = "SampleId"
    $SampleId.Description = "Sample ID"
    $SampleId.Type = "string"
	$Parameters = @{
	ApiId   = $API.ApiId
	Context = $APIContext
	Method  = 'GET'
	Name    = $GetPIIOperationName
	UrlTemplate = $GetPIIOperationURLTemplate
	TemplateParameters = @($SampleId)
	Description = $GetPIIOperationDescription
	Request = $Request
}
     
    New-AzureRmApiManagementOperation @Parameters
	setPolicies $GetPIIOperationName $logicappname $ResourceGroupName $APIMServiceName $APIName $policyFilePath $pathprefix $OriginUrls $cacheparams $GetPiiDataBackend $EnableRetry
    Write-Output "Created Operation: $GetPIIOperationName"

SetOperationPolicy $GetPIIOperationName $APIMPolicyFilePath $APIMPolicyConfigFilePath

#endregion

#endregion

#region - Operation - Get Transaction History

#region - Parameters for Operation - Get Transaction History
$TransactionHistoryOperationName = "Get Transaction History"
$TransactionHistoryOperationPath = "/GetTransactionHistory?SampleId={SampleId}"
$TransactionHistoryOperationDescription = "This operation gets the transaction history of a customer based on `n<br />Required Parameter: SampleId(string) and `n<br />Optional Parameter: AnotherId(string)"
$TransactionHistoryResponseStatusCode = "200"
$TransactionHistoryPathPrefix = "/SampleId/{SampleId}"
$TransactionHistoryCacheParams = @("SampleId", "AnotherId")
#endregion

#region - Check for the existance of Operation - Get Transaction History
Write-Output "Getting Operation: $TransactionHistoryOperationName"
$Parameters = @{
	ApiId	  = $API.ApiId
	Context   = $APIContext
}
$op = Get-AzureRmApiManagementOperation @Parameters

$opreq = $op | Where-Object { $PSItem.name -eq $TransactionHistoryOperationName }
if ($opreq -ne $null)
{
	#region - Remove Operation
	$Parameters = @{
		ApiId	  = $API.ApiId
		Context   = $APIContext
		OperationId = $opreq.OperationId
	}
	Remove-AzureRmApiManagementOperation @Parameters
	#endregion
}
#endregion

#region - Create a new Operation - Get Transaction History
Write-Output "Creating Operation: $TransactionHistoryOperationName"
$Request = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementRequest
$Request.Description = "Get the transaction history of a customer based on the Sample ID and AnotherId"

$Header = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
$Header.Name = 'Content-Type'
$Header.Type = 'string'
$Header.Values = @('application/json')
$Header.DefaultValue = @('application/json')
$Request.Headers = @($Header)

$AnotherId = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
$AnotherId.Name = "AnotherId"
$AnotherId.Description = "AnotherId"
$AnotherId.Type = "string"
$Request.QueryParameters = @($AnotherId)

$RequestRepresentation = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementRepresentation
$RequestRepresentation.ContentType = 'application/json'
$Request.Representations = @($requestRepresentation)

$SampleId = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
$SampleId.Name = "SampleId"
$SampleId.Description = "Smaple ID"
$SampleId.Type = "string"

$Response = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementResponse
$Response.StatusCode = $TransactionHistoryResponseStatusCode

$Parameters = @{
	ApiId   = $API.ApiId
	Context = $APIContext
	Name    = $TransactionHistoryOperationName
	Method  = 'GET'
	UrlTemplate = $TransactionHistoryOperationPath
	TemplateParameters = @($SampleId)
	Description = $TransactionHistoryOperationDescription
	Request = $Request
	Responses = @($Response)
}
New-AzureRmApiManagementOperation @Parameters

Write-Output "Created Operation: $TransactionHistoryOperationName"

#------Call the policy setting script with parameters to connect the Logic App
	Write-Output "Adding Policy to Operation: $TransactionHistoryOperationName"
    setPolicies $TransactionHistoryOperationName $GetTransactionsHistoryLogicAppName $ResourceGroupName $APIMServiceName $APIName $PolicyFilePath $TransactionHistoryPathPrefix $OriginUrls $TransactionHistoryCacheParams $backendUrl
	Write-Output "Added Policy to Operation: $TransactionHistoryOperationName"

SetOperationPolicy $TransactionHistoryOperationName $APIMPolicyFilePath $APIMPolicyConfigFilePath

#endregion

#endregion

#region - Operation - Get Order Status

#region - Parameters for Operation - Get Order Status
$NotificationOperationName = "Notification"
$NotificationOperationURLTemplate = "/"
$NotificationRequestRepresentationContentType = "application/json"
$NotificationRequestRepresentationSample = "{`n""NotificationType"":""Email"",`n""To"":""test@microsoft.com"",`n""Subject"":""test"",`n""Message"":""test""`n}"
$NotificationPrefixPath = ""
$NotificationOperationDescription = "This operation sends the message to service bus through Azure Function `n<br />Email `n<br />{ `n<br />""NotificationType"": ""Email"", `n<br />""Message"": ""<table align='center' border='1' cellpadding='0' cellspacing='0' width='600'><tr><td bgcolor='#70bbd9'>Row 1</td></tr><tr><td bgcolo='#ffffff'>Row 2</td></tr><tr><td bgcolor='#ee4c50'>Row 3</td></tr></table>"", `n<br />""To"": ""v-charis@microsoft.com"", `n<br />""Subject"": ""test"" `n<br />} `n<br />SMS `n<br />{ `n<br />""NotificationType"": ""SMS"", `n<br />""Message"": ""test"", `n<br />""Phone"": ""085719723349"" `n<br />} `n<br />Push Notification `n<br />{ `n<br />""NotificationType"": ""PushNotification"", `n<br />""Message"": ""test"" `n<br />} Note: Zero should be prefixed to Phone number for SMS Notification"
#endregion

#region - Check for the existence of Operation - Get Order Status
Write-Output "Getting Operation: $NotificationOperationName"
$Parameters = @{
	ApiId    = $API.ApiId
	Context  = $APIContext
}
$op = Get-AzureRmApiManagementOperation @Parameters

$opreq = $op | Where-Object { $PSItem.name -eq $NotificationOperationName }
if ($opreq -ne $null)
{
	#region - Remove Operation
	$Parameters = @{
		ApiId    = $API.ApiId
		Context  = $APIContext
		OperationId = $opreq.OperationId
	}
	Remove-AzureRmApiManagementOperation @Parameters
	#endregion
}
#endregion

#region - Create a new Operation - Get Order Status
Write-Output "Creating Operation: $NotificationOperationName"
$Request = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementRequest
$Request.Description = $NotificationDescription

$Header = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementParameter
$Header.Name = 'Content-Type'
$Header.Type = 'string'
$Header.Values = @('application/json')
$Header.DefaultValue = @('application/json')
$Request.Headers = @($Header)

$NotificationRequestRepresentation = New-Object -TypeName Microsoft.Azure.Commands.ApiManagement.ServiceManagement.Models.PsApiManagementRepresentation
$NotificationRequestRepresentation.ContentType = $NotificationRequestRepresentationContentType
$NotificationRequestRepresentation.Sample = $NotificationRequestRepresentationSample
$Request.Representations = @($NotificationRequestRepresentation)

$Parameters = @{
	ApiId   = $API.ApiId
	Context = $APIContext
	Method  = 'POST'
	Name    = $NotificationOperationName
	UrlTemplate = $NotificationOperationURLTemplate
	Description = $NotificationOperationDescription
	Request = $Request
}
New-AzureRmApiManagementOperation @Parameters

Write-Output "Created Notification Operation: $NotificationOperationName"

 #-------Call the policy setting script with parameters 
       Write-Output "Adding Policy to Operation: $NotificationOperationName"
       setPolicies $NotificationOperationName $logicappname $ResourceGroupName $APIMServiceName $APIName $policyFilePath $pathprefix $originUrl $cacheparams $NotificationFunctionBackend $EnableRetry
       Write-Output "Added Policy to Operation: $NotificationOperationName"

SetOperationPolicy $NotificationOperationName $APIMPolicyFilePath $APIMPolicyConfigFilePath
#endregion

#endregion

#region - Adding Policy to Product
Write-Output "Adding Policy to Product: $ProductTitle"
WritePolicyToProduct $ResourceGroupName $APIMServiceName $ProductTitle $APIMPolicyFilePath
Write-Output "Added Policy to Product: $ProductTitle"
#endregion

#endregion