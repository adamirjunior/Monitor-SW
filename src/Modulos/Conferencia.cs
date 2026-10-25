// Monitor - Conferência: confere se PDF e DXF batem com a peça (sem abrir o SolidWorks)
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace MonitorSW
{
    // resultado da conferência por código, compartilhado (conferencia.tsv na pasta do Monitor).
    // Vale enquanto modelo / desenho / PDF / DXF não mudarem (guarda a data de cada um).
    public static class Conf
    {
        class R { public string Msg = ""; public long M, D, P, X; public string Who = ""; public string When = ""; }
        static Dictionary<string, R> map = new Dictionary<string, R>(StringComparer.OrdinalIgnoreCase);
        static DateTime stamp = DateTime.MinValue, lastCheck = DateTime.MinValue;
        static readonly object sync = new object();
        public static string FilePath { get { return Path.Combine(Util.AppDir, "conferencia.tsv"); } }

        public static void Refresh(bool force)
        {
            if (!force && (DateTime.Now - lastCheck).TotalSeconds < 10) return;
            lastCheck = DateTime.Now;
            try
            {
                var t = File.Exists(FilePath) ? File.GetLastWriteTime(FilePath) : DateTime.MinValue;
                if (!force && t == stamp) return;
                var m = Load();
                lock (sync) { map = m; stamp = t; }
            }
            catch { }
        }

        static Dictionary<string, R> Load()
        {
            var m = new Dictionary<string, R>(StringComparer.OrdinalIgnoreCase);
            if (!File.Exists(FilePath)) return m;
            using (var fs = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new StreamReader(fs, Encoding.UTF8))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    if (line.StartsWith("#") || line.StartsWith("CODIGO\t")) continue;
                    var c = line.Split('\t');
                    if (c.Length < 8 || c[0].Length == 0) continue;
                    long a, b, d, e;
                    long.TryParse(c[1], out a); long.TryParse(c[2], out b); long.TryParse(c[3], out d); long.TryParse(c[4], out e);
                    m[c[0]] = new R { M = a, D = b, P = d, X = e, When = c[5], Who = c[6], Msg = c[7] };
                }
            }
            return m;
        }

        // resultado vale só se nada mudou desde a conferência
        public static string Get(Item it)
        {
            R r;
            lock (sync) if (!map.TryGetValue(it.Name, out r)) return null;
            if (r.M != it.Model.Ticks || r.D != it.Drw.Ticks || r.P != it.Pdf.Ticks || r.X != it.Dxf.Ticks) return null;
            return r.Msg;
        }

        public static string SaveMany(List<KeyValuePair<Item, string>> res)
        {
            for (int tries = 0; tries < 10; tries++)
            {
                try
                {
                    var m = Load();
                    string who = Users.Me, when = DateTime.Now.ToString("dd/MM/yy HH:mm");
                    foreach (var kv in res)
                    {
                        var it = kv.Key;
                        m[it.Name] = new R { M = it.Model.Ticks, D = it.Drw.Ticks, P = it.Pdf.Ticks, X = it.Dxf.Ticks, Who = who, When = when, Msg = (kv.Value ?? "").Replace("\t", " ").Replace("\r", " ").Replace("\n", " ") };
                    }
                    var sb = new StringBuilder();
                    sb.AppendLine("# Conferência do Monitor (PDF/DXF x peça). Vale enquanto as datas dos arquivos não mudarem.");
                    sb.AppendLine("CODIGO\tMODELO\tDESENHO\tPDF\tDXF\tQUANDO\tQUEM\tRESULTADO");
                    foreach (var kv in m.OrderBy(k => k.Key))
                    {
                        var r = kv.Value;
                        sb.Append(kv.Key).Append('\t').Append(r.M).Append('\t').Append(r.D).Append('\t').Append(r.P).Append('\t').Append(r.X).Append('\t')
                          .Append(r.When).Append('\t').Append(r.Who).Append('\t').Append(r.Msg).Append("\r\n");
                    }
                    var tmp = FilePath + "." + Environment.MachineName + ".tmp";
                    File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(true));
                    if (File.Exists(FilePath)) File.Replace(tmp, FilePath, null); else File.Move(tmp, FilePath);
                    lock (sync) { map = m; stamp = File.GetLastWriteTime(FilePath); }
                    return null;
                }
                catch (Exception ex) { if (tries == 9) return ex.Message; Thread.Sleep(250); }
            }
            return "erro";
        }

        // ---------------------------------------------------------------- a conferência de um item
        static string Norm(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var sb = new StringBuilder();
            foreach (char ch in s.ToUpperInvariant().Normalize(NormalizationForm.FormD))
            {
                if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
                if (char.IsLetterOrDigit(ch)) sb.Append(ch);
            }
            return sb.ToString();
        }

        static readonly Regex EspRx = new Regex(@"ESP\.?\s*([0-9]+(?:[\.,][0-9]+)?)", RegexOptions.IgnoreCase);
        static double Esp(string s)
        {
            var m = EspRx.Match(s ?? "");
            double v;
            if (m.Success && double.TryParse(m.Groups[1].Value.Replace(",", "."), NumberStyles.Float, CultureInfo.InvariantCulture, out v)) return v;
            return -1;
        }

        // devolve "" se está tudo certo, ou os problemas encontrados (separados por " + ")
        public static string Check(Item it)
        {
            var probs = new List<string>();
            string code = it.Name.Split(' ')[0];
            string desc = it.Desc ?? "";
            // 3D salvo depois do desenho: o desenho / PDF pode não mostrar a peça atual
            // 3D salvo depois do desenho E o PDF também é anterior ao 3D: o PDF pode não mostrar a peça atual.
            // (se o PDF foi gerado depois da alteração do 3D, já está resolvido mesmo sem salvar o .SLDDRW)
            if (it.Drw != DateTime.MinValue && it.Model > it.Drw.AddMinutes(2) && (it.Pdf == DateTime.MinValue || it.Pdf < it.Model.AddMinutes(-2)))
                probs.Add("3D alterado depois do desenho (" + Util.Fmt(it.Model) + ")");
            // PDF: carimbo
            if (it.Pdf != DateTime.MinValue && !string.IsNullOrEmpty(it.PdfPath) && File.Exists(it.PdfPath))
            {
                string txt = null;
                try { txt = PdfText.Extract(it.PdfPath); } catch { }
                if (!string.IsNullOrEmpty(txt) && txt.Length > 20)
                {
                    var nt = Norm(txt);
                    if (Norm(code).Length > 3 && !nt.Contains(Norm(code))) probs.Add("PDF não mostra o código " + code);
                    if (Norm(desc).Length > 3 && !nt.Contains(Norm(desc))) probs.Add("PDF com descrição diferente da peça");
                }
            }
            // DXF: escala, descrição, espessura, data
            if (it.Dxf != DateTime.MinValue && !string.IsNullOrEmpty(it.DxfPath) && File.Exists(it.DxfPath))
            {
                try
                {
                    var d = DxfInfo.Read(it.DxfPath);
                    if (d.Lfac > 0 && Math.Abs(d.Lfac - 1) > 0.001) probs.Add("DXF fora da escala 1:1 (fator " + d.Lfac.ToString("0.###", CultureInfo.GetCultureInfo("pt-BR")) + ")");
                    if (d.Texts.Count == 0) probs.Add("DXF sem a descrição");
                    else
                    {
                        string all = string.Join(" ", d.Texts.ToArray());
                        double e1 = Esp(all), e2 = Esp(desc);
                        if (e1 > 0 && e2 > 0 && Math.Abs(e1 - e2) > 0.001) probs.Add("DXF com espessura " + e1.ToString(CultureInfo.GetCultureInfo("pt-BR")) + " mm, peça " + e2.ToString(CultureInfo.GetCultureInfo("pt-BR")) + " mm");
                        else if (Norm(desc).Length > 3 && !Norm(all).Contains(Norm(desc))) probs.Add("DXF com descrição diferente da peça");
                    }
                }
                catch { }
            }
            return string.Join(" + ", probs.ToArray());
        }
    }

    // ---------------------------------------------------------------- DXF: fator de medição, textos
    public class DxfInfo
    {
        public double Lfac = 1;
        public List<string> Texts = new List<string>();
        public static DxfInfo Read(string path)
        {
            var r = new DxfInfo();
            var L = File.ReadAllLines(path, Encoding.Default);
            string sec = "", ent = "";
            for (int i = 0; i + 1 < L.Length; i += 2)
            {
                string c = L[i].Trim(), v = L[i + 1];
                if (c == "0" && v.Trim() == "SECTION") { sec = "?"; continue; }
                if (c == "2" && sec == "?") { sec = v.Trim(); continue; }
                if (c == "9" && v.Trim() == "$DIMLFAC" && i + 3 < L.Length) { double f; if (double.TryParse(L[i + 3].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out f)) r.Lfac = f; }
                if (sec != "ENTITIES") continue;
                if (c == "0") { ent = v.Trim(); continue; }
                if ((ent == "MTEXT" || ent == "TEXT") && (c == "1" || c == "3"))
                {
                    var t = Regex.Replace(v, @"\\[A-Za-z][^;\\]*;", "").Replace("\\P", " ").Replace("{", "").Replace("}", "").Trim();
                    if (t.Length > 0) r.Texts.Add(t);
                }
            }
            return r;
        }
    }

    // ---------------------------------------------------------------- texto de PDF (o suficiente para ler o carimbo do SolidWorks)
    public static class PdfText
    {
        static readonly Regex ObjRx = new Regex(@"(\d+)\s+0\s+obj\b", RegexOptions.Compiled);

        public static string Extract(string path)
        {
            var data = File.ReadAllBytes(path);
            if (data.Length > 30 * 1024 * 1024) return null;
            string lat = Encoding.GetEncoding(28591).GetString(data);
            // objetos: dicionário + stream
            var dicts = new Dictionary<int, string>();
            var streams = new Dictionary<int, byte[]>();
            foreach (Match m in ObjRx.Matches(lat))
            {
                int num = int.Parse(m.Groups[1].Value);
                int start = m.Index + m.Length;
                int end = lat.IndexOf("endobj", start, StringComparison.Ordinal);
                if (end < 0) continue;
                int st = lat.IndexOf("stream", start, StringComparison.Ordinal);
                if (st >= 0 && st < end)
                {
                    dicts[num] = lat.Substring(start, st - start);
                    int s0 = st + 6;
                    if (s0 < lat.Length && lat[s0] == '\r') s0++;
                    if (s0 < lat.Length && lat[s0] == '\n') s0++;
                    int es = lat.IndexOf("endstream", s0, StringComparison.Ordinal);
                    if (es > s0)
                    {
                        var raw = new byte[es - s0];
                        Array.Copy(data, s0, raw, 0, raw.Length);
                        streams[num] = dicts[num].Contains("/FlateDecode") ? Inflate(raw) : raw;
                    }
                }
                else dicts[num] = lat.Substring(start, end - start);
            }
            // fontes: nome do recurso -> tabela ToUnicode
            var fontObj = new Dictionary<string, int>();
            foreach (var kv in dicts)
            {
                foreach (Match fm in Regex.Matches(kv.Value, @"/Font\s*<<(.*?)>>", RegexOptions.Singleline))
                    foreach (Match r in Regex.Matches(fm.Groups[1].Value, @"/([^\s/<>\[\]]+)\s+(\d+)\s+0\s+R"))
                        fontObj[r.Groups[1].Value] = int.Parse(r.Groups[2].Value);
            }
            var cmaps = new Dictionary<string, Dictionary<int, string>>();
            var twoByte = new Dictionary<string, bool>();
            foreach (var kv in fontObj)
            {
                string fd;
                if (!dicts.TryGetValue(kv.Value, out fd)) continue;
                twoByte[kv.Key] = fd.Contains("/Type0") || fd.Contains("Identity");
                var tu = Regex.Match(fd, @"/ToUnicode\s+(\d+)\s+0\s+R");
                byte[] cm;
                if (tu.Success && streams.TryGetValue(int.Parse(tu.Groups[1].Value), out cm) && cm != null)
                    cmaps[kv.Key] = ParseCMap(Encoding.GetEncoding(28591).GetString(cm));
            }
            // conteúdo das páginas
            var sb = new StringBuilder();
            foreach (var kv in streams)
            {
                if (kv.Value == null) continue;
                string s = Encoding.GetEncoding(28591).GetString(kv.Value);
                if (s.IndexOf("Tj", StringComparison.Ordinal) < 0 && s.IndexOf("TJ", StringComparison.Ordinal) < 0) continue;
                ReadContent(s, cmaps, twoByte, sb);
            }
            return sb.ToString();
        }

        static byte[] Inflate(byte[] raw)
        {
            try
            {
                if (raw.Length < 3) return null;
                using (var ms = new MemoryStream(raw, 2, raw.Length - 2))
                using (var ds = new DeflateStream(ms, CompressionMode.Decompress))
                using (var o = new MemoryStream())
                {
                    var buf = new byte[65536]; int n;
                    try { while ((n = ds.Read(buf, 0, buf.Length)) > 0) o.Write(buf, 0, n); } catch { }
                    return o.ToArray();
                }
            }
            catch { return null; }
        }

        static Dictionary<int, string> ParseCMap(string s)
        {
            var m = new Dictionary<int, string>();
            foreach (Match b in Regex.Matches(s, @"beginbfchar(.*?)endbfchar", RegexOptions.Singleline))
                foreach (Match p in Regex.Matches(b.Groups[1].Value, @"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>"))
                    m[Convert.ToInt32(p.Groups[1].Value, 16)] = Hex16(p.Groups[2].Value);
            foreach (Match b in Regex.Matches(s, @"beginbfrange(.*?)endbfrange", RegexOptions.Singleline))
            {
                foreach (Match p in Regex.Matches(b.Groups[1].Value, @"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])"))
                {
                    int a = Convert.ToInt32(p.Groups[1].Value, 16), z = Convert.ToInt32(p.Groups[2].Value, 16);
                    if (z - a > 5000) continue;
                    if (p.Groups[4].Success)
                    {
                        int dst = Convert.ToInt32(p.Groups[4].Value, 16);
                        for (int k = a; k <= z; k++) m[k] = char.ConvertFromUtf32(Math.Min(0x10FFFF, dst + (k - a)));
                    }
                    else
                    {
                        var arr = Regex.Matches(p.Groups[5].Value, @"<([0-9A-Fa-f]+)>");
                        for (int k = a; k <= z && k - a < arr.Count; k++) m[k] = Hex16(arr[k - a].Groups[1].Value);
                    }
                }
            }
            return m;
        }

        static string Hex16(string h)
        {
            var sb = new StringBuilder();
            for (int i = 0; i + 3 < h.Length + 0 && i + 4 <= h.Length; i += 4) sb.Append((char)Convert.ToInt32(h.Substring(i, 4), 16));
            if (sb.Length == 0 && h.Length >= 2) sb.Append((char)Convert.ToInt32(h, 16));
            return sb.ToString();
        }

        static void ReadContent(string s, Dictionary<string, Dictionary<int, string>> cmaps, Dictionary<string, bool> twoByte, StringBuilder sb)
        {
            string font = "";
            int i = 0, n = s.Length;
            var pending = new StringBuilder();
            while (i < n)
            {
                char c = s[i];
                if (c == '/')
                {
                    int j = i + 1; while (j < n && !char.IsWhiteSpace(s[j]) && "/[]<>()".IndexOf(s[j]) < 0) j++;
                    string name = s.Substring(i + 1, j - i - 1);
                    // "/Fonte tamanho Tf"
                    int k = j; while (k < n && (char.IsWhiteSpace(s[k]) || char.IsDigit(s[k]) || s[k] == '.' || s[k] == '-')) k++;
                    if (k + 1 < n && s[k] == 'T' && s[k + 1] == 'f') font = name;
                    i = j; continue;
                }
                if (c == '<' && i + 1 < n && s[i + 1] != '<')
                {
                    int j = s.IndexOf('>', i + 1); if (j < 0) break;
                    pending.Append(DecodeHex(s.Substring(i + 1, j - i - 1), font, cmaps, twoByte));
                    i = j + 1; continue;
                }
                if (c == '(')
                {
                    int depth = 1, j = i + 1; var lit = new StringBuilder();
                    while (j < n && depth > 0)
                    {
                        char ch = s[j];
                        if (ch == '\\' && j + 1 < n) { lit.Append(s[j + 1]); j += 2; continue; }
                        if (ch == '(') depth++; else if (ch == ')') { depth--; if (depth == 0) break; }
                        lit.Append(ch); j++;
                    }
                    pending.Append(DecodeLit(lit.ToString(), font, cmaps, twoByte));
                    i = j + 1; continue;
                }
                if (c == 'T' && i + 1 < n && (s[i + 1] == 'j' || s[i + 1] == 'J'))
                {
                    if (pending.Length > 0) { sb.Append(pending).Append(' '); pending.Clear(); }
                    i += 2; continue;
                }
                if (c == 'E' && i + 1 < n && s[i + 1] == 'T') { sb.Append('\n'); i += 2; continue; }
                i++;
            }
        }

        static string Map(int code, string font, Dictionary<string, Dictionary<int, string>> cmaps)
        {
            Dictionary<int, string> cm; string u;
            if (cmaps.TryGetValue(font, out cm) && cm.TryGetValue(code, out u)) return u;
            // fonte sem tabela: nas fontes do SolidWorks o número do glifo é o caractere - 29 (ordem padrão TrueType)
            if (code >= 3 && code <= 226) return ((char)(code + 29)).ToString();
            return code >= 32 && code < 0xFFFF ? ((char)code).ToString() : "";
        }

        static string DecodeHex(string h, string font, Dictionary<string, Dictionary<int, string>> cmaps, Dictionary<string, bool> twoByte)
        {
            h = Regex.Replace(h, @"\s", "");
            bool two; twoByte.TryGetValue(font, out two);
            int w = two ? 4 : 2;
            var sb = new StringBuilder();
            for (int i = 0; i + w <= h.Length; i += w) sb.Append(Map(Convert.ToInt32(h.Substring(i, w), 16), font, cmaps));
            return sb.ToString();
        }

        static string DecodeLit(string s, string font, Dictionary<string, Dictionary<int, string>> cmaps, Dictionary<string, bool> twoByte)
        {
            bool two; twoByte.TryGetValue(font, out two);
            var sb = new StringBuilder();
            if (two) { for (int i = 0; i + 1 < s.Length; i += 2) sb.Append(Map((s[i] << 8) | s[i + 1], font, cmaps)); }
            else foreach (char ch in s) sb.Append(Map(ch, font, cmaps));
            return sb.ToString();
        }
    }
}
