// Monitor - Notificações: cada usuário escolhe de quais outros usuários quer receber avisos de alteração.
// notificacoes.tsv na pasta do Monitor (compartilhada, segue o usuário em qualquer PC): LOGIN, MODO (todos/marcados),
// SEM NOME (sim/não = avisos de alterações sem usuário identificado), USUÁRIOS (logins separados por |).
// Os avisos das próprias ações (gerar detalhamento, conferência, marcações) e a janelinha "Gerando detalhamento"
// não passam por aqui: aparecem sempre para quem fez.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace MonitorSW
{
    public static class Notificacoes
    {
        public class Pref
        {
            public bool Todos = false;     // padrão: só recebe de quem a pessoa ativar em Opções > Notificações
            public bool SemNome = false;
            public HashSet<string> Logins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }

        public static string FilePath { get { return Path.Combine(Util.AppDir, "notificacoes.tsv"); } }
        static Dictionary<string, Pref> map = new Dictionary<string, Pref>(StringComparer.OrdinalIgnoreCase);
        static DateTime stamp = DateTime.MinValue, lastCheck = DateTime.MinValue;
        static readonly object sync = new object();

        static string Chave { get { return Users.Current != null && Users.Current.Login.Length > 0 ? Users.Current.Login : Environment.UserName; } }

        static void Load(bool force)
        {
            lock (sync)
            {
                if (!force && (DateTime.Now - lastCheck).TotalSeconds < 15) return;
                lastCheck = DateTime.Now;
                try
                {
                    var t = File.Exists(FilePath) ? File.GetLastWriteTime(FilePath) : DateTime.MinValue;
                    if (!force && t == stamp) return;
                    stamp = t;
                    var m = new Dictionary<string, Pref>(StringComparer.OrdinalIgnoreCase);
                    if (File.Exists(FilePath))
                        foreach (var line in File.ReadAllLines(FilePath, Encoding.UTF8))
                        {
                            if (line.StartsWith("#") || line.StartsWith("LOGIN\t") || line.Trim().Length == 0) continue;
                            var c = line.Split('\t');
                            if (c.Length < 2) continue;
                            var p = new Pref();
                            p.Todos = !c[1].Trim().Equals("marcados", StringComparison.OrdinalIgnoreCase);
                            p.SemNome = c.Length >= 3 && c[2].Trim().StartsWith("s", StringComparison.OrdinalIgnoreCase);
                            if (c.Length > 3) foreach (var l in c[3].Split('|')) if (l.Trim().Length > 0) p.Logins.Add(l.Trim());
                            m[c[0].Trim()] = p;
                        }
                    map = m;
                }
                catch { }
            }
        }

        public static Pref Minha()
        {
            Load(false);
            Pref p;
            lock (sync) return map.TryGetValue(Chave, out p) ? p : new Pref();
        }

        public static string Salvar(Pref p)
        {
            try
            {
                Load(true);
                lock (sync)
                {
                    map[Chave] = p;
                    var sb = new StringBuilder();
                    sb.AppendLine("# Notificações do Monitor: de quais usuários cada um recebe avisos de alteração (Opções > Notificações)");
                    sb.AppendLine("LOGIN\tMODO\tSEM NOME\tUSUÁRIOS");
                    foreach (var kv in map.OrderBy(k => k.Key))
                        sb.AppendLine(kv.Key + "\t" + (kv.Value.Todos ? "todos" : "marcados") + "\t" + (kv.Value.SemNome ? "sim" : "não") + "\t" + string.Join("|", kv.Value.Logins.OrderBy(x => x)));
                    File.WriteAllText(FilePath, sb.ToString(), new UTF8Encoding(true));
                    stamp = File.GetLastWriteTime(FilePath);
                }
                return null;
            }
            catch (Exception ex) { return ex.Message; }
        }

        // usuário cadastrado que corresponde ao "salvo por" do evento (apelido, login, legenda ou usuário do Windows)
        static UserRec Dono(string who, List<UserRec> us)
        {
            if (string.IsNullOrEmpty(who)) return null;
            string w = who.Trim();
            foreach (var u in us)
            {
                if (u.Nome.Equals(w, StringComparison.OrdinalIgnoreCase) || u.Login.Equals(w, StringComparison.OrdinalIgnoreCase) ||
                    (u.Carimbo.Length > 0 && u.Carimbo.Equals(w, StringComparison.OrdinalIgnoreCase)) ||
                    ("," + u.Windows + ",").IndexOf("," + w + ",", StringComparison.OrdinalIgnoreCase) >= 0) return u;
            }
            return null;
        }

        // o aviso desta alteração deve aparecer para o usuário atual?
        public static bool Aceita(Ev e)
        {
            var p = Minha();
            if (p.Todos) return true;
            if (string.IsNullOrEmpty(e.Who)) return p.SemNome;
            var u = Dono(e.Who, Users.Load());
            if (u == null) return p.SemNome || p.Logins.Contains(e.Who.Trim());
            return p.Logins.Contains(u.Login);
        }

        // ------------------------------------------------------------ tela (Opções > Notificações...)
        public static void Editar(IWin32Window dono)
        {
            var p = Minha();
            var us = Users.Load().Where(u => !u.Login.Equals(Chave, StringComparison.OrdinalIgnoreCase)).OrderBy(u => u.Nome).ToList();
            using (var f = new Form())
            {
                f.Text = "Monitor - notificações de " + Users.Me; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, 440);
                Theme.Style(f);
                var t = new Label(); t.Text = "Receber avisos de alterações feitas por:"; t.SetBounds(16, 14, 408, 20);
                t.Font = new Font(f.Font, FontStyle.Bold);
                var rTodos = new RadioButton(); rTodos.Text = "Todos os usuários"; rTodos.SetBounds(16, 40, 408, 22);
                var rMarc = new RadioButton(); rMarc.Text = "Só os usuários marcados abaixo"; rMarc.SetBounds(16, 64, 408, 22);
                var lista = new CheckedListBox(); lista.SetBounds(34, 92, 390, 200); lista.CheckOnClick = true; lista.IntegralHeight = false;
                lista.BackColor = Theme.Surface; lista.ForeColor = Theme.Text; lista.BorderStyle = BorderStyle.FixedSingle;
                foreach (var u in us) lista.Items.Add(u.Nome + (u.Login.Equals(u.Nome, StringComparison.OrdinalIgnoreCase) ? "" : "  (" + u.Login + ")"), p.Logins.Contains(u.Login));
                var cSem = new CheckBox(); cSem.Text = "Alterações sem usuário identificado"; cSem.SetBounds(34, 298, 390, 22); cSem.Checked = p.SemNome;
                var n = new Label(); n.SetBounds(16, 326, 408, 62); n.ForeColor = Theme.Muted;
                n.Text = "Vale só para os avisos de peças e desenhos alterados por outras pessoas. A janelinha \"Gerando detalhamento\" e os avisos das suas próprias ações aparecem sempre no seu PC. A escolha segue o seu usuário em qualquer PC.";
                Action atualiza = () => { lista.Enabled = rMarc.Checked; cSem.Enabled = rMarc.Checked; };
                rTodos.CheckedChanged += (s, a) => atualiza(); rMarc.CheckedChanged += (s, a) => atualiza();
                rTodos.Checked = p.Todos; rMarc.Checked = !p.Todos; atualiza();
                var ok = new Button(); ok.Text = "Salvar"; ok.SetBounds(240, 398, 86, 28); ok.FlatStyle = FlatStyle.Flat; ok.BackColor = Theme.Accent; ok.ForeColor = Color.White;
                var ca = new Button(); ca.Text = "Cancelar"; ca.SetBounds(334, 398, 86, 28); ca.FlatStyle = FlatStyle.Flat; ca.DialogResult = DialogResult.Cancel;
                f.Controls.AddRange(new Control[] { t, rTodos, rMarc, lista, cSem, n, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                ok.Click += (s, a) =>
                {
                    var np = new Pref();
                    np.Todos = rTodos.Checked; np.SemNome = cSem.Checked;
                    for (int i = 0; i < lista.Items.Count; i++) if (lista.GetItemChecked(i)) np.Logins.Add(us[i].Login);
                    if (!np.Todos && np.Logins.Count == 0 && !np.SemNome &&
                        MessageBox.Show(f, "Nenhum usuário marcado: você não vai receber avisos de alterações de ninguém. Continuar?", "Notificações", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                    var err = Salvar(np);
                    if (err != null) { MessageBox.Show(f, "Não gravou: " + err, "Notificações", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                    f.DialogResult = DialogResult.OK; f.Close();
                };
                f.ShowDialog(dono);
            }
        }
    }
}
