#----------------------------------------------------------------#
#       aoai-on-your-data-private-networking-check-tool          #
#                                                                #
# Validates Private Networking configurations on AOAI, Storage   #
#  and Search resources for AOAI Use your Data feature.          #
#                                                                #
#    Contributors:                                               #
#            Ahmad Amireh (v-aamireh)                            #  
#            Hasan Mohammad (hamohamm)                           #
#            José Direito (josedireito)                          #
# Created: 21/02/2024                                            #
#----------------------------------------------------------------#

Write-Host -ForegroundColor Yellow "
*******************************************************************
Welcome! 
This script will help you validate if your resources are correctly configured for the usage of Azure OpenAI On Your Data over a Virtual Network.

Before running this script, ensure you have implemented our guidance on how to use Azure OpenAI On Your Data securely:
https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely

Please have at hand the Resource ID's for the following resources:
    - Azure OpenAI (e.g: /subscriptions/<Subscription ID>/resourceGroups/<Resource Group>/providers/Microsoft.CognitiveServices/accounts/<Resource Name>);
    - Azure Search (e.g: /subscriptions/<Subscription ID>/resourceGroups/<Resource Group>/providers/Microsoft.Search/searchServices/<Resource Name>);
    - Storage account (e.g: /subscriptions/<Subscription ID>/resourceGroups/<Resource Group>/providers/Microsoft.Storage/storageAccounts/<Resource Name>);
    - Virtual Network (e.g: /subscriptions/<Subscription ID>/resourceGroups/<Resource Group>/providers/Microsoft.Network/virtualNetworks/<Resource Name>);
*******************************************************************"
  
$SearchResourceID = Get-UserInput "Please enter your Azure Search Resource ID:"  
$StorageResourceID = Get-UserInput "Please enter your Storage account Resource ID:"  
$AzureOpenAIResourceID = Get-UserInput "Please enter your Azure Open AI Resource ID:"  
$VnetResourceID = Get-UserInput "Please enter your Virtual Network Resource ID:"  
  
Write-Host -ForegroundColor Yellow "`nValidating configurations for the following resources:"  
Write-Host -ForegroundColor White "Azure Search Resource ID:    $SearchResourceID"  
Write-Host "Storage account Resource ID: $StorageResourceID"  
Write-Host "Azure Open AI Resource ID:   $AzureOpenAIResourceID"  
Write-Host "Virtual Network Resource ID: $VnetResourceID"  


# Retrieve resources details using Azure CLI
Write-Host -ForegroundColor Yellow "Retrieving data from your resources..."

try {  
    $Storage_data = Invoke-Expression "az resource show --ids $StorageResourceID" | ConvertFrom-Json  
    if ($LASTEXITCODE -ne 0) { throw "Error: Storage account not found. Please ensure that you have provided a valid ResourceID." }  
  
    $Search_data = Invoke-Expression "az resource show --ids $SearchResourceID" | ConvertFrom-Json  
    if ($LASTEXITCODE -ne 0) { throw "Error: Azure Search not found. Please ensure that you have provided a valid ResourceID." }  
  
    $AzureOpenAI_data = Invoke-Expression "az resource show --ids $AzureOpenAIResourceID" | ConvertFrom-Json  
    if ($LASTEXITCODE -ne 0) { throw "Error: Azure OpenAI not found. Please ensure that you have provided a valid ResourceID." }  
}  
catch {  
    Write-Host -ForegroundColor Red "Failed to retrieve information." 
    Write-Host -ForegroundColor Red $_.Exception.Message  
}  


# Validate Azure Search RBAC is enabled 
Write-Host -ForegroundColor Yellow "Validating RBAC is enabled on Azure Search..."

$enabled_role = $Search_data.properties.authOptions.PSObject.Properties.Name
Write-Host $Search_data
if ($enabled_role -eq "aadOrApiKey") {  
    Write-Host -ForegroundColor Green "Your Azure Search has RBAC correctly enabled. (Authentication option is: $enabled_role)"  
}
else {  
    Write-Host -ForegroundColor Red "Error: Your Azure Search has RBAC disabled. The authentication is set to: $enabled_role, when it should be set to aadOrApiKey
    Please follow our guidance on: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#enable-role-based-access-control"  
}  

