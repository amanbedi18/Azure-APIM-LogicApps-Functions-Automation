#Requires -Version 5
#Requires -Module AzureRM.ApiManagement
<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
				
		File:		SetAPIMPolicy.ps1
		
		Purpose:	Deployment Automation Script
		
		Version: 	1.0.0.2 - 2nd November 2017 - Release Deployment Team
		==============================================================================================

	.SYNOPSIS
		Deployment Automation Script
	
	.DESCRIPTION
		Deployment Automation Script
		
		Deployment steps of the script are outlined below.
		1) Set APIM Policy Functions 
					
	.EXAMPLE
		Default:
		C:\PS> SetAPIMPolicy.ps1
       
#>

#region - Functions

<#
 ==============================================================================================	 
	Script Functions
		CreateProductPolicy						- Creates Product Policy	
		SetOperationPolicy						- Set Operation Policy
		WritePolicyToProduct					- Write Policy To Product
 ==============================================================================================	
#>
function CreateProductPolicy
{
	[CmdletBinding()]
	param
	(
		[string]$APIName,
		[string]$PolicyFilePath,
		[string]$PolicyConfigFilePath
	)
	
	$json = Get-Content $PolicyConfigFilePath | Out-String | ConvertFrom-Json
	
	$path = $PolicyFilePath
	$xml = [xml](Get-Content $path)
	$xml.RemoveAll()
	
	$root = $xml.CreateElement("policies")
	$xml.AppendChild($root)
	
	$inbound = $xml.CreateElement("inbound")
	$root.AppendChild($inbound)
	$inboundbase = $xml.CreateElement("base")
	$inbound.AppendChild($inboundbase)
	
	$ratelimit = $xml.CreateElement("rate-limit")
	$ratelimit.SetAttribute("calls", $json.ratelimit.calls)
	$ratelimit.SetAttribute("renewal-period", $json.ratelimit.renewalperiod)
	$inbound.AppendChild($ratelimit)
	
	$apim = $xml.CreateElement("api")
	$apim.SetAttribute("name", $APIName)
	$apim.SetAttribute("calls", $json.ratelimit.api.calls)
	#$apim.SetAttribute("renewal-period","90")
	$ratelimit.AppendChild($apim)
	
	$backend = $xml.CreateElement("backend")
	$root.AppendChild($backend)
	$backendbase = $xml.CreateElement("base")
	$backend.AppendChild($backendbase)
	
	$outbound = $xml.CreateElement("outbound")
	$root.AppendChild($outbound)
	$outboundbase = $xml.CreateElement("base")
	$outbound.AppendChild($outboundbase)
	
	$xml.Save("$path")
}

function SetOperationPolicy
{
	[CmdletBinding()]
	param
	(
		[string]$OperationName,
		[string]$PolicyFilePath,
		[string]$PolicyConfigFilePath
	)
	
	$path = $PolicyFilePath
	$xml = [xml](Get-Content $path)
	$json = Get-Content $PolicyConfigFilePath | Out-String | ConvertFrom-Json
	$apim = $xml.GetElementsByTagName("api")
	$op = $json.ratelimit.api.operations | Where-Object { $PSItem.name -eq $OperationName }
	if ($op -ne $null)
	{
		$operation = $xml.CreateElement("operation")
		$operation.SetAttribute("name", $op.Name)
		$operation.SetAttribute("calls", $op.Call)
		$apim.AppendChild($operation)
	}
	$xml.Save("$path")
}

function WritePolicyToProduct
{
	[CmdletBinding()]
	param
	(
		[string]$ResourceGroupName,
		[string]$APIMServiceName,
		[string]$ProductTitle,
		[string]$PolicyFilePath
	)
	
	$Parameters = @{
		ResourceGroupName	  = $ResourceGroupName
		ServiceName		      = $APIMServiceName
	}
	$apicontext = New-AzureRmApiManagementContext @Parameters
	
	$Parameters = @{
		Context	      = $APIContext
		Title		  = $ProductTitle
	}
	$Product = Get-AzureRmApiManagementProduct @Parameters
	
	$Parameters = @{
		Context	    = $apicontext
		ProductId   = $Product.ProductId
	}
	Remove-AzureRmApiManagementPolicy @Parameters
	
	$Parameters = @{
		Context	     = $apicontext
		ProductId    = $Product.ProductId
		PolicyFilePath = $PolicyFilePath
	}
	Set-AzureRmApiManagementPolicy @Parameters
}

#endregion