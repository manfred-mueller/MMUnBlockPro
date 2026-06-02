using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace mmunblockhost;

class Program
{
    static void Main(string[] args)
    {
        while (true)
        {
            try
            {
                string? filePath = ReadMessage();
                if (string.IsNullOrEmpty(filePath)) break;

                // Der Host geht davon aus, dass die mmunblock.exe im selben Ordner liegt
                string cliPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "mmunblock.exe");
                
                if (File.Exists(cliPath))
                {
                    var startInfo = new ProcessStartInfo
                    {
                        FileName = cliPath,
                        Arguments = $"\"{filePath}\" --quiet", 
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    
                    using var process = Process.Start(startInfo);
                    process?.WaitForExit();

                    SendMessage($"{{\"status\": \"success\", \"path\": \"{filePath.Replace("\\", "\\\\")}\"}}");
                }
                else
                {
                    SendMessage($"{{\"status\": \"error\", \"message\": \"mmunblock.exe fehlt im Ordner\"}}");
                }
            }
            catch
            {
                break;
            }
        }
    }

    private static string? ReadMessage()
    {
        var stdin = Console.OpenStandardInput();
        byte[] lengthBytes = new byte[4];
        if (stdin.Read(lengthBytes, 0, 4) < 4) return null;
        int length = BitConverter.ToInt32(lengthBytes, 0);
        byte[] buffer = new byte[length];
        if (stdin.Read(buffer, 0, length) < length) return null;
        using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(buffer));
        return doc.RootElement.TryGetProperty("filePath", out var pathProp) ? pathProp.GetString() : null;
    }

    private static void SendMessage(string jsonMessage)
    {
        var stdout = Console.OpenStandardOutput();
        byte[] bytes = Encoding.UTF8.GetBytes(jsonMessage);
        stdout.Write(BitConverter.GetBytes(bytes.Length), 0, 4);
        stdout.Write(bytes, 0, bytes.Length);
        stdout.Flush();
    }
}