# Validate Trusted Services are enabled on Storage account
Write-Host -ForegroundColor Yellow "Validating Trusted Services are enabled on Storage account..."

$openAiResourceName = ($AzureOpenAIResourceID -split "/")[-1]
$SearchResourceName = ($SearchResourceID -split "/")[-1]

try {
    $allowAzureServices = $Storage_data.properties.networkAcls.bypass

    if (($allowAzureServices -eq "None" ) -or ($null -eq $data -or $data -eq "")) {
        $networkConfig = $Storage_data.properties.networkAcls.bypass.resourceAccessRules
        $foundSubstring1 = $networkConfig | ForEach-Object { $_["resourceId"] -match $openAiResourceName }
        $foundSubstring2 = $networkConfig | ForEach-Object { $_["resourceId"] -match $searchResourceName }

        if ($foundSubstring1 -and $foundSubstring2) {
            Write-Host -ForegroundColor Green "Your Storage account has Trusted Services correctly enabled."
        }
        else {
            Write-Host -ForegroundColor Red "Error: Please enable Trusted Services on your Storage account: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#enable-trusted-service-1"
        }
    }
    else {
        Write-Host -ForegroundColor Green "Your Storage account has Trusted Services correctly enabled."
    }
}
catch {
    Write-Host -ForegroundColor Red "Error: Please enable Trusted Services on your Storage account: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#enable-trusted-service-1"
}

# Validate Trusted Services are enabled on Azure OpenAI
Write-Host -ForegroundColor Yellow "Validating Trusted Services are enabled on Azure Open AI..."

$api_version = "2023-10-01-preview"  
$token = az account get-access-token --resource https://management.azure.com --query "accessToken" --output tsv   
$url = "https://management.azure.com" + $AzureOpenAIResourceID + "?api-version=" + $api_version  
  
$headers = @{  
    "Authorization" = "Bearer $token"  
}  
  
try {  
    $response = Invoke-RestMethod -Uri $url -Headers $headers  
  
    if ($response.StatusCode -eq 200) {  
        $resource_info = $response.Content | ConvertFrom-Json  
    }  
  
    $Trusted_services = $resource_info.properties.networkAcls  
  
    if ($Trusted_services.PSObject.Properties.Name -contains "pybass" -and $Trusted_services.pybass -ne "AzureServices") {  
        Write-Host -ForegroundColor Red "Error: Please enable Trusted Services on your Azure Open AI resource: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#enable-trusted-service"  
    }  
    else {  
        Write-Host -ForegroundColor Green "Your Azure Open AI has Trusted Services correctly enabled." 
    }  
}  
catch {  
    Write-Host -ForegroundColor Red "Failed to retrieve Azure Search Trusted Services details." 
    Write-Host -ForegroundColor Red $_.Exception.Message 
}  

# Validate Private Endpoint for Microsoft managed virtual network was approved for Azure Search resource
Write-Host -ForegroundColor Yellow "Validating that a Private Endpoint for Microsoft managed virtual network was approved for your Azure Search resource..."
    
$endpoints = @{}  
  
$endpoints["Storage_Resource_private_endpoint"] = Get-PrivateEndpoint($Storage_data)
$endpoints["Search_private_endpoint"] = Get-PrivateEndpoint($Search_data) 
$endpoints["Open_AI_private_endpoint"] = Get-PrivateEndpoint($AzureOpenAI_data)

# Validate Private Endpoint configurations on AOAI, Search and Storage
Write-Host -ForegroundColor Yellow "Validating Private Endpoints configurations on the three services..."

if ($null -eq $endpoints["Storage_Resource_private_endpoint"] -or $endpoints["Storage_Resource_private_endpoint"].Length -eq 0) {    
    Write-Host -ForegroundColor Red "Error: You have no Private Endpoint setup for your Storage account."    
}    
    
if ($null -eq $endpoints["Search_private_endpoint"] -or $endpoints["Search_private_endpoint"].Length -eq 0) {    
    Write-Host -ForegroundColor Red "Error: You have no Private Endpoint setup for your Azure Search."    
}    
    
if ($null -eq $endpoints["Open_AI_private_endpoint"] -or $endpoints["Open_AI_private_endpoint"].Length -eq 0) {    
    Write-Host -ForegroundColor Red "Error: You have no Private Endpoint setup for your Azure OpenAI."    
}  

