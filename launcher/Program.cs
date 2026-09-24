using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Jellyfin Companion")]
[assembly: AssemblyProduct("Jellyfin Companion")]
[assembly: AssemblyDescription("Jellyfin address finder and playback-aware sleep or shutdown")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyCopyright("Jellyfin Companion contributors")]

internal static class Program
{
    private static readonly string[] Resources = { "JellyfinCompanion.ps1", "Core.ps1", "Settings.ps1", "App.ico" };
    private static readonly string[] Destinations = { "JellyfinCompanion.ps1", "src/Core.ps1", "src/Settings.ps1", "App.ico" };

    [STAThread]
    private static int Main(string[] args)
    {
        bool smoke = false, start = false, check = false;
        string action = "Sleep", diagnostics = null;
        string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JellyfinCompanion");
        try
        {
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--smoke-test": smoke = true; break;
                    case "--check": check = true; break;
                    case "--start": start = true; break;
                    case "--action":
                        action = Value(args, ref i);
                        if (!string.Equals(action, "Sleep", StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(action, "Shutdown", StringComparison.OrdinalIgnoreCase))
                            throw new ArgumentException("Action must be Sleep or Shutdown.");
                        break;
                    case "--data-directory": data = Path.GetFullPath(Value(args, ref i)); break;
                    case "--diagnostics": diagnostics = Path.GetFullPath(Value(args, ref i)); break;
                    default: throw new ArgumentException("Unknown option: " + args[i]);
                }
            }
            if (smoke && diagnostics == null) throw new ArgumentException("--smoke-test requires --diagnostics <folder>.");
            // Test mode must never arm a power action, even if --start was supplied.
            if (smoke || check) start = false;
            Directory.CreateDirectory(data);
            byte[][] contents = new byte[Resources.Length][];
            string payloadId;
            using (var combined = new MemoryStream())
            {
                for (int i = 0; i < Resources.Length; i++)
                {
                    using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(Resources[i]))
                    using (var copy = new MemoryStream())
                    {
                        if (resource == null) throw new InvalidOperationException("Missing bundled application file.");
                        resource.CopyTo(copy); contents[i] = copy.ToArray();
                        combined.Write(contents[i], 0, contents[i].Length);
                    }
                }
                using (var sha = SHA256.Create())
                    payloadId = BitConverter.ToString(sha.ComputeHash(combined.ToArray())).Replace("-", "").ToLowerInvariant();
            }
            string applicationDirectory = Path.Combine(data, "app", payloadId.Substring(0, 20));
            using (var extraction = new Mutex(false, "Local\\JellyfinCompanionExtract-" + payloadId.Substring(0, 20)))
            {
                try { extraction.WaitOne(); } catch (AbandonedMutexException) { }
                try
                {
                    for (int i = 0; i < Resources.Length; i++)
                    {
                        string path = Path.Combine(applicationDirectory, Destinations[i]);
                        Directory.CreateDirectory(Path.GetDirectoryName(path));
                        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                        File.WriteAllBytes(temporary, contents[i]);
                        if (File.Exists(path)) File.Replace(temporary, path, null);
                        else File.Move(temporary, path);
                    }
                }
                finally { extraction.ReleaseMutex(); }
            }
            string script = Path.Combine(applicationDirectory, "JellyfinCompanion.ps1");
            string command = "& " + PsLiteral(script) + " -DataDirectory " + PsLiteral(data) + " -PowerAction " + PsLiteral(action);
            if (start) command += " -StartMonitoring";
            if (check) command += " -Check";
            if (smoke) command += " -SmokeTest -DiagnosticsPath " + PsLiteral(diagnostics);
            // Explicit exit preserves a script failure as the launcher exit code.
            command += "; if (-not $?) { exit 1 }";
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            var info = new ProcessStartInfo(powershell);
            info.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
            info.UseShellExecute = false; info.CreateNoWindow = true; info.WindowStyle = ProcessWindowStyle.Hidden;
            info.WorkingDirectory = applicationDirectory;
            using (var process = Process.Start(info))
            {
                if (process == null) throw new InvalidOperationException("Could not start the application.");
                process.WaitForExit();
                if (process.ExitCode != 0 && !smoke && !check)
                    MessageBox.Show("Jellyfin Companion could not start. Check that Windows PowerShell 5.1 is available and permitted on this PC.", "Jellyfin Companion", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            if (!smoke && !check) MessageBox.Show(error.Message, "Jellyfin Companion", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string Value(string[] args, ref int index)
    {
        if (++index >= args.Length) throw new ArgumentException("An option value is missing.");
        return args[index];
    }
    private static string PsLiteral(string value) { return "'" + value.Replace("'", "''") + "'"; }
}
