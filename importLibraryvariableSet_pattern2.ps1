# Define octopus variables
$octopusURL = "$env:OCTOPUS_SERVER_URL"
$octopusAPIKey = "$env:OCTOPUS_API_KEY"
$header = @{ "X-Octopus-ApiKey" = $octopusAPIKey }

# Define working variables
$spaceName = "$env:SpaceName"
$variableSetFilePath = "$env:variableSetjsonFilePath"
$destinationvariableSetName = "$env:libraryVariableSetName"

# Set this value to add additional variable values found on source data not in destination
$addAdditionalVariableValuesOnExistingVariableSets = $True
# Set this value to to true to overwrite existing variable values
$overwriteExistingVariables = $True

# Set this value to to true to keep existing account variable values unchanged from the source file
$keepSourceAccountVariableValues = $True

#region "Functions"
function Convert-SourceIdListToDestinationIdList {
    param(
        $SourceList,
        $DestinationList,
        $IdList
    )

    $NewIdList = @()
    Write-Host "Converting id list with $($IdList.Length) item(s) over to destination space"     
    foreach ($idValue in $idList) {
        $ConvertedId = Convert-SourceIdToDestinationId -SourceList $SourceList -DestinationList $DestinationList -IdValue $IdValue

        if ($null -ne $ConvertedId) {
            $NewIdList += $ConvertedId
        }
    }

    return @($NewIdList)
}

function Convert-SourceIdToDestinationId {
    param(
        $SourceList,
        $DestinationList,
        $IdValue
    )

    $idValueSplit = $IdValue -split "-"
    if ($idValueSplit.Length -le 2) {
        if (($idValueSplit[1] -match "^[\d\.]+$") -eq $false) {
            Write-Host "The id value $idValue is a built in id, no need to convert, returning it."
            return $IdValue
        }
    }
    
    Write-Host "Getting Name of $IdValue"
    $sourceItem = Get-OctopusItemById -ItemList $SourceList -ItemId $IdValue

    $nameToUse = $sourceItem.Name
    if ([string]::IsNullOrWhiteSpace($nameToUse)) {
        Write-Host "The name property is null attempting the username property"
        $nameToUse = $sourceItem.UserName
    }

    if ([string]::IsNullOrWhiteSpace($nameToUse)) {
        Write-Host "Unable to find a name property for $IdValue"
        return $null
    }

    Write-Host "The name of $IdValue is $nameToUse, attempting to find in destination list"    

    $destinationItem = Get-OctopusItemByName -ItemName $nameToUse -ItemList $DestinationList    

    if ($null -eq $destinationItem) {
        Write-Host "Unable to find $nameToUse in the destination list"
        return $null
    }
    else {
        Write-Host "The destination id for $nameToUse is $($destinationItem.Id)"
        return $destinationItem.Id
    }
}


function Get-OctopusItemById {
    param (
        $ItemList,
        $ItemId
    ) 
        
    Write-Host "Attempting to find $ItemId in the item list of $($ItemList.Length) item(s)"

    foreach ($item in $ItemList) {
        Write-Host "Checking to see if $($item.Id) matches with $ItemId"
        if ($item.Id -eq $ItemId) {
            Write-Host "The Ids match, return the item $($item.Name)"
            return $item
        }
    }

    Write-Host "No match found returning null"
    return $null    
}

function Get-OctopusItemByName {
    param (
        $ItemList,
        $ItemName
    )    

    return ($ItemList | Where-Object { $_.Name -eq $ItemName })
}
#endregion

# Get space
$spaceList = Invoke-RestMethod "$octopusURL/api/spaces/all" -Headers $header
$space = $spaceList | Where-Object { $_.Name -eq $spaceName }

# Get destination Library variable set
Write-Host "Looking for library variable set '$libraryVariableSet'"
$LibraryvariableSets = (Invoke-RestMethod -Method Get -Uri "$octopusURL/api/$($space.Id)/libraryvariablesets?contentType=Variables" -Headers $header)
$LibraryVariableSet = $LibraryVariableSets.Items | Where-Object { $_.Name -eq $destinationvariableSetName }

if ($null -eq $libraryVariableSet) {
    Write-Warning "Library variable set not found with name '$libraryVariableSetName'."
    exit
}

$destinationVariableSetVariables = (Invoke-RestMethod -Method Get -Uri "$OctopusURL/api/$($Space.Id)/variables/$($LibraryVariableSet.VariableSetId)" -Headers $Header) 

# Get source variableset from file
$sourceVariableSetVariables = [IO.File]::ReadAllText($variableSetFilePath) | ConvertFrom-Json
$sourceEnvironmentList = $sourceVariableSetVariables.ScopeValues.Environments

# Get destination data
$destinationData = @{
    OctopusUrl    = $octopusUrl;
    OctopusApiKey = $octopusApiKey;
    SpaceName     = $spaceName
}