$Vnet_name = ($VnetResourceID -split "/")[-1]
$api_version = "2023-09-01"

$Azure_Open_Ai_Vnets = Get-Vnet($endpoints["Open_AI_private_endpoint"])
$Azure_Search_Ai_Vnets = Get-Vnet($endpoints["Search_private_endpoint"])
$Storage_Vnets = Get-Vnet($endpoints["Storage_Resource_private_endpoint"])

if (($Azure_Open_Ai_Vnets -contains $Vnet_name) -and ($Azure_Search_Ai_Vnets -contains $Vnet_name) -and ($Storage_Vnets -contains $Vnet_name)) {  
    Write-Host -ForegroundColor Green "Your Private Endpoints configuration is correct."  
}  
else {  
    Write-Host -ForegroundColor Red "Error: Your Private Endpoints configuration is not properly setup."  
}  
  
if (($Azure_Open_Ai_Vnets -notcontains $Vnet_name) -and ($endpoints["Open_AI_prvate_endpoint"].Count -gt 0)) {  
    Write-Host -ForegroundColor Red "Error: Private Endpoint for Azure Open AI is not on the correct vnet."  
}  
  
if (($Azure_Search_Ai_Vnets -notcontains $Vnet_name) -and ($endpoints["Search_prvate_endpoint"].Count -gt 0)) {  
    Write-Host -ForegroundColor Red "Error: Private Endpoint for Azure Search is not on the correct vnet."  
}  
  
if (($Storage_Vnets -notcontains $Vnet_name) -and ($endpoints["Storage_Resource_prvate_endpoint"].Count -gt 0)) {  
    Write-Host -ForegroundColor Red "Error: Private Endpoint for storage account is not on the correct vnet."  
}  

function Get-UserInput($prompt) {  
    Write-Host -ForegroundColor Cyan "`n$prompt"  
    Read-Host  
} 
function Get-PrivateEndpoint ($data) {    
    $result_ids = @()  
    $allApproved = $true  
    foreach ($connections in $data.properties.privateEndpointConnections) {        
          
        $status = $connections.properties.privateLinkServiceConnectionState.status.ToUpper()      
          
        $description = $connections.properties.privateLinkServiceConnectionState.description.ToUpper()      
         
        if ($description -notin "APPROVED", "AUTO-APPROVED") {  
            $allApproved = $false  
        }  
          
        if ($description -notin "APPROVED", "AUTO-APPROVED" -and $status -eq "APPROVED") {        
            Write-Host -ForegroundColor Green "Your Private Endpoint for Microsoft managed virtual network request was approved: ($description)"    
        }    
          
        elseif ($description -notin "APPROVED", "AUTO-APPROVED" -and $status -ne "APPROVED") {      
            Write-Host -ForegroundColor Red "Error: Your Private Endpoint for Microsoft managed virtual network request was denied: ($description).
            Please review our guidance on requesting access: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#disable-public-network-access-1"      
        }      
          
        else {      
            $result_ids += $connections.properties.privateEndpoint.id  
        }      
    }  
  
    if ($allApproved -and $data -eq $Search_data) {      
        Write-Host -ForegroundColor Red "Error: You have not requested a Private Endpoint for Microsoft managed virtual network.
            Please review our guidance on requesting access: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/use-your-data-securely#disable-public-network-access-1"      
    } 
  
    return $result_ids    
}
function Get-Vnet ($Resource_private_endpoints) {    
    $vnet_names = @()    
  
    foreach ($privateendpointId in $Resource_private_endpoints) {    
        $url = "https://management.azure.com" + $privateendpointId + "?api-version=" + $api_version      
  
        $headers = @{      
            "Authorization" = "Bearer $token"      
        }      
    
        try {      
            $response = Invoke-RestMethod -Uri $url -Headers $headers      
    
            if ($response.properties) {      
                $vnet_names += ($response.properties.subnet.id -split "/")[-3]    
            }      
        }    
        catch {      
            Write-Host -ForegroundColor Red "Failed to retrieve Virtual Network details." 
            Write-Host -ForegroundColor Red "Error making GET request: $_.Exception.Message"      
        }      
    }    
    return $vnet_names    
}   
