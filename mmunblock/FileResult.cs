namespace mmunblock;

internal enum FileResultKind { Unblocked, AlreadyClear, Failed }

internal sealed class FileResult
{
    public FileResultKind Kind { get; }
    public string Path    { get; }
    public string? Error  { get; }

    private FileResult(FileResultKind kind, string path, string? error = null)
    {
        Kind  = kind;
        Path  = path;
        Error = error;
    }

    public static FileResult Unblocked(string path)             => new(FileResultKind.Unblocked,    path);
    public static FileResult AlreadyClear(string path)          => new(FileResultKind.AlreadyClear, path);
    public static FileResult Failed(string path, string error)  => new(FileResultKind.Failed,       path, error);
}
