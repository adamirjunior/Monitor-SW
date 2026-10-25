// Monitor - histórico das listas das montagens e e-mail de alteração de cadastro (SAIU / ENTROU)
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace MonitorSW
{
    // historico_bom.tsv (pasta do Monitor): uma linha cada vez que a lista de uma montagem muda
    // CODIGO \t SALVA_EM (data do arquivo) \t REGISTRADO_EM \t filho=qtd|filho=qtd...
    public static class BomHist
    {
        static readonly object sync = new object();
        static Dictionary<string, string> last;
        public static string FilePath { get { return Path.Combine(Util.AppDir, "historico_bom.tsv"); } }

        public class Snap { public DateTime When; public Dictionary<string, int> Kids = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase); }

        static string Content(List<TreeRef> kids)
        {
            var m = new SortedDictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var k in kids) { string n = Util.NameOf(k.Child); int q; m.TryGetValue(n, out q); m[n] = q + k.Qty; }
            return string.Join("|", m.Select(kv => kv.Key.Replace("|", "/").Replace("=", "-") + "=" + kv.Value).ToArray());
        }

        static void LoadLast()
        {
            if (last != null) return;
            last = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                if (!File.Exists(FilePath)) return;
                using (var fs = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var r = new StreamReader(fs, Encoding.UTF8))
                {
                    string line;
                    while ((line = r.ReadLine()) != null)
                    {
                        var c = line.Split('\t');
                        if (c.Length >= 4 && !line.StartsWith("#") && c[0] != "CODIGO") last[c[0]] = c[3];
                    }
                }
            }
            catch { }
        }

        public static void Record(string asmPath, DateTime saved, List<TreeRef> kids)
        {
            if (kids == null || saved == DateTime.MinValue) return;
            string code = Util.NameOf(asmPath);
            string content = Content(kids);
            lock (sync)
            {
                LoadLast();
                string prev;
                if (last.TryGetValue(code, out prev) && prev == content) return;
                string line = code + "\t" + saved.ToString("yyyy-MM-dd HH:mm:ss") + "\t" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "\t" + content + "\r\n";
                for (int t = 0; t < 6; t++)
                {
                    try
                    {
                        bool novo = !File.Exists(FilePath);
                        using (var fs = new FileStream(FilePath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                        using (var w = new StreamWriter(fs, new UTF8Encoding(novo)))
                        {
                            if (novo) w.Write("# Histórico das listas das montagens (Monitor). Uma linha quando a lista muda.\r\nCODIGO\tSALVA_EM\tREGISTRADO_EM\tITENS\r\n");
                            w.Write(line);
                        }
                        last[code] = content;
                        return;
                    }
                    catch { Thread.Sleep(150); }
                }
            }
        }

        // todas as versões gravadas, por código (ordenadas pela data em que a montagem foi salva)
        public static Dictionary<string, List<Snap>> Load(HashSet<string> codes, out DateTime first)
        {
            first = DateTime.MaxValue;
            var res = new Dictionary<string, List<Snap>>(StringComparer.OrdinalIgnoreCase);
            if (!File.Exists(FilePath)) return res;
            using (var fs = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new StreamReader(fs, Encoding.UTF8))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    var c = line.Split('\t');
                    if (c.Length < 4 || line.StartsWith("#") || c[0] == "CODIGO") continue;
                    DateTime w;
                    if (!DateTime.TryParseExact(c[1], "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out w)) continue;
                    DateTime reg;
                    if (DateTime.TryParseExact(c[2], "yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out reg) && reg < first) first = reg;
                    if (!codes.Contains(c[0])) continue;
                    var s = new Snap { When = w };
                    foreach (var part in c[3].Split(new[] { '|' }, StringSplitOptions.RemoveEmptyEntries))
                    {
                        int eq = part.LastIndexOf('='); int q;
                        if (eq > 0 && int.TryParse(part.Substring(eq + 1), out q)) s.Kids[part.Substring(0, eq)] = q;
                    }
                    List<Snap> l;
                    if (!res.TryGetValue(c[0], out l)) res[c[0]] = l = new List<Snap>();
                    l.Add(s);
                }
            }
            foreach (var l in res.Values) l.Sort((a, b) => a.When.CompareTo(b.When));
            return res;
        }

        public static Snap At(List<Snap> l, DateTime t)
        {
            if (l == null) return null;
            Snap s = null;
            foreach (var x in l) { if (x.When <= t) s = x; else break; }
            return s;
        }
    }

    public static class EmailCadastro
    {
        class Bloco { public List<string> Codigos = new List<string>(); public string Corpo; public bool Nova; }

        // compara a lista de cada montagem do projeto no início x no fim do período e monta o texto do e-mail
        public static string Gerar(Project p, Config cfg, DateTime ini, DateTime fim, object sync, out string resumo)
        {
            var atual = new Dictionary<string, Dictionary<string, int>>(StringComparer.OrdinalIgnoreCase);
            var salvo = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
            var criado = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
            lock (sync)
            {
                foreach (var it in p.Items.Values)
                {
                    if (!it.IsAsm || it.Missing) continue;
                    var m = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                    foreach (var k in p.Kids(it.Key)) { string n = Util.NameOf(k.Child); int q; m.TryGetValue(n, out q); m[n] = q + k.Qty; }
                    atual[it.Name] = m;
                    salvo[it.Name] = it.Model;
                    try { criado[it.Name] = File.GetCreationTime(it.Path); } catch { criado[it.Name] = DateTime.MinValue; }
                }
            }
            DateTime first;
            var hist = BomHist.Load(new HashSet<string>(atual.Keys, StringComparer.OrdinalIgnoreCase), out first);
            bool fimAgora = fim >= DateTime.Now.AddMinutes(-1);
            var blocos = new List<Bloco>();
            var semHist = new List<string>();
            foreach (var code in atual.Keys.OrderBy(x => x))
            {
                List<BomHist.Snap> l; hist.TryGetValue(code, out l);
                // estado no FIM
                Dictionary<string, int> depois = atual[code];
                if (!fimAgora)
                {
                    var sf = BomHist.At(l, fim);
                    if (sf != null) depois = sf.Kids; else if (salvo[code] > fim) { if (criado[code] > fim) continue; semHist.Add(code); continue; }
                }
                // estado no INÍCIO
                Dictionary<string, int> antes = null;
                var si = BomHist.At(l, ini);
                if (si != null) antes = si.Kids;
                else if (salvo[code] <= ini) antes = (l != null && l.Count > 0) ? l[0].Kids : atual[code];   // não mudou desde antes do início
                else if (criado[code] > ini) { antes = null; }                                              // montagem nova no período
                else { semHist.Add(code); continue; }
                if (antes == null)
                {
                    var sbn = new StringBuilder();
                    foreach (var kv in depois.OrderBy(k => k.Key)) sbn.Append(kv.Value).Append("x ").Append(kv.Key).Append("\r\n");
                    blocos.Add(new Bloco { Codigos = { code }, Corpo = "ITENS:\r\n" + sbn, Nova = true });
                    continue;
                }
                var saiu = new List<string>(); var entrou = new List<string>();
                foreach (var n in antes.Keys.Union(depois.Keys, StringComparer.OrdinalIgnoreCase).OrderBy(x => x))
                {
                    int a, d; antes.TryGetValue(n, out a); depois.TryGetValue(n, out d);
                    if (d < a) saiu.Add((a - d) + "x " + n);
                    else if (d > a) entrou.Add((d - a) + "x " + n);
                }
                if (saiu.Count == 0 && entrou.Count == 0) continue;
                var sb = new StringBuilder();
                if (saiu.Count > 0) { sb.Append("SAIU:\r\n"); foreach (var x in saiu) sb.Append(x).Append("\r\n"); }
                if (entrou.Count > 0) { if (sb.Length > 0) sb.Append("\r\n"); sb.Append("ENTROU:\r\n"); foreach (var x in entrou) sb.Append(x).Append("\r\n"); }
                string corpo = sb.ToString();
                var igual = blocos.FirstOrDefault(b => !b.Nova && b.Corpo == corpo);   // mesma alteração em várias montagens: um bloco só
                if (igual != null) igual.Codigos.Add(code); else blocos.Add(new Bloco { Codigos = { code }, Corpo = corpo });
            }
            var t = new StringBuilder();
            t.Append("Assunto: ALTERAÇÃO DE CADASTRO ").Append(p.Name).Append("\r\n\r\n");
            t.Append(cfg.EmailSaudacao).Append("\r\n\r\n");
            bool primeiro = true;
            foreach (var b in blocos)
            {
                if (!primeiro) t.Append("\r\n").Append(new string('_', 70)).Append("\r\n\r\n");
                primeiro = false;
                string cods = b.Codigos.Count == 1 ? b.Codigos[0] : string.Join(", ", b.Codigos.Take(b.Codigos.Count - 1).ToArray()) + " e " + b.Codigos.Last();
                if (b.Nova) t.Append("Favor cadastrar a montagem nova ").Append(cods).Append(" para futuras prioridades:\r\n\r\n");
                else t.Append("Favor atualizar cadastro do código ").Append(cods).Append(" para futuras prioridades:\r\n\r\n");
                t.Append(b.Corpo);
            }
            if (blocos.Count == 0) t.Append("(Nenhuma alteração de itens encontrada nas montagens de ").Append(p.Name).Append(" no período.)\r\n");
            if (semHist.Count > 0)
                t.Append("\r\n").Append(new string('_', 70)).Append("\r\n\r\n[CONFERIR ANTES DE ENVIAR - apague este trecho]\r\nMontagens alteradas no período sem lista anterior registrada pelo Monitor (comparar manualmente):\r\n")
                 .Append(string.Join("\r\n", semHist.ToArray())).Append("\r\n");
            t.Append("\r\nAtenciosamente,\r\n");
            if (!string.IsNullOrEmpty(cfg.EmailAssinatura)) t.Append(cfg.EmailAssinatura.Replace("\\n", "\r\n")).Append("\r\n");
            resumo = blocos.Count + " bloco(s) de alteração" + (semHist.Count > 0 ? ", " + semHist.Count + " montagem(ns) sem histórico anterior" : "") +
                     (first != DateTime.MaxValue ? " · histórico desde " + first.ToString("dd/MM/yyyy HH:mm") : "");
            return t.ToString();
        }
    }
}
