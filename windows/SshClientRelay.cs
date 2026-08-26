using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

internal static class SshClientRelay
{
    private const string Protocol = "SSH_CLIENT_RELAY_ARGS_V1";
    private const string Version = "0.1.1";

    private sealed class Config
    {
        public string RelayHost;
        public string TargetAlias;
        public string TargetHost;
        public string RemoteHelper = "~/.local/bin/ssh-client-relay-helper";
        public string Ssh = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "OpenSSH", "ssh.exe");
    }

    public static int Main(string[] args)
    {
        try
        {
            if (args.Length == 1 && args[0] == "--version")
            {
                Console.WriteLine("ssh-client-relay " + Version);
                return 0;
            }
            Config config = LoadConfig();
            bool useRelay = false;
            string[] forwarded = new string[args.Length];

            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == config.TargetAlias)
                {
                    useRelay = true;
                    forwarded[i] = config.TargetHost;
                }
                else
                {
                    if (args[i] == config.TargetHost)
                        useRelay = true;
                    forwarded[i] = args[i];
                }
            }

            return useRelay
                ? RunRelayed(config, forwarded)
                : RunDirect(config.Ssh, args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ssh-client-relay: " + ex.Message);
            return 70;
        }
    }

    private static Config LoadConfig()
    {
        string configured = Environment.GetEnvironmentVariable(
            "SSH_CLIENT_RELAY_CONFIG");
        string path = String.IsNullOrEmpty(configured)
            ? Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.UserProfile), ".config",
                "ssh-client-relay", "config.windows")
            : configured;

        if (!File.Exists(path))
            throw new FileNotFoundException("configuration not found", path);

        Config config = new Config();
        foreach (string rawLine in File.ReadAllLines(path, Encoding.UTF8))
        {
            string line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith("#"))
                continue;
            int separator = line.IndexOf('=');
            if (separator < 1)
                throw new InvalidDataException("invalid configuration line: " + rawLine);
            string key = line.Substring(0, separator).Trim();
            string value = line.Substring(separator + 1);
            switch (key)
            {
                case "RELAY_HOST": config.RelayHost = value; break;
                case "TARGET_ALIAS": config.TargetAlias = value; break;
                case "TARGET_HOST": config.TargetHost = value; break;
                case "REMOTE_HELPER": config.RemoteHelper = value; break;
                case "SSH": config.Ssh = value; break;
            }
        }

        if (String.IsNullOrEmpty(config.RelayHost) ||
            String.IsNullOrEmpty(config.TargetAlias) ||
            String.IsNullOrEmpty(config.TargetHost))
            throw new InvalidDataException(
                "RELAY_HOST, TARGET_ALIAS, and TARGET_HOST are required in " + path);
        if (!File.Exists(config.Ssh))
            throw new FileNotFoundException("OpenSSH executable not found", config.Ssh);
        if (!IsSafeRemoteHelper(config.RemoteHelper))
            throw new InvalidDataException(
                "REMOTE_HELPER must be a safe path under ~/: " + config.RemoteHelper);
        return config;
    }

    private static bool IsSafeRemoteHelper(string path)
    {
        if (String.IsNullOrEmpty(path) || !path.StartsWith("~/") ||
            path.EndsWith("/") || path.Contains("//"))
            return false;
        string relative = path.Substring(2);
        foreach (char character in relative)
        {
            bool asciiLetterOrDigit =
                (character >= 'A' && character <= 'Z') ||
                (character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9');
            if (!(asciiLetterOrDigit || character == '.' || character == '_' ||
                character == '-' || character == '/'))
                return false;
        }
        foreach (string part in relative.Split('/'))
        {
            if (part.Length == 0 || part == "." || part == "..")
                return false;
        }
        return true;
    }

    private static int RunDirect(string ssh, string[] args)
    {
        using (Process process = new Process())
        {
            process.StartInfo = NewStartInfo(ssh, args, true);
            process.Start();

            Stream childInput = process.StandardInput.BaseStream;
            Task input = StartPump(Console.OpenStandardInput(), childInput, true);
            Task output = StartPump(process.StandardOutput.BaseStream,
                Console.OpenStandardOutput(), false);
            Task error = StartPump(process.StandardError.BaseStream,
                Console.OpenStandardError(), false);

            process.WaitForExit();
            Task.WaitAll(output, error);
            GC.KeepAlive(input);
            return process.ExitCode;
        }
    }

    private static int RunRelayed(Config config, string[] args)
    {
        List<string> outerArgs = new List<string>();
        outerArgs.Add("-x");
        outerArgs.Add("-T");
        AddDynamicForwardBridges(args, outerArgs);
        outerArgs.Add(config.RelayHost);
        outerArgs.Add(config.RemoteHelper);
        using (Process process = new Process())
        {
            process.StartInfo = NewStartInfo(config.Ssh, outerArgs.ToArray(), true);
            process.Start();

            ConsoleCancelEventHandler cancel = delegate(object sender,
                ConsoleCancelEventArgs eventArgs)
            {
                try { if (!process.HasExited) process.Kill(); }
                catch { }
            };
            Console.CancelKeyPress += cancel;

            Stream childInput = process.StandardInput.BaseStream;
            WriteFrame(childInput, args);

            Task input = StartPump(Console.OpenStandardInput(), childInput, true);
            Task output = StartPump(process.StandardOutput.BaseStream,
                Console.OpenStandardOutput(), false);
            Task error = StartPump(process.StandardError.BaseStream,
                Console.OpenStandardError(), false);

            process.WaitForExit();
            Task.WaitAll(output, error);
            Console.CancelKeyPress -= cancel;
            GC.KeepAlive(input);
            return process.ExitCode;
        }
    }

    private static void AddDynamicForwardBridges(
        string[] innerArgs, List<string> outerArgs)
    {
        for (int i = 0; i < innerArgs.Length; i++)
        {
            string spec = null;
            if (innerArgs[i] == "-D" && i + 1 < innerArgs.Length)
            {
                spec = innerArgs[++i];
            }
            else if (innerArgs[i].StartsWith("-D") && innerArgs[i].Length > 2)
            {
                spec = innerArgs[i].Substring(2);
            }

            if (spec == null)
                continue;
            int separator = spec.LastIndexOf(':');
            string port = separator >= 0 ? spec.Substring(separator + 1) : spec;
            int parsedPort;
            if (!Int32.TryParse(port, out parsedPort) ||
                parsedPort < 1 || parsedPort > 65535)
                throw new InvalidDataException(
                    "unsupported dynamic-forward spec: " + spec);

            outerArgs.Add("-L");
            outerArgs.Add(spec + ":127.0.0.1:" + port);
        }
    }

    private static void WriteFrame(Stream stream, string[] args)
    {
        WriteField(stream, Protocol);
        WriteField(stream, args.Length.ToString(
            System.Globalization.CultureInfo.InvariantCulture));
        foreach (string arg in args)
        {
            if (arg.IndexOf('\0') >= 0)
                throw new InvalidDataException("SSH argument contains a NUL byte");
            WriteField(stream, arg);
        }
        stream.Flush();
    }

    private static Task StartPump(
        Stream source, Stream destination, bool closeDestination)
    {
        return Task.Factory.StartNew(delegate
        {
            try
            {
                byte[] buffer = new byte[4096];
                int read;
                while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
                {
                    destination.Write(buffer, 0, read);
                    destination.Flush();
                }
            }
            catch (IOException)
            {
                // The SSH process may close stdin before its caller does.
            }
            finally
            {
                if (closeDestination)
                    try { destination.Close(); } catch { }
            }
        }, CancellationToken.None, TaskCreationOptions.LongRunning,
            TaskScheduler.Default);
    }

    private static void WriteField(Stream stream, string value)
    {
        byte[] bytes = new UTF8Encoding(false).GetBytes(value);
        stream.Write(bytes, 0, bytes.Length);
        stream.WriteByte(0);
    }

    private static ProcessStartInfo NewStartInfo(
        string executable, string[] args, bool redirect)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = executable;
        info.Arguments = JoinArguments(args);
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardInput = redirect;
        info.RedirectStandardOutput = redirect;
        info.RedirectStandardError = redirect;
        return info;
    }

    // Implements the CommandLineToArgvW quoting rules used by Windows programs.
    private static string JoinArguments(string[] args)
    {
        List<string> quoted = new List<string>();
        foreach (string arg in args)
            quoted.Add(QuoteArgument(arg));
        return String.Join(" ", quoted.ToArray());
    }

    private static string QuoteArgument(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            return arg;

        StringBuilder result = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char character in arg)
        {
            if (character == '\\')
            {
                backslashes++;
            }
            else if (character == '"')
            {
                result.Append('\\', backslashes * 2 + 1);
                result.Append('"');
                backslashes = 0;
            }
            else
            {
                result.Append('\\', backslashes);
                result.Append(character);
                backslashes = 0;
            }
        }
        result.Append('\\', backslashes * 2);
        result.Append('"');
        return result.ToString();
    }
}
