Set-StrictMode -Version Latest

class JevResponse {
    [string]$Id
    [string]$Model
    [string]$Provider
    [object]$Answers
    [object]$Usage
    [string]$Summary
    [object]$RawResponse

    JevResponse([object]$Response) {
        $this.RawResponse = $Response
        $this.Answers = $Response.answers
        foreach ($name in @('id','model','provider','usage')) {
            if ($null -ne $Response.PSObject.Properties[$name]) { $this.$name = $Response.$name }
        }
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($property in $this.Answers.PSObject.Properties) {
            $answer = $property.Value
            if ($null -ne $answer -and $null -ne $answer.PSObject.Properties['type']) {
                $valueProperty = $answer.PSObject.Properties[[string]$answer.type]
                if ($null -ne $valueProperty) {
                    $value = $valueProperty.Value
                    if ($answer.type -eq 'box') { $value = ConvertTo-Json -InputObject $value -Compress -Depth 10 }
                    $parts.Add(('{0}={1}' -f $property.Name,$value))
                }
            }
        }
        $this.Summary = $parts -join '; '
    }
}
class JevObject {
    [string]$Provider = 'TypeSafe'
    [uri]$Endpoint = 'https://api.typesafe.ai/v1/systemone'
    [string]$Model = 'jev-latest'
    hidden [securestring]$ApiKey
    hidden [hashtable]$Headers = @{}
    [int]$TimeoutSec = 60
    [System.Collections.Specialized.OrderedDictionary]$Questions = [ordered]@{}
    [object]$State
    hidden [bool]$HasState = $false
}
Update-TypeData -TypeName JevObject -DefaultDisplayPropertySet Provider,Endpoint,Model,Questions -Force

function New-JevObject {
<#
.SYNOPSIS
Creates a typed JevObject with default TypeSafe settings and no questions.
.EXAMPLE
New-JevObject | Set-JevConnection -Provider OpenRouter
#>
    [CmdletBinding()]
    [OutputType([JevObject])]
    param()
    [JevObject]::new()
}

function Set-JevConnection {
<#
.SYNOPSIS
Configures and returns the same JevObject; creates one if omitted.
.DESCRIPTION
Only supplied settings change. Changing provider resets endpoint/model and clears
credentials and headers unless replacements are supplied. Keys are not persisted.
.EXAMPLE
Set-JevConnection -Provider OpenRouter
.EXAMPLE
New-JevObject | Set-JevConnection -Provider Local -Endpoint http://localhost:8080/v1/systemone
#>
    [CmdletBinding()]
    [OutputType([JevObject])]
    param(
        [Parameter(ValueFromPipeline)][ValidateNotNull()][JevObject]$InputObject,
        [ValidateSet('TypeSafe','OpenRouter','Local')][string]$Provider,
        [uri]$Endpoint,
        [ValidateNotNullOrEmpty()][string]$Model,
        [securestring]$ApiKey,
        [hashtable]$Headers,
        [ValidateRange(1,3600)][int]$TimeoutSec
    )
    process {
        $target = if ($null -eq $InputObject) { New-JevObject } else { $InputObject }
        $nextProvider = if ($PSBoundParameters.ContainsKey('Provider')) { $Provider } else { $target.Provider }
        $changed = $nextProvider -ne $target.Provider
        $nextEndpoint = $target.Endpoint
        $nextModel = $target.Model
        if ($changed) {
            $nextEndpoint = switch ($nextProvider) {
                TypeSafe { [uri]'https://api.typesafe.ai/v1/systemone' }
                OpenRouter { [uri]'https://openrouter.ai/api/alpha/decisions' }
                Local { [uri]'http://localhost:8080/v1/systemone' }
            }
            $nextModel = if ($nextProvider -eq 'OpenRouter') { '~typesafe/jev-latest' } else { 'jev-latest' }
        }
        if ($PSBoundParameters.ContainsKey('Endpoint')) { $nextEndpoint = $Endpoint }
        if ($PSBoundParameters.ContainsKey('Model')) { $nextModel = $Model }
        if (-not $nextEndpoint -or -not $nextEndpoint.IsAbsoluteUri -or $nextEndpoint.Scheme -notin @('http','https') -or $nextEndpoint.UserInfo -or $nextEndpoint.Fragment) { throw 'Endpoint must be an absolute HTTP(S) URL without credentials or a fragment.' }
        if ($nextEndpoint.Scheme -eq 'http' -and -not $nextEndpoint.IsLoopback) { throw 'Use HTTPS for remote endpoints. HTTP is supported only on loopback.' }
        $target.Provider = $nextProvider; $target.Endpoint = $nextEndpoint; $target.Model = $nextModel
        if ($changed) { $target.ApiKey = $null; $target.Headers = @{} }
        if ($PSBoundParameters.ContainsKey('ApiKey')) { $target.ApiKey = $ApiKey }
        if ($PSBoundParameters.ContainsKey('Headers')) { $target.Headers = if ($Headers) { $Headers.Clone() } else { @{} } }
        if ($PSBoundParameters.ContainsKey('TimeoutSec')) { $target.TimeoutSec = $TimeoutSec }
        $target
    }
}

