#Requires -Version 5
#Requires -Module AzureRM.ApiManagement
#Requires -Module AzureRM.LogicApp
<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
				
		File:		UpdatePolicies.ps1
		
		Purpose:	Deployment Automation Script
		
		Version: 	1.0.0.1 - 27th October 2017 - Release Deployment Team
		==============================================================================================

	.SYNOPSIS
		Deployment Automation Script
	
	.DESCRIPTION
		Deployment Automation Script
		
		Deployment steps of the script are outlined below.
		1) UPdate Policies Functions
				
	.EXAMPLE
		Default:
        C:\PS> UpdatePolicies.ps1

#>

#region - Variables

Add-Type -Path "$PSScriptRoot\libs\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"

#endregion

#region - Functions

<#
 ==============================================================================================	 
	Script Functions
		GetAuthHeaders						- Get Authentication Headers
		setPolicies							- Set Policies		
 ==============================================================================================	
#>

function GetAuthHeaders
{
	# Authorization & resource Url 
	$authUrl = "https://login.windows.net/$TenantId/"
	$resource = "https://management.core.windows.net/"
	
	# Create credential for client application 
	$clientCred = [Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential]::new($ClientId, $ClientKey)
	
	# Create AuthenticationContext for acquiring token 
	$authContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authUrl, $false)
	
	# Acquire the authentication result 
	$authResult = $authContext.AcquireTokenAsync($resource, $clientCred).Result
	
	$Headers = New-Object "System.Collections.Generic.Dictionary[string,string]"
	$Headers.Add("Authorization", $authResult.CreateAuthorizationHeader())
	$Headers.Add("Content-Type", "application/json")
	return $Headers
}

