namespace SoundDesk;

public sealed class UserPlaylist
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "";
    public List<string> TrackPaths { get; set; } = [];
}
