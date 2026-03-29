using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace SudoWindows.Services;

/// <summary>
/// Fallback detection: captures window screenshot and uses Windows.Media.Ocr
/// to find buttons matching search terms. Runs entirely on-device.
/// Equivalent to OCRButtonFinder on macOS (which uses Apple Vision).
/// </summary>
public class OCRButtonFinder
{
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
        IntPtr hdcSource, int xSrc, int ySrc, uint rop);

    private const uint SRCCOPY = 0x00CC0020;
    private const uint PW_RENDERFULLCONTENT = 0x00000002;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
        public int Width => Right - Left;
        public int Height => Bottom - Top;
    }

    public class FindResult
    {
        public Point? ClickPoint { get; init; }
        public string? MatchedText { get; init; }
        public bool Succeeded { get; init; }
        public string? FailureReason { get; init; }

        public static FindResult Found(Point clickPoint, string matchedText) =>
            new() { ClickPoint = clickPoint, MatchedText = matchedText, Succeeded = true };

        public static FindResult NotFound(string reason) =>
            new() { Succeeded = false, FailureReason = reason };
    }

    public FindResult FindButton(string[] searchTerms, IntPtr windowHandle)
    {
        // Capture the window
        Bitmap? screenshot;
        RECT windowRect;
        try
        {
            screenshot = CaptureWindow(windowHandle, out windowRect);
            if (screenshot == null)
                return FindResult.NotFound("Could not capture window screenshot");
        }
        catch (Exception ex)
        {
            return FindResult.NotFound($"Screenshot capture failed: {ex.Message}");
        }

        try
        {
            var lowerTerms = searchTerms.Select(t => t.ToLower()).ToArray();

            // Use Windows OCR
            var ocrResults = PerformOCR(screenshot);
            if (ocrResults == null || ocrResults.Count == 0)
            {
                screenshot.Dispose();
                return FindResult.NotFound("OCR returned no results");
            }

            foreach (var result in ocrResults)
            {
                string lower = result.Text.ToLower().Trim();
                foreach (var term in lowerTerms)
                {
                    if (lower == term || lower.Contains(term))
                    {
                        // Convert OCR coordinates (relative to screenshot) to screen coordinates
                        int screenX = windowRect.Left + (int)(result.BoundingRect.X + result.BoundingRect.Width / 2);
                        int screenY = windowRect.Top + (int)(result.BoundingRect.Y + result.BoundingRect.Height / 2);
                        var point = new Point(screenX, screenY);

                        Console.WriteLine($"[sudo] OCR found '{result.Text}' at ({screenX}, {screenY})");
                        screenshot.Dispose();
                        return FindResult.Found(point, result.Text);
                    }
                }
            }

            screenshot.Dispose();
            return FindResult.NotFound("OCR found no matching text");
        }
        catch (Exception ex)
        {
            screenshot.Dispose();
            return FindResult.NotFound($"OCR processing failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Executes a click at the given screen coordinates.
    /// </summary>
    public void ClickAt(Point point)
    {
        SetCursorPos(point.X, point.Y);
        Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
    }

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);

    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;

    private Bitmap? CaptureWindow(IntPtr hWnd, out RECT windowRect)
    {
        windowRect = default;
        if (!GetWindowRect(hWnd, out windowRect))
            return null;

        int width = windowRect.Width;
        int height = windowRect.Height;
        if (width <= 0 || height <= 0)
            return null;

        // Try PrintWindow first (works with DWM compositing)
        var bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            IntPtr hdc = g.GetHdc();
            bool success = PrintWindow(hWnd, hdc, PW_RENDERFULLCONTENT);
            g.ReleaseHdc(hdc);

            if (success)
                return bmp;
        }

        // Fallback: BitBlt from screen DC
        bmp.Dispose();
        IntPtr hdcScreen = GetDC(IntPtr.Zero);
        IntPtr hdcMem = CreateCompatibleDC(hdcScreen);
        IntPtr hBitmap = CreateCompatibleBitmap(hdcScreen, width, height);
        IntPtr hOldBitmap = SelectObject(hdcMem, hBitmap);

        BitBlt(hdcMem, 0, 0, width, height, hdcScreen, windowRect.Left, windowRect.Top, SRCCOPY);

        SelectObject(hdcMem, hOldBitmap);
        var result = Image.FromHbitmap(hBitmap);

        DeleteObject(hBitmap);
        DeleteDC(hdcMem);
        ReleaseDC(IntPtr.Zero, hdcScreen);

        return result;
    }

    /// <summary>
    /// Performs OCR using Windows.Media.Ocr via the Windows Runtime API.
    /// Falls back to a simple text extraction if WinRT is not available.
    /// </summary>
    private List<OcrTextResult>? PerformOCR(Bitmap bitmap)
    {
        try
        {
            return PerformWindowsOCR(bitmap);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Windows OCR failed: {ex.Message}");
            return null;
        }
    }

    private List<OcrTextResult>? PerformWindowsOCR(Bitmap bitmap)
    {
        // Convert Bitmap to SoftwareBitmap via memory stream
        using var stream = new MemoryStream();
        bitmap.Save(stream, ImageFormat.Bmp);
        stream.Position = 0;

        // Use Windows.Media.Ocr through WinRT interop
        var decoder = Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(
            stream.AsRandomAccessStream()).AsTask().Result;

        var softwareBitmap = decoder.GetSoftwareBitmapAsync().AsTask().Result;

        var ocrEngine = Windows.Media.Ocr.OcrEngine.TryCreateFromUserProfileLanguages();
        if (ocrEngine == null)
        {
            Console.WriteLine("[sudo] OCR engine not available for current language");
            return null;
        }

        var ocrResult = ocrEngine.RecognizeAsync(softwareBitmap).AsTask().Result;

        var results = new List<OcrTextResult>();
        foreach (var line in ocrResult.Lines)
        {
            foreach (var word in line.Words)
            {
                results.Add(new OcrTextResult
                {
                    Text = word.Text,
                    BoundingRect = new RectangleF(
                        (float)word.BoundingRect.X,
                        (float)word.BoundingRect.Y,
                        (float)word.BoundingRect.Width,
                        (float)word.BoundingRect.Height)
                });
            }

            // Also add the full line text with the bounding rect of the first word
            // (useful for multi-word button labels like "Allow Once")
            if (line.Words.Count > 1)
            {
                var firstWord = line.Words[0];
                var lastWord = line.Words[line.Words.Count - 1];
                float x = (float)firstWord.BoundingRect.X;
                float y = (float)firstWord.BoundingRect.Y;
                float right = (float)(lastWord.BoundingRect.X + lastWord.BoundingRect.Width);
                float bottom = Math.Max(
                    (float)(firstWord.BoundingRect.Y + firstWord.BoundingRect.Height),
                    (float)(lastWord.BoundingRect.Y + lastWord.BoundingRect.Height));

                results.Add(new OcrTextResult
                {
                    Text = string.Join(" ", line.Words.Select(w => w.Text)),
                    BoundingRect = new RectangleF(x, y, right - x, bottom - y)
                });
            }
        }

        return results;
    }

    private class OcrTextResult
    {
        public string Text { get; init; } = "";
        public RectangleF BoundingRect { get; init; }
    }
}
