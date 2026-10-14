using System.Diagnostics;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>Audio-reactive desktop background matching the four macOS background choices.</summary>
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
            const int height = 28;
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
            case 3: DrawCellularHive(drawingContext, bounds, spectrum, time); break;
            default: DrawAurora(drawingContext, bounds, spectrum, time); break;
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
        const int rows = 28;
        var cell = Math.Min(bounds.Width / columns, bounds.Height / rows);
        var left = (bounds.Width - columns * cell) / 2;
        var top = (bounds.Height - rows * cell) / 2;
        for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
        {
            var band = spectrum.Length == 0 ? 0 : spectrum[(column * spectrum.Length / columns) % spectrum.Length];
            var wave = (Math.Sin(column * 0.19 + time * 0.7 + row * 0.11) + 1) * 0.5;
            var radius = cell * (0.12 + wave * 0.13 + band * 0.38);
            var color = _coverColors is { Length: > 0 } cover
                ? cover[row * columns + column]
                : Palette[(column / 16 + row / 9) % Palette.Length];
            var alpha = (byte)(18 + wave * 38 + band * 120);
            var brush = new SolidColorBrush(Color.FromArgb(alpha, color.R, color.G, color.B));
            brush.Freeze();
            dc.DrawEllipse(brush, null, new Point(left + (column + 0.5) * cell, top + (row + 0.5) * cell), radius, radius);
        }
    }

    private static void DrawCellularHive(DrawingContext dc, Rect bounds, float[] spectrum, double time)
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
