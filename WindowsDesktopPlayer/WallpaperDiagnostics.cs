using System.Diagnostics;
using System.IO;

namespace SoundDesk;

internal static class WallpaperDiagnostics
{
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "wallpaper.log");

    public static void Write(string message)
    {
        Debug.WriteLine(message);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 262144) File.Delete(LogPath);
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Wallpaper log unavailable: {error.Message}");
        }
    }
}
