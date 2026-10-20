// Monitor SW - indice de todas as maquinas (BOM em texto + onde e usado), para busca rapida
// Compativel com C# 5 / .NET Framework 4.5+
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace MonitorSW
{
    public class IdxPart
    {
        public string Path, Name;
        public DateTime MTime;
        public bool Known;
        public string Desc = "", Acab = "", Proc = "", Aprov = "", Blocked = "", LastBy = "";
    }

    public class WhereRow
    {
        public string Code, Desc, Machine, Chains, Proc, Path;
        public string Hay; // codigo + descricao em maiusculas, para busca rapida
        public int Qty, NPaths;
    }

    public class Indexer
    {
        readonly Func<Config> getCfg;
        public readonly object Sync = new object();
        public event Action<string> Progress;
        public event Action Updated;

        // arvore global: montagem -> filhos (com quantidade) e de quando e a informacao
        Dictionary<string, List<TreeRef>> children = new Dictionary<string, List<TreeRef>>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, DateTime> childrenSrc = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, IdxPart> parts = new Dictionary<string, IdxPart>(StringComparer.OrdinalIgnoreCase);
        List<string> asmFiles = new List<string>();
        // catalogo de arquivos (vem da propria listagem das pastas, sem abrir nada)
        List<CatEntry> catalog = new List<CatEntry>();
        Dictionary<string, DateTime> listed = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        static readonly string[] CatExt = { ".SLDPRT", ".SLDASM", ".SLDDRW", ".PDF", ".DXF" };

        class CatEntry { public string Path; public long Size; public DateTime MTime; }

        // data do arquivo: usa a da listagem (rapido); se nao estiver la, consulta o arquivo
        DateTime MT(string path)
        {
            DateTime t;
            if (listed.TryGetValue(path, out t)) return t;
            return Util.MTime(path);
        }
        DateTime lastDiscovery = DateTime.MinValue;
        bool loaded;

        // resultado pronto para busca
        List<WhereRow> where = new List<WhereRow>();
        public int Machines, Codes;
        public DateTime LastBuild;
        public string State = "";
        public double ListSeconds, LastRunSeconds;
        public DateTime FirstFullBuild = DateTime.MinValue;

        readonly AutoResetEvent wake = new AutoResetEvent(false);
        Thread thread;
        volatile bool stopping;

        public Indexer(Func<Config> cfg) { getCfg = cfg; }

        // gancho usado apenas nos testes (lista de montagens de uma pasta)
        public static Func<string, List<string>> EnumHook;

        Config Cfg { get { return getCfg(); } }
        public string Dir { get { var d = Cfg.IndexDir; return Path.IsPathRooted(d) ? d : Path.Combine(Util.AppDir, d); } }

        void Say(string s) { State = s; var h = Progress; if (h != null) h(s); }

        public void Start()
        {
            thread = new Thread(Loop);
            thread.IsBackground = true;
            thread.Priority = ThreadPriority.BelowNormal;
            thread.Name = "MonitorSW-Indice";
            thread.Start();
        }

        public void Stop() { stopping = true; wake.Set(); }
        public void Kick() { lastDiscovery = DateTime.MinValue; wake.Set(); }

        void Loop()
        {
            wake.WaitOne(15000); // deixa o monitor dos projetos comecar primeiro
            while (!stopping)
            {
                try
                {
                    if (!Cfg.IndexOn) Say("Índice desligado (config.ini)");
                    else if (OtherOwner()) FollowOwner();
                    else RunOnce();
                }
                catch (Exception ex) { Say("Índice: erro - " + ex.Message); }
                // quem so le o indice de outro PC confere de 5 em 5 minutos
                wake.WaitOne((Follower ? 5 : Math.Max(5, Cfg.IndexMin)) * 60000);
            }
        }

        // ------------------------------------------------------------ varias pessoas usando: so um PC monta o indice
        public bool Follower;
        public string OwnerName = "";
        DateTime whereLoadedStamp = DateTime.MinValue;
        static string Me { get { return Environment.MachineName + "|" + Environment.UserName; } }
        string OwnerFile { get { return Path.Combine(Dir, "_responsavel.txt"); } }

        // outro PC/usuario esta montando o indice (e esta ativo)?
        bool OtherOwner()
        {
            try
            {
                var f = OwnerFile;
                if (!File.Exists(f)) return false;
                var parts = File.ReadAllText(f).Trim().Split('|');
                if (parts.Length < 3) return false;
                string who = parts[0] + "|" + parts[1];
                if (who.Equals(Me, StringComparison.OrdinalIgnoreCase)) return false;
                long ticks;
                if (!long.TryParse(parts[2], out ticks)) return false;
                var age = DateTime.Now - new DateTime(ticks);
                OwnerName = parts[0];
                return age.TotalMinutes < Math.Max(5, Cfg.IndexMin) * 2 + 30;
            }
            catch { return false; }
        }

        void ClaimOwner()
        {
            try { Directory.CreateDirectory(Dir); File.WriteAllText(OwnerFile, Me + "|" + DateTime.Now.Ticks); } catch { }
        }

        void FollowOwner()
        {
            Follower = true;
            try
            {
                var f = Path.Combine(Dir, "codigos.tsv");
                var t = Util.MTime(f);
                if (t != whereLoadedStamp) { LoadWhere(); whereLoadedStamp = t; LastBuild = t; }
                Say("Índice: " + Machines + " máquinas, " + Codes + " códigos - atualizado " + LastBuild.ToString("dd/MM HH:mm") + " (montado pelo PC " + OwnerName + ")");
                var h = Updated; if (h != null) h();
            }
            catch (Exception ex) { Say("Índice: erro lendo índice compartilhado - " + ex.Message); }
        }

        // ------------------------------------------------------------ ciclo completo (so rele o que mudou)
        public void RunOnce()
        {
            var runStart = DateTime.Now;
            var cfg = Cfg;
            Directory.CreateDirectory(Dir);
            Follower = false;
            ClaimOwner();
            if (!loaded) { LoadCache(); LoadWhere(); loaded = true; }

            // 1) descobre as montagens nas pastas das maquinas
            if (lastDiscovery == DateTime.MinValue || DateTime.Now - lastDiscovery > TimeSpan.FromMinutes(cfg.IndexMin) || asmFiles.Count == 0)
            {
                Say("Índice: listando arquivos do servidor...");
                var found = new List<string>();
                var cat = new List<CatEntry>();
                var t0 = DateTime.Now;
                foreach (var r in cfg.IndexRoots)
                {
                    string root = r == "*" || r.Equals("TUDO", StringComparison.OrdinalIgnoreCase) || r.Length == 0 ? cfg.Root
                                : (Path.IsPathRooted(r) ? r : cfg.Root.TrimEnd('\\') + "\\" + r);
                    Enumerate(root.TrimEnd('\\'), found, cat, cfg.IndexSkip, 0);
                }
                var lst = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
                foreach (var c in cat) lst[c.Path] = c.MTime;
                asmFiles = found.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                catalog = cat;
                listed = lst;
                lastDiscovery = DateTime.Now;
                ListSeconds = (DateTime.Now - t0).TotalSeconds;
                Say("Índice: " + cat.Count + " arquivos listados (" + asmFiles.Count + " montagens) em " + ListSeconds.ToString("0") + " s");
                WriteCatalog();
            }

            // 2) arvore de cada montagem (le so a lista de componentes, no final do arquivo)
            int n = 0, read = 0;
            foreach (var a in asmFiles)
            {
                if (stopping) return;
                n++;
                var t = MT(a);
                if (t == DateTime.MinValue) continue;
                DateTime s;
                if (!childrenSrc.TryGetValue(a, out s) || t > s.AddSeconds(2))
                {
                    ReadTree(a, t);
                    read++;
                    if (read % 10 == 0) { Say("Índice: lendo montagens " + n + "/" + asmFiles.Count); SaveCache(); }
                }
            }

            // 3) maquinas = montagens que nao estao dentro de outra montagem das pastas de maquinas
            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in children) foreach (var c in kv.Value) used.Add(c.Child);
            var roots = asmFiles.Where(a => !used.Contains(a) && childrenSrc.ContainsKey(a)).ToList();

            // 4) submontagens salvas depois da montagem que as contem: rele o arquivo delas
            for (int pass = 0; pass < 4 && !stopping; pass++)
            {
                bool changed = false;
                var reach = Reach(roots);
                int k = 0;
                foreach (var a in reach.Where(x => x.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase)).ToList())
                {
                    k++;
                    var t = MT(a);
                    DateTime s;
                    if (t == DateTime.MinValue) continue;
                    if (!childrenSrc.TryGetValue(a, out s) || t > s.AddSeconds(2))
                    {
                        ReadTree(a, t);
                        changed = true;
                        if (k % 20 == 0) Say("Índice: conferindo submontagens " + k + "/" + reach.Count);
                    }
                }
                if (!changed) break;
            }
            SaveCache();

            // 5) propriedades (descricao, acabamento, processo...) de cada peca: so as que mudaram
            var all = Reach(roots);
            int done = 0, changedProps = 0;
            foreach (var p in all)
            {
                if (stopping) return;
                done++;
                var t = MT(p);
                IdxPart ip;
                if (!parts.TryGetValue(p, out ip)) { ip = new IdxPart(); ip.Path = p; ip.Name = Util.NameOf(p); parts[p] = ip; }
                if (ip.Known && ip.MTime == t) continue;
                ip.MTime = t;
                if (t != DateTime.MinValue) ReadProps(ip, cfg);
                changedProps++;
                if (changedProps % 50 == 0)
                {
                    Say("Índice: lendo propriedades " + done + "/" + all.Count + " (" + changedProps + " novas/alteradas)");
                    if (changedProps % 500 == 0) SaveCache();
                }
            }
            SaveCache();

            // 6) grava os arquivos de texto
            Say("Índice: gravando...");
            Write(roots, cfg);
            LastRunSeconds = (DateTime.Now - runStart).TotalSeconds;
            if (FirstFullBuild == DateTime.MinValue) FirstFullBuild = DateTime.Now;
            WriteStatus(cfg, roots.Count);
            ClaimOwner();
            Say("Índice: " + Machines + " máquinas, " + Codes + " códigos, " + catalog.Count + " arquivos - atualizado " + DateTime.Now.ToString("dd/MM HH:mm") + " (" + Dur(LastRunSeconds) + ")");
            var h = Updated;
            if (h != null) h();
        }

        void Enumerate(string dir, List<string> asmOut, List<CatEntry> cat, List<string> skip, int depth)
        {
            if (EnumHook != null)
            {
                foreach (var p in EnumHook(dir))
                {
                    var ce = new CatEntry(); ce.Path = p; ce.MTime = Util.MTime(p); cat.Add(ce);
                    if (p.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase)) asmOut.Add(p);
                }
                return;
            }
            if (depth > 12 || stopping) return;
            DirectoryInfo di;
            try { di = new DirectoryInfo(dir); } catch { return; }
            try
            {
                // uma unica listagem por pasta: nome, tamanho e data vem juntos (nao abre nenhum arquivo)
                foreach (var fi in di.GetFiles())
                {
                    var name = fi.Name;
                    if (name.StartsWith("~$")) continue;
                    var ext = fi.Extension.ToUpperInvariant();
                    if (Array.IndexOf(CatExt, ext) < 0) continue;
                    var p = dir + "\\" + name;
                    var ce = new CatEntry(); ce.Path = p; ce.Size = fi.Length; ce.MTime = fi.LastWriteTime;
                    cat.Add(ce);
                    if (ext == ".SLDASM") asmOut.Add(p);
                }
            }
            catch { }
            try
            {
                foreach (var d in di.GetDirectories())
                {
                    var name = d.Name;
                    if (skip.Any(x => name.StartsWith(x, StringComparison.OrdinalIgnoreCase))) continue;
                    if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    Enumerate(dir + "\\" + name, asmOut, cat, skip, depth + 1);
                }
            }
            catch { }
        }

        static string Dur(double sec)
        {
            if (sec < 90) return sec.ToString("0") + " s";
            if (sec < 5400) return (sec / 60).ToString("0") + " min";
            return (sec / 3600).ToString("0.0") + " h";
        }

        // prefixo usado para dividir os arquivos (ex.: 0227009 -> 0227, 13011591 -> 1301)
        public static string Prefix(string code)
        {
            code = (code ?? "").Trim();
            if (code.Length >= 4 && code.Substring(0, 4).All(char.IsDigit)) return code.Substring(0, 4);
            return "outros";
        }

        void WriteCatalog()
        {
            try
            {
                string cdir = Path.Combine(Dir, "catalogo");
                Directory.CreateDirectory(cdir);
                var groups = catalog.GroupBy(c => Prefix(Util.NameOf(c.Path))).ToList();
                var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var g in groups)
                {
                    var sb = new StringBuilder();
                    sb.AppendLine("CODIGO\tTIPO\tTAMANHO_KB\tDATA\tPASTA");
                    foreach (var c in g.OrderBy(x => Util.NameOf(x.Path)).ThenBy(x => x.Path))
                        sb.AppendLine(string.Join("\t", new string[] { C(Util.NameOf(c.Path)), Path.GetExtension(c.Path).TrimStart('.').ToUpperInvariant(),
                            (c.Size / 1024).ToString(), Util.Fmt(c.MTime), C(Util.WDir(c.Path)) }));
                    WriteAtomic(Path.Combine(cdir, g.Key + ".tsv"), sb.ToString());
                    keep.Add(g.Key + ".tsv");
                }
                foreach (var f in Directory.GetFiles(cdir, "*.tsv")) if (!keep.Contains(Path.GetFileName(f))) File.Delete(f);
            }
            catch { }
        }

        void WriteStatus(Config cfg, int roots)
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("Ultima atualizacao: " + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss"));
                sb.AppendLine("Primeira leitura completa concluida em: " + FirstFullBuild.ToString("dd/MM/yyyy HH:mm:ss"));
                sb.AppendLine("Duracao desta rodada: " + Dur(LastRunSeconds) + " (" + LastRunSeconds.ToString("0") + " s)");
                sb.AppendLine("Listagem das pastas: " + Dur(ListSeconds));
                sb.AppendLine("Arquivos no catalogo: " + catalog.Count);
                sb.AppendLine("Montagens encontradas: " + asmFiles.Count);
                sb.AppendLine("Maquinas/montagens principais: " + roots);
                sb.AppendLine("Codigos distintos usados em montagens: " + Codes);
                sb.AppendLine("Pecas com propriedades lidas: " + parts.Values.Count(x => x.Known));
                WriteAtomic(Path.Combine(Dir, "status.txt"), sb.ToString());
            }
            catch { }
        }

        void ReadTree(string file, DateTime stamp)
        {
            var cfg = Cfg;
            var meta = SwReader.Read(file, true);
            if (meta.Error != null) return; // nao conseguiu ler agora (rede/arquivo aberto): mantem o que ja sabia
            lock (Sync)
            {
                if (meta.TreeXml == null)
                {
                    // formato antigo ou sem componentes: mantem o que ja se sabia (vindo da montagem de cima)
                    if (!children.ContainsKey(file)) children[file] = new List<TreeRef>();
                    childrenSrc[file] = stamp;
                    return;
                }
                string rootStored;
                Dictionary<string, List<TreeRef>> tree;
                try { tree = SwReader.ParseTree(meta.TreeXml, out rootStored); }
                catch { children[file] = new List<TreeRef>(); childrenSrc[file] = stamp; return; }
                foreach (var kv in tree)
                {
                    string parent = string.Equals(kv.Key, rootStored, StringComparison.OrdinalIgnoreCase) ? file : cfg.Map(kv.Key);
                    bool isRoot = string.Equals(parent, file, StringComparison.OrdinalIgnoreCase);
                    DateTime s;
                    if (!isRoot && childrenSrc.TryGetValue(parent, out s) && s >= stamp) continue;
                    var list = new List<TreeRef>();
                    foreach (var c in kv.Value)
                    {
                        var m = cfg.Map(c.Child);
                        var ex = list.FirstOrDefault(x => string.Equals(x.Child, m, StringComparison.OrdinalIgnoreCase));
                        if (ex != null) ex.Qty += c.Qty; else { var r = new TreeRef(); r.Child = m; r.Qty = c.Qty; list.Add(r); }
                    }
                    children[parent] = list;
                    childrenSrc[parent] = stamp;
                }
                if (!tree.ContainsKey(rootStored ?? "")) { children[file] = new List<TreeRef>(); childrenSrc[file] = stamp; }
                List<TreeRef> mine;
                if (children.TryGetValue(file, out mine)) BomHist.Record(file, stamp, mine);
            }
        }

        void ReadProps(IdxPart ip, Config cfg)
        {
            var m = SwReader.Read(ip.Path, false, 1024 * 1024, 25);
            if (m.Error != null) return; // tenta de novo no proximo ciclo
            ip.Known = true;
            ip.LastBy = m.LastBy ?? "";
            string v;
            var pr = m.Props ?? new Dictionary<string, string>();
            ip.Desc = pr.TryGetValue(cfg.DescProp, out v) ? v : (pr.TryGetValue("Description", out v) ? v : "");
            ip.Acab = pr.TryGetValue("ACABAMENTO", out v) ? v : "";
            ip.Aprov = pr.TryGetValue(cfg.AprovProp, out v) ? v : "";
            ip.Blocked = pr.TryGetValue(cfg.BlockProp, out v) && v.IndexOf("BLOQ", StringComparison.OrdinalIgnoreCase) >= 0 ? "Sim" : "";
            bool isAsm = ip.Path.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase);
            bool laser = cfg.LaserWords.Any(w => ip.Desc.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0);
            bool mach = cfg.MachProps.Any(mp => pr.TryGetValue(mp, out v) && v.Trim().Length > 0);
            if (cfg.IsIgnored(ip.Path)) ip.Proc = "Comercial";
            else if (isAsm) ip.Proc = cfg.IsWeldFolder(ip.Path) ? "Solda" : "Montagem";
            else if (laser) ip.Proc = mach ? "Laser + usinagem" : "Laser";
            else if (mach) ip.Proc = "Usinagem";
            else ip.Proc = "Fabricada";
            if (m.OldFormat) ip.Proc += " (formato antigo)";
        }

        List<string> Reach(List<string> roots)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var order = new List<string>();
            var q = new Queue<string>();
            lock (Sync)
            {
                foreach (var r in roots) if (seen.Add(r)) q.Enqueue(r);
                while (q.Count > 0)
                {
                    var k = q.Dequeue();
                    order.Add(k);
                    List<TreeRef> ch;
                    if (!children.TryGetValue(k, out ch)) continue;
                    foreach (var c in ch) if (seen.Add(c.Child)) q.Enqueue(c.Child);
                }
            }
            return order;
        }

        // ------------------------------------------------------------ arquivos de saida
        static string Safe(string s)
        {
            var bad = Path.GetInvalidFileNameChars();
            return new string(s.Select(ch => bad.Contains(ch) ? '_' : ch).ToArray()).Trim();
        }

        static string C(string s) { return (s ?? "").Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' '); }

        IdxPart P(string path)
        {
            IdxPart ip;
            if (parts.TryGetValue(path, out ip)) return ip;
            ip = new IdxPart(); ip.Path = path; ip.Name = Util.NameOf(path);
            return ip;
        }

        List<TreeRef> Kids(string k)
        {
            List<TreeRef> l;
            return children.TryGetValue(k, out l) ? l : new List<TreeRef>();
        }

        class Acc { public int Qty; public List<string> Chains = new List<string>(); public int NPaths; }

        void Write(List<string> roots, Config cfg)
        {
            string mdir = Path.Combine(Dir, "maquinas");
            string adir = Path.Combine(Dir, "avulsas");
            Directory.CreateDirectory(mdir);
            Directory.CreateDirectory(adir);
            var keepA = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var newWhere = new List<WhereRow>();
            var newMachinePaths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var summary = new StringBuilder();
            summary.AppendLine("MAQUINA\tTIPO\tITENS_DISTINTOS\tLINHAS_BOM\tMONTAGEM_SALVA\tARQUIVO_INDICE\tCAMINHO");
            var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            lock (Sync)
            {
                foreach (var root in roots.OrderBy(x => x))
                {
                    if (stopping) return;
                    string mname = Util.NameOf(root);
                    // maquina = montagem principal na pasta de maquinas (01); as demais sao montagens avulsas (nao usadas em nenhuma outra)
                    bool isMachine = cfg.IndexMachineFolders.Any(mf => root.IndexOf("\\" + mf + "\\", StringComparison.OrdinalIgnoreCase) >= 0);
                    string odir = isMachine ? mdir : adir;
                    string label = isMachine ? mname : "[avulsa] " + mname;
                    string fname = Safe(mname);
                    if (names.ContainsKey(fname)) fname = Safe(mname + " (" + Util.WFile(Util.WDir(root)) + ")");
                    if (names.ContainsKey(fname)) fname = fname + "_" + names.Count;
                    names[fname] = root;

                    var sb = new StringBuilder();
                    sb.AppendLine("# MAQUINA: " + mname + "   (" + root + ")");
                    sb.AppendLine("# Gerado pelo Monitor SW em " + DateTime.Now.ToString("dd/MM/yyyy HH:mm") + ". QTD = na montagem de cima; QTD_TOTAL = na máquina inteira.");
                    sb.AppendLine("ITEM\tNIVEL\tCODIGO\tDESCRICAO\tQTD\tQTD_TOTAL\tACABAMENTO\tPROCESSO\tAPROVADO\tBLOQUEADO\tSALVO_POR\tCAMINHO");
                    var acc = new Dictionary<string, Acc>(StringComparer.OrdinalIgnoreCase);
                    int lines = 0;
                    var stack = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    stack.Add(root);
                    WriteKids(root, "", 1, 1, new List<string> { mname }, stack, sb, acc, ref lines);
                    var tmp = Path.Combine(odir, fname + ".tsv.tmp");
                    var dst = Path.Combine(odir, fname + ".tsv");
                    File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(true));
                    if (File.Exists(dst)) File.Delete(dst);
                    File.Move(tmp, dst);
                    if (isMachine) keep.Add(fname + ".tsv"); else keepA.Add(fname + ".tsv");
                    foreach (var kv in acc)
                    {
                        var ip = P(kv.Key);
                        var w = new WhereRow();
                        w.Code = ip.Name; w.Desc = ip.Desc; w.Machine = label; w.Qty = kv.Value.Qty; w.NPaths = kv.Value.NPaths;
                        w.Chains = string.Join(" | ", kv.Value.Chains.ToArray()) + (kv.Value.NPaths > kv.Value.Chains.Count ? " | ..." : "");
                        w.Proc = ip.Proc; w.Path = kv.Key;
                        w.Hay = ((w.Code ?? "") + " " + (w.Desc ?? "")).ToUpperInvariant();
                        newWhere.Add(w);
                    }
                    newMachinePaths[mname] = root;
                    summary.AppendLine(string.Join("\t", new string[] { C(mname), isMachine ? "MAQUINA" : "AVULSA", acc.Count.ToString(), lines.ToString(), Util.Fmt(MT(root)), (isMachine ? "maquinas\\" : "avulsas\\") + fname + ".tsv", C(root) }));
                }
            }
            // remove indices de maquinas que nao existem mais
            try
            {
                foreach (var f in Directory.GetFiles(mdir, "*.tsv"))
                    if (!keep.Contains(Path.GetFileName(f))) File.Delete(f);
                foreach (var f in Directory.GetFiles(adir, "*.tsv"))
                    if (!keepA.Contains(Path.GetFileName(f))) File.Delete(f);
            }
            catch { }

            // onde_usado dividido por prefixo do codigo (0227.tsv, 0305.tsv, 1301.tsv...) para busca rapida
            string wdir = Path.Combine(Dir, "onde_usado");
            Directory.CreateDirectory(wdir);
            var keepW = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var g in newWhere.GroupBy(x => Prefix(x.Code)))
            {
                var ws = new StringBuilder();
                ws.AppendLine("CODIGO\tDESCRICAO\tMAQUINA\tQTD_TOTAL\tPROCESSO\tCAMINHOS\tONDE (submontagem > ... > máquina)\tARQUIVO");
                foreach (var w in g.OrderBy(x => x.Code).ThenBy(x => x.Machine.StartsWith("[") ? 1 : 0).ThenBy(x => x.Machine))
                    ws.AppendLine(string.Join("\t", new string[] { C(w.Code), C(w.Desc), C(w.Machine), w.Qty.ToString(), C(w.Proc), w.NPaths.ToString(), C(w.Chains), C(w.Path) }));
                WriteAtomic(Path.Combine(wdir, g.Key + ".tsv"), ws.ToString());
                keepW.Add(g.Key + ".tsv");
            }
            try { foreach (var f in Directory.GetFiles(wdir, "*.tsv")) if (!keepW.Contains(Path.GetFileName(f))) File.Delete(f); } catch { }
            try { var old = Path.Combine(Dir, "onde_usado.tsv"); if (File.Exists(old)) File.Delete(old); } catch { }

            // codigos.tsv: uma linha por codigo (busca por descricao, ex.: LUBRIFIL), dizendo em quantas maquinas aparece
            var cs = new StringBuilder();
            cs.AppendLine("CODIGO\tDESCRICAO\tPROCESSO\tMAQUINAS\tAVULSAS\tARQUIVO_ONDE_USADO");
            foreach (var g in newWhere.GroupBy(x => x.Code, StringComparer.OrdinalIgnoreCase).OrderBy(g => g.Key))
            {
                var f0 = g.First();
                int nm = g.Count(x => !x.Machine.StartsWith("[")), na = g.Count() - nm;
                cs.AppendLine(string.Join("\t", new string[] { C(f0.Code), C(f0.Desc), C(f0.Proc), nm.ToString(), na.ToString(), "onde_usado\\" + Prefix(f0.Code) + ".tsv" }));
            }
            WriteAtomic(Path.Combine(Dir, "codigos.tsv"), cs.ToString());
            WriteAtomic(Path.Combine(Dir, "maquinas.tsv"), summary.ToString());
            WriteAtomic(Path.Combine(Dir, "LEIA-ME.txt"), Readme());

            lock (Sync)
            {
                machinePaths = newMachinePaths;
                where = newWhere;
                Machines = roots.Count;
                Codes = newWhere.Select(x => x.Code).Distinct(StringComparer.OrdinalIgnoreCase).Count();
                LastBuild = DateTime.Now;
            }
        }

        void WriteKids(string asm, string num, int level, int mult, List<string> chain, HashSet<string> stack, StringBuilder sb, Dictionary<string, Acc> acc, ref int lines)
        {
            if (level > 20) return;
            // mesma ordem da LISTA DE PEÇAS: primeiro pecas, depois submontagens
            var kids = Kids(asm).Select((k, i) => new { k, i })
                .OrderBy(x => x.k.Child.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase) ? 1 : 0).ThenBy(x => x.i).Select(x => x.k).ToList();
            int n = 0;
            foreach (var c in kids)
            {
                n++;
                string cnum = num.Length == 0 ? n.ToString() : num + "." + n;
                var ip = P(c.Child);
                int tot = c.Qty * mult;
                sb.AppendLine(string.Join("\t", new string[] { cnum, level.ToString(), C(ip.Name), C(ip.Desc), c.Qty.ToString(), tot.ToString(), C(ip.Acab), C(ip.Proc), C(ip.Aprov), ip.Blocked, C(ip.LastBy), C(c.Child) }));
                lines++;
                Acc a;
                if (!acc.TryGetValue(c.Child, out a)) { a = new Acc(); acc[c.Child] = a; }
                a.Qty += tot;
                a.NPaths++;
                if (a.Chains.Count < 4)
                {
                    var parentsUp = new List<string>(chain);
                    parentsUp.Reverse();
                    string ch = string.Join(" > ", parentsUp.ToArray());
                    if (!a.Chains.Contains(ch)) a.Chains.Add(ch);
                }
                if (c.Child.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase) && stack.Add(c.Child))
                {
                    chain.Add(ip.Name);
                    WriteKids(c.Child, cnum, level + 1, tot, chain, stack, sb, acc, ref lines);
                    chain.RemoveAt(chain.Count - 1);
                    stack.Remove(c.Child);
                }
            }
        }

        static void WriteAtomic(string path, string text)
        {
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(true));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }

        static string Readme()
        {
            return "ÍNDICE DO MONITOR SW\r\n" +
                   "====================\r\n" +
                   "Gerado automaticamente a partir de toda a pasta SOLIDWORKS. Não edite: é refeito sozinho.\r\n\r\n" +
                   "codigos.tsv          -> uma linha por código usado em montagens: descrição, processo, em quantas\r\n" +
                   "                        máquinas aparece e em qual arquivo de onde_usado procurar.\r\n" +
                   "onde_usado\\XXXX.tsv -> (XXXX = 4 primeiros dígitos do código, ex.: 0305, 0227, 1301)\r\n" +
                   "                        uma linha por (código, máquina): quantidade total e por quais submontagens passa.\r\n" +
                   "maquinas\\*.tsv      -> BOM completa de cada máquina da pasta 01 (MONTAGEM), formato LISTA DE PEÇAS.\r\n" +
                   "avulsas\\*.tsv       -> BOM das montagens que não estão dentro de nenhuma máquina.\r\n" +
                   "maquinas.tsv         -> lista de máquinas e montagens avulsas.\r\n" +
                   "catalogo\\XXXX.tsv   -> TODOS os arquivos .SLDPRT/.SLDASM/.SLDDRW/.PDF/.DXF do servidor (nome, tipo,\r\n" +
                   "                        tamanho, data, pasta), inclusive peças soltas que não estão em montagens.\r\n" +
                   "status.txt           -> quando foi a última atualização e quanto tempo levou.\r\n" +
                   "_cache_*.tsv         -> memória interna do Monitor SW (para só reler o que mudou).\r\n\r\n" +
                   "Texto separado por TAB (abre no Excel ou Bloco de Notas).\r\n";
        }

        // ------------------------------------------------------------ busca (usada pela tela)
        // busca por palavras: todas precisam aparecer no codigo ou na descricao (ex.: "metalon 15x15")
        public List<WhereRow> Search(string q, int max)
        {
            var toks = (q ?? "").ToUpperInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            if (toks.Length == 0) return new List<WhereRow>();
            List<WhereRow> src;
            lock (Sync) src = where;
            var res = new List<WhereRow>();
            foreach (var w in src)
            {
                var h = w.Hay;
                bool ok = true;
                for (int i = 0; i < toks.Length; i++) if (h.IndexOf(toks[i], StringComparison.Ordinal) < 0) { ok = false; break; }
                if (ok) { res.Add(w); if (res.Count >= max) break; }
            }
            return res.OrderBy(w => w.Code).ThenBy(w => w.Machine).ToList();
        }

        Dictionary<string, string> machinePaths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public List<string> AcabValues()
        {
            lock (Sync) return parts.Values.Select(x => (x.Acab ?? "").Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }

        public List<KeyValuePair<string, string>> MachineList()
        {
            lock (Sync) return machinePaths.OrderBy(k => k.Key).ToList();
        }

        public string MachinePath(string machine)
        {
            if (string.IsNullOrEmpty(machine)) return null;
            string m = machine.StartsWith("[avulsa] ") ? machine.Substring(9) : machine;
            string p;
            lock (Sync) if (machinePaths.TryGetValue(m, out p) || machinePaths.TryGetValue(machine, out p)) return p;
            return null;
        }

        void LoadWhere()
        {
            try
            {
                var wdir = Path.Combine(Dir, "onde_usado");
                if (!Directory.Exists(wdir)) return;
                var list = new List<WhereRow>();
                foreach (var line in Directory.GetFiles(wdir, "*.tsv").SelectMany(f => File.ReadAllLines(f, Encoding.UTF8)))
                {
                    if (line.StartsWith("#") || line.StartsWith("CODIGO\t")) continue;
                    var c = line.Split('\t');
                    if (c.Length < 8) continue;
                    var w = new WhereRow();
                    w.Code = c[0]; w.Desc = c[1]; w.Machine = c[2]; int q; int.TryParse(c[3], out q); w.Qty = q; w.Proc = c[4];
                    int np; int.TryParse(c[5], out np); w.NPaths = np; w.Chains = c[6]; w.Path = c[7];
                    w.Hay = (w.Code + " " + w.Desc).ToUpperInvariant();
                    list.Add(w);
                }
                var mp = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    var mf = Path.Combine(Dir, "maquinas.tsv");
                    if (File.Exists(mf))
                        foreach (var line in File.ReadAllLines(mf, Encoding.UTF8))
                        {
                            var c = line.Split('\t');
                            if (c.Length >= 7 && c[0] != "MAQUINA" && c[0].Trim('\uFEFF') != "MAQUINA") { var k = c[0].TrimStart('\uFEFF'); if (k.StartsWith("[avulsa] ")) k = k.Substring(9); mp[k] = c[6]; }
                        }
                }
                catch { }
                lock (Sync)
                {
                    machinePaths = mp;
                    where = list;
                    Machines = list.Select(x => x.Machine).Distinct().Count();
                    Codes = list.Select(x => x.Code).Distinct(StringComparer.OrdinalIgnoreCase).Count();
                }
            }
            catch { }
        }

        // ------------------------------------------------------------ cache em disco
        static long T(DateTime d) { return d == DateTime.MinValue ? 0 : d.Ticks; }
        static DateTime D(string s) { long v; return long.TryParse(s, out v) && v > 0 ? new DateTime(v) : DateTime.MinValue; }

        void SaveCache()
        {
            try
            {
                var sb = new StringBuilder();
                lock (Sync)
                {
                    foreach (var kv in children)
                    {
                        DateTime s;
                        childrenSrc.TryGetValue(kv.Key, out s);
                        sb.Append("P\t").Append(kv.Key).Append('\t').Append(T(s)).Append("\r\n");
                        foreach (var c in kv.Value) sb.Append("C\t").Append(c.Child).Append('\t').Append(c.Qty).Append("\r\n");
                    }
                }
                WriteAtomic(Path.Combine(Dir, "_cache_arvores.tsv"), sb.ToString());
                sb.Length = 0;
                lock (Sync)
                {
                    foreach (var ip in parts.Values)
                        sb.Append(string.Join("\t", new string[] { ip.Path, T(ip.MTime).ToString(), ip.Known ? "1" : "0", C(ip.Desc), C(ip.Acab), C(ip.Proc), C(ip.Aprov), ip.Blocked, C(ip.LastBy) })).Append("\r\n");
                }
                WriteAtomic(Path.Combine(Dir, "_cache_pecas.tsv"), sb.ToString());
            }
            catch { }
        }

        void LoadCache()
        {
            try
            {
                var f = Path.Combine(Dir, "_cache_arvores.tsv");
                if (File.Exists(f))
                {
                    string cur = null;
                    List<TreeRef> list = null;
                    foreach (var line in File.ReadAllLines(f, Encoding.UTF8))
                    {
                        var c = line.Split('\t');
                        if (c.Length < 3) continue;
                        if (c[0] == "P") { cur = c[1]; list = new List<TreeRef>(); children[cur] = list; childrenSrc[cur] = D(c[2]); }
                        else if (c[0] == "C" && list != null) { var r = new TreeRef(); r.Child = c[1]; int q; int.TryParse(c[2], out q); r.Qty = q; list.Add(r); }
                    }
                }
                f = Path.Combine(Dir, "_cache_pecas.tsv");
                if (File.Exists(f))
                {
                    foreach (var line in File.ReadAllLines(f, Encoding.UTF8))
                    {
                        var c = line.Split('\t');
                        if (c.Length < 9) continue;
                        var ip = new IdxPart();
                        ip.Path = c[0]; ip.Name = Util.NameOf(c[0]); ip.MTime = D(c[1]); ip.Known = c[2] == "1";
                        ip.Desc = c[3]; ip.Acab = c[4]; ip.Proc = c[5]; ip.Aprov = c[6]; ip.Blocked = c[7]; ip.LastBy = c[8];
                        parts[ip.Path] = ip;
                    }
                }
            }
            catch { }
        }
    }
}