function Copy-JevObject {
<#
.SYNOPSIS
Copies a JevObject for independent configuration, questions, and JSON state.
.EXAMPLE
$variant = $jev | Copy-JevObject | Set-JevConnection -Model another-model
#>
    [CmdletBinding()]
    [OutputType([JevObject])]
    param([Parameter(Mandatory,ValueFromPipeline)][JevObject]$InputObject)
    process {
        $copy = New-JevObject
        $copy.Provider = $InputObject.Provider; $copy.Endpoint = $InputObject.Endpoint
        $copy.Model = $InputObject.Model; $copy.TimeoutSec = $InputObject.TimeoutSec
        if ($InputObject.ApiKey) { $copy.ApiKey = $InputObject.ApiKey.Copy() }
        $copy.Headers = $InputObject.Headers.Clone()
        $data = @{ state=$InputObject.State; questions=$InputObject.Questions } | ConvertTo-Json -Depth 100 -WarningAction Stop | ConvertFrom-Json -AsHashtable -Depth 100
        $copy.State = $data.state; $copy.HasState = $InputObject.HasState
        foreach ($key in $data.questions.Keys) { $copy.Questions[$key] = $data.questions[$key] }
        $copy
    }
}

function Set-JevState {
<#
.SYNOPSIS
Sets state and returns the same JevObject.
.EXAMPLE
$jev | Set-JevState -State 'Checkout is down' | Invoke-JevDecision
#>
    [CmdletBinding()]
    [OutputType([JevObject])]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][JevObject]$InputObject,
        [Parameter(Mandatory)][ValidateNotNull()][object]$State
    )
    process { $InputObject.State = $State; $InputObject.HasState = $true; $InputObject }
}
function New-JevQuestion {
<#
.SYNOPSIS
Builds a named Choice, Noul, Score, or Box question with tab-completable types.
.PARAMETER Options
Choice labels, or a dictionary mapping labels to descriptions (null is allowed).
.PARAMETER Levels
Score rubric in ascending order. At least two levels are required.
.PARAMETER Criteria
Optional Noul descriptions keyed by 'true' and/or 'false'.
.EXAMPLE
New-JevQuestion -Name team -Choice -Instructions 'Who owns this?' -Options billing,technical,other
.EXAMPLE
New-JevQuestion -Name urgent -Noul -Instructions 'Is this urgent?'
.EXAMPLE
New-JevQuestion -Name severity -Score -Instructions 'How severe?' -Levels low,medium,high
#>
    [CmdletBinding(DefaultParameterSetName='Noul')]
    param(
        [Parameter(Mandatory,Position=0)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Instructions,
        [Parameter(Mandatory,ParameterSetName='Choice')][switch]$Choice,
        [Parameter(Mandatory,ParameterSetName='Choice')][object]$Options,
        [Parameter(ParameterSetName='Noul')][switch]$Noul,
        [Parameter(ParameterSetName='Noul')][hashtable]$Criteria,
        [Parameter(Mandatory,ParameterSetName='Score')][switch]$Score,
        [Parameter(Mandatory,ParameterSetName='Score')][ValidateCount(2,10000)][object[]]$Levels,
        [Parameter(Mandatory,ParameterSetName='Box')][switch]$Box
    )
    $definition = [ordered]@{ type = $PSCmdlet.ParameterSetName.ToLowerInvariant(); instructions = $Instructions }
    switch ($PSCmdlet.ParameterSetName) {
        Choice {
            $labels = [ordered]@{}
            if ($Options -is [System.Collections.IDictionary]) {
                foreach ($key in $Options.Keys) {
                    if ($key -isnot [string] -or [string]::IsNullOrWhiteSpace($key)) { throw 'Choice labels must be nonempty strings.' }
                    $labels[$key] = $Options[$key]
                }
            } else {
                foreach ($label in @($Options)) {
                    if ($label -isnot [string] -or [string]::IsNullOrWhiteSpace($label)) { throw 'Choice labels must be nonempty strings.' }
                    if ($labels.Contains($label)) { throw "Duplicate choice label: $label" }
                    $labels[$label] = $null
                }
            }
            if ($labels.Count -eq 0) { throw 'Supply at least one choice option.' }
            $definition.criteria = $labels
        }
        Score { $definition.criteria = $Levels }
        Noul {
            if ($Criteria) {
                foreach ($key in $Criteria.Keys) { if ($key -cnotin @('true','false')) { throw "Noul criteria keys must be 'true' or 'false'." } }
                $definition.criteria = $Criteria.Clone()
            }
        }
    }
    [pscustomobject]@{ PSTypeName = 'Jev.Question'; Name = $Name; Definition = $definition }
}

function ConvertTo-JevQuestions {
    param([object[]]$Question)
    $map = [ordered]@{}
    foreach ($q in $Question) {
        if ($null -eq $q -or $q.PSObject.TypeNames -notcontains 'Jev.Question') { throw 'Supply questions created by New-JevQuestion.' }
        if ($map.Contains($q.Name)) { throw "Duplicate question name: $($q.Name)" }
        $map[$q.Name] = $q.Definition
    }
    if ($map.Count -eq 0) { throw 'At least one question is required.' }
    return ,$map
}



function Add-JevQuestion {
<#
.SYNOPSIS
Adds inline or reusable questions and returns the same JevObject.
.DESCRIPTION
InputObject is required via pipeline or variable. Duplicate names fail atomically.
.EXAMPLE
$jev | Add-JevQuestion -Name team -Choice -Instructions 'Which team?' -Options billing,technical
.EXAMPLE
Add-JevQuestion -InputObject $jev -Question $urgent,$severity
#>
    [CmdletBinding(DefaultParameterSetName='Noul')]
    [OutputType([JevObject])]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][JevObject]$InputObject,
        [Parameter(Mandatory,ParameterSetName='Reusable')][object[]]$Question,
        [Parameter(Mandatory,ParameterSetName='Choice')]
        [Parameter(Mandatory,ParameterSetName='Noul')]
        [Parameter(Mandatory,ParameterSetName='Score')]
        [Parameter(Mandatory,ParameterSetName='Box')][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory,ParameterSetName='Choice')]
        [Parameter(Mandatory,ParameterSetName='Noul')]
        [Parameter(Mandatory,ParameterSetName='Score')]
        [Parameter(Mandatory,ParameterSetName='Box')][ValidateNotNullOrEmpty()][string]$Instructions,
        [Parameter(Mandatory,ParameterSetName='Choice')][switch]$Choice,
        [Parameter(Mandatory,ParameterSetName='Choice')][object]$Options,
        [Parameter(ParameterSetName='Noul')][switch]$Noul,
        [Parameter(ParameterSetName='Noul')][hashtable]$Criteria,
        [Parameter(Mandatory,ParameterSetName='Score')][switch]$Score,
        [Parameter(Mandatory,ParameterSetName='Score')][ValidateCount(2,10000)][object[]]$Levels,
        [Parameter(Mandatory,ParameterSetName='Box')][switch]$Box
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Reusable') { $questionsToAdd = $Question }
        else {
            $arguments = @{}
            foreach ($key in @('Name','Instructions','Choice','Options','Noul','Criteria','Score','Levels','Box')) {
                if ($PSBoundParameters.ContainsKey($key)) { $arguments[$key] = $PSBoundParameters[$key] }
            }
            $questionsToAdd = @(New-JevQuestion @arguments)
        }
        $additional = ConvertTo-JevQuestions $questionsToAdd
        foreach ($key in $additional.Keys) {
            if ($InputObject.Questions.Contains($key)) { throw "Duplicate question name: $key" }
        }
        foreach ($key in $additional.Keys) { $InputObject.Questions[$key] = $additional[$key] }
        $InputObject
    }
}

