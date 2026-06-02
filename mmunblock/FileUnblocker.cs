using System.ComponentModel;

namespace mmunblock;

/// <summary>
/// Removes the Zone.Identifier Alternate Data Stream (ADS) from files,
/// effectively "unblocking" files downloaded from the internet.
/// </summary>
internal static class FileUnblocker
{
    private const string ZoneSuffix = ":Zone.Identifier";

    /// <summary>
    /// Returns true if the file has a Zone.Identifier ADS.
    /// </summary>
    public static bool IsBlocked(string filePath)
    {
        string adsPath = filePath + ZoneSuffix;
        // GetFileAttributes returns INVALID_FILE_ATTRIBUTES (0xFFFFFFFF) if the ADS does not exist.
        uint attrs = NativeMethods.GetFileAttributes(adsPath);
        return attrs != NativeMethods.INVALID_FILE_ATTRIBUTES;
    }

    /// <summary>
    /// Deletes the Zone.Identifier ADS. Returns true if unblocked, false if it was not blocked.
    /// Throws <see cref="Win32Exception"/> on other errors.
    /// </summary>
    public static bool Unblock(string filePath)
    {
        if (!IsBlocked(filePath))
            return false;

        bool ok = NativeMethods.DeleteFile(filePath + ZoneSuffix);
        if (!ok)
        {
            int err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            if (err != 2) // ERROR_FILE_NOT_FOUND — already gone, treat as success
                throw new Win32Exception(err);
        }
        return true;
    }

    /// <summary>
    /// Processes a single file. Returns the result as a <see cref="FileResult"/>.
    /// </summary>
    public static FileResult ProcessFile(string filePath)
    {
        try
        {
            bool unblocked = Unblock(filePath);
            return unblocked ? FileResult.Unblocked(filePath) : FileResult.AlreadyClear(filePath);
        }
        catch (Exception ex)
        {
            return FileResult.Failed(filePath, ex.Message);
        }
    }

    /// <summary>
    /// Recursively processes all files under <paramref name="directoryPath"/>.
    /// Inaccessible subdirectories are skipped and reported as errors.
    /// </summary>
    public static IEnumerable<FileResult> ProcessDirectory(string directoryPath, bool recursive)
    {
        IEnumerable<string>? files = null;
        string? fileExceptionMessage = null;

        try
        {
            files = Directory.GetFiles(directoryPath);
        }
        catch (Exception ex)
        {
            fileExceptionMessage = ex.Message;
        }

        // Falls ein Fehler beim Lesen der Dateien auftrat, geben wir ihn hier zurück
        if (fileExceptionMessage != null)
        {
            yield return FileResult.Failed(directoryPath, fileExceptionMessage);
            yield break;
        }

        if (files != null)
        {
            foreach (string file in files)
                yield return ProcessFile(file);
        }

        if (!recursive)
            yield break;

        IEnumerable<string>? subdirs = null;
        string? subdirExceptionMessage = null;

        try
        {
            subdirs = Directory.GetDirectories(directoryPath);
        }
        catch (Exception ex)
        {
            subdirExceptionMessage = ex.Message;
        }

        // Falls ein Fehler beim Lesen der Unterverzeichnisse auftrat
        if (subdirExceptionMessage != null)
        {
            yield return FileResult.Failed(directoryPath, subdirExceptionMessage);
            yield break;
        }

        if (subdirs != null)
        {
            foreach (string subdir in subdirs)
            {
                foreach (FileResult result in ProcessDirectory(subdir, recursive: true))
                    yield return result;
            }
        }
    }
}