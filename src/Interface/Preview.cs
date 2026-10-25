// Monitor - miniaturas: desenho DXF (desenhado pelo próprio Monitor) e miniatura do Windows (PDF)
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace MonitorSW
{
    public static class DxfRender
    {
        class Mat
        {
            public double a = 1, b = 0, c = 0, d = 0, e = 1, f = 0;
            public PointF P(double x, double y) { return new PointF((float)(a * x + b * y + c), (float)(d * x + e * y + f)); }
            public Mat Mul(Mat m) // this * m
            {
                return new Mat { a = a * m.a + b * m.d, b = a * m.b + b * m.e, c = a * m.c + b * m.f + c, d = d * m.a + e * m.d, e = d * m.b + e * m.e, f = d * m.c + e * m.f + f };
            }
            public double Scale { get { return Math.Sqrt(Math.Abs(a * e - b * d)); } }
            public double Rot { get { return Math.Atan2(d, a); } }
        }
        class Ent { public string Type; public List<KeyValuePair<int, string>> G = new List<KeyValuePair<int, string>>(); public List<Ent> Verts; }
        class Shape { public PointF[] Pts; public bool Closed, Fill; }
        class Txt { public PointF P; public float H, Rot; public string S; }

        static double D(string s) { double v; return double.TryParse(s.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : 0; }
        static string V(Ent e, int code) { foreach (var g in e.G) if (g.Key == code) return g.Value; return null; }
        static double N(Ent e, int code, double def = 0) { var s = V(e, code); return s == null ? def : D(s); }

        public static Image Render(string path, int w, int h)
        {
            string[] lines;
            try { lines = File.ReadAllLines(path, Encoding.Default); } catch { return null; }
            var blocks = new Dictionary<string, List<Ent>>(StringComparer.OrdinalIgnoreCase);
            var blockBase = new Dictionary<string, PointF>(StringComparer.OrdinalIgnoreCase);
            var ents = new List<Ent>();
            string section = null; List<Ent> cur = null; string curBlock = null; Ent e = null; Ent poly = null;
            for (int i = 0; i + 1 < lines.Length; i += 2)
            {
                int code; if (!int.TryParse(lines[i].Trim(), out code)) { i--; continue; }
                string val = lines[i + 1];
                if (code == 0)
                {
                    string t = val.Trim();
                    // fecha a entidade anterior
                    if (e != null)
                    {
                        if (e.Type == "BLOCK") { curBlock = V(e, 2) ?? ""; blocks[curBlock] = new List<Ent>(); blockBase[curBlock] = new PointF((float)N(e, 10), (float)N(e, 20)); cur = blocks[curBlock]; }
                        else if (e.Type == "VERTEX" && poly != null) poly.Verts.Add(e);
                        else if (e.Type == "SEQEND") poly = null;
                        else if (cur != null && e.Type != "ENDBLK" && e.Type != "SECTION" && e.Type != "ENDSEC") { cur.Add(e); if (e.Type == "POLYLINE") { e.Verts = new List<Ent>(); poly = e; } }
                        e = null;
                    }
                    if (t == "SECTION") { section = null; e = new Ent { Type = t }; continue; }
                    if (t == "ENDSEC") { section = null; cur = null; continue; }
                    if (t == "ENDBLK") { cur = section == "BLOCKS" ? null : cur; curBlock = null; continue; }
                    if (t == "EOF") break;
                    if (section == "ENTITIES") cur = ents;
                    e = new Ent { Type = t };
                    continue;
                }
                if (e != null && e.Type == "SECTION" && code == 2) { section = val.Trim(); if (section == "ENTITIES") cur = ents; continue; }
                if (e != null) e.G.Add(new KeyValuePair<int, string>(code, val));
            }
            if (e != null && cur != null) cur.Add(e);

            var shapes = new List<Shape>(); var texts = new List<Txt>();
            Emit(ents, new Mat(), blocks, blockBase, shapes, texts, 0);
            if (shapes.Count == 0) return null;

            double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
            foreach (var s in shapes) foreach (var p in s.Pts) { minX = Math.Min(minX, p.X); maxX = Math.Max(maxX, p.X); minY = Math.Min(minY, p.Y); maxY = Math.Max(maxY, p.Y); }
            double bw = Math.Max(maxX - minX, 1e-6), bh = Math.Max(maxY - minY, 1e-6);
            double sc = Math.Min((w - 30) / bw, (h - 30) / bh);
            float ox = (float)((w - bw * sc) / 2), oy = (float)((h - bh * sc) / 2);
            Func<PointF, PointF> T = p => new PointF(ox + (float)((p.X - minX) * sc), h - oy - (float)((p.Y - minY) * sc));

            var bmp = new Bitmap(w, h);
            using (var g = Graphics.FromImage(bmp))
            using (var pen = new Pen(Color.FromArgb(30, 30, 30), 1.2f))
            using (var br = new SolidBrush(Color.FromArgb(30, 30, 30)))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.White);
                foreach (var s in shapes)
                {
                    var pts = s.Pts.Select(T).ToArray();
                    if (pts.Length < 2) continue;
                    if (s.Fill && pts.Length >= 3) g.FillPolygon(br, pts);
                    else if (s.Closed && pts.Length >= 3) g.DrawPolygon(pen, pts);
                    else g.DrawLines(pen, pts);
                }
                foreach (var t in texts)
                {
                    float px = (float)(t.H * sc);
                    if (px < 5 || string.IsNullOrEmpty(t.S)) continue;
                    using (var f = new Font("Arial", Math.Min(px, 40f), GraphicsUnit.Pixel))
                    {
                        var p = T(t.P);
                        var st = g.Save();
                        g.TranslateTransform(p.X, p.Y);
                        g.RotateTransform(-t.Rot);
                        g.DrawString(t.S, f, br, 0, -px);
                        g.Restore(st);
                    }
                }
            }
            return bmp;
        }

        static void Emit(List<Ent> list, Mat m, Dictionary<string, List<Ent>> blocks, Dictionary<string, PointF> bases, List<Shape> shapes, List<Txt> texts, int depth)
        {
            if (depth > 8) return;
            foreach (var e in list)
            {
                if (shapes.Count > 60000) return;
                switch (e.Type)
                {
                    case "LINE": shapes.Add(new Shape { Pts = new[] { m.P(N(e, 10), N(e, 20)), m.P(N(e, 11), N(e, 21)) } }); break;
                    case "CIRCLE": shapes.Add(new Shape { Pts = Arc(m, N(e, 10), N(e, 20), N(e, 40), 0, 360), Closed = true }); break;
                    case "ARC": { double a0 = N(e, 50), a1 = N(e, 51); if (a1 < a0) a1 += 360; shapes.Add(new Shape { Pts = Arc(m, N(e, 10), N(e, 20), N(e, 40), a0, a1) }); break; }
                    case "ELLIPSE":
                        {
                            double cx = N(e, 10), cy = N(e, 20), mx = N(e, 11), my = N(e, 21), r = N(e, 40, 1), p0 = N(e, 41), p1 = N(e, 42, Math.PI * 2);
                            if (p1 < p0) p1 += Math.PI * 2;
                            double L = Math.Sqrt(mx * mx + my * my), ang = Math.Atan2(my, mx); int n = 64; var pts = new PointF[n + 1];
                            for (int k = 0; k <= n; k++) { double t = p0 + (p1 - p0) * k / n; double x = L * Math.Cos(t), y = L * r * Math.Sin(t); pts[k] = m.P(cx + x * Math.Cos(ang) - y * Math.Sin(ang), cy + x * Math.Sin(ang) + y * Math.Cos(ang)); }
                            shapes.Add(new Shape { Pts = pts }); break;
                        }
                    case "LWPOLYLINE":
                        {
                            var vs = new List<double[]>(); double[] curv = null;
                            foreach (var g in e.G)
                            {
                                if (g.Key == 10) { curv = new double[] { D(g.Value), 0, 0 }; vs.Add(curv); }
                                else if (g.Key == 20 && curv != null) curv[1] = D(g.Value);
                                else if (g.Key == 42 && curv != null) curv[2] = D(g.Value);
                            }
                            bool closed = ((int)N(e, 70) & 1) == 1;
                            shapes.Add(new Shape { Pts = Bulged(m, vs, closed), Closed = false }); break;
                        }
                    case "POLYLINE":
                        {
                            if (e.Verts == null) break;
                            var vs = e.Verts.Select(v => new double[] { N(v, 10), N(v, 20), N(v, 42) }).ToList();
                            bool closed = ((int)N(e, 70) & 1) == 1;
                            shapes.Add(new Shape { Pts = Bulged(m, vs, closed) }); break;
                        }
                    case "SPLINE":
                        {
                            var xs = e.G.Where(g => g.Key == 11).Select(g => D(g.Value)).ToList(); var ys = e.G.Where(g => g.Key == 21).Select(g => D(g.Value)).ToList();
                            if (xs.Count < 2) { xs = e.G.Where(g => g.Key == 10).Select(g => D(g.Value)).ToList(); ys = e.G.Where(g => g.Key == 20).Select(g => D(g.Value)).ToList(); }
                            int n = Math.Min(xs.Count, ys.Count); if (n >= 2) shapes.Add(new Shape { Pts = Enumerable.Range(0, n).Select(k => m.P(xs[k], ys[k])).ToArray() });
                            break;
                        }
                    case "SOLID":
                    case "TRACE":
                        shapes.Add(new Shape { Pts = new[] { m.P(N(e, 10), N(e, 20)), m.P(N(e, 11), N(e, 21)), m.P(N(e, 13), N(e, 23)), m.P(N(e, 12), N(e, 22)) }, Fill = true }); break;
                    case "TEXT":
                    case "MTEXT":
                        {
                            string s = string.Concat(e.G.Where(g => g.Key == 3).Select(g => g.Value)) + (V(e, 1) ?? "");
                            s = CleanMText(s);
                            double rot = N(e, 50); if (e.Type == "MTEXT" && V(e, 11) != null) rot = Math.Atan2(N(e, 21), N(e, 11)) * 180 / Math.PI;
                            texts.Add(new Txt { P = m.P(N(e, 10), N(e, 20)), H = (float)(N(e, 40, 2.5) * m.Scale), Rot = (float)(rot + m.Rot * 180 / Math.PI), S = s });
                            break;
                        }
                    case "INSERT":
                    case "DIMENSION":
                        {
                            string name = V(e, 2); List<Ent> bl;
                            if (name == null || !blocks.TryGetValue(name, out bl)) break;
                            PointF bp; bases.TryGetValue(name, out bp);
                            double ix = e.Type == "INSERT" ? N(e, 10) : 0, iy = e.Type == "INSERT" ? N(e, 20) : 0;
                            double sx = e.Type == "INSERT" ? N(e, 41, 1) : 1, sy = e.Type == "INSERT" ? N(e, 42, 1) : 1, r = e.Type == "INSERT" ? N(e, 50) * Math.PI / 180 : 0;
                            var t = new Mat { a = Math.Cos(r) * sx, b = -Math.Sin(r) * sy, c = ix, d = Math.Sin(r) * sx, e = Math.Cos(r) * sy, f = iy };
                            var tb = new Mat { c = -bp.X, f = -bp.Y };
                            Emit(bl, m.Mul(t).Mul(tb), blocks, bases, shapes, texts, depth + 1);
                            break;
                        }
                }
            }
        }

        static string CleanMText(string s)
        {
            s = s.Replace("\\P", " ").Replace("%%c", "Ø").Replace("%%C", "Ø").Replace("%%d", "°").Replace("%%p", "±");
            s = System.Text.RegularExpressions.Regex.Replace(s, @"\\[A-Za-z][^;\\]*;", "");
            s = s.Replace("{", "").Replace("}", "");
            return s.Trim();
        }

        static PointF[] Arc(Mat m, double cx, double cy, double r, double a0, double a1)
        {
            int n = Math.Max(8, (int)((a1 - a0) / 6));
            var pts = new PointF[n + 1];
            for (int k = 0; k <= n; k++) { double t = (a0 + (a1 - a0) * k / n) * Math.PI / 180; pts[k] = m.P(cx + r * Math.Cos(t), cy + r * Math.Sin(t)); }
            return pts;
        }

        static PointF[] Bulged(Mat m, List<double[]> vs, bool closed)
        {
            var res = new List<PointF>();
            int n = vs.Count; if (n == 0) return new PointF[0];
            int segs = closed ? n : n - 1;
            res.Add(m.P(vs[0][0], vs[0][1]));
            for (int i = 0; i < segs; i++)
            {
                var p = vs[i]; var q = vs[(i + 1) % n]; double bulge = p[2];
                if (Math.Abs(bulge) < 1e-9) { res.Add(m.P(q[0], q[1])); continue; }
                double th = 4 * Math.Atan(bulge), dx = q[0] - p[0], dy = q[1] - p[1], chord = Math.Sqrt(dx * dx + dy * dy);
                if (chord < 1e-12) continue;
                double r = chord / (2 * Math.Sin(th / 2));
                double mx = (p[0] + q[0]) / 2, my = (p[1] + q[1]) / 2, h = r * Math.Cos(th / 2);
                double nx = -dy / chord, ny = dx / chord;
                double cx = mx + nx * h, cy = my + ny * h;
                double a0 = Math.Atan2(p[1] - cy, p[0] - cx); int k = 16;
                for (int j = 1; j <= k; j++) { double a = a0 + th * j / k; res.Add(m.P(cx + Math.Abs(r) * Math.Cos(a), cy + Math.Abs(r) * Math.Sin(a))); }
            }
            return res.ToArray();
        }
    }

    // miniatura que o próprio Windows gera (PDF etc.), se houver um leitor instalado que forneça miniaturas
    public static class ShellThumb
    {
        [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm); }
        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [In] ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

        public static Image Get(string path, int size)
        {
            Image result = null;
            var t = new Thread(() =>
            {
                try
                {
                    var iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
                    IShellItemImageFactory f;
                    SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out f);
                    IntPtr hb;
                    if (f.GetImage(new SIZE { cx = size, cy = size }, 0x08 /*só miniatura*/, out hb) == 0 && hb != IntPtr.Zero)
                    {
                        using (var im = Image.FromHbitmap(hb)) result = new Bitmap(im);
                        DeleteObject(hb);
                    }
                    Marshal.ReleaseComObject(f);
                }
                catch { }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            t.Join(20000);
            return result;
        }
    }
}
