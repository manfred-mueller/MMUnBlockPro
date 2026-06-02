using System.CommandLine;
using mmunblock;

// ── CLI definition ────────────────────────────────────────────────────────────

var pathsArg = new Argument<string[]>(
    name: "paths",
    description: mmunblock.Properties.Resources.OneOrMoreFileOrFolderPathsToUnblockWildcardsAreExpandedByTheShell)
{
    Arity = ArgumentArity.OneOrMore
};

var noRecurseOption = new Option<bool>(
    aliases: new[] { "--no-recurse", "-n" },
    description: mmunblock.Properties.Resources.DoNotRecurseIntoSubdirectories);

var quietOption = new Option<bool>(
    aliases: new[] { "--quiet", "-q" },
    description: mmunblock.Properties.Resources.OnlyPrintErrorsAndTheFinalSummary);

var rootCommand = new RootCommand(mmunblock.Properties.Resources.RemovesTheZoneIdentifierADSInternetBlockFromFiles)
{
    pathsArg,
    noRecurseOption,
    quietOption,
};

// ── Eigene Validierung für die Fehlermeldung bei fehlenden Pfaden ──────────────
rootCommand.AddValidator(result =>
{
    var pathsResult = result.FindResultFor(pathsArg);
    if (pathsResult == null || pathsResult.Tokens.Count == 0)
    {
        result.ErrorMessage = mmunblock.Properties.Resources.ErrorRequiredArgumentMissing;
    }
});

rootCommand.SetHandler((string[] paths, bool noRecurse, bool quiet) =>
{
    bool recursive = !noRecurse;
    int unblocked = 0, alreadyClear = 0, failed = 0;

    foreach (string rawPath in paths)
    {
        if (Directory.Exists(rawPath))
        {
            foreach (var result in FileUnblocker.ProcessDirectory(rawPath, recursive))
                Handle(result);
        }
        else if (File.Exists(rawPath))
        {
            Handle(FileUnblocker.ProcessFile(rawPath));
        }
        else
        {
            Console.Error.WriteLine(String.Format(mmunblock.Properties.Resources.NOTFOUND, rawPath));
            failed++;
        }
    }

    // ── Summary ───────────────────────────────────────────────────────────────
    Console.WriteLine();
    Console.WriteLine(String.Format(mmunblock.Properties.Resources.Done0Unblocked1AlreadyClear2Failed, unblocked, alreadyClear, failed));

    if (failed > 0)
        Environment.Exit(2);
    if (unblocked == 0 && alreadyClear == 0)
        Environment.Exit(1);

    void Handle(FileResult result)
    {
        switch (result.Kind)
        {
            case FileResultKind.Unblocked:
                unblocked++;
                if (!quiet) Console.WriteLine(String.Format(mmunblock.Properties.Resources.LogUnblocked, result.Path));
                break;

            case FileResultKind.AlreadyClear:
                alreadyClear++;
                if (!quiet) Console.WriteLine(String.Format(mmunblock.Properties.Resources.LogAlreadyClear, result.Path));
                break;

            case FileResultKind.Failed:
                failed++;
                Console.Error.WriteLine(String.Format(mmunblock.Properties.Resources.ERROR01, result.Path, result.Error));
                break;
        }
    }

}, pathsArg, noRecurseOption, quietOption);

// ── Globale Live-Übersetzung der Konsolenausgabe ──────────────────────────────
// Wir leiten den Standard-Ausgabetext durch einen eigenen Übersetzer, 
// bevor er im Terminal landet. Das fängt sowohl "--help" als auch automatische Fehler ab!
var originalOut = Console.Out;
var originalError = Console.Error;

using var localOutTranslator = new LiveTranslationWriter(originalOut);
using var localErrorTranslator = new LiveTranslationWriter(originalError);

Console.SetOut(localOutTranslator);
Console.SetError(localErrorTranslator);

// Framework ausführen (Ausgaben werden jetzt automatisch live übersetzt)
int exitCode = rootCommand.Invoke(args);

// Konsolen-Streams wieder sauber zurücksetzen
Console.SetOut(originalOut);
Console.SetError(originalError);

return exitCode;


// ── Hilfsklasse für die Echtzeit-Übersetzung ──────────────────────────────────
internal class LiveTranslationWriter : TextWriter
{
    private readonly TextWriter _originalWriter;
    public override System.Text.Encoding Encoding => _originalWriter.Encoding;

    public LiveTranslationWriter(TextWriter originalWriter)
    {
        _originalWriter = originalWriter;
    }

    public override void Write(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            _originalWriter.Write(value);
            return;
        }

        // Übersetzt alle bekannten System.CommandLine-Begriffe live aus deinen Ressourcen
        string translated = value
            .Replace("Description:", mmunblock.Properties.Resources.Description)
            .Replace("<paths>... [options]", mmunblock.Properties.Resources.PathOptions)
            .Replace("Usage:", mmunblock.Properties.Resources.Usage)
            .Replace("Arguments:", mmunblock.Properties.Resources.Arguments)
            .Replace("Options:", mmunblock.Properties.Resources.Options)
            .Replace("Show version information", mmunblock.Properties.Resources.VersionInfo)
            .Replace("Show help and usage information", mmunblock.Properties.Resources.UsageInfo)
            .Replace("Required argument missing for command:", mmunblock.Properties.Resources.ErrorRequiredArgumentMissing); // Passt auf deinen Fehler-Screenshot

        _originalWriter.Write(translated);
    }

    public override void WriteLine(string? value) => Write(value + Environment.NewLine);
}