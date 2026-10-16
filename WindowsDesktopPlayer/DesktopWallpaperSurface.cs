using System.Diagnostics;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>WPF fallback surface; native D3D implements the full desktop effects.</summary>
public sealed class DesktopWallpaperSurface : FrameworkElement
{
    private readonly AudioReactiveMonitor _audio;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private Color[]? _coverColors;
    private static readonly Brush BaseBrush = Frozen(new SolidColorBrush(Color.FromRgb(3, 7, 18)));
    private static readonly Color[] Palette =
    [
        Color.FromRgb(73, 226, 205), Color.FromRgb(103, 122, 255), Color.FromRgb(187, 91, 233),
        Color.FromRgb(255, 173, 110), Color.FromRgb(110, 185, 255)
    ];

    public int EffectIndex { get; set; }

    public DesktopWallpaperSurface(AudioReactiveMonitor audio)
    {
        _audio = audio;
        IsHitTestVisible = false;
    }

    public void SetArtwork(ImageSource? artwork)
    {
        _coverColors = null;
        if (artwork is BitmapSource source && source.PixelWidth > 0 && source.PixelHeight > 0)
        {
            const int width = 48;
            const int height = 48;
            var target = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            var visual = new DrawingVisual();
            using (var context = visual.RenderOpen()) context.DrawImage(source, new Rect(0, 0, width, height));
            target.Render(visual);
            var pixels = new byte[width * height * 4];
            target.CopyPixels(pixels, width * 4, 0);
            _coverColors = new Color[width * height];
            for (var index = 0; index < _coverColors.Length; index++)
            {
                var offset = index * 4;
                _coverColors[index] = Color.FromArgb(255, pixels[offset + 2], pixels[offset + 1], pixels[offset]);
            }
        }
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;
        drawingContext.DrawRectangle(BaseBrush, null, bounds);
        var spectrum = _audio.Spectrum;
        var time = _clock.Elapsed.TotalSeconds;
        switch (EffectIndex)
        {
            case 1: DrawTyndall(drawingContext, bounds, spectrum, time); break;
            case 2: DrawCoverDots(drawingContext, bounds, spectrum, time); break;
            case 3: DrawHexagonMorph(drawingContext, bounds, spectrum, time); break;
            default: DrawMacCellularHive(drawingContext, bounds, spectrum, time); break;
        }
    }

    private static void DrawAurora(DrawingContext dc, Rect bounds, float[] spectrum, double time)
    {
        var amplitude = Average(spectrum, 0, 16);
        for (var ribbon = 0; ribbon < 4; ribbon++)
        {
            var phase = time * (0.18 + ribbon * 0.025) + ribbon * 1.7;
            var yBase = bounds.Height * (0.38 + ribbon * 0.105);
            var height = bounds.Height * (0.07 + amplitude * 0.18);
            var figure = new StreamGeometry();
            using (var context = figure.Open())
            {
                context.BeginFigure(new Point(0, yBase), true, true);
                for (var step = 0; step <= 48; step++)
                {
                    var x = bounds.Width * step / 48;
                    var band = spectrum.Length == 0 ? 0 : spectrum[(step + ribbon * 7) % spectrum.Length];
                    var y = yBase + Math.Sin(step * 0.21 + phase) * height + band * height * 3;
                    context.LineTo(new Point(x, y), true, false);
                }
                context.LineTo(new Point(bounds.Width, bounds.Height), true, false);
                context.LineTo(new Point(0, bounds.Height), true, false);
            }
            figure.Freeze();
            var color = Palette[ribbon % Palette.Length];
            var brush = new LinearGradientBrush(Color.FromArgb((byte)(8 + amplitude * 35), color.R, color.G, color.B),
                Color.FromArgb(0, color.R, color.G, color.B), new Point(0.5, 0), new Point(0.5, 1));
            brush.Freeze();
            dc.DrawGeometry(brush, null, figure);
        }
        DrawSpectrumHorizon(dc, bounds, spectrum, time, 0.77);
    }

