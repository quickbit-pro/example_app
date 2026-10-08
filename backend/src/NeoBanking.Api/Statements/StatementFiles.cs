using System.Globalization;
using System.Text;
using PdfSharp.Drawing;
using PdfSharp.Fonts;
using PdfSharp.Pdf;
namespace NeoBanking.Api.Statements;
public sealed record StatementRow(int Number, StatementTransaction Transaction, IReadOnlyList<string> Files);
public static class StatementFiles
{
    public static string AttachmentName(int position, string merchant, int attachment, string contentType)
    {
        var clean = new string(merchant.Normalize(NormalizationForm.FormD).Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
            .Select(c => char.IsAsciiLetterOrDigit(c) ? c : '_').ToArray());
        while (clean.Contains("__")) clean = clean.Replace("__", "_");
        clean = clean.Trim('_'); if (clean.Length == 0) clean = "Transaction";
        if (clean.Length > 60) clean = clean[..60];
        var ext = contentType switch { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp", "application/pdf" => ".pdf", _ => throw new StatementExportException("An attachment format is not supported.") };
        return $"invoices/{position:D4}_{clean}_{attachment:D2}{ext}";
    }
    public static byte[] Csv(IReadOnlyList<StatementRow> rows)
    {
        static string Cell(string value)
        {
            if (value.TrimStart().StartsWith('=') || value.TrimStart().StartsWith('+') || value.TrimStart().StartsWith('-') || value.TrimStart().StartsWith('@') || value.StartsWith('\t') || value.StartsWith('\r')) value = "'" + value;
            return "\"" + value.Replace("\"", "\"\"") + "\"";
        }
        var text = new StringBuilder("Position,Date (UTC),Merchant,Description,Type,Status,Amount,Currency,Source,Transaction ID,Invoice files\r\n");
        foreach (var row in rows)
        {
            var t = row.Transaction;
            text.Append(row.Number).Append(',').Append(string.Join(',', new[] {t.Date.ToString("yyyy-MM-dd HH:mm:ss'Z'"),t.Merchant,t.Description,t.Type,t.Status}.Select(Cell)))
                .Append(',').Append(t.Amount.ToString(CultureInfo.InvariantCulture)).Append(',')
                .Append(string.Join(',', new[] {t.Currency,t.Source,t.Id,string.Join("; ", row.Files)}.Select(Cell))).Append("\r\n");
        }
        return Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(text.ToString())).ToArray();
    }
    private static readonly object FontLock = new();
    public static byte[] Pdf(int year, int month, string owner, IReadOnlyList<StatementRow> rows, DateTimeOffset generated)
    {
        lock (FontLock) { GlobalFontSettings.FontResolver ??= new StatementFontResolver(); }
        using var doc = new PdfDocument(); doc.Info.Title = $"Monthly transactions {year:D4}-{month:D2}";
        var regular = new XFont("Statement", 9); var small = new XFont("Statement", 8); var title = new XFont("Statement", 20);
        var muted = new XSolidBrush(XColor.FromArgb(90, 96, 112)); var accent = new XSolidBrush(XColor.FromArgb(91, 69, 195));
        XGraphics? graphics = null; double y = 0;
        void Page()
        {
            graphics?.Dispose(); var page = doc.AddPage(); page.Size = PdfSharp.PageSize.A4; graphics = XGraphics.FromPdfPage(page);
            graphics.DrawString("Monthly transactions", title, accent, 36, 47);
            graphics.DrawString($"{year:D4}-{month:D2}  |  {rows.Count} {(rows.Count == 1 ? "transaction" : "transactions")}  |  UTC", regular, muted, 36, 68);
            y = 85;
            foreach (var line in Wrap(owner, 515, regular)) { graphics.DrawString(line, regular, XBrushes.Black, 36, y); y += 12; }
            graphics.DrawString($"Generated {generated:yyyy-MM-dd HH:mm} UTC", small, muted, 36, y); y += 18;
            graphics.DrawLine(XPens.LightGray, 36, y, 559, y); y += 20;
            graphics.DrawString($"Page {doc.PageCount}", small, muted, 36, 811);
        }
        IEnumerable<string> Wrap(string value, double width, XFont font)
        {
            value = new string(value.Where(c => !char.IsControl(c) || c == '\n').ToArray()).Replace('\n', ' ');
            if (value.Length == 0) { yield return ""; yield break; }
            var line = "";
            foreach (var word in value.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                var candidate = line.Length == 0 ? word : line + " " + word;
                if (graphics!.MeasureString(candidate, font).Width <= width) { line = candidate; continue; }
                if (line.Length > 0) { yield return line; line = ""; }
                foreach (var ch in word)
                {
                    if (line.Length > 0 && graphics.MeasureString(line + ch, font).Width > width) { yield return line; line = ""; }
                    line += ch;
                }
            }
            if (line.Length > 0) yield return line;

        }
        Page();
        foreach (var row in rows)
        {
            var t = row.Transaction;
            if (y > 715) Page();
            graphics!.DrawString($"{row.Number:D4}", regular, accent, 36, y);
            graphics.DrawString(t.Date.ToString("dd MMM HH:mm", CultureInfo.InvariantCulture), small, muted, 77, y);
            var amount = t.Amount.ToString("0.00########", CultureInfo.InvariantCulture) + " " + t.Currency;
            var amounts = Wrap(amount, 155, regular).ToArray();
            var merchants = Wrap(t.Merchant.Length == 0 ? "Transaction" : t.Merchant, 235, regular).ToArray();
            for (var line = 0; line < Math.Max(amounts.Length, merchants.Length); line++)
            {
                if (y > 775) Page();
                if (line < amounts.Length) graphics!.DrawString(amounts[line], regular, XBrushes.Black, new XRect(400, y-9, 159, 14), XStringFormats.TopRight);
                if (line < merchants.Length) graphics!.DrawString(merchants[line], regular, XBrushes.Black, 155, y);
                y += 13;
            }
            void Detail(string value)
            {
                foreach (var line in Wrap(value, 480, small)) { if (y > 775) Page(); graphics!.DrawString(line, small, muted, 77, y); y += 12; }
            }
            Detail($"{CultureInfo.InvariantCulture.TextInfo.ToTitleCase(t.Type.ToLowerInvariant().Replace('_', ' '))} | {t.Status} | Ref: {t.Id}");
            foreach (var file in row.Files) Detail(file);
            if (row.Files.Count == 0) Detail("No attached invoices");
            y += 7; graphics!.DrawLine(XPens.LightGray, 36, y, 559, y); y += 20;
        }
        if (rows.Count == 0) graphics!.DrawString("No transactions in this month.", regular, muted, 36, y);
        graphics!.Dispose(); using var stream = new MemoryStream(); doc.Save(stream, false); return stream.ToArray();
    }
    private sealed class StatementFontResolver : IFontResolver
    {
        public FontResolverInfo ResolveTypeface(string familyName, bool isBold, bool isItalic) => new("Geist");
        public byte[] GetFont(string faceName)
        {
            using var stream = typeof(StatementFiles).Assembly.GetManifestResourceStream("NeoBanking.Api.Statements.Fonts.Geist-Regular.ttf")!;
            using var buffer = new MemoryStream(); stream.CopyTo(buffer); return buffer.ToArray();
        }
    }
}
