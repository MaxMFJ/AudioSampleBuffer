using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SoundDesk;

/// <summary>Stores platform cookies protected to the current Windows user using DPAPI.</summary>
public sealed class PlatformCredentialStore
{
    private readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "platform-cookies.json");

    public string? Load(string provider)
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(_path)) return null;
        try
        {
            var entries = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path));
            if (entries is null || !entries.TryGetValue(provider, out var value)) return null;
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(value), null, DataProtectionScope.CurrentUser));
        }
        catch (CryptographicException) { return null; }
        catch (FormatException) { return null; }
    }

    public void Save(string provider, string cookie)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("平台凭据只能在 Windows 上保护和保存。");
        var entries = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (File.Exists(_path))
        {
            try { entries = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path)) ?? entries; }
            catch (JsonException) { }
        }
        entries[provider] = Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(cookie), null, DataProtectionScope.CurrentUser));
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path, JsonSerializer.Serialize(entries));
    }

    public void Delete(string provider)
    {
        if (!File.Exists(_path)) return;
        var entries = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path)) ?? [];
        entries.Remove(provider);
        File.WriteAllText(_path, JsonSerializer.Serialize(entries));
    }
}