    private static void DrawTyndall(DrawingContext dc, Rect bounds, float[] spectrum, double time)
    {
        var center = new Point(bounds.Width * 0.52, bounds.Height * 0.36);
        for (var beam = 0; beam < 17; beam++)
        {
            var x = (beam / 16d - 0.5) * bounds.Width * 1.3 + Math.Sin(time * 0.2) * bounds.Width * 0.04;
            var band = spectrum.Length == 0 ? 0 : spectrum[(beam * 3) % spectrum.Length];
            var spread = bounds.Width * (0.015 + band * 0.09);
            var end = new Point(center.X + x, bounds.Height * (0.92 + band * 0.08));
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                context.BeginFigure(center, true, true);
                context.LineTo(new Point(end.X - spread, end.Y), true, false);
                context.LineTo(new Point(end.X + spread, end.Y), true, false);
            }
            geometry.Freeze();
            var alpha = (byte)(8 + Math.Clamp(band * 85, 0, 60));
            var color = Palette[beam % Palette.Length];
            var brush = new LinearGradientBrush(Color.FromArgb(alpha, color.R, color.G, color.B),
                Color.FromArgb(0, color.R, color.G, color.B), center, end);
            brush.Freeze();
            dc.DrawGeometry(brush, null, geometry);
        }
        DrawSpectrumHorizon(dc, bounds, spectrum, time, 0.9);
    }

    private void DrawCoverDots(DrawingContext dc, Rect bounds, float[] spectrum, double time)
    {
        const int columns = 48;
        var rows = Math.Max(1, (int)Math.Round(columns / (bounds.Width / bounds.Height)));
        var cell = Math.Min(bounds.Width / columns, bounds.Height / rows);
        var left = (bounds.Width - columns * cell) / 2;
        var top = (bounds.Height - rows * cell) / 2;
        var coverHeight = bounds.Height * 0.68;
        var coverWidth = coverHeight;
        var coverLeft = (bounds.Width - coverWidth) / 2;
        var coverTop = (bounds.Height - coverHeight) / 2;
        for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
        {
            var band = spectrum.Length == 0 ? 0 : spectrum[(column * spectrum.Length / columns) % spectrum.Length];
            var point = new Point(left + (column + 0.5) * cell, top + (row + 0.5) * cell);
            var inCover = _coverColors is { Length: > 0 } && point.X >= coverLeft && point.X < coverLeft + coverWidth
                && point.Y >= coverTop && point.Y < coverTop + coverHeight;
            var u = Math.Clamp((point.X - coverLeft) / coverWidth, 0, 0.9999);
            var v = Math.Clamp((point.Y - coverTop) / coverHeight, 0, 0.9999);
            var coverIndex = (int)(v * 48) * 48 + (int)(u * 48);
            var seed = Math.Abs(Math.Sin(column * 12.9898 + row * 78.233) * 43758.5453) % 1;
            var beat = Math.Clamp(Average(spectrum, 0, 6) * 2.8, 0, 1);
            var wave = (Math.Sin((inCover ? u * 21 : column * 0.12) + time * 2.4)
                * Math.Cos((inCover ? v * 17 : row * 0.17) - time * 1.7) + 1) * 0.5;
            var radius = cell * (inCover ? 0.31 + wave * 0.08 + band * 0.10 : 0.12 + beat * 0.25 * seed);
            var color = inCover && _coverColors is { } cover
                ? cover[Math.Clamp(coverIndex, 0, cover.Length - 1)]
                : Color.FromRgb(12, 15, 22);
            var alpha = (byte)(inCover ? 220 : 24 + beat * seed * 150);
            var brush = new SolidColorBrush(Color.FromArgb(alpha, color.R, color.G, color.B));
            brush.Freeze();
            dc.DrawEllipse(brush, null, point, radius, radius);
        }
    }

    private static void DrawMacCellularHive(DrawingContext dc, Rect bounds, float[] spectrum, double time)
    {
        var center = new Point(bounds.Width * 0.5, bounds.Height * 0.5);
        var scale = Math.Min(bounds.Width, bounds.Height);
        var bass = Average(spectrum, 0, Math.Max(1, spectrum.Length / 8));
        var energy = Average(spectrum, 0, spectrum.Length);
        var core = scale * (0.285 + bass * 0.022);
        var outer = scale * 0.49;
        var rings = 18;
        // Mac 蜂窝的主视觉是带透视和细胞孔洞的放射状膜，不是平铺蜂格。
        for (var ring = rings; ring >= 0; ring--)
        {
            var ratio = ring / (double)rings;
            var radius = core + (outer - core) * ratio;
            var segments = Math.Max(16, (int)(ratio * 88));
            for (var segment = 0; segment < segments; segment++)
            {
                var angle = Math.Tau * segment / segments;
                var depth = -Math.Log(Math.Max(ratio, 0.018)) * 2.15;
                var cellPhase = angle * 19 + depth * 0.52 + time * 0.31;
                var breathe = Math.Sin(cellPhase + time * 0.46) * (1.4 + energy * 3.0);
                var point = new Point(center.X + Math.Cos(angle) * (radius + breathe), center.Y + Math.Sin(angle) * (radius + breathe));
                var cell = Math.Max(2.0, scale * (0.006 + ratio * 0.004));
                var hue = (segment % 19 + ring * 0.18) % 1;
                var color = ColorFromHue(0.49 + hue * 0.2);
                var pulse = 0.45 + 0.55 * Math.Sin(time * 0.8 + segment * 0.37 + ring * 0.23);
                var alpha = (byte)Math.Clamp(11 + pulse * 24 + energy * 42, 0, 90);
                var brush = new SolidColorBrush(Color.FromArgb(alpha, color.R, color.G, color.B));
                brush.Freeze();
                var cellShape = new StreamGeometry();
                using (var context = cellShape.Open())
                {
                    for (var vertex = 0; vertex < 6; vertex++)
                    {
                        var cellAngle = Math.Tau * vertex / 6 + Math.PI / 6 + Math.Sin(time * 0.2 + segment) * 0.08;
                        var vertexPoint = new Point(point.X + Math.Cos(cellAngle) * cell, point.Y + Math.Sin(cellAngle) * cell);
                        if (vertex == 0) context.BeginFigure(vertexPoint, true, true);
                        else context.LineTo(vertexPoint, true, false);
                    }
                }
                cellShape.Freeze();
                var outline = new Pen(new SolidColorBrush(Color.FromArgb((byte)(alpha + 18), color.R, color.G, color.B)), 0.8);
                outline.Freeze();
                dc.DrawGeometry(brush, outline, cellShape);
            }
        }
        var coreBrush = new RadialGradientBrush(Color.FromArgb(95, 44, 151, 207), Color.FromArgb(0, 3, 8, 25));
        coreBrush.Freeze();
        dc.DrawEllipse(coreBrush, null, center, core * 1.25, core * 1.25);
        for (var wave = 0; wave < 3; wave++)
        {
            var phase = (time * (0.08 + wave * 0.012) + wave / 3d) % 1;
            var radius = core + phase * scale * 0.40;
            var pen = new Pen(new SolidColorBrush(Color.FromArgb((byte)(55 * (1 - phase)), 67, 210, 255)), 1.2);
            pen.Freeze();
            dc.DrawEllipse(null, pen, center, radius * bounds.Width / scale, radius);
        }
    }

    private static void DrawHexagonMorph(DrawingContext dc, Rect bounds, float[] spectrum, double time)
    {
        var radius = Math.Clamp(Math.Min(bounds.Width / 31, bounds.Height / 18) * 0.47, 8, 40);
        var dx = radius * 1.78;
        var dy = radius * 1.54;
        for (var row = -1; row < (int)(bounds.Height / dy) + 2; row++)
        for (var column = -1; column < (int)(bounds.Width / dx) + 2; column++)
        {
            var center = new Point(column * dx + (row % 2 == 0 ? 0 : dx / 2), row * dy);
            var band = spectrum.Length == 0 ? 0 : spectrum[(Math.Abs(column * 5 + row * 11)) % spectrum.Length];
            var pulse = (Math.Sin(time * 0.65 + column * 0.23 + row * 0.29) + 1) * 0.5;
            var shape = new StreamGeometry();
            using (var context = shape.Open())
            {
                for (var vertex = 0; vertex < 6; vertex++)
                {
                    var angle = Math.PI / 3 * vertex + Math.PI / 6;
                    var point = new Point(center.X + Math.Cos(angle) * radius, center.Y + Math.Sin(angle) * radius);
                    if (vertex == 0) context.BeginFigure(point, true, true);
                    else context.LineTo(point, true, false);
                }
            }
            shape.Freeze();
            var color = Palette[Math.Abs(column + row * 3) % Palette.Length];
            var alpha = (byte)(10 + pulse * 20 + band * 150);
            var fill = new SolidColorBrush(Color.FromArgb(alpha, color.R, color.G, color.B));
            var stroke = new Pen(new SolidColorBrush(Color.FromArgb((byte)(18 + band * 130), color.R, color.G, color.B)), 1);
            fill.Freeze(); stroke.Brush.Freeze(); stroke.Freeze();
            dc.DrawGeometry(fill, stroke, shape);
        }
    }

    private static Color ColorFromHue(double hue)
    {
        var sector = (hue % 1) * 6;
        var chroma = 0.75;
        var x = chroma * (1 - Math.Abs(sector % 2 - 1));
        var (r, g, b) = sector switch
        {
            < 1 => (chroma, x, 0d), < 2 => (x, chroma, 0d), < 3 => (0d, chroma, x),
            < 4 => (0d, x, chroma), < 5 => (x, 0d, chroma), _ => (chroma, 0d, x)
        };
        return Color.FromRgb((byte)(r * 255), (byte)(g * 255), (byte)(b * 255));
    }

    private static void DrawSpectrumHorizon(DrawingContext dc, Rect bounds, float[] spectrum, double time, double yRatio)
    {
        var baseline = bounds.Height * yRatio;
        var figure = new StreamGeometry();
        using (var context = figure.Open())
        {
            context.BeginFigure(new Point(0, baseline), false, false);
            for (var index = 0; index < spectrum.Length; index++)
            {
                var x = bounds.Width * index / Math.Max(1, spectrum.Length - 1);
                var y = baseline - spectrum[index] * bounds.Height * 0.25 - Math.Sin(index * 0.25 + time) * 2;
                context.LineTo(new Point(x, y), true, false);
            }
        }
        figure.Freeze();
        var pen = new Pen(new LinearGradientBrush(Palette[0], Palette[2], 0), 1.5);
        pen.Freeze();
        dc.DrawGeometry(null, pen, figure);
    }

    private static double Average(float[] values, int start, int count)
    {
        if (values.Length == 0) return 0;
        var end = Math.Min(values.Length, start + count);
        return end <= start ? 0 : values.Skip(start).Take(end - start).Average();
    }

    private static T Frozen<T>(T value) where T : Freezable
    {
        value.Freeze();
        return value;
    }
}
