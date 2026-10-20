using System.IO;
using System.Net.Http;
using System.Text.Json.Nodes;

namespace SoundDesk;

public sealed record OnlineSearchResult(string Rid, string Name, string Artist);

/// <summary>The console's online search, using the same api.qqmp3.vip flow as the iOS cloud download and Mac console.</summary>
public sealed class OnlineMusicService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };
    private readonly string _downloadDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "Downloads");

    public async Task<IReadOnlyList<OnlineSearchResult>> SearchAsync(string keyword, CancellationToken ct)
    {
        var url = "https://api.qqmp3.vip/api/songs.php?type=search&keyword=" + Uri.EscapeDataString(keyword);
        var payload = await GetJsonAsync(url, TimeSpan.FromSeconds(15), ct);
        if (Number(payload["code"]) != 200 || payload["data"] is not JsonArray rows)
            throw new InvalidOperationException("在线音乐服务返回了无法识别的数据");
        return rows.Select(row => (Rid: Text(row?["rid"]), Name: Text(row?["name"]), Artist: Text(row?["artist"])))
            .Where(row => row.Rid is not null && row.Name is not null && row.Artist is not null)
            .Select(row => new OnlineSearchResult(row.Rid!, row.Name!, row.Artist!))
            .ToArray();
    }

    /// <summary>Resolves, downloads and stores a result; returns the saved path and the service's metadata.</summary>
    public async Task<(string Path, string Title, string Artist)> DownloadAsync(OnlineSearchResult result, IProgress<string> status, CancellationToken ct)
    {
        status.Report($"正在获取歌曲信息：{result.Name}");
        var detailUrl = $"https://api.qqmp3.vip/api/kw.php?rid={Uri.EscapeDataString(result.Rid)}&type=json&level=exhigh&lrc=true";
        var payload = await GetJsonAsync(detailUrl, TimeSpan.FromSeconds(20), ct);
        var detail = payload["data"];
        if (Number(payload["code"]) != 200 || !Uri.TryCreate(Text(detail?["url"]), UriKind.Absolute, out var audioUrl)
            || audioUrl.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("没有获取到有效的歌曲下载地址");

        status.Report($"正在下载：{result.Name}");
        Directory.CreateDirectory(_downloadDirectory);
        var temporary = Path.Combine(_downloadDirectory, $"{Guid.NewGuid():N}.partial");
        try
        {
            using (var request = CreateRequest(audioUrl))
            using (var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct))
            {
                response.EnsureSuccessStatusCode();
                await using var input = await response.Content.ReadAsStreamAsync(ct);
                await using var output = File.Create(temporary);
                await input.CopyToAsync(output, ct);
            }
            var extension = SniffExtension(temporary)
                ?? throw new InvalidOperationException("下载内容不是可识别的音频文件，歌曲服务可能返回了错误页或无效数据");
            var title = Text(detail?["name"]) ?? result.Name;
            var artist = Text(detail?["artist"]) ?? result.Artist;
            var safeName = string.Join("_", $"{title} - {artist}".Split(Path.GetInvalidFileNameChars(), StringSplitOptions.RemoveEmptyEntries)).Trim();
            var destination = Path.Combine(_downloadDirectory, $"{safeName}.{extension}");
            File.Move(temporary, destination, overwrite: true);
            var lyrics = Text(detail?["lrc"]);
            if (lyrics is not null && lyrics.Contains('[')) await File.WriteAllTextAsync(Path.ChangeExtension(destination, ".lrc"), lyrics, ct);
            return (destination, title, artist);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private static string? SniffExtension(string path)
    {
        var bytes = new byte[16];
        using (var stream = File.OpenRead(path)) _ = stream.Read(bytes, 0, bytes.Length);
        bool Ascii(int offset, string text) => text.Select((c, i) => bytes[offset + i] == c).All(x => x);
        if (Ascii(0, "fLaC")) return "flac";
        if (Ascii(0, "RIFF") && Ascii(8, "WAVE")) return "wav";
        if (Ascii(4, "ftyp")) return "m4a";
        if (Ascii(0, "ID3")) return "mp3";
        if (bytes[0] == 0xFF && (bytes[1] & 0xF6) == 0xF0) return "aac";
        if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return "mp3";
        return null;
    }

    private static async Task<JsonNode> GetJsonAsync(string url, TimeSpan timeout, CancellationToken ct)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutSource.CancelAfter(timeout);
        using var request = CreateRequest(new Uri(url));
        using var response = await Http.SendAsync(request, timeoutSource.Token);
        response.EnsureSuccessStatusCode();
        return JsonNode.Parse(await response.Content.ReadAsStringAsync(timeoutSource.Token)) ?? new JsonObject();
    }

    private static HttpRequestMessage CreateRequest(Uri url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Referrer = new Uri("https://www.qqmp3.vip");
        request.Headers.TryAddWithoutValidation("Origin", "https://www.qqmp3.vip");
        request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36");
        request.Headers.TryAddWithoutValidation("Accept", "*/*");
        request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh-Hans;q=0.9");
        return request;
    }

    private static string? Text(JsonNode? node) => node is JsonValue value
        ? value.TryGetValue<string>(out var text) ? (text.Length > 0 ? text : null)
        : value.TryGetValue<long>(out var number) ? number.ToString() : null
        : null;

    private static int Number(JsonNode? node) => node is JsonValue value
        ? value.TryGetValue<int>(out var number) ? number : int.TryParse(value.ToString(), out var parsed) ? parsed : 0
        : 0;
}
