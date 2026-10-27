﻿// Monitor SW - nucleo (leitura dos arquivos SolidWorks, BOM, regras de PDF/DXF por processo, onde e usado)
// Compativel com C# 5 / .NET Framework 4.5+
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Xml;

namespace MonitorSW
{
    public static class Util
    {
        public static string AppDir = AppDomain.CurrentDomain.BaseDirectory;
        // dados de cada usuario (lista de projetos e estado) - permite varias pessoas usando o mesmo programa
        public static string UserDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MonitorSW");
        // quando o programa roda a partir da rede: caminho do .exe original (compartilhado)
        public static string Origin;

        public static string Fmt(DateTime d)
        {
            return d == DateTime.MinValue ? "" : d.ToString("dd/MM/yy HH:mm", CultureInfo.InvariantCulture);
        }

        public static string Between(string s, string a, string b)
        {
            int i = s.IndexOf(a, StringComparison.Ordinal);
            if (i < 0) return null;
            i += a.Length;
            int j = s.IndexOf(b, i, StringComparison.Ordinal);
            if (j < 0) return null;
            return s.Substring(i, j - i);
        }

        // helpers para caminhos Windows (funcionam igual em qualquer plataforma)
        public static string WFile(string path)
        {
            int i = path.LastIndexOf('\\');
            return i < 0 ? path : path.Substring(i + 1);
        }

        public static string WDir(string path)
        {
            int i = path.LastIndexOf('\\');
            return i < 0 ? "" : path.Substring(0, i);
        }

        public static string NameOf(string path)
        {
            string f = WFile(path);
            int i = f.LastIndexOf('.');
            return i <= 0 ? f : f.Substring(0, i);
        }

        // ganchos usados apenas nos testes
        public static Func<string, DateTime> MTimeHook;
        public static Func<string, string> OpenHook;
        public static Func<string, string, List<KeyValuePair<string, DateTime>>> ListHook;

        public static DateTime MTime(string path)
        {
            if (MTimeHook != null) return MTimeHook(path);
            try
            {
                var fi = new FileInfo(path);
                if (fi.Exists) return fi.LastWriteTime;
            }
            catch { }
            return DateTime.MinValue;
        }

        // lista arquivos de uma pasta que batem com o padrao (filtro feito pelo servidor)
        public static List<KeyValuePair<string, DateTime>> ListFiles(string dir, string pattern)
        {
            if (ListHook != null) return ListHook(dir, pattern);
            var res = new List<KeyValuePair<string, DateTime>>();
            try
            {
                foreach (var fi in new DirectoryInfo(dir).GetFiles(pattern))
                    res.Add(new KeyValuePair<string, DateTime>(dir.TrimEnd('\\') + "\\" + fi.Name, fi.LastWriteTime));
            }
            catch { }
            return res;
        }

        static readonly Regex AprRx = new Regex(@"^[\s_\-]*APR[\s_\-\.]*(\d+)\s*$", RegexOptions.IgnoreCase);

        // "0227021 APR-002.PDF" com stem "0227021" -> 2 ; caso contrario -1
        public static int AprNumber(string fileName, string stem)
        {
            string n = NameOf(fileName);
            if (!n.StartsWith(stem, StringComparison.OrdinalIgnoreCase)) return -1;
            var m = AprRx.Match(n.Substring(stem.Length));
            int v;
            return m.Success && int.TryParse(m.Groups[1].Value, out v) ? v : -1;
        }

        public static string Clean(string s)
        {
            return (s ?? "").Replace('\u00A0', ' ').Trim();
        }
    }

    // ------------------------------------------------------------------ marcações (exceção / pendente / revisado)
    // ficam num arquivo compartilhado na pasta do Monitor (marcacoes.tsv): instantâneo, sem abrir o SolidWorks
    public static class Marks
    {
        static Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static DateTime stamp = DateTime.MinValue;
        static DateTime lastCheck = DateTime.MinValue;
        static readonly object sync = new object();
        public static string FilePath { get { return Path.Combine(Util.AppDir, "marcacoes.tsv"); } }

        public static void Refresh(bool force)
        {
            if (!force && (DateTime.Now - lastCheck).TotalSeconds < 10) return;
            lastCheck = DateTime.Now;
            try
            {
                var f = FilePath;
                var t = File.Exists(f) ? File.GetLastWriteTime(f) : DateTime.MinValue;
                if (!force && t == stamp) return;
                var m = Load(f);
                lock (sync) { map = m; stamp = t; }
            }
            catch { }
        }

