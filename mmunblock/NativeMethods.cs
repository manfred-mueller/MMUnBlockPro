using System.Runtime.InteropServices;

namespace mmunblock;

/// <summary>
/// P/Invoke declarations. Kept in one place so the rest of the code stays P/Invoke-free.
/// </summary>
internal static class NativeMethods
{
    public const uint INVALID_FILE_ATTRIBUTES = 0xFFFF_FFFF;

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint GetFileAttributes(string lpFileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool DeleteFile(string lpFileName);
}
