using System.Security.Cryptography;
using System.Net.Http;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SoundDesk;

public enum MusicProvider { QQ, NetEase, Kugou }

public sealed record PlatformTrack(
    string Id, MusicProvider Provider, string Title, string Artist, string Album,
    double DurationSeconds, string? CoverUrl, string? MediaId = null,
    string? Hash = null, string? AlbumId = null, string? AlbumAudioId = null)
{
    public string DurationText => DurationSeconds <= 0 ? "—" : $"{(int)TimeSpan.FromSeconds(DurationSeconds).TotalMinutes}:{TimeSpan.FromSeconds(DurationSeconds).Seconds:00}";
}

public sealed class PlatformMusicService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private const string QQScrambleHex = "5927b396da523afcb134ba7b7840f2858fa179b3";
    private readonly PlatformCredentialStore _credentials = new();

    public static IReadOnlyList<MusicProvider> Providers { get; } = Enum.GetValues<MusicProvider>();

    public async Task<IReadOnlyList<PlatformTrack>> SearchAsync(MusicProvider provider, string keywords, int limit = 30, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(keywords)) return [];
        return provider switch
        {
            MusicProvider.QQ => await SearchQQAsync(keywords, limit, cancellationToken),
            MusicProvider.NetEase => await SearchNetEaseAsync(keywords, limit, cancellationToken),
            MusicProvider.Kugou => await SearchKugouAsync(keywords, limit, cancellationToken),
            _ => []
        };
    }

    public async Task<Uri> ResolvePlaybackAsync(PlatformTrack track, CancellationToken cancellationToken = default)
    {
        return track.Provider switch
        {
            MusicProvider.QQ => await ResolveQQAsync(track, cancellationToken),
            MusicProvider.NetEase => await ResolveNetEaseAsync(track, cancellationToken),
            MusicProvider.Kugou => await ResolveKugouAsync(track, cancellationToken),
            _ => throw new InvalidOperationException("不支持的音乐平台。")
        };
    }

    public async Task<string> DownloadTrackAsync(PlatformTrack track, CancellationToken cancellationToken = default)
    {
        var url = await ResolvePlaybackAsync(track, cancellationToken);
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "PlatformAudio");
        Directory.CreateDirectory(directory);
        var extension = Path.GetExtension(url.AbsolutePath);
        if (string.IsNullOrWhiteSpace(extension) || extension.Length > 8) extension = ".audio";
        var fileName = System.Text.RegularExpressions.Regex.Replace($"{track.Provider}-{track.Id}", "[^a-zA-Z0-9_-]", "_");
        var destination = Path.Combine(directory, fileName + extension);
        if (File.Exists(destination) && new FileInfo(destination).Length > 4096) return destination;

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        AddProviderHeaders(request, track.Provider switch
        {
            MusicProvider.QQ => "https://y.qq.com/",
            MusicProvider.NetEase => "https://music.163.com/",
            _ => "https://www.kugou.com/"
        }, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36");
        using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > 314_572_800)
            throw new InvalidOperationException("平台音频文件超过 300 MB，已停止下载。");
        var contentType = response.Content.Headers.ContentType?.MediaType ?? "";
        if (contentType.Contains("text/html", StringComparison.OrdinalIgnoreCase)
            || contentType.Contains("json", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("平台返回的不是音频数据，播放地址可能已过期。");
        var temporary = destination + ".partial";
        await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var output = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None, 65536, useAsync: true))
        {
            var buffer = new byte[65536];
            long total = 0;
            int read;
            while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
            {
                total += read;
                if (total > 314_572_800) throw new InvalidOperationException("平台音频文件超过 300 MB，已停止下载。");
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }
            if (total < 4096) throw new InvalidOperationException("平台返回的音频数据不完整。");
        }
        File.Move(temporary, destination, overwrite: true);
        return destination;
    }

    public string? LoadCookie(MusicProvider provider) => _credentials.Load(provider.ToString());
    public void SaveCookie(MusicProvider provider, string cookie) => _credentials.Save(provider.ToString(), NormalizeCookie(cookie));
    public void DeleteCookie(MusicProvider provider) => _credentials.Delete(provider.ToString());

    private async Task<IReadOnlyList<PlatformTrack>> SearchNetEaseAsync(string query, int limit, CancellationToken cancellationToken)
    {
        var payload = new JsonObject
        {
            ["s"] = query, ["type"] = 1, ["limit"] = Math.Clamp(limit, 1, 50), ["offset"] = 0, ["total"] = true
        };
        var response = await NetEaseRequestAsync("/api/cloudsearch/pc", payload, cancellationToken);
        var rows = response["result"]?["songs"]?.AsArray() ?? [];
        return rows.Select(row =>
        {
            var song = row?.AsObject();
            var artists = song?["ar"]?.AsArray() ?? song?["artists"]?.AsArray() ?? [];
            var artist = string.Join(" / ", artists.Select(item => item?["name"]?.GetValue<string>()).Where(name => !string.IsNullOrWhiteSpace(name)));
            return new PlatformTrack(
                song?["id"]?.ToString() ?? "", MusicProvider.NetEase,
                song?["name"]?.GetValue<string>() ?? "", artist,
                song?["al"]?["name"]?.GetValue<string>() ?? song?["album"]?["name"]?.GetValue<string>() ?? "",
                (song?["dt"]?.GetValue<double>() ?? 0) / 1000,
                song?["al"]?["picUrl"]?.GetValue<string>() ?? song?["album"]?["picUrl"]?.GetValue<string>());
        }).Where(track => track.Id.Length > 0).ToArray();
    }

    private async Task<IReadOnlyList<PlatformTrack>> SearchQQAsync(string query, int limit, CancellationToken cancellationToken)
    {
        var pageSize = Math.Clamp(limit, 1, 30);
        var payload = new JsonObject
        {
            ["comm"] = new JsonObject { ["ct"] = "11", ["cv"] = "14090508", ["v"] = "14090508", ["tmeAppID"] = "qqmusic", ["phonetype"] = "EBG-AN10", ["os_ver"] = "12", ["OpenUDID"] = "0", ["QIMEI36"] = "0", ["udid"] = "0", ["chid"] = "0", ["aid"] = "0", ["oaid"] = "0", ["taid"] = "0", ["tid"] = "0", ["wid"] = "0", ["uid"] = "0", ["sid"] = "0", ["modeSwitch"] = "6", ["teenMode"] = "0", ["ui_mode"] = "2", ["nettype"] = "1020" },
            ["req"] = new JsonObject { ["module"] = "music.search.SearchCgiService", ["method"] = "DoSearchForQQMusicMobile", ["param"] = new JsonObject { ["search_type"] = 0, ["searchid"] = Guid.NewGuid().ToString(), ["query"] = query, ["page_num"] = 1, ["num_per_page"] = pageSize, ["sin"] = 0, ["cat"] = 2, ["grp"] = 1, ["highlight"] = 0, ["nqc_flag"] = 0, ["multi_zhida"] = 0, ["sem"] = 0 } }
        };
        var body = JsonSerializer.SerializeToUtf8Bytes(payload);
        var url = "https://u.y.qq.com/cgi-bin/musics.fcg?sign=" + Uri.EscapeDataString(QQSearchSign(body));
        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new ByteArrayContent(body) };
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        AddProviderHeaders(request, "https://y.qq.com/", "QQMusic 14090508(android 12)");
        using var response = await Http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var root = JsonNode.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var reqData = root?["req"]?["data"];
        var bodyNode = reqData?["body"] ?? reqData;
        var items = bodyNode?["item_song"]?.AsArray() ?? bodyNode?["song"]?["list"]?.AsArray() ?? [];
        return items.Select(item =>
        {
            var song = item?["track_info"] ?? item?["songInfo"] ?? item;
            var singers = song?["singer"]?.AsArray() ?? [];
            var artist = string.Join(" / ", singers.Select(s => s?["name"]?.GetValue<string>()).Where(s => !string.IsNullOrWhiteSpace(s)));
            var albumMid = song?["album"]?["mid"]?.GetValue<string>();
            return new PlatformTrack(song?["mid"]?.GetValue<string>() ?? "", MusicProvider.QQ,
                song?["name"]?.GetValue<string>() ?? "", artist, song?["album"]?["name"]?.GetValue<string>() ?? "",
                song?["interval"]?.GetValue<double>() ?? 0,
                string.IsNullOrWhiteSpace(albumMid) ? null : $"https://y.qq.com/music/photo_new/T002R300x300M000{albumMid}.jpg",
                song?["file"]?["media_mid"]?.GetValue<string>());
        }).Where(track => track.Id.Length > 0).ToArray();
    }

    private async Task<IReadOnlyList<PlatformTrack>> SearchKugouAsync(string query, int limit, CancellationToken cancellationToken)
    {
        var parameters = new Dictionary<string, string>
        {
            ["keyword"] = query, ["page"] = "1", ["pagesize"] = Math.Clamp(limit, 1, 20).ToString(),
            ["userid"] = "-1", ["clientver"] = "2000", ["platform"] = "WebFilter", ["tag"] = "em",
            ["filter"] = "2", ["iscorrection"] = "1", ["privilege_filter"] = "0", ["filter_ver"] = "2", ["appid"] = "1014", ["token"] = ""
        };
        var url = "https://songsearch.kugou.com/song_search_v2?" + string.Join("&", parameters.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        AddProviderHeaders(request, "https://www.kugou.com/", "Mozilla/5.0");
        using var response = await Http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var root = JsonNode.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var rows = root?["data"]?["lists"]?.AsArray() ?? [];
        return rows.Select(row =>
        {
            var hash = row?["FileHash"]?.GetValue<string>() ?? "";
            var title = StripHtml(row?["SongName"]?.GetValue<string>() ?? row?["FileName"]?.GetValue<string>() ?? "");
            return new PlatformTrack(hash, MusicProvider.Kugou, title,
                row?["SingerName"]?.GetValue<string>() ?? "", row?["AlbumName"]?.GetValue<string>() ?? "",
                row?["Duration"]?.GetValue<double>() ?? 0, row?["Image"]?.GetValue<string>(), Hash: hash,
                AlbumId: row?["AlbumID"]?.ToString(), AlbumAudioId: row?["MixSongID"]?.ToString());
        }).Where(track => track.Id.Length > 0 && track.Title.Length > 0).ToArray();
    }

    private async Task<Uri> ResolveNetEaseAsync(PlatformTrack track, CancellationToken cancellationToken)
    {
        var payload = new JsonObject { ["ids"] = JsonSerializer.Serialize(new[] { track.Id }), ["level"] = "exhigh", ["encodeType"] = "flac" };
        var response = await NetEaseRequestAsync("/api/song/enhance/player/url/v1", payload, cancellationToken);
        var row = response["data"]?.AsArray().FirstOrDefault();
        var url = row?["url"]?.GetValue<string>();
        return Uri.TryCreate(url, UriKind.Absolute, out var result) ? result : throw new InvalidOperationException("网易云未返回可播放地址（可能受版权或会员限制）。");
    }

    private async Task<Uri> ResolveQQAsync(PlatformTrack track, CancellationToken cancellationToken)
    {
        var cookie = _credentials.Load("QQ") ?? "";
        var uin = CookieValue(cookie, "uin") ?? CookieValue(cookie, "qqmusic_uin") ?? "0";
        var key = CookieValue(cookie, "qm_keyst") ?? CookieValue(cookie, "qqmusic_key") ?? "";
        var qualities = new[] { ("M800", ".mp3"), ("M500", ".mp3"), ("C400", ".m4a") };
        var mediaId = string.IsNullOrWhiteSpace(track.MediaId) ? track.Id : track.MediaId;
        var filenames = qualities.Select(item => item.Item1 + mediaId + item.Item2).ToArray();
        var payload = new JsonObject
        {
            ["comm"] = new JsonObject { ["uin"] = uin, ["format"] = "json", ["ct"] = string.IsNullOrEmpty(key) ? 24 : 19, ["cv"] = 0, ["authst"] = key },
            ["req_0"] = new JsonObject { ["module"] = "vkey.GetVkeyServer", ["method"] = "CgiGetVkey", ["param"] = new JsonObject { ["guid"] = Random.Shared.Next(10_000_000, 99_999_999).ToString(), ["songmid"] = new JsonArray(filenames.Select(_ => (JsonNode?)JsonValue.Create(track.Id)).ToArray()), ["songtype"] = new JsonArray(filenames.Select(_ => (JsonNode?)JsonValue.Create(0)).ToArray()), ["uin"] = uin, ["loginflag"] = 1, ["platform"] = "20", ["filename"] = new JsonArray(filenames.Select(name => (JsonNode?)JsonValue.Create(name)).ToArray()) } }
        };
        var body = JsonSerializer.SerializeToUtf8Bytes(payload);
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://u.y.qq.com/cgi-bin/musics.fcg") { Content = new ByteArrayContent(body) };
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        if (!string.IsNullOrWhiteSpace(cookie)) request.Headers.TryAddWithoutValidation("Cookie", cookie);
        AddProviderHeaders(request, "https://y.qq.com/", "QQMusic 14090508(android 12)");
        using var response = await Http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var root = JsonNode.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var data = root?["req_0"]?["data"];
        var info = data?["midurlinfo"]?.AsArray().FirstOrDefault(item => !string.IsNullOrWhiteSpace(item?["purl"]?.GetValue<string>()));
        var purl = info?["purl"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(purl)) throw new InvalidOperationException("QQ 音乐未返回可播放音源。需要先登录 QQ 音乐，并且歌曲需在账号权限范围内。");
        var sip = data?["sip"]?.AsArray().FirstOrDefault()?.GetValue<string>() ?? "https://ws.stream.qqmusic.qq.com/";
        return new Uri(sip + purl);
    }

    private async Task<Uri> ResolveKugouAsync(PlatformTrack track, CancellationToken cancellationToken)
    {
        var cookie = _credentials.Load("Kugou") ?? "";
        var userId = CookieValue(cookie, "userid") ?? CookieValue(cookie, "KugooID");
        var token = CookieValue(cookie, "token") ?? CookieValue(cookie, "t");
        if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(token) || string.IsNullOrWhiteSpace(track.Hash))
            throw new InvalidOperationException("酷狗播放需要登录凭据。请在平台账号窗口保存酷狗 Cookie 后重试。");
        var mid = CookieValue(cookie, "kg_mid") ?? Md5("mineradio-kugou:" + (userId ?? token));
        var parameters = new Dictionary<string, string>
        {
            ["hash"] = track.Hash, ["album_id"] = track.AlbumId ?? "0", ["album_audio_id"] = track.AlbumAudioId ?? "0",
            ["srcappid"] = "2919", ["clientver"] = "20000", ["uuid"] = mid, ["mid"] = mid,
            ["userid"] = userId!, ["token"] = token!
        };
        const string salt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt";
        parameters["signature"] = Md5(salt + string.Join("", parameters.OrderBy(pair => pair.Key).Select(pair => pair.Key + "=" + pair.Value)) + salt);
        var url = "https://wwwapi.kugou.com/play/songinfo?" + string.Join("&", parameters.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("Cookie", cookie);
        AddProviderHeaders(request, "https://www.kugou.com/", "Mozilla/5.0");
        using var response = await Http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var root = JsonNode.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var stream = root?["url"]?.GetValue<string>() ?? root?["play_url"]?.GetValue<string>() ?? root?["data"]?["url"]?.GetValue<string>();
        return Uri.TryCreate(stream, UriKind.Absolute, out var result) ? result : throw new InvalidOperationException("酷狗未返回可播放地址。");
    }

    private async Task<JsonNode> NetEaseRequestAsync(string path, JsonObject payload, CancellationToken cancellationToken)
    {
        var cookie = _credentials.Load("NetEase") ?? "";
        var cookies = ParseCookie(cookie);
        payload["csrf_token"] = cookies.GetValueOrDefault("__csrf", "");
        payload["e_r"] = false;
        payload["header"] = new JsonObject
        {
            ["osver"] = "14.0.0", ["deviceId"] = "", ["os"] = "iPhone OS", ["appver"] = "9.0.90",
            ["versioncode"] = "140", ["mobilename"] = "", ["buildver"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(),
            ["resolution"] = "1920x1080", ["__csrf"] = cookies.GetValueOrDefault("__csrf", ""), ["channel"] = "distribution",
            ["requestId"] = Guid.NewGuid().ToString("N"), ["MUSIC_U"] = cookies.GetValueOrDefault("music_u", ""),
            ["MUSIC_A"] = cookies.GetValueOrDefault("music_a", "")
        };
        var plaintext = payload.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
        var md5 = Md5($"nobody{path}use{plaintext}md5forencrypt");
        var envelope = $"{path}-36cd479b6b5-{plaintext}-36cd479b6b5-{md5}";
        var encrypted = AesEcbPkcs7(Encoding.UTF8.GetBytes(envelope), Encoding.UTF8.GetBytes("e82ckenh8dichen8"));
        var form = "params=" + Convert.ToHexString(encrypted);
        var url = "https://interface.music.163.com/eapi/" + path[5..];
        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(form, Encoding.UTF8, "application/x-www-form-urlencoded") };
        request.Headers.Referrer = new Uri("https://music.163.com/");
        request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36");
        if (!string.IsNullOrWhiteSpace(cookie)) request.Headers.TryAddWithoutValidation("Cookie", cookie);
        using var response = await Http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var text = await response.Content.ReadAsStringAsync(cancellationToken);
        try { return JsonNode.Parse(text) ?? new JsonObject(); }
        catch (JsonException)
        {
            try { return JsonNode.Parse(Encoding.UTF8.GetString(AesEcbPkcs7(Convert.FromHexString(text), Encoding.UTF8.GetBytes("e82ckenh8dichen8"), decrypt: true))) ?? new JsonObject(); }
            catch { throw new InvalidOperationException("网易云接口返回了无法识别的数据。"); }
        }
    }

    private static byte[] AesEcbPkcs7(byte[] data, byte[] key, bool decrypt = false)
    {
        using var aes = Aes.Create();
        aes.Key = key; aes.Mode = CipherMode.ECB; aes.Padding = PaddingMode.PKCS7;
        using var transform = decrypt ? aes.CreateDecryptor() : aes.CreateEncryptor();
        return transform.TransformFinalBlock(data, 0, data.Length);
    }

    private static string QQSearchSign(byte[] body)
    {
        var hash = Convert.ToHexString(SHA1.HashData(body)).ToLowerInvariant();
        var first = new[] { 23, 14, 6, 36, 16, 0, 7, 19 }.Select(index => hash[index]).Aggregate(new StringBuilder(), (builder, value) => builder.Append(value)).ToString();
        var second = new[] { 16, 1, 32, 12, 19, 27, 8, 5 }.Select(index => hash[index]).Aggregate(new StringBuilder(), (builder, value) => builder.Append(value)).ToString();
        var scramble = Convert.FromHexString(QQScrambleHex);
        for (var index = 0; index < scramble.Length; index++) scramble[index] ^= Convert.ToByte(hash.Substring(index * 2, 2), 16);
        var middle = Convert.ToBase64String(scramble).Replace("\\", "").Replace("/", "").Replace("+", "").Replace("=", "");
        return $"zzc{first}{middle}{second}".ToLowerInvariant();
    }

    private static void AddProviderHeaders(HttpRequestMessage request, string referer, string userAgent)
    {
        request.Headers.Referrer = new Uri(referer);
        request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
    }

    private static string NormalizeCookie(string cookie) => string.Join("; ", ParseCookie(cookie).Select(pair => $"{pair.Key}={pair.Value}"));
    private static Dictionary<string, string> ParseCookie(string cookie) => cookie.Split(';', StringSplitOptions.RemoveEmptyEntries)
        .Select(part => part.Split('=', 2)).Where(parts => parts.Length == 2)
        .GroupBy(parts => parts[0].Trim().ToLowerInvariant(), StringComparer.OrdinalIgnoreCase)
        .ToDictionary(group => group.Key, group => group.Last()[1].Trim(), StringComparer.OrdinalIgnoreCase);
    private static string? CookieValue(string cookie, string name) => ParseCookie(cookie).GetValueOrDefault(name.ToLowerInvariant());
    private static string Md5(string value) => Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    private static string StripHtml(string value) => System.Text.RegularExpressions.Regex.Replace(value, "<[^>]+>", "").Trim();
}
