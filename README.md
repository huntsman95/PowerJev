# Jev PowerShell

Use Jev PowerShell to send decision requests to TypeSafe, OpenRouter, or a local API.
Use the answers to classify data, select an option, or measure a condition.

The module uses the PowerShell pipeline to prepare and send requests.
It converts each JSON response to a `JevResponse` object.
Use standard PowerShell commands to select and filter the results.

## Requirements

- PowerShell 7.2 or later.
- Access to a Jev API or a local API that accepts Jev decision requests.
- An API key for TypeSafe or OpenRouter.

## Start

From the project directory, import the module:

```powershell
Import-Module ./Jev/Jev.psd1
```

Create a connection. Enter your API key when prompted.
Add questions, set the state, and send the request.

```powershell
$jev = Set-JevConnection -Provider OpenRouter `
    -ApiKey (Read-Host 'OpenRouter API key' -AsSecureString)

$result = $jev |
    Add-JevQuestion -Name team -Choice `
        -Instructions 'Which team must process this request?' `
        -Options billing,technical,other |
    Add-JevQuestion -Name urgent -Noul `
        -Instructions 'Does this request need immediate action?' |
    Set-JevState -State 'The payment system does not operate.' |
    Invoke-JevDecision

$result
$result.Answers.team.choice
$result.Answers.urgent.noul
```

All questions in the object are sent in one API call.
The default display shows the decisions, model, and provider.

## Select an API

Use `Set-JevConnection` to create or change a connection.
Supply the full URL for a local endpoint.

```powershell
# Use the official TypeSafe API.
$jev = Set-JevConnection -Provider TypeSafe

# Use OpenRouter.
$jev = Set-JevConnection -Provider OpenRouter

# Use a local API.
$jev = Set-JevConnection -Provider Local `
    -Endpoint http://localhost:8080/v1/systemone `
    -Model jev
```

If you do not supply `-ApiKey`, the module reads the applicable environment variable:

| Provider | Environment variable | Default model |
| --- | --- | --- |
| TypeSafe | `TYPESAFE_API_KEY` | `jev-latest` |
| OpenRouter | `OPENROUTER_API_KEY` | `~typesafe/jev-latest` |
| Local | None | `jev-latest` |

Use `-Model` to select a different model.
Use HTTPS for remote endpoints.
HTTP is permitted for loopback addresses.

## Prepare a request

A `JevObject` contains the connection settings, questions, and state.
State is the data that the model examines.
Use text, an object, or an array as state.

You can create an empty object before you set the connection:

```powershell
$jev = New-JevObject |
    Set-JevConnection -Provider OpenRouter |
    Add-JevQuestion -Name urgent -Noul `
        -Instructions 'Does this request need immediate action?' |
    Set-JevState -State @{
        message = 'The payment system does not operate.'
        customer = 'Example Company'
    }

$jev | Invoke-JevDecision
```

`Set-JevConnection`, `Add-JevQuestion`, and `Set-JevState` change the same object.
Each command returns that object to the pipeline.
`Invoke-JevDecision` sends the state stored in the object.

You can also supply the object through a parameter:

```powershell
Set-JevState -InputObject $jev -State 'Please correct my invoice.' | Out-Null
Invoke-JevDecision -InputObject $jev
```

## Add questions

Each question needs a name and instructions.
Names must be unique in each request.

| Type | Purpose | Main answer property |
| --- | --- | --- |
| Choice | Select one option. | `choice` |
| Noul | Measure the probability that a condition is true. | `noul` |
| Score | Measure a position on an ordered scale. | `score` |
| Box | Locate a target in an image. | `box` |

A Noul answer is a probability from 0 to 1.
A Score answer can be between two levels.
Box requires image input and a model that supports it.
The module sends JSON requests only.

### Choice

Supply option names or a dictionary with descriptions.

```powershell
$jev | Add-JevQuestion -Name team -Choice `
    -Instructions 'Which team must process this request?' `
    -Options @{
        billing = 'Invoices, charges, and refunds'
        technical = 'Equipment or software faults'
        other = 'All other requests'
    }
```

### Noul

```powershell
$jev | Add-JevQuestion -Name complete -Noul `
    -Instructions 'Does the request contain all necessary information?'
```

### Score

Supply at least two levels.
Put the levels in order, from the lowest to the highest.

```powershell
$jev | Add-JevQuestion -Name severity -Score `
    -Instructions 'How much does this fault affect operation?' `
    -Levels 'No effect','Reduced operation','No operation'
```

### Use a question again

Use `New-JevQuestion` to prepare a separate question.
Use `Add-JevQuestion` to add it to an object.

```powershell
$question = New-JevQuestion -Name approved -Noul `
    -Instructions 'Does the request meet the approval conditions?'

$jev | Add-JevQuestion -Question $question
```

## Read the response

`Invoke-JevDecision` returns a `JevResponse` object.
`Invoke-JevResponse` is an alias for the same command.

```powershell
$result = $jev | Invoke-JevResponse

$result | Select-Object Model,Provider,Answers,Usage
$result | Select-Object -ExpandProperty Answers
$result | Get-JevAnswer -Name urgent
$result | Get-JevAnswer -Name urgent -ValueOnly
```

Use `Answers` to read answer values, probabilities, and confidence data.
Use `Usage` to read the usage data supplied by the API.
Use `RawResponse` to read the complete JSON response as a PowerShell object.

```powershell
$result.Answers
$result.Usage
$result.RawResponse
```

## Process more than one item

Use `Copy-JevObject` to make an independent copy of a prepared request.
Set the state on each copy.
The example sends one API call for each message.

```powershell
$messages = @(
    'The payment system does not operate.'
    'Please correct my invoice.'
)

$results = $messages | ForEach-Object {
    $jev | Copy-JevObject |
        Set-JevState -State $_ |
        Invoke-JevDecision
}

$results | Where-Object { $_.Answers.urgent.noul -gt 0.8 }
$results | Select-Object Model,Summary
```

## Examine a request before submission

Use `-WhatIf` to examine the submission action without an API call.

```powershell
$jev.Questions | ConvertTo-Json -Depth 100
$jev.State
$jev | Invoke-JevDecision -WhatIf
```

## Find commands and help

```powershell
Get-Command -Module Jev
Get-Help Add-JevQuestion -Examples
Get-Help Set-JevState -Full
Get-Help Invoke-JevDecision -Full
```
