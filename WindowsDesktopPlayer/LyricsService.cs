using System.Net.Http;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SoundDesk;

public sealed record TimedLyric(double Time, string Text);

public sealed class LyricsService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private static readonly Regex Timestamp = new(@"\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]", RegexOptions.Compiled);
    private readonly string _cacheDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "Lyrics");
    private readonly string _settingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "lyrics-settings.json");
    public LyricsDisplaySettings Settings { get; private set; } = new() { Enabled = false };

    public LyricsService()
    {
        try
        {
            if (File.Exists(_settingsPath))
                Settings = JsonSerializer.Deserialize<LyricsDisplaySettings>(File.ReadAllText(_settingsPath)) ?? Settings;
        }
        catch (Exception error) when (error is IOException or JsonException) { }
    }

    public void UpdateSettings(LyricsDisplaySettings settings)
    {
        settings.LineCount = Math.Clamp(settings.LineCount, 1, 12);
        settings.PositionX = Math.Clamp(settings.PositionX, 0, 1);
        settings.PositionY = Math.Clamp(settings.PositionY, 0, 1);
        settings.WidthFraction = Math.Clamp(settings.WidthFraction, .2, 1);
        settings.FontSize = Math.Clamp(settings.FontSize, 12, 72);
        settings.InactiveScale = Math.Clamp(settings.InactiveScale, .3, 1);
        settings.InactiveOpacity = Math.Clamp(settings.InactiveOpacity, 0, 1);
        Settings = settings;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
            File.WriteAllText(_settingsPath, JsonSerializer.Serialize(settings));
        }
        catch (IOException) { }
    }

    public async Task<IReadOnlyList<TimedLyric>> LoadAsync(LocalTrack track, CancellationToken cancellationToken = default)
    {
        var local = Path.ChangeExtension(track.Path, ".lrc");
        if (File.Exists(local))
        {
            var parsed = Parse(await File.ReadAllTextAsync(local, cancellationToken));
            if (parsed.Count > 0) return parsed;
        }

        var cached = Path.Combine(_cacheDirectory, SafeFileName($"{track.Artist}-{track.Title}") + ".lrc");
        if (File.Exists(cached))
        {
            var parsed = Parse(await File.ReadAllTextAsync(cached, cancellationToken));
            if (parsed.Count > 0) return parsed;
        }

        var lyrics = await FetchFromQQAsync(track.Title, track.Artist, cancellationToken);
        if (string.IsNullOrWhiteSpace(lyrics)) return [];
        var lines = Parse(lyrics);
        if (lines.Count == 0) return [];
        Directory.CreateDirectory(_cacheDirectory);
        await File.WriteAllTextAsync(cached, lyrics, cancellationToken);
        return lines;
    }

    public static IReadOnlyList<TimedLyric> Parse(string content)
    {
        var output = new List<TimedLyric>();
        foreach (var line in content.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            var matches = Timestamp.Matches(line);
            if (matches.Count == 0) continue;
            var text = Timestamp.Replace(line, "").Trim();
            if (text.Length == 0) continue;
            foreach (Match match in matches)
            {
                if (!int.TryParse(match.Groups[1].Value, out var minutes)
                    || !int.TryParse(match.Groups[2].Value, out var seconds)) continue;
                var fractionText = match.Groups[3].Value;
                var fraction = fractionText.Length switch
                {
                    1 when int.TryParse(fractionText, out var tenth) => tenth / 10d,
                    2 when int.TryParse(fractionText, out var hundredth) => hundredth / 100d,
                    3 when int.TryParse(fractionText, out var millisecond) => millisecond / 1000d,
                    _ => 0d
                };
                output.Add(new TimedLyric(minutes * 60 + seconds + fraction, text));
            }
        }
        return output.OrderBy(item => item.Time).ToArray();
    }

    public static (int Active, string Previous, string Current, string Next) FrameAt(IReadOnlyList<TimedLyric> lines, double time)
    {
        var active = -1;
        for (var index = 0; index < lines.Count; index++)
        {
            if (lines[index].Time > time) break;
            active = index;
        }
        if (active < 0) return (-1, "", "", lines.Count > 0 ? lines[0].Text : "暂无歌词");
        return (active,
            active > 0 ? lines[active - 1].Text : "",
            lines[active].Text,
            active + 1 < lines.Count ? lines[active + 1].Text : "");
    }

    private static async Task<string?> FetchFromQQAsync(string title, string artist, CancellationToken cancellationToken)
    {
        var query = Uri.EscapeDataString($"{artist} {title}".Trim());
        var searchUrl = $"https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=1&w={query}&format=json";
        using var searchRequest = new HttpRequestMessage(HttpMethod.Get, searchUrl);
        searchRequest.Headers.Referrer = new Uri("https://y.qq.com/");
        using var searchResponse = await Http.SendAsync(searchRequest, cancellationToken);
        searchResponse.EnsureSuccessStatusCode();
        using var searchJson = JsonDocument.Parse(await searchResponse.Content.ReadAsStringAsync(cancellationToken));
        if (!searchJson.RootElement.TryGetProperty("data", out var data)
            || !data.TryGetProperty("song", out var song)
            || !song.TryGetProperty("list", out var list)
            || list.GetArrayLength() == 0
            || !list[0].TryGetProperty("songmid", out var songMid)) return null;

        var lyricUrl = $"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid={Uri.EscapeDataString(songMid.GetString() ?? "")}&format=json";
        using var lyricRequest = new HttpRequestMessage(HttpMethod.Get, lyricUrl);
        lyricRequest.Headers.Referrer = new Uri("https://y.qq.com/");
        using var lyricResponse = await Http.SendAsync(lyricRequest, cancellationToken);
        lyricResponse.EnsureSuccessStatusCode();
        using var lyricJson = JsonDocument.Parse(await lyricResponse.Content.ReadAsStringAsync(cancellationToken));
        if (!lyricJson.RootElement.TryGetProperty("lyric", out var encoded)) return null;
        try { return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(encoded.GetString() ?? "")); }
        catch (FormatException) { return null; }
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var safe = new string(value.Select(character => invalid.Contains(character) ? '_' : character).ToArray());
        return safe.Length > 100 ? safe[..100] : safe;
    }
}