        static Dictionary<string, string> Load(string f)
        {
            var m = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!File.Exists(f)) return m;
            using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new StreamReader(fs, Encoding.UTF8))
            {
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    if (line.StartsWith("#") || line.StartsWith("CODIGO\t")) continue;
                    var c = line.Split('\t');
                    if (c.Length >= 2 && c[0].Length > 0) { if (c[1].Length > 0) m[c[0]] = c[1]; else m.Remove(c[0]); }
                }
            }
            return m;
        }

        // chave = nome do arquivo sem extensão (o código), assim vale mesmo se a peça mudar de pasta
        public static string Get(string name)
        {
            string v;
            lock (sync) return name != null && map.TryGetValue(name, out v) ? v : null;
        }

        public static string Set(string name, string value)
        {
            return SetMany(new Dictionary<string, string> { { name, value } });
        }
        // várias marcações de uma vez (seleção múltipla): grava o arquivo uma vez só
        public static string SetMany(Dictionary<string, string> values)
        {
            for (int tries = 0; tries < 10; tries++)
            {
                try
                {
                    var f = FilePath;
                    var m = Load(f); // relê para não perder o que outra pessoa marcou
                    foreach (var kv in values) { if (string.IsNullOrEmpty(kv.Value)) m.Remove(kv.Key); else m[kv.Key] = kv.Value; }
                    var sb = new StringBuilder();
                    sb.AppendLine("# Marcações do Monitor (exceção / pendente / revisado). Uma linha por código.");
                    sb.AppendLine("CODIGO\tMARCACAO");
                    foreach (var kv in m.OrderBy(k => k.Key)) sb.Append(kv.Key).Append('\t').Append(kv.Value.Replace("\t", " ")).Append("\r\n");
                    var tmp = f + "." + Environment.MachineName + ".tmp";
                    File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(true));
                    if (File.Exists(f)) File.Replace(tmp, f, null); else File.Move(tmp, f);
                    lock (sync) { map = m; stamp = File.GetLastWriteTime(f); }
                    return null;
                }
                catch (Exception ex) { if (tries == 9) return ex.Message; Thread.Sleep(200); }
            }
            return "erro";
        }
    }

    // ------------------------------------------------------------------ usuários (login do Monitor)
    // usuarios.tsv na pasta do Monitor (compartilhada): LOGIN, NOME, NOME NO CARIMBO, E-MAIL, SAL, SENHA (hash), USUÁRIOS DO WINDOWS
    // Identifica quem está usando (carimbo do desenho, "conferido por", marcações). Não é cofre: quem acessa a pasta pode editar o arquivo.
    public class UserRec
    {
        public string Login = "", Nome = "", Carimbo = "", Email = "", Sal = "", Hash = "", Windows = "";
    }

    public static class Users
    {
        public static UserRec Current;
        public static string FilePath { get { return Path.Combine(Util.AppDir, "usuarios.tsv"); } }
        static string RememberFile { get { return Path.Combine(Util.UserDir, "usuario.txt"); } }

        // nome que aparece no Monitor ("conferido por", marcações); sem login = usuário do Windows
        public static string Me { get { return Current != null && Current.Nome.Length > 0 ? Current.Nome : Environment.UserName; } }
        public static string Carimbo { get { return Current == null ? "" : (Current.Carimbo.Length > 0 ? Current.Carimbo : Current.Nome); } }

        public static List<UserRec> Load()
        {
            var l = new List<UserRec>();
            try
            {
                if (!File.Exists(FilePath)) return l;
                foreach (var line in File.ReadAllLines(FilePath, Encoding.UTF8))
                {
                    if (line.StartsWith("#") || line.Trim().Length == 0 || line.StartsWith("LOGIN\t")) continue;
                    var c = line.Split('\t');
                    if (c.Length < 6) continue;
                    l.Add(new UserRec { Login = c[0].Trim(), Nome = c[1].Trim(), Carimbo = c[2].Trim(), Email = c[3].Trim(), Sal = c[4].Trim(), Hash = c[5].Trim(), Windows = c.Length > 6 ? c[6].Trim() : "" });
                }
            }
            catch { }
            return l;
        }

        // grava (relê antes para não perder o que outra pessoa cadastrou)
        public static string Save(UserRec u, string loginAntigo = null)
        {
            for (int tries = 0; tries < 10; tries++)
            {
                try
                {
                    var l = Load();
                    l.RemoveAll(x => x.Login.Equals(u.Login, StringComparison.OrdinalIgnoreCase) || (!string.IsNullOrEmpty(loginAntigo) && x.Login.Equals(loginAntigo, StringComparison.OrdinalIgnoreCase)));
                    l.Add(u);
                    var sb = new StringBuilder();
                    sb.AppendLine("# Usuários do Monitor. A senha fica só como hash (não dá para ler). Uma linha por pessoa.");
                    sb.AppendLine("LOGIN\tNOME\tNOME NO CARIMBO\tE-MAIL\tSAL\tSENHA\tUSUARIOS DO WINDOWS");
                    foreach (var x in l.OrderBy(k => k.Login, StringComparer.OrdinalIgnoreCase))
                        sb.Append(string.Join("\t", new[] { x.Login, x.Nome, x.Carimbo, x.Email, x.Sal, x.Hash, x.Windows }.Select(v => (v ?? "").Replace("\t", " ")).ToArray())).Append("\r\n");
                    var tmp = FilePath + "." + Environment.MachineName + ".tmp";
                    File.WriteAllText(tmp, sb.ToString(), new UTF8Encoding(true));
                    if (File.Exists(FilePath)) File.Replace(tmp, FilePath, null); else File.Move(tmp, FilePath);
                    return null;
                }
                catch (Exception ex) { if (tries == 9) return ex.Message; Thread.Sleep(200); }
            }
            return "erro";
        }

        public static string HashOf(string sal, string senha)
        {
            using (var sha = System.Security.Cryptography.SHA256.Create())
            {
                var b = sha.ComputeHash(Encoding.UTF8.GetBytes(sal + "|" + (senha ?? "")));
                for (int i = 0; i < 20000; i++) b = sha.ComputeHash(b);
                return Convert.ToBase64String(b);
            }
        }
        public static string NewSalt() { var b = new byte[16]; using (var r = System.Security.Cryptography.RandomNumberGenerator.Create()) r.GetBytes(b); return Convert.ToBase64String(b); }
        // usuário do Windows (ex.: "salvo por" DIAS no arquivo do SolidWorks) -> apelido cadastrado (Guilherme Dias)
        static List<UserRec> cache; static DateTime cacheEm = DateTime.MinValue;
        public static string Display(string windowsUser)
        {
            if (string.IsNullOrEmpty(windowsUser)) return windowsUser ?? "";
            try
            {
                if (cache == null || (DateTime.Now - cacheEm).TotalSeconds > 60) { cache = Load(); cacheEm = DateTime.Now; }
                var u = cache.FirstOrDefault(x => ("," + x.Windows + ",").IndexOf("," + windowsUser.Trim() + ",", StringComparison.OrdinalIgnoreCase) >= 0);
                if (u != null && u.Nome.Length > 0) return u.Nome;
            }
            catch { }
            return windowsUser;
        }
        public static bool Check(UserRec u, string senha) { return u != null && u.Hash.Length > 0 && HashOf(u.Sal, senha) == u.Hash; }

        public static string Remembered()
        {
            try { return File.Exists(RememberFile) ? File.ReadAllText(RememberFile).Trim() : ""; } catch { return ""; }
        }
        public static void Remember(string login)
        {
            try { Directory.CreateDirectory(Util.UserDir); if (string.IsNullOrEmpty(login)) { if (File.Exists(RememberFile)) File.Delete(RememberFile); } else File.WriteAllText(RememberFile, login); } catch { }
        }
    }

    // ------------------------------------------------------------------ configuracao
    public class Config
    {
        public string Root = @"X:\SOLIDWORKS";        // raiz neste PC (pode ser outra letra / caminho de rede)
        public string RootStored = @"X:\SOLIDWORKS";  // raiz gravada no config.ini (compartilhado)
        public bool RootFound = true;
        public List<string> Ignored = new List<string>();
        public List<string> WeldFolders = new List<string>();
        public List<string> LaserWords = new List<string>();
        public List<string> MachProps = new List<string>();
        public List<string> ListCols = new List<string>();
        public List<string> AcabOptions = new List<string>();
        public string DescProp = "DESCRI\u00C7\u00C3O";
        public string AprovProp = "APROVADO";
        public string BlockProp = "BLOQUEADO";
        public string MarkProp = "MONITOR";
        public int IntervalSec = 60;
        public int TolMin = 10;
        public bool Propagate = true;
        public bool NotifyOthersOnly = false;
        public string EmailSaudacao = "Bom dia João,";
        public string EmailAssinatura = "";
        public string HistoryFile = "historico.csv";
        public string GenCmd = "";
        // indice de todas as maquinas (busca rapida / onde e usado)
        public bool IndexOn = true;
        public string IndexDir = "indice";
        public List<string> IndexRoots = new List<string>();
        public List<string> IndexSkip = new List<string>();
        public List<string> IndexMachineFolders = new List<string>();
        public int IndexMin = 60;
        public List<string> Projects = new List<string>();
        public string FilePath;
        public DateTime LoadedStamp;

        public const string DefaultProject = @"X:\SOLIDWORKS\01 (MONTAGEM)\0155 (CUP)\0155023 (CUP-400 V1)\0155023 CUP-400 V1.SLDASM";

        public string HistoryPath
        {
            get { return Path.IsPathRooted(HistoryFile) ? HistoryFile : Path.Combine(Util.AppDir, HistoryFile); }
        }

        static bool Yes(string v)
        {
            v = (v ?? "").Trim().ToLowerInvariant();
            return v == "sim" || v == "s" || v == "1" || v == "true" || v == "yes";
        }

        static void Fill(List<string> l, string v)
        {
            l.Clear();
            foreach (var p in v.Split('|')) if (p.Trim().Length > 0) l.Add(p.Trim());
        }

        void Defaults()
        {
            if (Ignored.Count == 0) Ignored.Add("03 (MAT\u00C9RIA PRIMA)");
            if (WeldFolders.Count == 0) { WeldFolders.Add("1301"); WeldFolders.Add("1304"); }
            if (LaserWords.Count == 0) LaserWords.Add("LASER");
            if (MachProps.Count == 0) MachProps.AddRange(new string[] { "TORNO", "TORNO CNC", "FRESA", "FRESA CNC", "FURADEIRA", "ELETRO" });
            if (IndexRoots.Count == 0) IndexRoots.Add("TUDO");
            if (IndexSkip.Count == 0) IndexSkip.AddRange(new string[] { "ANTIGOS", "ANTIGO", "PASTAS ANTIGAS", "BACKUP", "PDM" });
            if (IndexMachineFolders.Count == 0) IndexMachineFolders.Add("01 (MONTAGEM)");
            if (ListCols.Count == 0) ListCols.AddRange(new string[] { "ACABAMENTO", "QDT.", "TORNO", "TORNO CNC", "FRESA", "FRESA CNC", "ELETRO", "SOLDA", "ACAB.MANUAL" });
        }

        public static Config Load(string path)
        {
            var c = new Config();
            c.FilePath = path;
            if (!File.Exists(path))
            {
                c.Defaults();
                c.SharedProjects.Add(DefaultProject);
                c.Save();
                c.ApplyUserProjects();
                return c;
            }
            bool sawEmail = false;
            bool sawWeld = false, sawCols = false, sawIdx = false, sawIdxMain = false, sawGen = false, sawAcab = false;
            foreach (var raw in File.ReadAllLines(path, Encoding.UTF8))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string k = line.Substring(0, eq).Trim().ToLowerInvariant();
                string v = line.Substring(eq + 1).Trim();
                int n;
                switch (k)
                {
                    case "raizservidor": c.RootStored = c.Root = v.TrimEnd('\\'); break;
                    case "pastasignoradas": Fill(c.Ignored, v); break;
                    case "pastassolda": Fill(c.WeldFolders, v); sawWeld = true; break;
                    case "palavraslaser": Fill(c.LaserWords, v); break;
                    case "propriedadesusinagem": Fill(c.MachProps, v); break;
                    case "propriedadedescricao": if (v.Length > 0) c.DescProp = v; break;
                    case "propriedadeaprovado": if (v.Length > 0) c.AprovProp = v; break;
                    case "propriedadebloqueado": if (v.Length > 0) c.BlockProp = v; break;
                    case "propriedademonitor": if (v.Length > 0) c.MarkProp = v; break;
                    case "colunaslista": Fill(c.ListCols, v); sawCols = true; break;
                    case "opcoesacabamento": Fill(c.AcabOptions, v); sawAcab = true; break;
                    case "indiceativo": c.IndexOn = Yes(v); sawIdx = true; break;
                    case "indicepasta": if (v.Length > 0) c.IndexDir = v; break;
                    case "indicepastasmaquinas": Fill(c.IndexRoots, v); break;
                    case "indiceignorarpastas": Fill(c.IndexSkip, v); break;
                    case "indicepastasmaquinasprincipais": Fill(c.IndexMachineFolders, v); sawIdxMain = true; break;
                    case "indiceintervalominutos": if (int.TryParse(v, out n) && n >= 5) c.IndexMin = n; break;
                    case "intervalosegundos": if (int.TryParse(v, out n) && n >= 10) c.IntervalSec = n; break;
                    case "toleranciaminutos": if (int.TryParse(v, out n) && n >= 0) c.TolMin = n; break;
                    case "propagaralteracaodecomponentes": c.Propagate = Yes(v); break;
                    case "avisarsoalteracoesdeoutros": c.NotifyOthersOnly = Yes(v); break;
                    case "emailsaudacao": c.EmailSaudacao = v; sawEmail = true; break;
                    case "emailassinatura": c.EmailAssinatura = v; break;
                    case "arquivohistorico": if (v.Length > 0) c.HistoryFile = v; break;
                    case "comandogerardetalhamento": c.GenCmd = v; sawGen = true; break;
                    case "projeto": if (v.Length > 0) c.SharedProjects.Add(v); break;
                }
            }
            // config da v1.4 (indexava so a 01): passa para a pasta SOLIDWORKS inteira
            if (!sawIdxMain && c.IndexRoots.Count == 1 && c.IndexRoots[0].Equals("01 (MONTAGEM)", StringComparison.OrdinalIgnoreCase)) c.IndexRoots.Clear();
            c.Defaults();
            c.Root = ResolveRoot(c.RootStored, out c.RootFound);
            c.LoadedStamp = Util.MTime(path);
            if (!sawEmail || !sawWeld || !sawCols || !sawIdx || !sawIdxMain || !sawGen || !sawAcab) c.Save(); // atualiza arquivo antigo com as opcoes novas
            c.ApplyUserProjects();
            return c;
        }

        // Montagens abertas são de cada USUÁRIO do Monitor (login), em preferencias.tsv (chave "projetos"): cada um vê só as suas,
        // em qualquer PC. As linhas Projeto= do config.ini ficam só como lista inicial de quem ainda não tem a sua.
        public List<string> SharedProjects = new List<string>();
        public DateTime PrefsStamp;
        static string LoginAtual { get { return Users.Current != null && Users.Current.Login.Length > 0 ? Users.Current.Login : null; } }

        public void ApplyUserProjects()
        {
            PrefsStamp = Util.MTime(Preferencias.FilePath);
            string login = LoginAtual;
            string v = login == null ? null : Preferencias.Get(login, "projetos");
            Projects.Clear();
            var src = v == null ? (IEnumerable<string>)SharedProjects : v.Split('|');
            foreach (var x in src)
            {
                var t = x.Trim();
                if (t.Length > 0 && !Projects.Contains(t, StringComparer.OrdinalIgnoreCase)) Projects.Add(t);
            }
        }

        public void SaveUserProjects()
        {
            string login = LoginAtual;
            if (login == null) { SharedProjects = new List<string>(Projects); Save(); return; }
            Preferencias.Set(login, "projetos", string.Join("|", Projects.ToArray()));
            PrefsStamp = Util.MTime(Preferencias.FilePath);
        }

        public void Save()
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Monitor - configuração");
            sb.AppendLine("# Edite com o Bloco de Notas. O monitor recarrega sozinho ao salvar.");
            sb.AppendLine("#");
            sb.AppendLine("# Pasta raiz dos projetos neste PC (caminhos gravados com Y:, Z: ou \\\\10.0.0.20 são convertidos para esta raiz)");
            sb.AppendLine("RaizServidor=" + RootStored);
            sb.AppendLine("# Pastas de itens comerciais (não exigem PDF/DXF). Separe várias com |");
            sb.AppendLine("PastasIgnoradas=" + string.Join("|", Ignored.ToArray()));
            sb.AppendLine("# Pastas de submontagens de SOLDA (exigem desenho/PDF). Basta o começo do nome da pasta");
            sb.AppendLine("PastasSolda=" + string.Join("|", WeldFolders.ToArray()));
            sb.AppendLine("#");
            sb.AppendLine("# REGRAS POR PROCESSO (lidas das propriedades da peça):");
            sb.AppendLine("#  - Peça de LASER (descrição contém uma das palavras abaixo): exige PDF + DXF");
            sb.AppendLine("#  - Demais peças fabricadas (usinagem etc.): exigem PDF");
            sb.AppendLine("#  - Submontagens de solda: exigem PDF");
            sb.AppendLine("PalavrasLaser=" + string.Join("|", LaserWords.ToArray()));
            sb.AppendLine("PropriedadesUsinagem=" + string.Join("|", MachProps.ToArray()));
            sb.AppendLine("PropriedadeDescricao=" + DescProp);
            sb.AppendLine("PropriedadeAprovado=" + AprovProp);
            sb.AppendLine("PropriedadeBloqueado=" + BlockProp);
            sb.AppendLine("# Propriedade gravada no arquivo pelo Monitor: EXCECAO (não precisa detalhamento), PENDENTE (revisar depois) ou REVISADO");
            sb.AppendLine("PropriedadeMonitor=" + MarkProp);
            sb.AppendLine("# Colunas da BOM na tela (propriedades das peças; QDT. = quantidade). Mudança vale ao reabrir o monitor");
            sb.AppendLine("ColunasLista=" + string.Join("|", ListCols.ToArray()));
            sb.AppendLine("# Opções de ACABAMENTO na edição (clique direito > Editar acabamento). Os acabamentos já usados nas peças também aparecem");
            sb.AppendLine("OpcoesAcabamento=" + string.Join("|", AcabOptions.ToArray()));
            sb.AppendLine("#");
            sb.AppendLine("# ÍNDICE DE TODAS AS MÁQUINAS (busca rápida de código / onde é usado, também usado pelo Claude)");
            sb.AppendLine("# Lê só a lista de componentes de cada montagem (não abre o SolidWorks) e grava arquivos de texto na pasta abaixo");
            sb.AppendLine("IndiceAtivo=" + (IndexOn ? "sim" : "não"));
            sb.AppendLine("IndicePasta=" + IndexDir);
            sb.AppendLine("# Pastas (dentro da RaizServidor) que entram no índice. TUDO = a pasta SOLIDWORKS inteira. Separe várias com |");
            sb.AppendLine("IndicePastasMaquinas=" + string.Join("|", IndexRoots.ToArray()));
            sb.AppendLine("# Pasta onde ficam as máquinas (montagens principais). Montagens de outras pastas que não estão em nenhuma máquina viram \"avulsas\"");
            sb.AppendLine("IndicePastasMaquinasPrincipais=" + string.Join("|", IndexMachineFolders.ToArray()));
            sb.AppendLine("# Pastas que não entram no índice (basta o começo do nome)");
            sb.AppendLine("IndiceIgnorarPastas=" + string.Join("|", IndexSkip.ToArray()));
            sb.AppendLine("# De quanto em quanto tempo conferir o servidor inteiro (as alterações só são relidas onde mudou)");
            sb.AppendLine("IndiceIntervaloMinutos=" + IndexMin);
            sb.AppendLine("#");
            sb.AppendLine("IntervaloSegundos=" + IntervalSec);
            sb.AppendLine("# Folga entre salvar o desenho e gerar o PDF/DXF");
            sb.AppendLine("ToleranciaMinutos=" + TolMin);
            sb.AppendLine("# sim = quando uma peça muda, o PDF da submontagem de solda que a usa também fica pendente");
            sb.AppendLine("PropagarAlteracaoDeComponentes=" + (Propagate ? "sim" : "não"));
            sb.AppendLine("# sim = não avisar quando quem salvou foi o próprio usuário deste PC");
            sb.AppendLine("AvisarSoAlteracoesDeOutros=" + (NotifyOthersOnly ? "sim" : "não"));
            sb.AppendLine("# Botão E-mail (alteração de cadastro): saudação e assinatura do e-mail");
            sb.AppendLine("EmailSaudacao=" + EmailSaudacao);
            sb.AppendLine("EmailAssinatura=" + EmailAssinatura);
            sb.AppendLine("# Histórico (pode ser um caminho na rede para todos verem o mesmo)");
            sb.AppendLine("ArquivoHistorico=" + HistoryFile);
            sb.AppendLine("#");
            sb.AppendLine("# Botão \"Gerar detalhamento\": programa/script que gera o desenho+PDF/DXF da peça selecionada.");
            sb.AppendLine("# {arquivo} = caminho da peça/montagem, {desenho} = caminho do .SLDDRW, {pasta} = pasta da peça. Vazio = ainda não configurado");
            sb.AppendLine("ComandoGerarDetalhamento=" + GenCmd);
            sb.AppendLine("#");
            sb.AppendLine("# Lista inicial de montagens (só para quem ainda não abriu as suas). Cada usuário tem a sua lista em preferencias.tsv");
            foreach (var p in SharedProjects) sb.AppendLine("Projeto=" + p);
            string text = sb.ToString();
            try { if (File.Exists(FilePath) && File.ReadAllText(FilePath, Encoding.UTF8) == text) return; } catch { }
            File.WriteAllText(FilePath, text, new UTF8Encoding(true));
            LoadedStamp = Util.MTime(FilePath);
        }

        // a pasta SOLIDWORKS pode ter outra letra (ou so caminho de rede) em outro PC: acha a certa
        static string rootCacheKey, rootCacheVal; static bool rootCacheFound;
        static string ResolveRoot(string stored, out bool found)
        {
            if (stored == rootCacheKey && rootCacheVal != null) { found = rootCacheFound; return rootCacheVal; }
            string name = Util.WFile(stored.TrimEnd('\\'));
            var cands = new List<string> { stored };
            try { cands.Add(Path.Combine(Path.GetDirectoryName(Util.AppDir.TrimEnd('\\')) ?? "", name)); } catch { }
            try { if (!string.IsNullOrEmpty(Util.Origin)) cands.Add(Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(Util.Origin)) ?? "", name)); } catch { }
            try { foreach (var d in DriveInfo.GetDrives()) if (d.DriveType == DriveType.Network || d.DriveType == DriveType.Fixed) cands.Add(Path.Combine(d.Name, name)); } catch { }
            string res = null;
            foreach (var c in cands)
            {
                if (string.IsNullOrEmpty(c) || c.Length < 4) continue;
                try { if (Directory.Exists(c)) { res = c.TrimEnd('\\'); break; } } catch { }
            }
            found = res != null;
            rootCacheKey = stored; rootCacheVal = res ?? stored; rootCacheFound = found;
            return rootCacheVal;
        }

        // caminho deste PC -> como fica gravado no config compartilhado (com a raiz gravada)
        public string Unmap(string local)
        {
            if (string.IsNullOrEmpty(local)) return local;
            string r = Root.TrimEnd('\\') + "\\";
            if (!string.Equals(Root, RootStored, StringComparison.OrdinalIgnoreCase) && local.StartsWith(r, StringComparison.OrdinalIgnoreCase))
                return RootStored.TrimEnd('\\') + "\\" + local.Substring(r.Length);
            return local;
        }

        // Converte um caminho gravado na montagem para a raiz deste PC
        public string Map(string stored)
        {
            if (string.IsNullOrEmpty(stored)) return stored;
            string rootName = Util.WFile(Root.TrimEnd('\\'));
            string marker = "\\" + rootName.ToUpperInvariant() + "\\";
            int i = stored.ToUpperInvariant().IndexOf(marker, StringComparison.Ordinal);
            if (i < 0) return stored;
            return Root.TrimEnd('\\') + stored.Substring(i + marker.Length - 1);
        }

        static bool InFolder(string path, List<string> list)
        {
            foreach (var seg in path.Split('\\'))
                foreach (var ig in list)
                    if (seg.StartsWith(ig, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public bool IsIgnored(string path) { return InFolder(Util.WDir(path), Ignored); }
        public bool IsWeldFolder(string path) { return InFolder(Util.WDir(path), WeldFolders); }
    }

    // ------------------------------------------------------------------ leitura do arquivo SolidWorks (formato 2015+)
    public class SwMeta
    {
        public string TreeXml;
        public string LastBy;
        public Dictionary<string, string> Props;
        public bool OldFormat;
        public string Error;
        internal Dictionary<string, string> cfgProps, custProps;
    }

    public class TreeRef
    {
        public string Child;
        public int Qty;
    }

    public static class SwReader
    {
        static string RotName(byte[] b, int off, int len)
        {
            var c = new char[len];
            for (int k = 0; k < len; k++)
            {
                int x = b[off + k];
                c[k] = (char)(((x << 4) | (x >> 4)) & 0xFF);
            }
            return new string(c);
        }

        static byte[] Inflate(byte[] b, int off, int comp, int unc)
        {
            try
            {
                using (var ds = new DeflateStream(new MemoryStream(b, off, comp), CompressionMode.Decompress))
                using (var ms = new MemoryStream(unc > 0 && unc < 300000000 ? unc : 4096))
                {
                    ds.CopyTo(ms);
                    return ms.ToArray();
                }
            }
            catch
            {
                if (comp == unc)
                {
                    var r = new byte[comp];
                    Buffer.BlockCopy(b, off, r, 0, comp);
                    return r;
                }
                return null;
            }
        }

        // ---- "assinatura" da geometria de uma peça: corpo Parasolid de cada configuração (Contents/Config-N-Partition).
        // Salvar sem mexer em nada regrava o arquivo (data nova) mas a geometria é a mesma -> assinatura igual.
        static readonly Dictionary<string, KeyValuePair<DateTime, string>> geoCache = new Dictionary<string, KeyValuePair<DateTime, string>>(StringComparer.OrdinalIgnoreCase);
        public static string GeoSig(string path, DateTime mtime)
        {
            lock (geoCache) { KeyValuePair<DateTime, string> c; if (geoCache.TryGetValue(path, out c) && c.Key == mtime) return c.Value; }
            string res = "";
            try
            {
                string real = Util.OpenHook != null ? Util.OpenHook(path) : path;
                byte[] b;
                using (var fs = new FileStream(real, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length > 80L * 1024 * 1024) return "";
                    b = ReadRange(fs, 0, (int)fs.Length);
                }
                if (b.Length >= 4 && b[0] == 0xD0 && b[1] == 0xCF) return "";   // formato antigo
                int n = b.Length, i = 0, partes = 0;
                ulong h = 14695981039346656037UL;
                while (true)
                {
                    i = Array.IndexOf(b, (byte)0x14, i);
                    if (i < 0 || i + 26 > n) break;
                    if (b[i + 1] == 0 && b[i + 2] == 6 && b[i + 3] == 0 && b[i + 4] == 8 && b[i + 5] == 0)
                    {
                        int comp = BitConverter.ToInt32(b, i + 14), unc = BitConverter.ToInt32(b, i + 18), nl = BitConverter.ToInt32(b, i + 22);
                        if (nl > 0 && nl < 512 && comp > 0 && (long)i + 26 + nl + comp <= n)
                        {
                            string name = RotName(b, i + 26, nl);
                            if (name.StartsWith("Contents/Config-", StringComparison.Ordinal) && name.EndsWith("-Partition", StringComparison.Ordinal) && name.IndexOf("Ghost", StringComparison.Ordinal) < 0)
                            {
                                var d = Inflate(b, i + 26 + nl, comp, unc);
                                if (d != null && d.Length == unc)
                                {
                                    foreach (char ch in name) { h ^= ch; h *= 1099511628211UL; }
                                    foreach (byte x in d) { h ^= x; h *= 1099511628211UL; }
                                    partes++;
                                }
                            }
                            i += 26 + nl;
                            continue;
                        }
                    }
                    i++;
                }
                if (partes > 0) res = "g" + h.ToString("x16") + partes;
            }
            catch { res = ""; }
            lock (geoCache) geoCache[path] = new KeyValuePair<DateTime, string>(mtime, res);
            return res;
        }

        // ---- miniatura (PreviewPNG gravado dentro do proprio arquivo SolidWorks; nao depende do Explorer)
        static readonly byte[] PrevName = RotBytes("PreviewPNG");
        static byte[] RotBytes(string s) { var r = new byte[s.Length]; for (int k = 0; k < s.Length; k++) { int x = s[k]; r[k] = (byte)(((x << 4) | (x >> 4)) & 0xFF); } return r; }

        static byte[] FindPreview(byte[] b, int n)
        {
            // procura de tras para frente a ultima secao PreviewPNG que vira um PNG valido
            for (int i = n - PrevName.Length; i >= 26; i--)
            {
                if (b[i] != PrevName[0]) continue;
                bool eq = true;
                for (int k = 1; k < PrevName.Length; k++) if (b[i + k] != PrevName[k]) { eq = false; break; }
                if (!eq) continue;
                int s0 = i - 26;
                if (b[s0] != 0x14 || b[s0 + 1] != 0 || b[s0 + 2] != 6 || b[s0 + 4] != 8) continue;
                int comp = BitConverter.ToInt32(b, s0 + 14), unc = BitConverter.ToInt32(b, s0 + 18), nl = BitConverter.ToInt32(b, s0 + 22);
                if (nl != PrevName.Length || comp <= 0 || (long)i + nl + comp > n) continue;
                var d = Inflate(b, i + nl, comp, unc);
                if (d != null && d.Length > 8 && d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) return d;
            }
            return null;
        }

        public static byte[] ReadPreview(string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    long len = fs.Length;
                    // final do arquivo (montagens grandes guardam a imagem no fim); arquivo inteiro so se for pequeno
                    foreach (long want in new long[] { 2 * 1024 * 1024, len <= 40L * 1024 * 1024 ? len : 2 * 1024 * 1024 })
                    {
                        int take = (int)Math.Min(len, want);
                        fs.Seek(len - take, SeekOrigin.Begin);
                        var b = new byte[take];
                        int got = 0, r;
                        while (got < take && (r = fs.Read(b, got, take - got)) > 0) got += r;
                        var png = FindPreview(b, got);
                        if (png != null || take >= len || len > 40L * 1024 * 1024) return png;
                    }
                }
            }
            catch { }
            return null;
        }

        static readonly Regex PropRx = new Regex("<property[^>]*?name=\"([^\"]*)\"[^>]*>(.*?)</property>", RegexOptions.Singleline);
        static readonly Regex TagRx = new Regex("<[^>]+>");

        static Dictionary<string, string> ParseProps(string xml)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match m in PropRx.Matches(xml))
            {
                string k = System.Net.WebUtility.HtmlDecode(m.Groups[1].Value);
                if (k.Length == 0) continue;
                string v = System.Net.WebUtility.HtmlDecode(TagRx.Replace(m.Groups[2].Value, ""));
                d[k] = Util.Clean(v);
            }
            return d;
        }

        static void Scan(byte[] b, SwMeta meta, bool wantTree)
        {
            int n = b.Length;
            int i = 0;
            while (true)
            {
                i = Array.IndexOf(b, (byte)0x14, i);
                if (i < 0 || i + 26 > n) break;
                if (b[i + 1] == 0 && b[i + 2] == 6 && b[i + 3] == 0 && b[i + 4] == 8 && b[i + 5] == 0)
                {
                    int comp = BitConverter.ToInt32(b, i + 14);
                    int unc = BitConverter.ToInt32(b, i + 18);
                    int nl = BitConverter.ToInt32(b, i + 22);
                    if (nl > 0 && nl < 512 && comp > 0 && (long)i + 26 + nl + comp <= n)
                    {
                        string name = RotName(b, i + 26, nl);
                        bool isTree = wantTree && meta.TreeXml == null && name.EndsWith("swXmlContents/COMPINSTANCETREE", StringComparison.Ordinal);
                        bool isCore = string.IsNullOrEmpty(meta.LastBy) && name.EndsWith("docProps/core.xml", StringComparison.Ordinal);
                        bool isCfg = meta.cfgProps == null && name.EndsWith("docProps/Config-0-Properties.xml", StringComparison.Ordinal);
                        bool isCust = meta.custProps == null && name.EndsWith("docProps/custom.xml", StringComparison.Ordinal);
                        if (isTree || isCore || isCfg || isCust)
                        {
                            var data = Inflate(b, i + 26 + nl, comp, unc);
                            if (data != null)
                            {
                                string s = Encoding.UTF8.GetString(data);
                                if (isTree) meta.TreeXml = s;
                                else if (isCore) meta.LastBy = Util.Between(s, "lastModifiedBy>", "<");
                                else if (isCfg) meta.cfgProps = ParseProps(s);
                                else meta.custProps = ParseProps(s);
                            }
                        }
                    }
                    if (!string.IsNullOrEmpty(meta.LastBy) && (!wantTree || meta.TreeXml != null) && meta.cfgProps != null && meta.custProps != null) return;
                    i += 6;
                    continue;
                }
                i++;
            }
        }

        static byte[] ReadRange(FileStream fs, long start, int count)
        {
            var buf = new byte[count];
            fs.Seek(start, SeekOrigin.Begin);
            int got = 0;
            while (got < count)
            {
                int r = fs.Read(buf, got, count - got);
                if (r <= 0) break;
                got += r;
            }
            return buf;
        }

        // Le arvore de componentes (opcional), quem salvou por ultimo e as propriedades. Nao bloqueia o SolidWorks.
        public static SwMeta Read(string path, bool wantTree)
        {
            return Read(path, wantTree, 4L * 1024 * 1024, 10);
        }

        // minTail/frac: quanto do final do arquivo ler primeiro (os dados ficam no final; se nao achar, le tudo)
        public static SwMeta Read(string path, bool wantTree, long minTail, int frac)
        {
            var meta = new SwMeta();
            try
            {
                if (Util.OpenHook != null) path = Util.OpenHook(path);
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    long len = fs.Length;
                    var head = ReadRange(fs, 0, (int)Math.Min(8, len));
                    if (head.Length >= 4 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0)
                    {
                        meta.OldFormat = true;
                        return meta;
                    }
                    long tail = Math.Min(len, Math.Max(minTail, len / Math.Max(1, frac)));
                    var buf = ReadRange(fs, len - tail, (int)tail);
                    Scan(buf, meta, wantTree);
                    bool missing = (wantTree && meta.TreeXml == null) || string.IsNullOrEmpty(meta.LastBy);
                    if (missing && tail < len && len < int.MaxValue)
                    {
                        buf = null;
                        buf = ReadRange(fs, 0, (int)len);
                        Scan(buf, meta, wantTree);
                    }
                }
            }
            catch (Exception ex)
            {
                meta.Error = ex.Message;
            }
            // propriedades da configuracao valem mais que as do arquivo
            var props = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (meta.custProps != null) foreach (var kv in meta.custProps) props[kv.Key] = kv.Value;
            if (meta.cfgProps != null) foreach (var kv in meta.cfgProps) if (kv.Value.Length > 0 || !props.ContainsKey(kv.Key)) props[kv.Key] = kv.Value;
            if (meta.cfgProps != null || meta.custProps != null) meta.Props = props;
            return meta;
        }

        // pai -> filhos com quantidade (caminhos como gravados). Ignora suprimidos e "excluir da lista de materiais".
        public static Dictionary<string, List<TreeRef>> ParseTree(string xml, out string rootStored)
        {
            var result = new Dictionary<string, List<TreeRef>>(StringComparer.OrdinalIgnoreCase);
            rootStored = null;
            var doc = new XmlDocument();
            doc.XmlResolver = null;
            doc.LoadXml(xml);
            const string NSURI = "http://www.solidworks.com/sw2003/schema";
            var files = new Dictionary<string, string>();
            foreach (XmlElement f in doc.GetElementsByTagName("swFile", NSURI))
            {
                files[f.GetAttribute("id")] = f.GetAttribute("swPath");
                if (rootStored == null) rootStored = f.GetAttribute("swPath");
            }
            var mfile = new Dictionary<string, string>();
            var models = doc.GetElementsByTagName("swModel", NSURI);
            foreach (XmlElement m in models)
            {
                string p;
                if (files.TryGetValue(m.GetAttribute("swFileRef"), out p)) mfile[m.GetAttribute("id")] = p;
            }
            foreach (XmlElement m in models)
            {
                string parent;
                if (!mfile.TryGetValue(m.GetAttribute("id"), out parent)) continue;
                foreach (XmlNode c in m.ChildNodes)
                {
                    var e = c as XmlElement;
                    if (e != null && e.LocalName == "swReference") AddRef(result, parent, e, mfile);
                }
            }
            return result;
        }

        static void AddRef(Dictionary<string, List<TreeRef>> res, string parent, XmlElement e, Dictionary<string, string> mfile)
        {
            if (e.GetAttribute("swIsVirtualComponent") == "YES") return;
            if (e.GetAttribute("swSuppressed") == "YES") return;
            if (e.GetAttribute("swExcludeFromBOM") == "YES") return;
            string child;
            if (!mfile.TryGetValue(e.GetAttribute("swModelRef"), out child)) return;
            if (child.IndexOf("\\VC~~\\", StringComparison.Ordinal) >= 0 || child.IndexOf('^') >= 0) return;
            List<TreeRef> list;
            if (!res.TryGetValue(parent, out list)) { list = new List<TreeRef>(); res[parent] = list; }
            foreach (var x in list) if (string.Equals(x.Child, child, StringComparison.OrdinalIgnoreCase)) { x.Qty++; return; }
            var r = new TreeRef(); r.Child = child; r.Qty = 1;
            list.Add(r);
        }
    }

    // ------------------------------------------------------------------ modelo de dados
    public class Item
    {
        public string Key, Path, Name, Folder;
        public bool IsAsm, Ignored, Missing, IsWeld;
        public DateTime Model, Drw, Pdf, Dxf, Eff;
        public string EffSource;
        public string DrwPath, PdfPath, DxfPath;
        public string PdfVer = "", DxfVer = "";
        public int PdfAprMax = -1;
        public string LastBy;
        public DateTime LastByStamp;
        // propriedades da peca
        public bool PropsKnown;
        public string Desc = "", Aprov = "", Blocked = "", MachSteps = "";
        public bool IsLaser, IsMach;
        public Dictionary<string, string> Props = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public string P(string name) { string v; return Props.TryGetValue(name, out v) ? v : ""; }
        // regras
        public bool NeedPdf, NeedDxf;
        public string Process = "", Need = "";
        public string Status = "", PdfSt = "", DxfSt = "", Reason = "";
        public int Sev; // 0 ok, 1 informativo, 2 pendente
        public int TotQty, PendBelow, MissBelow;
        // falta detalhamento (desenho/PDF/DXF que a regra pede e não existe) - o que precisa ser feito antes da conferência
        public bool FaltaDet { get { return !Ignored && !IsException && (Missing || (NeedPdf && Pdf == DateTime.MinValue) || (NeedDxf && Dxf == DateTime.MinValue)); } }
        public List<string> Parents = new List<string>();
        public bool OldFormat;

        public string Sig = "";  // montagem: lista de itens + propriedades (salvar sem mudar nada não conta como alteração)
        public string Mark = ""; // EXCECAO / PENDENTE / REVISADO (propriedade gravada pelo Monitor)
        public bool IsException { get { return Mark.StartsWith("EXCE", StringComparison.OrdinalIgnoreCase); } }
        public bool IsBlocked { get { return Blocked.Length > 0 && Blocked.IndexOf("BLOQ", StringComparison.OrdinalIgnoreCase) >= 0; } }
    }

    public class Snap
    {
        public DateTime Model, Drw, Pdf, Dxf, LastByStamp;
        public string LastBy, Desc = "", Aprov = "", Blocked = "", MachSteps = "";
        public Dictionary<string, string> Props = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public bool PropsKnown, IsLaser, IsMach;
        public int Sev = -1;
        public string Sig = "";
    }

    public class Project
    {
        public string MainPath, Name;
        public string Error;
        public Dictionary<string, Item> Items = new Dictionary<string, Item>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, List<TreeRef>> Children = new Dictionary<string, List<TreeRef>>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, DateTime> ChildrenSrc = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, Snap> Prev = new Dictionary<string, Snap>(StringComparer.OrdinalIgnoreCase);
        public bool HadState;
        public DateTime LastScan;
        public int Pend, Info, Ok;
        public int PropsPending;

        public Project(string main)
        {
            MainPath = main;
            Name = Util.NameOf(main);
        }

        public string StateFile
        {
            get
            {
                uint h = 2166136261;
                foreach (char ch in MainPath.ToUpperInvariant()) { h ^= ch; h *= 16777619; }
                return System.IO.Path.Combine(System.IO.Path.Combine(Util.UserDir, "estado"), h.ToString("x8") + ".tsv");
            }
        }

        public List<TreeRef> Kids(string key)
        {
            List<TreeRef> l;
            return Children.TryGetValue(key, out l) ? l : new List<TreeRef>();
        }

        // cadeias "peca > submontagem > ... > montagem principal"
        public List<List<string>> Chains(string key, int max)
        {
            var res = new List<List<string>>();
            var path = new List<string>();
            path.Add(key);
            Walk(key, path, res, max);
            return res;
        }

        void Walk(string key, List<string> path, List<List<string>> res, int max)
        {
            if (res.Count >= max) return;
            Item it;
            if (!Items.TryGetValue(key, out it) || it.Parents.Count == 0 || path.Count > 20)
            {
                res.Add(new List<string>(path));
                return;
            }
            foreach (var p in it.Parents)
            {
                if (path.Contains(p)) continue;
                path.Add(p);
                Walk(p, path, res, max);
                path.RemoveAt(path.Count - 1);
                if (res.Count >= max) return;
            }
        }
    }

    public class Ev
    {
        public DateTime When;
        public string Project, Key, Item, Kind, Who, Detail;
        public int Sev;
    }

    // ------------------------------------------------------------------ motor de verificacao
    public class Engine
    {
        public Config Cfg;
        public readonly List<Project> Projects = new List<Project>();
        public readonly object Sync = new object();
        // false = mostra só se TEM ou NÃO TEM detalhamento (PDF/DXF); true = confere também se está atualizado
        public volatile bool CheckUpdates;
        public event Action<List<Ev>> Updated;
        public event Action<string> Progress;

        readonly AutoResetEvent wake = new AutoResetEvent(false);
        Thread thread;
        volatile bool stopping;

        public Engine(Config cfg)
        {
            Cfg = cfg;
            SyncProjects();
        }

        public void SyncProjects()
        {
            lock (Sync)
            {
                var keep = new List<Project>();
                foreach (var stored in Cfg.Projects)
                {
                    var path = Cfg.Map(stored);
                    var ex = Projects.FirstOrDefault(p => string.Equals(p.MainPath, path, StringComparison.OrdinalIgnoreCase));
                    if (ex == null) { ex = new Project(path); LoadState(ex); }
                    if (!keep.Contains(ex)) keep.Add(ex);
                }
                Projects.Clear();
                Projects.AddRange(keep);
            }
        }

        public void Start()
        {
            thread = new Thread(Loop);
            thread.IsBackground = true;
            thread.Name = "MonitorSW";
            thread.Start();
        }

        public void Stop() { stopping = true; wake.Set(); }
        public void Kick() { wake.Set(); }

        // botão "Atualizar lista": esquece o que já sabia (árvore, propriedades, marcações) e confere tudo de novo agora
        public void ForceRefresh(Project only)
        {
            try { Marks.Refresh(true); } catch { }
            lock (Sync)
            {
                Priority = only ?? Projects.FirstOrDefault();
            }
            wake.Set();
        }

        public void SetCheckUpdates(bool on)
        {
            CheckUpdates = on;
            lock (Sync) foreach (var p in Projects) { Reclassify(p); SyncPrevSev(p); }
            Publish(new List<Ev>());
        }

        void Say(string s) { var h = Progress; if (h != null) h(s); }
        void Publish(List<Ev> evs) { var h = Updated; if (h != null) h(evs); }

        void Loop()
        {
            while (!stopping)
            {
                try
                {
                    if (Cfg.FilePath != null && Util.MTime(Cfg.FilePath) > Cfg.LoadedStamp.AddSeconds(1))
                    {
                        var n = Config.Load(Cfg.FilePath);
                        lock (Sync) { Cfg = n; }
                        SyncProjects();
                    }
                    else if (Util.MTime(Preferencias.FilePath) > Cfg.PrefsStamp.AddSeconds(1))
                    {
                        // o mesmo usuário abriu/fechou montagem em outro PC
                        lock (Sync) Cfg.ApplyUserProjects();
                        SyncProjects();
                    }
                    RunOnce();
                }
                catch (Exception ex)
                {
                    Say("Erro: " + ex.Message);
                }
                wake.WaitOne(Cfg.IntervalSec * 1000);
            }
        }

        public Project Priority; // projeto pedido no "Atualizar lista": é conferido primeiro e aparece na hora

        public List<Ev> RunOnce()
        {
            var all = new List<Ev>();
            List<Project> list;
            lock (Sync)
            {
                list = new List<Project>(Projects);
                if (Priority != null && list.Remove(Priority)) list.Insert(0, Priority);
                Priority = null;
            }
            foreach (var p in list)
            {
                if (Priority != null) break; // novo pedido de "Atualizar lista": recomeça pelo projeto pedido
                Say("Verificando " + p.Name + "...");
                var evs = new List<Ev>();
                try { evs = ScanProject(p); all.AddRange(evs); }
                catch (Exception ex) { p.Error = ex.Message; }
                SaveState(p);
                Publish(new List<Ev>()); // cada projeto aparece atualizado assim que termina (não espera os outros)
            }
            Say("Última verificação: " + DateTime.Now.ToString("HH:mm:ss"));
            Publish(all);
            FillProps(list, 600);
            return all;
        }

        // le descricao/processo/aprovado/bloqueado/quem salvou dos arquivos ainda nao lidos (so o final de cada arquivo)
        public void FillProps(List<Project> list, int budget)
        {
            foreach (var p in list)
            {
                if (Priority != null) break;
                List<Item> todo;
                lock (Sync) todo = p.Items.Values.Where(i => !i.Missing && i.LastByStamp != i.Model).OrderBy(i => i.Ignored ? 1 : 0).ToList();
                if (todo.Count == 0) continue;
                int done = 0;
                foreach (var it in todo)
                {
                    if (budget-- <= 0 || stopping || Priority != null) break; // "Atualizar lista" pediu: para e confere já
                    ReadProps(it);
                    done++;
                    if (done % 40 == 0)
                    {
                        Say("Lendo propriedades das peças de " + p.Name + ": " + done + "/" + todo.Count);
                        lock (Sync) { Reclassify(p); SyncPrevSev(p); }
                        Publish(new List<Ev>());
                    }
                }
                lock (Sync) { Reclassify(p); SyncPrevSev(p); }
                SaveState(p);
                Say("Última verificação: " + DateTime.Now.ToString("HH:mm:ss"));
                Publish(new List<Ev>());
            }
        }

        void ReadProps(Item it)
        {
            var m = SwReader.Read(it.Path, false);
            if (m.Error != null) return; // nao conseguiu ler agora (rede/arquivo): mantem o que ja sabia e tenta de novo depois
            it.LastBy = Users.Display(m.LastBy ?? "");   // DIAS -> Guilherme Dias (cadastro de usuários)
            it.OldFormat = m.OldFormat;
            it.LastByStamp = it.Model;
            if (m.Props != null)
            {
                var c = Cfg;
                string v;
                it.Props = m.Props;
                it.Desc = m.Props.TryGetValue(c.DescProp, out v) ? v : "";
                if (it.Desc.Length == 0 && m.Props.TryGetValue("Description", out v)) it.Desc = v;
                it.Aprov = m.Props.TryGetValue(c.AprovProp, out v) ? v : "";
                it.Blocked = m.Props.TryGetValue(c.BlockProp, out v) ? v : "";
                var steps = new List<string>();
                foreach (var mp in c.MachProps)
                    if (m.Props.TryGetValue(mp, out v) && v.Trim().Length > 0) steps.Add(mp);
                it.MachSteps = string.Join(", ", steps.ToArray());
                it.IsMach = steps.Count > 0;
                it.IsLaser = c.LaserWords.Any(w => it.Desc.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0);
                it.PropsKnown = true;
            }
            else
            {
                it.PropsKnown = true; // arquivo sem propriedades (ou formato antigo)
            }
        }

        string Who(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";
            var m = SwReader.Read(path, false);
            return m.LastBy ?? "";
        }

        // quem gravou o PDF/DXF: dono do arquivo no servidor (usuário do Windows, sem o domínio)
        static string DonoArquivo(string path)
        {
            try
            {
                if (string.IsNullOrEmpty(path) || !File.Exists(path)) return "";
                var acc = File.GetAccessControl(path).GetOwner(typeof(System.Security.Principal.NTAccount)).ToString();
                int i = acc.LastIndexOf('\\');
                acc = i >= 0 ? acc.Substring(i + 1) : acc;
                if (acc.Equals("Administradores", StringComparison.OrdinalIgnoreCase) || acc.Equals("Administrators", StringComparison.OrdinalIgnoreCase) || acc.Equals("SYSTEM", StringComparison.OrdinalIgnoreCase)) return "";
                return acc;
            }
            catch { return ""; }
        }

        // ------------------------------------------------------------ verificacao de um projeto
        public List<Ev> ScanProject(Project p)
        {
            var evs = new List<Ev>();
            var cfg = Cfg;
            string mainKey = p.MainPath;
            DateTime mainTime = Util.MTime(mainKey);
            if (mainTime == DateTime.MinValue)
            {
                p.Error = "Montagem principal não encontrada: " + mainKey;
                return evs;
            }
            p.Error = null;

            // 1) arvore: le a montagem principal e as submontagens salvas depois dela
            var children = new Dictionary<string, List<TreeRef>>(p.Children, StringComparer.OrdinalIgnoreCase);
            var src = new Dictionary<string, DateTime>(p.ChildrenSrc, StringComparer.OrdinalIgnoreCase);
            if (!src.ContainsKey(mainKey) || mainTime > src[mainKey])
            {
                Say("Lendo árvore de " + p.Name + "...");
                if (!ReadTreeInto(mainKey, mainKey, mainTime, children, src))
                {
                    if (children.Count == 0) { p.Error = "Não foi possível ler a árvore de componentes (abra e salve a montagem no SolidWorks 2016)."; return evs; }
                }
            }
            var reach = Reach(mainKey, children);
            for (int pass = 0; pass < 5; pass++)
            {
                bool changed = false;
                foreach (var k in reach)
                {
                    if (string.Equals(k, mainKey, StringComparison.OrdinalIgnoreCase)) continue;
                    if (!k.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase)) continue;
                    var t = Util.MTime(k);
                    DateTime s;
                    if (t == DateTime.MinValue) continue;
                    if (!src.TryGetValue(k, out s) || t > s.AddSeconds(2))
                    {
                        Say("Lendo submontagem " + Util.NameOf(k) + "...");
                        ReadTreeInto(k, k, t, children, src);
                        src[k] = t;
                        changed = true;
                    }
                }
                if (!changed) break;
                reach = Reach(mainKey, children);
            }

            // 2) situacao dos arquivos
            Say("Conferindo PDF/DXF de " + p.Name + "...");
            var items = new Dictionary<string, Item>(StringComparer.OrdinalIgnoreCase);
            var aprCache = new Dictionary<string, List<KeyValuePair<string, DateTime>>>(StringComparer.OrdinalIgnoreCase);
            var sec = TimeSpan.FromSeconds(2);
            var modelChanged = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int sigBudget = 40;   // assinaturas de peça calculadas por varredura (as que ainda não têm)
            foreach (var k in reach)
            {
                Item old;
                Snap ps;
                var it = new Item();
                it.Key = k; it.Path = k; it.Name = Util.NameOf(k);
                it.Folder = Util.WFile(Util.WDir(k));
                it.IsAsm = k.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase);
                it.Ignored = cfg.IsIgnored(k);
                it.IsWeld = it.IsAsm && cfg.IsWeldFolder(k);
                it.Model = Util.MTime(k);
                it.Missing = it.Model == DateTime.MinValue;
                if (p.Items.TryGetValue(k, out old)) CopyProps(old, it);
                else if (p.Prev.TryGetValue(k, out ps)) CopyProps(ps, it);
                if (!it.Ignored && !it.Missing)
                {
                    string b = Util.WDir(k) + "\\" + it.Name;
                    it.DrwPath = b + ".SLDDRW"; it.Drw = Util.MTime(it.DrwPath);
                    it.PdfPath = b + ".PDF"; it.Pdf = Util.MTime(it.PdfPath);
                    it.DxfPath = b + ".DXF"; it.Dxf = Util.MTime(it.DxfPath);
                    // arquivos "... APR-XXX" são revisões ANTIGAS guardadas como registro: não contam como PDF/DXF atual

                }
                bool temPs = p.Prev.TryGetValue(k, out ps);
                if (temPs && !it.Ignored && ps.Model != DateTime.MinValue && it.Model > ps.Model + sec)
                {
                    ReadProps(it); // peca alterada agora: rele propriedades e quem salvou
                    // montagem salva sem mudar nada (mesma lista de itens e mesmas propriedades): não conta como alteração
                    // peça salva sem mudar nada (mesma geometria e mesmas propriedades): idem
                    string ns = !it.PropsKnown ? "" : it.IsAsm ? SigOf(children, k, it) : PartSig(k, it);
                    if (ns.Length > 0 && !string.IsNullOrEmpty(ps.Sig) && ns == ps.Sig)
                    {
                        it.Model = ps.Model; it.LastByStamp = it.Model; it.Sig = ns;
                    }
                    else { modelChanged.Add(k); it.Sig = ns; }
                }
                else if (it.IsAsm && !it.Ignored)
                {
                    if (temPs && !string.IsNullOrEmpty(ps.Sig) && ps.Model == it.Model) it.Sig = ps.Sig;
                    else if (it.PropsKnown) it.Sig = SigOf(children, k, it);
                    if (temPs && ps.Model != DateTime.MinValue && it.Model > ps.Model) it.Model = ps.Model; // mantém a data da última alteração real
                }
                else if (!it.Ignored && !it.Missing)
                {
                    // peça: guarda a assinatura (geometria + propriedades) para reconhecer depois um "salvar sem mudar nada".
                    // Calcula aos poucos (lê o arquivo inteiro): no máximo algumas por varredura
                    if (temPs && !string.IsNullOrEmpty(ps.Sig)) it.Sig = ps.Sig;
                    else if (it.PropsKnown && sigBudget > 0) { sigBudget--; it.Sig = PartSig(k, it); }
                    if (temPs && ps.Model != DateTime.MinValue && it.Model > ps.Model) it.Model = ps.Model;
                }
                items[k] = it;
            }

            // 3) publica e classifica
            bool baseline = !p.HadState && p.Items.Count == 0;
            Dictionary<string, Snap> prevSnap;
            lock (Sync)
            {
                p.Children = children;
                p.ChildrenSrc = src;
                // histórico da lista de cada montagem (para o e-mail de alteração de cadastro): só grava quando muda
                foreach (var kv in children)
                {
                    Item ai;
                    if (!items.TryGetValue(kv.Key, out ai) || !ai.IsAsm || ai.Missing) continue;
                    BomHist.Record(kv.Key, ai.Model, kv.Value);
                }
                p.Items = items;
                p.LastScan = DateTime.Now;
                Reclassify(p);
                prevSnap = p.Prev;
                p.Prev = MakeSnap(p);
                p.HadState = true;
            }

            // 4) eventos
            if (!baseline) evs = Events(p, items, prevSnap, modelChanged, cfg);
            return evs;
        }

        // "assinatura" de uma peça: geometria (corpo Parasolid) + propriedades. Sem geometria legível = "" (conta como alteração)
        static string PartSig(string key, Item it)
        {
            string g = SwReader.GeoSig(key, Util.MTime(key));
            if (g.Length == 0) return "";
            // propriedades de data (data de salvamento etc.) mudam sozinhas ao salvar: ficam de fora
            var tmp = new Item();
            if (it.Props != null)
                foreach (var kv in it.Props)
                {
                    string kk = kv.Key.ToUpperInvariant();
                    if (kk.Contains("DATE") || kk.Contains("DATA") || kk.Contains("SAVE") || kk.Contains("SALV")) continue;
                    tmp.Props[kv.Key] = kv.Value;
                }
            return g + "|" + SigOf(new Dictionary<string, List<TreeRef>>(), key, tmp);
        }

        // "assinatura" de uma montagem: itens (com quantidade) + propriedades. Igual = nada mudou de verdade
        static string SigOf(Dictionary<string, List<TreeRef>> children, string key, Item it)
        {
            var sb = new StringBuilder();
            List<TreeRef> l;
            if (children.TryGetValue(key, out l))
                foreach (var c in l.OrderBy(x => Util.NameOf(x.Child), StringComparer.OrdinalIgnoreCase)) sb.Append(Util.NameOf(c.Child).ToUpperInvariant()).Append('=').Append(c.Qty).Append(';');
            sb.Append('#');
            if (it.Props != null)
                foreach (var kv in it.Props.OrderBy(x => x.Key, StringComparer.OrdinalIgnoreCase)) sb.Append(kv.Key.ToUpperInvariant()).Append('=').Append((kv.Value ?? "").Trim()).Append(';');
            uint h = 2166136261;
            foreach (char ch in sb.ToString()) { h ^= ch; h *= 16777619; }
            return h.ToString("x8") + sb.Length.ToString("x");
        }

        static void CopyProps(Item o, Item it)
        {
            it.LastBy = o.LastBy; it.LastByStamp = o.LastByStamp; it.OldFormat = o.OldFormat;
            it.PropsKnown = o.PropsKnown; it.Desc = o.Desc; it.Aprov = o.Aprov; it.Blocked = o.Blocked;
            it.MachSteps = o.MachSteps; it.IsLaser = o.IsLaser; it.IsMach = o.IsMach; it.Props = o.Props;
        }

        static void CopyProps(Snap o, Item it)
        {
            it.LastBy = o.LastBy; it.LastByStamp = o.LastByStamp;
            it.PropsKnown = o.PropsKnown; it.Desc = o.Desc; it.Aprov = o.Aprov; it.Blocked = o.Blocked;
            it.MachSteps = o.MachSteps; it.IsLaser = o.IsLaser; it.IsMach = o.IsMach; it.Props = o.Props;
        }

        static Dictionary<string, Snap> MakeSnap(Project p)
        {
            var prev = new Dictionary<string, Snap>(StringComparer.OrdinalIgnoreCase);
            foreach (var it in p.Items.Values)
            {
                var s = new Snap();
                s.Model = it.Model; s.Drw = it.Drw; s.Pdf = it.Pdf; s.Dxf = it.Dxf; s.Sev = it.Sev;
                s.LastBy = it.LastBy; s.LastByStamp = it.LastByStamp;
                s.PropsKnown = it.PropsKnown; s.Desc = it.Desc; s.Aprov = it.Aprov; s.Blocked = it.Blocked;
                s.MachSteps = it.MachSteps; s.IsLaser = it.IsLaser; s.IsMach = it.IsMach; s.Props = it.Props; s.Sig = it.Sig ?? "";
                prev[it.Key] = s;
            }
            return prev;
        }

        static void SyncPrevSev(Project p)
        {
            foreach (var it in p.Items.Values)
            {
                Snap s;
                if (p.Prev.TryGetValue(it.Key, out s)) s.Sev = it.Sev;
            }
        }

        List<Ev> Events(Project p, Dictionary<string, Item> items, Dictionary<string, Snap> prev, HashSet<string> modelChanged, Config cfg)
        {
            var evs = new List<Ev>();
            var sec = TimeSpan.FromSeconds(2);
            foreach (var it in items.Values)
            {
                Snap ps;
                if (!prev.TryGetValue(it.Key, out ps))
                {
                    if (!it.Ignored && prev.Count > 0)
                        evs.Add(NewEv(p, it, "Componente adicionado", it.LastBy, "Entrou em " + ParentNames(it) + ". " + it.Need + ": " + it.Status));
                    continue;
                }
                if (it.Ignored) continue;
                bool modelCh = modelChanged.Contains(it.Key);
                bool drwCh = it.Drw > ps.Drw + sec;
                bool pdfCh = it.Pdf > ps.Pdf + sec;
                bool dxfCh = it.Dxf > ps.Dxf + sec;
                if (!modelCh && !drwCh && !pdfCh && !dxfCh)
                {
                    if (ps.Sev != 2 && it.Sev == 2 && ps.Sev >= 0 && (it.EffSource == null || !modelChanged.Contains(it.EffSource)))
                        evs.Add(NewEv(p, it, "Ficou pendente", "", it.Status + (it.Reason.Length > 0 ? " (" + it.Reason + ")" : "")));
                    continue;
                }
                var kinds = new List<string>();
                string who = "";
                if (modelCh)
                {
                    if (it.IsBlocked || ps.Blocked.IndexOf("BLOQ", StringComparison.OrdinalIgnoreCase) >= 0) kinds.Add("ATENÇÃO: peça BLOQUEADA alterada");
                    kinds.Add(it.IsAsm ? "Montagem alterada" : "Peça alterada");
                    who = it.LastBy ?? "";
                    if (ps.Aprov != it.Aprov && it.Aprov.Length > 0) kinds.Add("aprovação " + (ps.Aprov.Length > 0 ? ps.Aprov + " -> " : "") + it.Aprov);
                }
                if (drwCh)
                {
                    kinds.Add(ps.Drw == DateTime.MinValue ? "Desenho criado" : "Desenho alterado");
                    if (who.Length == 0) who = Who(it.DrwPath);
                }
                if (pdfCh) kinds.Add("PDF gerado" + (it.PdfVer.Length > 0 ? " (" + it.PdfVer + ")" : ""));
                if (dxfCh) kinds.Add("DXF gerado" + (it.DxfVer.Length > 0 ? " (" + it.DxfVer + ")" : ""));
                if (who.Length == 0 && dxfCh) who = DonoArquivo(it.DxfPath);
                if (who.Length == 0 && pdfCh) who = DonoArquivo(it.PdfPath);

                var sb = new StringBuilder();
                sb.Append(it.Process.Length > 0 ? "[" + it.Process + " - exige " + it.Need + "] " : "");
                sb.Append(it.Sev == 2 ? it.Status : (it.NeedPdf ? "PDF/DXF em dia" : it.Status));
                if (modelCh && it.Parents.Count > 0)
                {
                    int nUses = p.Chains(it.Key, 50).Count;
                    sb.Append(". Usado em: " + ParentNames(it) + (nUses > 1 ? " (" + nUses + " caminhos até a montagem principal)" : ""));
                }
                if (modelCh)
                {
                    var affected = items.Values.Where(o => o != it && !o.Ignored && o.Sev == 2 && o.EffSource != null
                                     && string.Equals(o.EffSource, it.Key, StringComparison.OrdinalIgnoreCase)).Select(o => o.Name).ToList();
                    if (affected.Count > 0) sb.Append(". Também ficaram pendentes: " + string.Join(", ", affected.Take(8).ToArray()) + (affected.Count > 8 ? "..." : ""));
                }
                var e = NewEv(p, it, string.Join(" + ", kinds.ToArray()), who, sb.ToString());
                if (kinds.Count > 0 && kinds[0].StartsWith("ATEN")) e.Sev = 2;
                evs.Add(e);
            }
            foreach (var kv in prev)
            {
                if (!items.ContainsKey(kv.Key) && !cfg.IsIgnored(kv.Key))
                {
                    var e = new Ev();
                    e.When = DateTime.Now; e.Project = p.Name; e.Key = kv.Key; e.Item = Util.NameOf(kv.Key);
                    e.Kind = "Componente removido"; e.Who = ""; e.Detail = "Saiu da montagem"; e.Sev = 1;
                    evs.Add(e);
                }
            }
            return evs;
        }

        static string ParentNames(Item it)
        {
            return string.Join(", ", it.Parents.Select(x => Util.NameOf(x)).Take(6).ToArray()) + (it.Parents.Count > 6 ? "..." : "");
        }

        Ev NewEv(Project p, Item it, string kind, string who, string detail)
        {
            var e = new Ev();
            e.When = DateTime.Now; e.Project = p.Name; e.Key = it.Key; e.Item = it.Name;
            e.Kind = kind; e.Who = who ?? ""; e.Detail = detail; e.Sev = it.Sev;
            return e;
        }

        // arquivos "*APR*" de cada pasta (uma consulta por pasta por verificacao)
        static List<KeyValuePair<string, DateTime>> AprFiles(Dictionary<string, List<KeyValuePair<string, DateTime>>> cache, string dir)
        {
            List<KeyValuePair<string, DateTime>> l;
            if (!cache.TryGetValue(dir, out l))
            {
                l = Util.ListFiles(dir, "*APR*");
                cache[dir] = l;
            }
            return l;
        }

        // Versoes APR-XXX sao revisoes mais novas: a de maior numero passa a ser o PDF/DXF vigente
        static void ApplyApr(Item it, List<KeyValuePair<string, DateTime>> files)
        {
            int bestPdf = -1, bestDxf = -1;
            foreach (var f in files)
            {
                int n = Util.AprNumber(f.Key, it.Name);
                if (n < 0) continue;
                string ext = f.Key.Substring(f.Key.LastIndexOf('.') + 1).ToUpperInvariant();
                if (ext == "PDF" && (n > bestPdf || (n == bestPdf && f.Value > it.Pdf)))
                {
                    bestPdf = n; it.PdfPath = f.Key; it.Pdf = f.Value; it.PdfVer = "APR-" + n.ToString("000");
                }
                else if (ext == "DXF" && (n > bestDxf || (n == bestDxf && f.Value > it.Dxf)))
                {
                    bestDxf = n; it.DxfPath = f.Key; it.Dxf = f.Value; it.DxfVer = "APR-" + n.ToString("000");
                }
            }
            it.PdfAprMax = bestPdf;
        }

        bool ReadTreeInto(string file, string asKey, DateTime stamp, Dictionary<string, List<TreeRef>> children, Dictionary<string, DateTime> src)
        {
            var meta = SwReader.Read(file, true);
            if (meta.TreeXml == null) return false;
            string rootStored;
            var tree = SwReader.ParseTree(meta.TreeXml, out rootStored);
            foreach (var kv in tree)
            {
                string parent = string.Equals(kv.Key, rootStored, StringComparison.OrdinalIgnoreCase) ? asKey : Cfg.Map(kv.Key);
                bool isRoot = string.Equals(parent, asKey, StringComparison.OrdinalIgnoreCase);
                DateTime s;
                if (!isRoot && src.TryGetValue(parent, out s) && s >= stamp) continue;
                var list = new List<TreeRef>();
                foreach (var c in kv.Value)
                {
                    var m = Cfg.Map(c.Child);
                    var ex = list.FirstOrDefault(x => string.Equals(x.Child, m, StringComparison.OrdinalIgnoreCase));
                    if (ex != null) ex.Qty += c.Qty;
                    else { var r = new TreeRef(); r.Child = m; r.Qty = c.Qty; list.Add(r); }
                }
                children[parent] = list;
                src[parent] = stamp;
            }
            if (!tree.ContainsKey(rootStored ?? "")) { children[asKey] = new List<TreeRef>(); src[asKey] = stamp; }
            return true;
        }

        static List<string> Reach(string root, Dictionary<string, List<TreeRef>> children)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var order = new List<string>();
            var q = new Queue<string>();
            q.Enqueue(root); seen.Add(root);
            while (q.Count > 0)
            {
                var k = q.Dequeue();
                order.Add(k);
                List<TreeRef> ch;
                if (!children.TryGetValue(k, out ch)) continue;
                foreach (var c in ch) if (seen.Add(c.Child)) q.Enqueue(c.Child);
            }
            return order;
        }

        // ------------------------------------------------------------ classificacao (sem acesso a disco)
        public void Reclassify(Project p)
        {
            Marks.Refresh(false);
            Conf.Refresh(false);
            var cfg = Cfg;
            var tol = TimeSpan.FromMinutes(cfg.TolMin);
            var items = p.Items;
            foreach (var it in items.Values) it.Parents.Clear();
            foreach (var kv in p.Children)
            {
                if (!items.ContainsKey(kv.Key)) continue;
                foreach (var c in kv.Value)
                {
                    Item ci;
                    if (items.TryGetValue(c.Child, out ci) && !ci.Parents.Contains(kv.Key, StringComparer.OrdinalIgnoreCase)) ci.Parents.Add(kv.Key);
                }
            }
            var memo = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var it in items.Values) Effective(it, p, memo, new HashSet<string>(StringComparer.OrdinalIgnoreCase), cfg.Propagate);

            int pend = 0, info = 0, ok = 0, unknown = 0;
            foreach (var it in items.Values)
            {
                Classify(it, cfg, tol, CheckUpdates);
                if (it.Ignored && it.Sev != 2) continue; // comercial só conta se foi marcado para revisão
                if (!it.PropsKnown && !it.Missing) unknown++;
                if (it.Sev == 2) pend++; else if (it.Sev == 1) info++; else ok++;
            }
            p.Pend = pend; p.Info = info; p.Ok = ok; p.PropsPending = unknown;

            // quantidade total na maquina
            var tot = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var it in items.Values) it.TotQty = TotQty(it.Key, p, tot, 0);

            // pendencias dentro de cada montagem
            foreach (var it in items.Values)
            {
                if (!it.IsAsm) continue;
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                CountBelow(it.Key, p, seen);
                it.PendBelow = seen.Count(k => { Item x; return items.TryGetValue(k, out x) && x.Sev == 2 && !x.Ignored; });
                it.MissBelow = seen.Count(k => { Item x; return items.TryGetValue(k, out x) && x.FaltaDet; });
            }
        }

        static int TotQty(string key, Project p, Dictionary<string, int> memo, int depth)
        {
            int v;
            if (memo.TryGetValue(key, out v)) return v;
            if (string.Equals(key, p.MainPath, StringComparison.OrdinalIgnoreCase)) { memo[key] = 1; return 1; }
            Item it;
            if (depth > 25 || !p.Items.TryGetValue(key, out it)) return 0;
            int sum = 0;
            foreach (var par in it.Parents)
            {
                var r = p.Kids(par).FirstOrDefault(x => string.Equals(x.Child, key, StringComparison.OrdinalIgnoreCase));
                if (r != null) sum += r.Qty * TotQty(par, p, memo, depth + 1);
            }
            memo[key] = sum;
            return sum;
        }

        static void CountBelow(string key, Project p, HashSet<string> seen)
        {
            foreach (var c in p.Kids(key))
                if (seen.Add(c.Child)) CountBelow(c.Child, p, seen);
        }

        static void Effective(Item it, Project p, HashSet<string> memo, HashSet<string> stack, bool propagate)
        {
            if (memo.Contains(it.Key)) return;
            it.Eff = it.Model; it.EffSource = null;
            if (propagate && it.IsAsm && stack.Add(it.Key))
            {
                foreach (var c in p.Kids(it.Key))
                {
                    Item ci;
                    if (!p.Items.TryGetValue(c.Child, out ci) || ci.Ignored || ci.Missing) continue;
                    Effective(ci, p, memo, stack, propagate);
                    if (ci.Eff > it.Eff)
                    {
                        it.Eff = ci.Eff;
                        it.EffSource = ci.EffSource ?? ci.Key;
                    }
                }
                stack.Remove(it.Key);
            }
            memo.Add(it.Key);
        }

        static void Classify(Item it, Config cfg, TimeSpan tol, bool chk)
        {
            it.Reason = ""; it.PdfSt = ""; it.DxfSt = "";
            it.NeedPdf = false; it.NeedDxf = false;

            // processo e o que e exigido
            if (it.Ignored) { it.Process = "Comercial"; it.Need = "-"; }
            else if (it.IsAsm)
            {
                if (it.IsWeld) { it.Process = "Solda"; it.NeedPdf = true; }
                else it.Process = "Montagem";
            }
            else if (!it.PropsKnown)
            {
                // ainda nao leu as propriedades: usa a existencia do DXF como pista
                it.Process = it.LastByStamp == it.Model ? "não lido" : "lendo...";
                it.NeedPdf = true;
                it.NeedDxf = it.Dxf != DateTime.MinValue;
            }
            else
            {
                it.NeedPdf = true;
                if (it.IsLaser) { it.NeedDxf = true; it.Process = it.IsMach ? "Laser + usinagem" : "Laser"; }
                else if (it.IsMach) it.Process = "Usinagem";
                else it.Process = it.Desc.Length == 0 ? "Sem descrição" : "Fabricada";
            }
            if (!it.Ignored) it.Need = it.NeedPdf ? (it.NeedDxf ? "PDF + DXF" : "PDF") : "-";

            it.Mark = Marks.Get(it.Name) ?? "";
            if (it.Mark.Length == 0 && it.Props != null)
                foreach (var kv in it.Props)
                    if (string.Equals(kv.Key, cfg.MarkProp, StringComparison.OrdinalIgnoreCase)) { it.Mark = (kv.Value ?? "").Trim(); break; }
            if (it.Missing) { it.Sev = 2; it.Status = "Arquivo não encontrado"; ApplyMark(it); return; }
            if (it.Ignored && !it.IsException) { it.Sev = 0; it.Status = "Comercial"; ApplyMark(it); return; }
            if (it.IsException)
            {
                // exceção: item de representação etc. - não precisa detalhamento, sai das pendências
                it.NeedPdf = false; it.NeedDxf = false; it.Need = "Exceção";
                it.PdfSt = it.Pdf == DateTime.MinValue ? "-" : "Tem"; it.DxfSt = it.Dxf == DateTime.MinValue ? "-" : "Tem";
                it.Sev = 0; it.Status = "Exceção - não precisa detalhamento";
                return;
            }

            // data de referencia: o mais novo entre modelo, desenho e componentes internos (so para quem exige PDF)
            DateTime refT = it.Drw; string why = "desenho salvo em " + Util.Fmt(it.Drw);
            if (it.Model > refT) { refT = it.Model; why = (it.IsAsm ? "montagem" : "peça") + " salva em " + Util.Fmt(it.Model); }
            if (it.EffSource != null && it.Eff > refT && it.IsWeld)
            {
                refT = it.Eff;
                why = "componente " + Util.NameOf(it.EffSource) + " alterado em " + Util.Fmt(it.Eff);
            }
            var lim = refT - tol;
            var pend = new List<string>();
            var info = new List<string>();

            // PDF
            if (it.Pdf == DateTime.MinValue)
            {
                it.PdfSt = it.NeedPdf ? "Falta" : "-";
                if (it.NeedPdf) pend.Add(it.Drw == DateTime.MinValue ? "Sem detalhamento" : "Sem PDF (tem desenho)");
            }
            else if (chk && it.Pdf < lim)
            {
                it.PdfSt = "Desatualizado";
                if (it.NeedPdf) pend.Add("PDF desatualizado"); else info.Add("PDF antigo");
            }
            else it.PdfSt = chk ? "OK" : "Tem";
            if (it.PdfVer.Length > 0 && it.Pdf != DateTime.MinValue) it.PdfSt += " (" + it.PdfVer + ")";

            // versao aprovada x versao do PDF
            // (APR-XXX = revisões antigas de registro: não entram na conferência)

            // DXF
            if (it.Dxf == DateTime.MinValue)
            {
                it.DxfSt = it.NeedDxf ? "Falta" : "-";
                if (it.NeedDxf) pend.Add("Sem DXF (laser)");
            }
            else if (chk && it.Dxf < lim)
            {
                it.DxfSt = "Desatualizado";
                if (it.NeedDxf) pend.Add("DXF desatualizado"); else info.Add("DXF antigo");
            }
            else it.DxfSt = chk ? "OK" : "Tem";
            if (it.DxfVer.Length > 0 && it.Dxf != DateTime.MinValue) it.DxfSt += " (" + it.DxfVer + ")";

            // resultado do botão Conferência (PDF/DXF x peça), enquanto os arquivos não mudarem
            if (chk && !it.Ignored)
            {
                var cm = Conf.Get(it);
                if (cm != null && cm.StartsWith("✓"))
                {
                    // alguém conferiu e confirmou que está em dia: tira os avisos de data (falta de arquivo continua valendo)
                    pend.RemoveAll(x => x.IndexOf("desatualizado", StringComparison.OrdinalIgnoreCase) >= 0 || x.StartsWith("PDF é APR"));
                    if (it.PdfSt.StartsWith("Desatualizado")) it.PdfSt = "OK";
                    if (it.DxfSt.StartsWith("Desatualizado")) it.DxfSt = "OK";
                    if (pend.Count == 0) { it.Sev = 0; it.Status = cm; ApplyMark(it); return; }
                }
                else if (!string.IsNullOrEmpty(cm))
                    foreach (var pr in cm.Split(new[] { " + " }, StringSplitOptions.RemoveEmptyEntries))
                        if (!pend.Any(x => x.Equals(pr, StringComparison.OrdinalIgnoreCase))) pend.Add(pr);
            }
            if (pend.Count > 0)
            {
                it.Sev = 2;
                it.Status = string.Join(" + ", pend.ToArray());
                if (pend.Any(x => x.Contains("desatualizado"))) it.Reason = why;
            }
            else if (!it.NeedPdf && !it.IsAsm && !it.PropsKnown) { it.Sev = 1; it.Status = "Lendo propriedades..."; }
            else if (info.Count > 0) { it.Sev = 1; it.Status = string.Join(" + ", info.ToArray()) + " (não obrigatório)"; }
            else if (!it.NeedPdf) { it.Sev = 0; it.Status = it.IsAsm ? "-" : "OK"; }
            else { it.Sev = 0; it.Status = chk ? "OK - atualizado" : "Tem detalhamento"; }
            ApplyMark(it);
        }

        // pendente / revisado valem para qualquer item (inclusive comercial ou sem pendência)
        static void ApplyMark(Item it)
        {
            if (it.Mark.StartsWith("PEND", StringComparison.OrdinalIgnoreCase))
            {
                it.Status = "Marcado para revisão" + (it.Sev == 2 ? " + " + it.Status : "");
                it.Sev = 2;
            }
            else if (it.Mark.StartsWith("REVIS", StringComparison.OrdinalIgnoreCase)) it.Status = it.Status + "  ✓ revisado";
        }

        // ------------------------------------------------------------ estado em disco
        static long T(DateTime d) { return d == DateTime.MinValue ? 0 : d.Ticks; }
        static DateTime D(string s) { long v; return long.TryParse(s, out v) && v > 0 ? new DateTime(v) : DateTime.MinValue; }
        static string E(string s) { return (s ?? "").Replace("\t", " ").Replace("\r", " ").Replace("\n", " "); }

        static string PackProps(Dictionary<string, string> d)
        {
            var sb = new StringBuilder();
            foreach (var kv in d)
            {
                if (kv.Value.Length == 0) continue;
                if (sb.Length > 0) sb.Append('\u001E');
                sb.Append(E(kv.Key)).Append('\u001F').Append(E(kv.Value));
            }
            return sb.ToString();
        }

        static Dictionary<string, string> UnpackProps(string s)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var pair in s.Split('\u001E'))
            {
                int i = pair.IndexOf('\u001F');
                if (i > 0) d[pair.Substring(0, i)] = pair.Substring(i + 1);
            }
            return d;
        }

        void SaveState(Project p)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(p.StateFile));
                var sb = new StringBuilder();
                sb.AppendLine("#v2\t" + p.MainPath);
                lock (Sync)
                {
                    foreach (var it in p.Items.Values)
                        sb.AppendLine(string.Join("\t", new string[] { it.Key, T(it.Model).ToString(), T(it.Drw).ToString(), T(it.Pdf).ToString(), T(it.Dxf).ToString(),
                            it.Sev.ToString(), E(it.LastBy), T(it.LastByStamp).ToString(),
                            it.PropsKnown ? "1" : "0", E(it.Desc), E(it.Aprov), E(it.Blocked), E(it.MachSteps), it.IsLaser ? "1" : "0", it.IsMach ? "1" : "0", PackProps(it.Props), E(it.Sig ?? "") }));
                }
                File.WriteAllText(p.StateFile, sb.ToString(), Encoding.UTF8);
            }
            catch { }
        }

        void LoadState(Project p)
        {
            try
            {
                if (!File.Exists(p.StateFile)) return;
                foreach (var line in File.ReadAllLines(p.StateFile, Encoding.UTF8))
                {
                    if (line.StartsWith("#")) continue;
                    var f = line.Split('\t');
                    if (f.Length < 8) continue;
                    var s = new Snap();
                    s.Model = D(f[1]); s.Drw = D(f[2]); s.Pdf = D(f[3]); s.Dxf = D(f[4]);
                    int sev; s.Sev = int.TryParse(f[5], out sev) ? sev : -1;
                    s.LastBy = f[6]; s.LastByStamp = D(f[7]);
                    if (f.Length >= 15)
                    {
                        s.PropsKnown = f[8] == "1"; s.Desc = f[9]; s.Aprov = f[10]; s.Blocked = f[11]; s.MachSteps = f[12];
                        s.IsLaser = f[13] == "1"; s.IsMach = f[14] == "1";
                        if (f.Length >= 16) s.Props = UnpackProps(f[15]); else s.LastByStamp = DateTime.MinValue;
                        if (f.Length >= 17) s.Sig = f[16];
                    }
                    else s.LastByStamp = DateTime.MinValue; // estado da versao anterior: rele as propriedades
                    p.Prev[f[0]] = s;
                }
                p.HadState = p.Prev.Count > 0;
            }
            catch { }
        }

        // ------------------------------------------------------------ historico CSV
        public static void AppendHistory(string file, IEnumerable<Ev> evs)
        {
            var sb = new StringBuilder();
            foreach (var e in evs)
                sb.AppendLine(string.Join(";", new string[] { e.When.ToString("dd/MM/yyyy HH:mm:ss"), Csv(Environment.MachineName), Csv(e.Project), Csv(e.Item), Csv(e.Kind), Csv(e.Who), Csv(e.Detail) }));
            if (sb.Length == 0) return;
            for (int tries = 0; tries < 5; tries++)
            {
                try
                {
                    bool exists = File.Exists(file);
                    var dir = Path.GetDirectoryName(file);
                    if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                    using (var fs = new FileStream(file, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                    using (var w = new StreamWriter(fs, new UTF8Encoding(!exists)))
                    {
                        if (!exists) w.WriteLine("Data;PC;Projeto;Item;Evento;Salvo por;Detalhe");
                        w.Write(sb.ToString());
                    }
                    return;
                }
                catch { Thread.Sleep(300); }
            }
        }

        static string Csv(string s)
        {
            s = s ?? "";
            if (s.IndexOfAny(new char[] { ';', '"', '\n', '\r' }) >= 0) return "\"" + s.Replace("\"", "\"\"").Replace("\r", " ").Replace("\n", " ") + "\"";
            return s;
        }
    }
}