$destinationApiInformation = Invoke-RestMethod -Method Get -Uri "$octopusURL/api" -Headers $header
$destinationData.Version = $destinationApiInformation.Version
Write-Host "The version of $octopusURL is $($destinationData.Version)"
$splitVersion = $destinationData.Version -split "\."
$destinationData.MajorVersion = [int]$splitVersion[0]
$destinationData.MinorVersion = [int]$splitVersion[1]
$destinationData.HasRunbooks = ($destinationData.MajorVersion -ge 2019 -and $destinationData.MinorVersion -ge 11) -or $destinationData.MajorVersion -ge 2020

$destinationEnvironmentList = Invoke-RestMethod -Method Get -Uri "$octopusURL/api/$($space.Id)/environments/all" -Headers $header



$variableTracker = @{}

try {
    foreach ($octopusVariable in $sourceVariableSetVariables.Variables) {
        $variableName = $octopusVariable.Name

        if (Get-Member -InputObject $octopusVariable.Scope -Name "Environment" -MemberType Properties) {
            Write-Host "$variableName has environment scoping, converting to destination values"
            $NewEnvironmentIds = @(Convert-SourceIdListToDestinationIdList -SourceList $sourceEnvironmentList -DestinationList $destinationEnvironmentList -IdList $octopusVariable.Scope.Environment)
            $octopusVariable.Scope.Environment = @($NewEnvironmentIds)            
        }

        if ($octopusVariable.Type -match ".*Account") {
            if ($keepSourceAccountVariableValues -eq $false) {
                Write-Host "Warning: Cannot convert account type to destination account as keepSourceAccountVariableValues set to false. Setting to DUMMY VALUE" -ForegroundColor Yellow  
                $octopusVariable.Value = "DUMMY VALUE"
            }
        }

        if ($octopusVariable.IsSensitive -eq $true) {
            Write-Host "Warning: Setting sensitive value for $($variableName) to DUMMY VALUE" -ForegroundColor Yellow  
            $octopusVariable.Value = "DUMMY VALUE"
        }

        $trackingName = $variableName -replace "\.", ""        
        
        Write-Host "Cloning $variableName"
        if ($null -eq $variableTracker[$trackingName]) {
            Write-Host "This is the first time we've seen $variableName"
            $variableTracker[$trackingName] = 1
        }
        else {
            $variableTracker.$trackingName += 1
            Write-Host "We've now seen $variableName $($variableTracker[$trackingName]) times"
        }

        $foundCounter = 0
        $foundIndex = -1
        $variableExistsOnDestination = $false        
        for ($i = 0; $i -lt $destinationVariableSetVariables.Variables.Length; $i++) {            
            if ($destinationVariableSetVariables.Variables[$i].Name -eq $variableName) {
                $variableExistsOnDestination = $true
                $foundCounter += 1
                if ($foundCounter -eq $variableTracker[$trackingName]) {
                    $foundIndex = $i
                }
            }
        }
        if ($foundCounter -gt 1 -and $variableExistsOnDestination -eq $true -and $addAdditionalVariableValuesOnExistingVariableSets -eq $false) {
            Write-Host "The variable $variableName already exists on destination. You selected to skip duplicate instances, skipping."
        }
        elseif ($foundIndex -eq -1) {
            Write-Host "New variable $variableName value found.  This variable has appeared so far $($variableTracker[$trackingName]) time(s) in the source variable set.  Adding to list."
            $destinationVariableSetVariables.Variables += $octopusVariable
        }
        elseif ($OverwriteExistingVariables -eq $false) {
            Write-Host "The variable $variableName already exists on the host and you elected to only copy over new items, skipping this one."
        }                                         
        elseif ($foundIndex -gt -1 -and $destinationVariableSetVariables.Variables[$foundIndex].IsSensitive -eq $true) {
            Write-Host "The variable $variableName at value index $($variableTracker[$trackingName]) is sensitive, leaving as is on the destination."
        }
        elseif ($foundIndex -gt -1) {
            $destinationVariableSetVariables.Variables[$foundIndex].Value = $octopusVariable.Value
            $destinationVariableSetVariables.Variables[$foundIndex].Scope = $octopusVariable.Scope
            if ($octopusVariable.Value -eq "Dummy Value") {                
                Write-Host "The variable $variableName is a sensitive variable, value set to 'Dummy Value'" -ForegroundColor Yellow  
            }
        }  
    }
    Write-Host "Saving variables to $octopusURL$($LibraryvariableSet.Links.Variables)"       
    Invoke-RestMethod -Method Put -Uri "$octopusURL$($LibraryvariableSet.Links.Variables)" -Body ($destinationVariableSetVariables | ConvertTo-Json -Depth 10) -Headers $header | Out-Null
    
}
catch {
    Write-Host $_.Exception.Message
}
