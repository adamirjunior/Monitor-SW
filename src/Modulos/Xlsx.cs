// Monitor - gravador de planilha .xlsx simples (sem Excel instalado), usado na LISTA DE PEÇAS
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security;
using System.Text;

namespace MonitorSW
{
    public class XlsxSheet
    {
        // estilos: 0 normal esquerda, 1 normal centro, 2 negrito esquerda, 3 negrito centro
        public const int Left = 0, Center = 1, BoldLeft = 2, BoldCenter = 3;
        class Cell { public object V; public int S; }
        readonly SortedDictionary<int, SortedDictionary<int, Cell>> rows = new SortedDictionary<int, SortedDictionary<int, Cell>>();
        public readonly List<string> Merges = new List<string>();
        public readonly Dictionary<int, double> ColWidths = new Dictionary<int, double>();
        public readonly Dictionary<int, double> RowHeights = new Dictionary<int, double>();
        public string Name = "Planilha1";

        public void Set(int r, int c, object v, int style)
        {
            SortedDictionary<int, Cell> row;
            if (!rows.TryGetValue(r, out row)) rows[r] = row = new SortedDictionary<int, Cell>();
            row[c] = new Cell { V = v, S = style };
        }
        public void Merge(int r1, int c1, int r2, int c2)
        {
            if (r1 == r2 && c1 == c2) return;
            Merges.Add(Ref(r1, c1) + ":" + Ref(r2, c2));
        }
        public static string Col(int c) { string s = ""; while (c > 0) { int m = (c - 1) % 26; s = (char)('A' + m) + s; c = (c - 1) / 26; } return s; }
        public static string Ref(int r, int c) { return Col(c) + r; }

        public void Save(string path)
        {
            if (File.Exists(path)) File.Delete(path);
            using (var fs = new FileStream(path, FileMode.CreateNew))
            using (var z = new ZipArchive(fs, ZipArchiveMode.Create))
            {
                Put(z, "[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>");
                Put(z, "_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>");
                Put(z, "xl/workbook.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"" + X(Name) + "\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
                Put(z, "xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>");
                Put(z, "xl/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
                    "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Arial\"/></font><font><b/><sz val=\"11\"/><name val=\"Arial\"/></font></fonts>" +
                    "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>" +
                    "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>" +
                    "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>" +
                    "<cellXfs count=\"4\">" +
                    "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyAlignment=\"1\"><alignment horizontal=\"left\" vertical=\"center\" wrapText=\"1\"/></xf>" +
                    "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf>" +
                    "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyAlignment=\"1\"><alignment horizontal=\"left\" vertical=\"center\" wrapText=\"1\"/></xf>" +
                    "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf>" +
                    "</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>");
                var sb = new StringBuilder();
                sb.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">");
                if (ColWidths.Count > 0)
                {
                    sb.Append("<cols>");
                    foreach (var kv in ColWidths.OrderBy(k => k.Key))
                        sb.Append("<col min=\"" + kv.Key + "\" max=\"" + kv.Key + "\" width=\"" + kv.Value.ToString(CultureInfo.InvariantCulture) + "\" customWidth=\"1\"/>");
                    sb.Append("</cols>");
                }
                sb.Append("<sheetData>");
                foreach (var r in rows)
                {
                    double h;
                    sb.Append("<row r=\"" + r.Key + "\"" + (RowHeights.TryGetValue(r.Key, out h) ? " ht=\"" + h.ToString(CultureInfo.InvariantCulture) + "\" customHeight=\"1\"" : "") + ">");
                    foreach (var c in r.Value)
                    {
                        string rf = Ref(r.Key, c.Key);
                        var v = c.Value.V;
                        if (v == null || (v is string && ((string)v).Length == 0)) sb.Append("<c r=\"" + rf + "\" s=\"" + c.Value.S + "\"/>");
                        else if (v is double || v is int || v is long)
                            sb.Append("<c r=\"" + rf + "\" s=\"" + c.Value.S + "\"><v>" + Convert.ToDouble(v).ToString(CultureInfo.InvariantCulture) + "</v></c>");
                        else sb.Append("<c r=\"" + rf + "\" s=\"" + c.Value.S + "\" t=\"inlineStr\"><is><t xml:space=\"preserve\">" + X(v.ToString()) + "</t></is></c>");
                    }
                    sb.Append("</row>");
                }
                sb.Append("</sheetData>");
                if (Merges.Count > 0)
                {
                    sb.Append("<mergeCells count=\"" + Merges.Count + "\">");
                    foreach (var m in Merges) sb.Append("<mergeCell ref=\"" + m + "\"/>");
                    sb.Append("</mergeCells>");
                }
                sb.Append("<pageMargins left=\"0.4\" right=\"0.4\" top=\"0.5\" bottom=\"0.5\" header=\"0.3\" footer=\"0.3\"/></worksheet>");
                Put(z, "xl/worksheets/sheet1.xml", sb.ToString());
            }
        }

        static string X(string s)
        {
            var sb = new StringBuilder();
            foreach (char ch in s ?? "")
            {
                if (ch < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') continue;
                sb.Append(ch);
            }
            return SecurityElement.Escape(sb.ToString());
        }

        static void Put(ZipArchive z, string name, string content)
        {
            var e = z.CreateEntry(name, CompressionLevel.Optimal);
            using (var s = e.Open()) { var b = new UTF8Encoding(false).GetBytes(content); s.Write(b, 0, b.Length); }
        }
    }
}
