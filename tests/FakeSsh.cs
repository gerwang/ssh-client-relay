using System;
using System.IO;
using System.Text;

internal static class FakeSsh
{
    public static int Main(string[] args)
    {
        string argsPath = Environment.GetEnvironmentVariable("TEST_ARGS");
        string stdinPath = Environment.GetEnvironmentVariable("TEST_STDIN");
        if (String.IsNullOrEmpty(argsPath) || String.IsNullOrEmpty(stdinPath))
            return 64;
        File.WriteAllBytes(argsPath,
            Encoding.UTF8.GetBytes(String.Join("\0", args) + "\0"));
        using (FileStream output = File.Create(stdinPath))
            Console.OpenStandardInput().CopyTo(output);
        Console.Write(Environment.GetEnvironmentVariable("TEST_STDOUT") ??
            "fake-ssh-output");
        return 0;
    }
}