function setPolicies
{
	[CmdletBinding()]
	param
	
	([string]$OperationName,
		[string]$LogicAppName,
		[string]$ResourceGroupName,
		[string]$APIMServiceName,
		[string]$APIName,
		[string]$PolicyFilePath,
		[string]$PathPrefix,
		[string[]]$OriginUrls,
		[string[]]$CacheParams,
		[string]$BackendUrl,
		[bool]$EnableRetry = $false
	)
	
	$Parameters = @{
		ResourceGroupName	  = $ResourceGroupName
		ServiceName		      = $APIMServiceName
	}
	$apicontext = New-AzureRmApiManagementContext @Parameters
	
	$Parameters = @{
		Context	      = $APIContext
		Name		  = $APIName
	}
	$API = Get-AzureRmApiManagementApi @Parameters
	
	$Parameters = @{
		Context	      = $APIContext
		ApiId		  = $API.ApiId
	}
	$op = Get-AzureRmApiManagementOperation @Parameters
	
	$opreq = $op | Where-Object { $PSItem.name -eq $OperationName }
	
	$path = $PolicyFilePath
	$xml = [xml](Get-Content $path)
	
	$xml.RemoveAll()
	
	$comment = $xml.CreateComment('    IMPORTANT:
    - Policy elements can appear only within the <inbound>, <outbound>, <backend> section elements.
    - Only the <forward-request> policy element can appear within the <backend> section element.
    - To apply a policy to the incoming request (before it is forwarded to the backend service), place a corresponding policy element within the <inbound> section element.
    - To apply a policy to the outgoing response (before it is sent back to the caller), place a corresponding policy element within the <outbound> section element.
    - To add a policy position the cursor at the desired insertion point and click on the round button associated with the policy.
    - To remove a policy, delete the corresponding policy statement from the policy document.
    - Position the <base> element within a section element to inherit all policies from the corresponding section element in the enclosing scope.
    - Remove the <base> element to prevent inheriting policies from the corresponding section element in the enclosing scope.
    - Policies are applied in the order of their appearance, from the top down.')
	
	$xml.AppendChild($comment)
	
	$root = $xml.CreateElement("policies")
	$xml.AppendChild($root)
	
	$inbound = $xml.CreateElement("inbound")
	$root.AppendChild($inbound)
	$inboundbase = $xml.CreateElement("base")
	$inbound.AppendChild($inboundbase)
	
	$backend = $xml.CreateElement("backend")
	$root.AppendChild($backend)
	$backendbase = $xml.CreateElement("base")
	$backend.AppendChild($backendbase)
	
	$outbound = $xml.CreateElement("outbound")
	$root.AppendChild($outbound)
	$outboundbase = $xml.CreateElement("base")
	$outbound.AppendChild($outboundbase)
	
	if (-not ([string]::IsNullOrEmpty($BackendUrl)))
	{
		$setbackendservice = $xml.CreateElement("set-backend-service")
		$setbackendservice.SetAttribute("id", "apim-generated-policy")
		$setbackendservice.SetAttribute("base-url", $BackendUrl)
		$inbound.AppendChild($setbackendservice)
	}
	
	if ($OriginUrls.count -gt 0)
	{
		#CORS POLICY
		$cors = $xml.CreateElement("cors")
		$inbound.AppendChild($cors)
		$origins = $xml.CreateElement("allowed-origins")
		$cors.AppendChild($origins)
		
		[string[]]$arr = $OriginUrls -split ','
		
		$arr.ForEach{
			$originUrl = $xml.CreateElement("origin")
			$originUrl.InnerText = $PSItem.Trim('"')
			$origins.AppendChild($originUrl)
		}
		
		$methods = $xml.CreateElement("allowed-methods")
		$cors.AppendChild($methods)
		$method = $xml.CreateElement("method")
		$method.InnerText = "*"
		$methods.AppendChild($method)
		
		$headers = $xml.CreateElement("allowed-headers")
		$cors.AppendChild($headers)
		$header = $xml.CreateElement("header")
		$header.InnerText = "*"
		$headers.AppendChild($header)
	}
	
	if ($CacheParams.count -gt 0)
	{
		# CACHING POLICY
		$cachelookup = $xml.CreateElement("cache-lookup")
		$cachelookup.SetAttribute("vary-by-developer-groups", "false")
		$cachelookup.SetAttribute("vary-by-developer", "false")
		$inbound.AppendChild($cachelookup)
		
		$CacheParams.ForEach{
			$queryparameter = $xml.CreateElement("vary-by-query-parameter")
			$queryparameter.InnerText = $PSItem
			$cachelookup.AppendChild($queryparameter)
		}
		
		$varybyheader = $xml.CreateElement("vary-by-header")
		$varybyheader.InnerText = "Accept"
		$cachelookup.AppendChild($varybyheader)
		
		$varybyheaderch = $xml.CreateElement("vary-by-header")
		$varybyheaderch.InnerText = "Accept-Charset"
		$cachelookup.AppendChild($varybyheaderch)
		
		# CACHING POLICY
		[int]$duration = 3600
		$cachestore = $xml.CreateElement("cache-store")
		$cachestore.SetAttribute("duration", $duration.ToString())
		$outbound.AppendChild($cachestore)
	}
	if($EnableRetry -eq $true)
{
    # RETRY POLICY
    $condition = "@(context.Response.StatusCode != 200)"
	[int] $count = 4
	[int] $interval = 10
	$firstfastretry = "true"
    $retry = $xml.CreateElement("retry")
    $retry.SetAttribute("condition",$condition)
	$retry.SetAttribute("count",$count.ToString())
	$retry.SetAttribute("interval",$interval.ToString())
	$retry.SetAttribute("first-fast-retry",$firstfastretry)
    $outbound.AppendChild($retry)
}
	
	if (-not ([string]::IsNullOrEmpty($LogicAppName)))
	{
		$rewriteuri = $xml.CreateElement("rewrite-uri")
		$rewriteuri.SetAttribute("id", "apim-generated-policy")
		$rewriteuri.SetAttribute("template", "?api-version=2016-06-01&amp;sp=/triggers/request/run&amp;{{createlead-dev}}")
		$inbound.AppendChild($rewriteuri)
		
		$setbackendservice = $xml.CreateElement("set-backend-service")
		$setbackendservice.SetAttribute("id", "apim-generated-policy")
		$setbackendservice.SetAttribute("base-url", "https://prod-55.southeastasia.logic.azure.com/workflows/ed5d9eb20e654e898cfda02cb8823b8a/triggers/request/paths/invoke")
		$inbound.AppendChild($setbackendservice)
		
		#$setheader = $xml.CreateElement("set-header")
		#$setheader.SetAttribute("name","Ocp-Apim-Subscription-Key")
		#$setheader.SetAttribute("exists-action","override")
		#$inbound.AppendChild($setheader)
		
		$armcomment = $xml.CreateComment('{
        "azureResource":  {
                              "type":  "logicapp",
                              "id":  "/subscriptions/9ef12c7b-e8dd-40a3-86be-5a2c28cb62a6/resourceGroups/RG/providers/Microsoft.Logic/workflows/createupdateprospect/triggers/request"
                          }
    }')
		$backend.AppendChild($armcomment)
		
		Write-Output "Getting Logic App Reference"
		
		$Parameters = @{
			ResourceGroupName	  = $ResourceGroupName
			Name				  = $LogicAppName
		}
		$logicapp = Get-AzureRmLogicApp @Parameters
		
		$Headers = GetAuthHeaders
		
		$trigger = Get-AzureRmLogicAppTrigger @Parameters
		
		$requestUrl = "https://management.azure.com/$($logicapp.Id)/triggers/$($trigger.Name)/listCallbackURL?api-version=2016-06-01"
		
		$Response = Invoke-RestMethod -Uri $requestUrl -Headers $Headers -Method Post
		
		Write-Output $Response
		
		[string]$signature = "sv=" + $Response.queries.sv + "&sig=" + $Response.queries.sig
		
		$propertyName = $LogicAppName + "Sig"
		
		$Parameters = @{
			Context		    = $apicontext
			Name		    = $propertyName
		}
		$property = Get-AzureRmApiManagementProperty @Parameters
		
		if ($property -ne $null)
		{
			$Parameters = @{
				Context		     = $apicontext
				PropertyId	     = $property.PropertyId.ToString()
				Value		     = $signature
				Secret		     = $true
			}
			Set-AzureRmApiManagementProperty @Parameters
		}
		else
		{
			$Parameters = @{
				Context		    = $apicontext
				Name		    = $propertyName
				Value		    = $signature
			}
			New-AzureRmApiManagementProperty @Parameters -Secret
		}
		
		$Originalstring = $Response.value
		$FirstSeparator = "/triggers/"
		$SecondSeparator = "/paths/"
		$FirstSplit = $Originalstring -split $FirstSeparator
		$SecondSplit = $FirstSplit[1] -split $SecondSeparator
		$Result = $SecondSplit[0]
		$template = [string]::Empty
		
		$propertyName = $LogicAppName + "Sig"
		if (-not ([string]::IsNullOrEmpty($PathPrefix)))
		{
			$template = $PathPrefix + "?api-version=2016-06-01&sp=/triggers/" + $Result + "/run&{{" + $propertyName + "}}"
		}
		else
		{
			$template = "?api-version=2016-06-01&sp=/triggers/" + $Result + "/run&{{" + $propertyName + "}}"
		}
		
		$nodes = $xml.policies.inbound.ChildNodes
		$node = $nodes | Where-Object { $PSItem.Name -eq "rewrite-uri" }
		
		$node.template = $template
		
		$node = $nodes | Where-Object { $PSItem.Name -eq "set-backend-service" }
		
		$node.'base-url' = $Response.basePath
		
		$jsonobj = $xml.policies.backend.'#comment'
		$psobj = $jsonobj | ConvertFrom-Json
		$psobj.azureResource.id = $logicapp.Id + "/triggers/" + $Result
		$newjson = ConvertTo-Json -InputObject $psobj
		$xml.policies.backend.'#comment' = $newjson.ToString()
		
	}
	
	$xml.Save("$path")
	
	$Parameters = @{
		ApiId	  = $API.ApiId
		Context   = $APIContext
		OperationId = $opreq.OperationId
		PolicyFilePath = $path
	}
	Set-AzureRmApiManagementPolicy @Parameters
}