function Invoke-JevDecision {
<#
.SYNOPSIS
Submits the questions and state stored in a JevObject.
.DESCRIPTION
Use Set-JevState before submission. Returns a JevResponse with Answers, Usage, Model, Provider, Id, and RawResponse.
Each piped JevObject makes one call. Submission does not change stored state.
.EXAMPLE
$jev | Set-JevState -State 'Checkout is down' | Invoke-JevDecision
.EXAMPLE
Invoke-JevDecision -InputObject $jev -WhatIf
#>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([JevResponse])]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][Alias('JevObject')][JevObject]$InputObject,
        [string]$Model,
        [switch]$AnswersOnly
    )
    process {
        $context = $InputObject
        if ($context.Questions.Count -eq 0) { throw 'Add at least one question before submitting.' }
        if (-not $context.HasState) { throw 'Use Set-JevState before submitting.' }
        $request = [ordered]@{ state=$context.State; questions=$context.Questions; model=$context.Model }
        if ($Model) { $request.model = $Model }
        # Stop on truncation rather than silently submitting an incomplete state.
        $body = ConvertTo-Json -InputObject $request -Depth 100 -Compress -WarningAction Stop -ErrorAction Stop
        if ($PSCmdlet.ShouldProcess($context.Endpoint.AbsoluteUri, 'Submit Jev decision')) {
            $headers = $context.Headers.Clone()
            $headers.Accept = 'application/json'
            $key = $null
            try {
                if ($context.ApiKey) { $key = [System.Net.NetworkCredential]::new('', $context.ApiKey).Password }
                elseif ($context.Provider -eq 'TypeSafe') { $key = $env:TYPESAFE_API_KEY }
                elseif ($context.Provider -eq 'OpenRouter') { $key = $env:OPENROUTER_API_KEY }
                if ($key) { $headers.Authorization = "Bearer $key" }
                elseif ($context.Provider -ne 'Local' -and -not $headers.ContainsKey('Authorization')) {
                    throw 'Missing API key. Supply -ApiKey on Set-JevConnection or set the provider API key environment variable.'
                }
                Write-Verbose "Submitting decision to $($context.Endpoint.GetLeftPart([UriPartial]::Path))"
                $response = Invoke-WebRequest -Uri $context.Endpoint -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec $context.TimeoutSec -MaximumRedirection 0 -ErrorAction Stop
                $result = ConvertFrom-Json -InputObject $response.Content -Depth 100 -ErrorAction Stop
                if ($null -eq $result -or $null -eq $result.PSObject.Properties['answers']) { throw 'Response JSON does not contain an answers object.' }
                if ($AnswersOnly) { $result.answers }
                else { [JevResponse]::new($result) }
            } finally {
                $key = $null
                $headers.Remove('Authorization')
            }
        }
    }
}



function Get-JevAnswer {
<#
.SYNOPSIS
Selects a named answer from each parsed Jev result.
.DESCRIPTION
By default returns the complete answer with probabilities. -ValueOnly returns the
choice label, Noul probability, score, or box. Noul is a probability, not a Boolean.
.EXAMPLE
$results | Get-JevAnswer -Name team -ValueOnly
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][object]$InputObject,
        [Parameter(Mandatory,Position=0)][string]$Name,
        [switch]$ValueOnly
    )
    process {
        $answers = if ($InputObject.PSObject.Properties['answers']) { $InputObject.answers } else { $InputObject }
        $property = $answers.PSObject.Properties[$Name]
        if ($null -eq $property) { throw "Answer '$Name' was not found." }
        $answer = $property.Value
        if ($ValueOnly) { $answer.($answer.type) } else { $answer }
    }
}



Export-ModuleMember -Function New-JevObject,Set-JevConnection,Copy-JevObject,Set-JevState,New-JevQuestion,Add-JevQuestion,Invoke-JevDecision,Get-JevAnswer


Set-Alias -Name Invoke-JevResponse -Value Invoke-JevDecision
Export-ModuleMember -Alias Invoke-JevResponse


