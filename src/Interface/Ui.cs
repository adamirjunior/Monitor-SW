// Monitor SW - interface (icone na bandeja + janela com a BOM)
// Compativel com C# 5 / .NET Framework 4.5+
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Monitor")]
[assembly: AssemblyDescription("BOM dos projetos SolidWorks com status de PDF/DXF")]
[assembly: AssemblyProduct("Monitor")]
[assembly: AssemblyVersion("2.12.0.0")]
[assembly: AssemblyFileVersion("2.12.0.0")]

namespace MonitorSW
{
    // ------------------------------------------------------------ tema (escuro / claro; escolha em Opções › Tema, por usuário)
    static class Theme
    {
        public static readonly bool Escuro = LerEscolha();
        public static readonly Color Bg       = Escuro ? Color.FromArgb(14, 16, 20)    : Color.FromArgb(243, 244, 246);  // fundo geral
        public static readonly Color Surface  = Escuro ? Color.FromArgb(20, 23, 29)    : Color.FromArgb(255, 255, 255);  // paineis / tabela
        public static readonly Color Surface2 = Escuro ? Color.FromArgb(28, 32, 40)    : Color.FromArgb(232, 235, 240);  // cabecalhos, barra
        public static readonly Color Hover    = Escuro ? Color.FromArgb(38, 43, 54)    : Color.FromArgb(218, 224, 232);
        public static readonly Color Border   = Escuro ? Color.FromArgb(40, 45, 56)    : Color.FromArgb(206, 212, 220);
        public static readonly Color Text     = Escuro ? Color.FromArgb(228, 231, 236) : Color.FromArgb(28, 32, 38);
        public static readonly Color Muted    = Escuro ? Color.FromArgb(132, 140, 154) : Color.FromArgb(98, 106, 118);
        public static readonly Color Accent   = Escuro ? Color.FromArgb(77, 141, 255)  : Color.FromArgb(37, 99, 235);
        public static readonly Color Sel      = Escuro ? Color.FromArgb(34, 56, 96)    : Color.FromArgb(200, 222, 255);
        public static readonly Color SelText  = Escuro ? Color.White                   : Color.FromArgb(16, 24, 40);
        public static readonly Color AsmRow   = Escuro ? Color.FromArgb(24, 29, 38)    : Color.FromArgb(236, 241, 248);
        public static readonly Color PendRow  = Escuro ? Color.FromArgb(56, 26, 30)    : Color.FromArgb(255, 226, 228);
        public static readonly Color MissRow  = Escuro ? Color.FromArgb(56, 40, 20)    : Color.FromArgb(255, 238, 212);
        public static readonly Color PendText = Escuro ? Color.FromArgb(255, 128, 128) : Color.FromArgb(196, 36, 36);
        public static readonly Color WarnText = Escuro ? Color.FromArgb(255, 184, 108) : Color.FromArgb(184, 96, 0);
        public static readonly Color OkText   = Escuro ? Color.FromArgb(92, 211, 138)  : Color.FromArgb(20, 135, 66);
        public static readonly Color LaserTxt = Escuro ? Color.FromArgb(240, 160, 90)  : Color.FromArgb(196, 88, 16);
        public static readonly Color Purple   = Escuro ? Color.FromArgb(185, 140, 255) : Color.FromArgb(118, 66, 200);
        public static readonly Color PurpleBg = Escuro ? Color.FromArgb(44, 34, 64)    : Color.FromArgb(240, 232, 255);
        public static readonly Color Solda    = Escuro ? Color.FromArgb(200, 140, 255) : Color.FromArgb(128, 70, 210);

        static string Arquivo { get { return Path.Combine(Util.UserDir, "tema.txt"); } }

        // tema é do USUÁRIO do Monitor (preferencias.tsv na pasta compartilhada); antes do login usa o último usuário deste PC
        static bool LerEscolha() { return EscuroDe(Users.Remembered()); }

        public static bool EscuroDe(string login)
        {
            try
            {
                string v = Preferencias.Get(login, "tema");
                if (v == null && File.Exists(Arquivo)) v = File.ReadAllText(Arquivo).Trim();   // escolha antiga (por PC)
                return v == null || !v.Equals("claro", StringComparison.OrdinalIgnoreCase);
            }
            catch { return true; }   // padrão: escuro
        }

        public static void GravarEscolha(bool escuro)
        {
            string login = Users.Current != null ? Users.Current.Login : Users.Remembered();
            if (!string.IsNullOrEmpty(login)) Preferencias.Set(login, "tema", escuro ? "escuro" : "claro");
            Directory.CreateDirectory(Util.UserDir);
            File.WriteAllText(Arquivo, escuro ? "escuro" : "claro");
        }

        public static readonly Font UiFont    = new Font("Segoe UI", 9.5f);
        public static readonly Font UiBold    = new Font("Segoe UI Semibold", 9.5f);
        public static readonly Font Title     = new Font("Segoe UI Semibold", 11f);

        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);

        // barra de titulo escura (Windows 10 1809+ / 11); em versoes antigas nao faz nada
        public static void DarkTitle(Form f)
        {
            if (!Escuro) return;
            try
            {
                int on = 1;
                if (DwmSetWindowAttribute(f.Handle, 20, ref on, 4) != 0) DwmSetWindowAttribute(f.Handle, 19, ref on, 4);
            }
            catch { }
        }

        // barras de rolagem escuras quando o Windows suporta
        public static void DarkScroll(Control c)
        {
            if (!Escuro) return;
            EventHandler h = (s, a) => { try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { } };
            if (c.IsHandleCreated) h(c, EventArgs.Empty); else c.HandleCreated += h;
        }

        public static void Style(ToolStrip ts)
        {
            ts.Renderer = new DarkRenderer();
            ts.BackColor = Surface2;
            ts.ForeColor = Text;
            ts.Font = UiFont;
        }

        public static void Style(ListView lv)
        {
            lv.BackColor = Surface;
            lv.ForeColor = Text;
            lv.BorderStyle = BorderStyle.None;
            lv.Font = UiFont;
            lv.OwnerDraw = true;
            lv.DrawColumnHeader += (s, e) =>
            {
                using (var b = new SolidBrush(Surface2)) e.Graphics.FillRectangle(b, e.Bounds);
                using (var p = new Pen(Border)) e.Graphics.DrawLine(p, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
                var r = new Rectangle(e.Bounds.X + 8, e.Bounds.Y, e.Bounds.Width - 12, e.Bounds.Height);
                var fl = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | (e.Header.TextAlign == HorizontalAlignment.Right ? TextFormatFlags.Right : TextFormatFlags.Left);
                TextRenderer.DrawText(e.Graphics, e.Header.Text, UiBold, r, Muted, fl);
            };
            lv.DrawItem += (s, e) => { };
            lv.DrawSubItem += (s, e) =>
            {
                bool sel = e.Item.Selected;
                using (var b = new SolidBrush(sel ? Sel : Surface)) e.Graphics.FillRectangle(b, e.Bounds);
                var r = new Rectangle(e.Bounds.X + 8, e.Bounds.Y, e.Bounds.Width - 12, e.Bounds.Height);
                var al = lv.Columns[e.ColumnIndex].TextAlign;
                var fl = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | (al == HorizontalAlignment.Right ? TextFormatFlags.Right : TextFormatFlags.Left);
                TextRenderer.DrawText(e.Graphics, e.SubItem.Text, lv.Font, r, e.Item.ForeColor, fl);
            };
            DarkScroll(lv);
        }

        public static void Style(SplitContainer sc)
        {
            sc.BackColor = Border;
            sc.SplitterWidth = 4;
            sc.Panel1.BackColor = Bg;
            sc.Panel2.BackColor = Bg;
        }

        public static void Style(Form f)
        {
            f.BackColor = Bg;
            f.ForeColor = Text;
            f.Font = UiFont;
            f.HandleCreated += (s, a) => DarkTitle(f);
        }
    }

    // ------------------------------------------------------------ login (quem está usando o Monitor)
    static class LoginUi
    {
        static TextBox Tb(Control parent, string label, int y, string val, bool senha)
        {
            var l = new Label(); l.Text = label; l.SetBounds(16, y, 140, 22); l.ForeColor = Theme.Muted; l.TextAlign = ContentAlignment.MiddleLeft;
            var t = new TextBox(); t.SetBounds(160, y, 260, 24); t.Text = val ?? ""; t.BackColor = Theme.Surface2; t.ForeColor = Theme.Text; t.BorderStyle = BorderStyle.FixedSingle;
            if (senha) t.UseSystemPasswordChar = true;
            parent.Controls.Add(l); parent.Controls.Add(t);
            return t;
        }
        static Button Bt(string txt, int x, int y, int w, bool principal)
        {
            var b = new Button(); b.Text = txt; b.SetBounds(x, y, w, 30); b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderColor = principal ? Theme.Accent : Theme.Border; b.BackColor = principal ? Theme.Accent : Theme.Surface2; b.ForeColor = principal ? Color.White : Theme.Text;
            return b;
        }

        // na abertura: usuário lembrado neste PC entra direto; senão pede login (ou cadastro, se ainda não tem ninguém)
        public static bool Startup()
        {
            var lista = Users.Load();
            string rem = Users.Remembered();
            var u = lista.FirstOrDefault(x => x.Login.Equals(rem, StringComparison.OrdinalIgnoreCase));
            if (u != null) { Users.Current = u; return true; }
            return Escolher(null);
        }

        // tela de login; devolve false se cancelar
        public static bool Escolher(IWin32Window dono)
        {
            while (true)
            {
                var lista = Users.Load();
                if (lista.Count == 0)
                {
                    MessageBox.Show(dono, "Ainda não tem nenhum usuário cadastrado no Monitor.\nCadastre o seu (nome completo, nome que vai no carimbo do desenho, e-mail e senha).", "Monitor - primeiro acesso", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    var novo = Editar(dono, null);
                    if (novo == null) return false;
                    Users.Current = novo; Users.Remember(novo.Login);
                    return true;
                }
                using (var f = new Form())
                {
                    f.Text = "Monitor - entrar"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterScreen;
                    f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, 214); Theme.Style(f); f.TopMost = dono == null;
                    var t = new Label(); t.Text = "Quem está usando o Monitor?"; t.SetBounds(16, 12, 400, 24); t.Font = Theme.Title; t.ForeColor = Theme.Text;
                    var lu = new Label(); lu.Text = "Usuário"; lu.SetBounds(16, 50, 140, 22); lu.ForeColor = Theme.Muted; lu.TextAlign = ContentAlignment.MiddleLeft;
                    var cb = new ComboBox(); cb.DropDownStyle = ComboBoxStyle.DropDownList; cb.SetBounds(160, 50, 260, 24); cb.BackColor = Theme.Surface2; cb.ForeColor = Theme.Text; cb.FlatStyle = FlatStyle.Flat;
                    foreach (var x in lista.OrderBy(k => k.Nome)) cb.Items.Add(x.Nome + "  (" + x.Login + ")");
                    var ordenada = lista.OrderBy(k => k.Nome).ToList();
                    int pre = ordenada.FindIndex(x => x.Login.Equals(Users.Remembered(), StringComparison.OrdinalIgnoreCase));
                    if (pre < 0) pre = ordenada.FindIndex(x => ("," + x.Windows + ",").IndexOf("," + Environment.UserName + ",", StringComparison.OrdinalIgnoreCase) >= 0);
                    cb.SelectedIndex = Math.Max(0, pre);
                    f.Controls.Add(t); f.Controls.Add(lu); f.Controls.Add(cb);
                    var ts = Tb(f, "Senha", 84, "", true);
                    var ck = new CheckBox(); ck.Text = "Lembrar neste computador (não pedir de novo)"; ck.SetBounds(160, 116, 270, 24); ck.Checked = true; ck.ForeColor = Theme.Text; ck.FlatStyle = FlatStyle.Flat;
                    f.Controls.Add(ck);
                    var ok = Bt("Entrar", 240, 166, 86, true); var ca = Bt("Cancelar", 334, 166, 86, false); var nv = Bt("Novo usuário...", 16, 166, 120, false);
                    ok.DialogResult = DialogResult.OK; ca.DialogResult = DialogResult.Cancel; nv.DialogResult = DialogResult.Retry;
                    f.Controls.AddRange(new Control[] { ok, ca, nv }); f.AcceptButton = ok; f.CancelButton = ca;
                    f.Shown += (s, a) => ts.Focus();
                    var r = dono == null ? f.ShowDialog() : f.ShowDialog(dono);
                    if (r == DialogResult.Cancel) return false;
                    if (r == DialogResult.Retry)
                    {
                        var novo = Editar(dono, null);
                        if (novo != null) { Users.Current = novo; Users.Remember(novo.Login); return true; }
                        continue;
                    }
                    var u = ordenada[cb.SelectedIndex];
                    if (!Users.Check(u, ts.Text)) { MessageBox.Show(dono, "Senha errada.", "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Warning); continue; }
                    Users.Current = u;
                    Users.Remember(ck.Checked ? u.Login : "");
                    // guarda o usuário do Windows deste PC (para sugerir o nome na próxima vez)
                    if (("," + u.Windows + ",").IndexOf("," + Environment.UserName + ",", StringComparison.OrdinalIgnoreCase) < 0)
                    { u.Windows = (u.Windows.Length > 0 ? u.Windows + "," : "") + Environment.UserName; Users.Save(u); }
                    return true;
                }
            }
        }

        // cadastro (u == null) ou "meus dados"; devolve o usuário gravado ou null
        public static UserRec Editar(IWin32Window dono, UserRec u)
        {
            bool novo = u == null;
            using (var f = new Form())
            {
                f.Text = novo ? "Monitor - novo usuário" : "Monitor - meus dados"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterScreen;
                // meus dados: só apelido, legenda e e-mail (login e senha ficam em Opções › Configurações);
                // usuário novo: também a senha (o login é o próprio apelido)
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, novo ? 290 : 222); Theme.Style(f); f.TopMost = dono == null;
                var tn = Tb(f, "Nome (apelido)", 16, novo ? "" : u.Nome, false);
                var tc = Tb(f, "Nome na legenda", 50, novo ? "" : u.Carimbo, false);
                var te = Tb(f, "E-mail", 84, novo ? "" : u.Email, false);
                TextBox ts1 = null, ts2 = null;
                if (novo) { ts1 = Tb(f, "Senha", 118, "", true); ts2 = Tb(f, "Repetir a senha", 152, "", true); }
                int yn = novo ? 186 : 118;
                var n = new Label(); n.SetBounds(16, yn, 404, 50); n.ForeColor = Theme.Muted;
                n.Text = "\"Nome na legenda\" vai no campo Desenhista do detalhamento (ex.: G. Dias). O apelido aparece no Monitor (conferido por, marcações). O e-mail fica para avisos e conferências automáticas.";
                f.Controls.Add(n);
                var ok = Bt("Salvar", 240, yn + 58, 86, true); var ca = Bt("Cancelar", 334, yn + 58, 86, false);
                ca.DialogResult = DialogResult.Cancel; f.Controls.AddRange(new Control[] { ok, ca }); f.AcceptButton = ok; f.CancelButton = ca;
                UserRec res = null;
                ok.Click += (s, a) =>
                {
                    string nome = tn.Text.Trim();
                    if (nome.Length == 0) { MessageBox.Show(f, "Preencha o nome (apelido).", "Monitor"); return; }
                    if (novo && Users.Load().Any(x => x.Login.Equals(nome, StringComparison.OrdinalIgnoreCase) || x.Nome.Equals(nome, StringComparison.OrdinalIgnoreCase))) { MessageBox.Show(f, "Já existe um usuário com esse nome.", "Monitor"); return; }
                    if (novo && ts1.Text.Length < 4) { MessageBox.Show(f, "A senha precisa ter pelo menos 4 caracteres.", "Monitor"); return; }
                    if (novo && ts1.Text != ts2.Text) { MessageBox.Show(f, "As duas senhas não são iguais.", "Monitor"); return; }
                    var r = novo ? new UserRec() : u;
                    if (novo) { r.Login = nome; r.Windows = Environment.UserName; r.Sal = Users.NewSalt(); r.Hash = Users.HashOf(r.Sal, ts1.Text); }
                    r.Nome = nome; r.Carimbo = tc.Text.Trim(); r.Email = te.Text.Trim();
                    string err = Users.Save(r);
                    if (err != null) { MessageBox.Show(f, "Não gravou: " + err, "Monitor"); return; }
                    res = r; f.DialogResult = DialogResult.OK;
                };
                if ((dono == null ? f.ShowDialog() : f.ShowDialog(dono)) != DialogResult.OK) return null;
                return res;
            }
        }

        // Opções › Configurações › Alterar login e senha (pede a senha atual)
        public static UserRec AlterarLogin(IWin32Window dono, UserRec u)
        {
            using (var f = new Form())
            {
                f.Text = "Monitor - login e senha"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, 230); Theme.Style(f);
                var tl = Tb(f, "Login", 16, u.Login, false);
                var ta = Tb(f, "Senha atual", 50, "", true);
                var ts1 = Tb(f, "Nova senha", 84, "", true);
                var ts2 = Tb(f, "Repetir a nova senha", 118, "", true);
                var n = new Label(); n.SetBounds(16, 150, 404, 30); n.ForeColor = Theme.Muted; n.Text = "Deixe a nova senha em branco para trocar só o login.";
                f.Controls.Add(n);
                var ok = Bt("Salvar", 240, 186, 86, true); var ca = Bt("Cancelar", 334, 186, 86, false);
                ca.DialogResult = DialogResult.Cancel; f.Controls.AddRange(new Control[] { ok, ca }); f.AcceptButton = ok; f.CancelButton = ca;
                UserRec res = null;
                ok.Click += (s, a) =>
                {
                    string login = tl.Text.Trim();
                    if (login.Length == 0) { MessageBox.Show(f, "Preencha o login.", "Monitor"); return; }
                    if (!Users.Check(u, ta.Text)) { MessageBox.Show(f, "Senha atual errada.", "Monitor"); return; }
                    if (!login.Equals(u.Login, StringComparison.OrdinalIgnoreCase) && Users.Load().Any(x => x.Login.Equals(login, StringComparison.OrdinalIgnoreCase))) { MessageBox.Show(f, "Já existe um usuário com esse login.", "Monitor"); return; }
                    if (ts1.Text.Length > 0 && ts1.Text.Length < 4) { MessageBox.Show(f, "A senha precisa ter pelo menos 4 caracteres.", "Monitor"); return; }
                    if (ts1.Text != ts2.Text) { MessageBox.Show(f, "As duas senhas novas não são iguais.", "Monitor"); return; }
                    string antigo = u.Login;
                    var r = new UserRec { Login = login, Nome = u.Nome, Carimbo = u.Carimbo, Email = u.Email, Sal = u.Sal, Hash = u.Hash, Windows = u.Windows };
                    if (ts1.Text.Length > 0) { r.Sal = Users.NewSalt(); r.Hash = Users.HashOf(r.Sal, ts1.Text); }
                    string err = Users.Save(r, antigo);
                    if (err != null) { MessageBox.Show(f, "Não gravou: " + err, "Monitor"); return; }
                    if (Users.Remembered().Equals(antigo, StringComparison.OrdinalIgnoreCase)) Users.Remember(login);
                    res = r; f.DialogResult = DialogResult.OK;
                };
                if (f.ShowDialog(dono) != DialogResult.OK) return null;
                return res;
            }
        }
    }

    class DarkColors : ProfessionalColorTable
    {
        public override Color ToolStripGradientBegin { get { return Theme.Surface2; } }
        public override Color ToolStripGradientMiddle { get { return Theme.Surface2; } }
        public override Color ToolStripGradientEnd { get { return Theme.Surface2; } }
        public override Color ToolStripBorder { get { return Theme.Surface2; } }
        public override Color ToolStripDropDownBackground { get { return Theme.Surface2; } }
        public override Color MenuBorder { get { return Theme.Border; } }
        public override Color MenuItemBorder { get { return Theme.Hover; } }
        public override Color MenuItemSelected { get { return Theme.Hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Theme.Hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Theme.Hover; } }
        public override Color MenuItemPressedGradientBegin { get { return Theme.Sel; } }
        public override Color MenuItemPressedGradientEnd { get { return Theme.Sel; } }
        public override Color ImageMarginGradientBegin { get { return Theme.Surface2; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.Surface2; } }
        public override Color ImageMarginGradientEnd { get { return Theme.Surface2; } }
        public override Color ButtonSelectedBorder { get { return Theme.Hover; } }
        public override Color ButtonSelectedHighlight { get { return Theme.Hover; } }
        public override Color ButtonSelectedGradientBegin { get { return Theme.Hover; } }
        public override Color ButtonSelectedGradientMiddle { get { return Theme.Hover; } }
        public override Color ButtonSelectedGradientEnd { get { return Theme.Hover; } }
        public override Color ButtonPressedGradientBegin { get { return Theme.Sel; } }
        public override Color ButtonPressedGradientMiddle { get { return Theme.Sel; } }
        public override Color ButtonPressedGradientEnd { get { return Theme.Sel; } }
        public override Color ButtonCheckedGradientBegin { get { return Theme.Sel; } }
        public override Color ButtonCheckedGradientMiddle { get { return Theme.Sel; } }
        public override Color ButtonCheckedGradientEnd { get { return Theme.Sel; } }
        public override Color SeparatorDark { get { return Theme.Border; } }
        public override Color SeparatorLight { get { return Theme.Border; } }
        public override Color StatusStripGradientBegin { get { return Theme.Surface2; } }
        public override Color StatusStripGradientEnd { get { return Theme.Surface2; } }
    }

    class DarkRenderer : ToolStripProfessionalRenderer
    {
        public DarkRenderer() : base(new DarkColors()) { RoundedEdges = false; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (e.Item.Tag as string == "titulo") e.TextColor = Theme.Text;
            else if (e.Item is ToolStripLabel && !(e.Item is ToolStripStatusLabel)) e.TextColor = Theme.Muted;
            else e.TextColor = e.Item.ForeColor == SystemColors.ControlText ? Theme.Text : e.Item.ForeColor;
            base.OnRenderItemText(e);
        }
        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            if (e.ToolStrip is ToolStripDropDown) base.OnRenderToolStripBorder(e);
        }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = Theme.Muted;
            base.OnRenderArrow(e);
        }
    }

    // abas simples no tema escuro (o TabControl do Windows nao aceita fundo escuro)
    class DarkTabs : Panel
    {
        readonly ToolStrip strip = new ToolStrip();
        readonly Panel body = new Panel();
        readonly List<Control> pages = new List<Control>();
        readonly List<ToolStripButton> btns = new List<ToolStripButton>();
        int sel = -1;

        public DarkTabs()
        {
            Theme.Style(strip);
            strip.GripStyle = ToolStripGripStyle.Hidden;
            strip.Padding = new Padding(6, 3, 6, 3);
            strip.Dock = DockStyle.Top;
            body.Dock = DockStyle.Fill;
            body.BackColor = Theme.Surface;
            BackColor = Theme.Surface;
            Controls.Add(body);
            Controls.Add(strip);
        }

        public void AddPage(string title, Control c)
        {
            int idx = pages.Count;
            var b = new ToolStripButton(title);
            b.Padding = new Padding(8, 2, 8, 2);
            b.Click += (s, a) => SelectedIndex = idx;
            strip.Items.Add(b);
            btns.Add(b);
            c.Dock = DockStyle.Fill;
            c.Visible = false;
            body.Controls.Add(c);
            pages.Add(c);
            if (sel < 0) SelectedIndex = 0;
        }

        public int SelectedIndex
        {
            get { return sel; }
            set
            {
                if (value < 0 || value >= pages.Count) return;
                sel = value;
                for (int i = 0; i < pages.Count; i++)
                {
                    pages[i].Visible = i == sel;
                    btns[i].Checked = i == sel;
                    btns[i].ForeColor = i == sel ? Theme.Text : Theme.Muted;
                    btns[i].Font = i == sel ? Theme.UiBold : Theme.UiFont;
                }
            }
        }
    }

    static class Program
    {
        static string Arg(string[] args, string name)
        {
            foreach (var a in args)
                if (a.StartsWith(name + "=", StringComparison.OrdinalIgnoreCase)) return a.Substring(name.Length + 1).Trim('"');
            return null;
        }

        static bool IsNetworkPath(string path)
        {
            try
            {
                if (path.StartsWith(@"\\")) return true;
                var root = Path.GetPathRoot(path);
                return !string.IsNullOrEmpty(root) && new DriveInfo(root).DriveType == DriveType.Network;
            }
            catch { return false; }
        }

        // rodando da rede: copia o programa para o PC da pessoa e abre a copia (o .exe da rede fica livre para atualizar)
        internal static bool LaunchShadow(string exe, string[] args)
        {
            try
            {
                var bin = Path.Combine(Util.UserDir, "bin");
                Directory.CreateDirectory(bin);
                var stamp = File.GetLastWriteTime(exe).Ticks.ToString();
                var target = Path.Combine(bin, "Monitor_" + stamp + ".exe");
                if (!File.Exists(target)) File.Copy(exe, target, true);
                // copia fixa usada para abrir junto com o Windows (local: o Windows nao pergunta nada)
                try { File.Copy(target, Path.Combine(bin, "Monitor.exe"), true); } catch { }
                foreach (var old in Directory.GetFiles(bin, "Monitor_*.exe"))
                    if (!old.Equals(target, StringComparison.OrdinalIgnoreCase)) try { File.Delete(old); } catch { }
                var extra = string.Join(" ", args.Where(a => !a.StartsWith("/dados=", StringComparison.OrdinalIgnoreCase) && !a.StartsWith("/origem=", StringComparison.OrdinalIgnoreCase)).Select(a => "\"" + a + "\"").ToArray());
                var dir = Path.GetDirectoryName(exe);
                if (dir.EndsWith("\\")) dir += ".";
                var psi = new ProcessStartInfo(target, "\"/dados=" + dir + "\" \"/origem=" + exe + "\" " + extra);
                psi.UseShellExecute = false;
                psi.WorkingDirectory = bin;
                Process.Start(psi);
                return true;
            }
            catch { return false; }
        }

        [STAThread]
        static void Main(string[] args)
        {
            string exePath = Application.ExecutablePath;
            string dados = Arg(args, "/dados");
            if (dados == null && IsNetworkPath(exePath) && LaunchShadow(exePath, args)) return;
            Util.AppDir = dados ?? Path.GetDirectoryName(exePath);
            Util.Origin = Arg(args, "/origem");
            // aberto pela copia local fixa (ex.: ao iniciar o Windows) mas a versao da rede e outra: abre a versao certa
            if (Util.Origin != null && File.Exists(Util.Origin))
            {
                string expected = "Monitor_" + File.GetLastWriteTime(Util.Origin).Ticks + ".exe";
                if (!Path.GetFileName(exePath).Equals(expected, StringComparison.OrdinalIgnoreCase) && LaunchShadow(Util.Origin, args)) return;
            }
            MigrateUserData();
            bool created;
            // sempre uma única instância: quem abre por último fecha as outras (inclusive versões antigas ou travadas)
            bool replace = true;
            CloseOthers();
            using (var mtx = new Mutex(true, "MonitorSW_" + Environment.UserName, out created))
            {
                if (!created && replace)
                {
                    // a versao antiga ainda esta saindo: espera um pouco e tenta de novo
                    for (int i = 0; i < 20 && !created; i++) { Thread.Sleep(500); try { created = mtx.WaitOne(0); } catch (AbandonedMutexException) { created = true; } }
                }
                if (!created)
                {
                    MessageBox.Show("O Monitor já está aberto.\nProcure o ícone \"SW\" perto do relógio do Windows.", "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                // erro inesperado: não derruba o Monitor; grava os detalhes em erros.log (pasta do Monitor) para corrigir
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += (s, ev) =>
                {
                    try
                    {
                        string f = Path.Combine(Util.AppDir, "erros.log");
                        File.AppendAllText(f, DateTime.Now.ToString("dd/MM/yy HH:mm:ss") + " | " + Environment.MachineName + " | " + Users.Me + " | " +
                            Assembly.GetExecutingAssembly().GetName().Version + "\r\n" + ev.Exception + "\r\n\r\n", Encoding.UTF8);
                    }
                    catch { }
                    try { MessageBox.Show("Aconteceu um erro inesperado, mas o Monitor continua funcionando.\n\n" + ev.Exception.Message + "\n\n(Detalhes gravados em erros.log)", "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Warning); } catch { }
                };
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                string cfgPath = Path.Combine(Util.AppDir, "config.ini");
                string marker = Path.Combine(Util.UserDir, "primeiro_uso.txt");
                bool firstRun = !File.Exists(marker);
                if (firstRun) try { Directory.CreateDirectory(Util.UserDir); File.WriteAllText(marker, DateTime.Now.ToString()); } catch { }
                Config cfg;
                try { cfg = Config.Load(cfgPath); }
                catch (Exception ex)
                {
                    MessageBox.Show("Não foi possível ler config.ini:\n" + ex.Message, "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                // login: quem está usando (carimbo do desenho, "conferido por", e-mail para avisos)
                if (!LoginUi.Startup()) return;
                // tema é de cada usuário: se quem entrou usa outro tema (a tela de login abriu com o do último usuário), reabre com o dele
                if (Users.Current != null && Theme.EscuroDe(Users.Current.Login) != Theme.Escuro)
                {
                    try
                    {
                        Users.Remember(Users.Current.Login);
                        var psi = new ProcessStartInfo(Application.ExecutablePath, string.Join(" ", args.Select(x => "\"" + x + "\"")));
                        psi.UseShellExecute = false; psi.WorkingDirectory = Path.GetDirectoryName(Application.ExecutablePath);
                        Process.Start(psi);
                        return;
                    }
                    catch { }
                }
                if (firstRun || MainForm.IsAutoStart()) MainForm.SetAutoStart(true);
                bool startHidden = args.Any(a => a.Equals("/bandeja", StringComparison.OrdinalIgnoreCase));
                if (!cfg.RootFound && !startHidden)
                    MessageBox.Show("Não encontrei a pasta dos projetos (" + cfg.RootStored + ") neste computador.\n\n" +
                        "Confira se a unidade de rede do servidor está conectada (ex.: X:) e abra o Monitor de novo.\n" +
                        "Sem ela a lista de peças não abre.", "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                var engine = new Engine(cfg);
                var indexer = new Indexer(() => engine.Cfg);
                var form = new MainForm(engine, indexer);
                Application.Run(new TrayContext(form, !startHidden));
                GC.KeepAlive(mtx);
            }
        }

        // fecha as outras instancias do Monitor SW (usado na atualizacao)
        // estado das verificacoes passou a ficar na pasta do usuario: copia o que ja existia
        static void MigrateUserData()
        {
            try
            {
                var dst = Path.Combine(Util.UserDir, "estado");
                var src = Path.Combine(Util.AppDir, "estado");
                if (Directory.Exists(dst) || !Directory.Exists(src)) return;
                Directory.CreateDirectory(dst);
                foreach (var f in Directory.GetFiles(src, "*.tsv")) try { File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), false); } catch { }
            }
            catch { }
        }

        // fecha as outras instancias do Monitor SW deste usuario (usado na atualizacao)
        static void CloseOthers()
        {
            var cur = Process.GetCurrentProcess();
            Process[] ps;
            try { ps = Process.GetProcesses(); } catch { return; }
            foreach (var p in ps)
            {
                try
                {
                    if (p.Id == cur.Id || p.SessionId != cur.SessionId) continue;
                    var pn = p.ProcessName;
                    if (!(pn.Equals("Monitor", StringComparison.OrdinalIgnoreCase) || pn.StartsWith("Monitor_", StringComparison.OrdinalIgnoreCase) || pn.StartsWith("MonitorSW", StringComparison.OrdinalIgnoreCase))) continue;
                    p.Kill(); p.WaitForExit(5000);
                }
                catch { }
            }
        }
    }

    // janelinha de aviso no canto inferior direito
    class Toast : Form
    {
        public event Action Clicked;
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008; return cp; } // NOACTIVATE | TOOLWINDOW | TOPMOST
        }
        public Toast(string title, string text, bool warn, int ms)
        {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
            BackColor = Theme.Surface2; ForeColor = Theme.Text; Width = 380; Padding = new Padding(14, 10, 12, 10);
            var bar = new Panel { Dock = DockStyle.Left, Width = 5, BackColor = warn ? Theme.WarnText : Theme.Accent };
            var t = new Label { Text = title, Dock = DockStyle.Top, Height = 24, Font = new Font(Theme.UiFont, FontStyle.Bold), ForeColor = warn ? Theme.WarnText : Theme.Text, AutoEllipsis = true };
            var b = new Label { Text = text, Dock = DockStyle.Fill, Font = Theme.UiFont, ForeColor = Theme.Text };
            var x = new Label { Text = "✕", Dock = DockStyle.Right, Width = 20, ForeColor = Theme.Muted, Cursor = Cursors.Hand, TextAlign = ContentAlignment.TopRight };
            x.Click += (s, a) => Close();
            using (var g = CreateGraphics())
            {
                var sz = g.MeasureString(text ?? "", Theme.UiFont, Width - 50);
                Height = Math.Min(260, Math.Max(78, (int)sz.Height + 50));
            }
            Controls.Add(b); Controls.Add(t); Controls.Add(x); Controls.Add(bar);
            foreach (Control c in new Control[] { this, t, b }) { c.Cursor = Cursors.Hand; c.Click += (s, a) => { var h = Clicked; Close(); if (h != null) h(); }; }
            Paint += (s, a) => { using (var p = new Pen(Theme.Border)) a.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1); };
            timer.Interval = ms; timer.Tick += (s, a) => { timer.Stop(); Close(); };
        }
        public void ShowNoFocus()
        {
            var wa = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(wa.Right - Width - 12, wa.Bottom - Height - 12);
            Show();
            timer.Start();
            try { System.Media.SystemSounds.Asterisk.Play(); } catch { }
        }
        protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
    }

    class TrayContext : ApplicationContext
    {
        public TrayContext(MainForm form, bool show)
        {
            var h = form.Handle;
            form.StartEngine();
            if (show) form.ShowWindow();
        }
    }

    class NodeTag
    {
        public string Id, Key;
        public bool HasKids, Open;
    }

    public class MainForm : Form
    {
        readonly Engine engine;
        readonly Indexer indexer;
        readonly ToolStripStatusLabel lblIndex = new ToolStripStatusLabel();
        readonly NotifyIcon tray = new NotifyIcon();
        readonly ListView projList = new ListView();
        readonly DataGridView grid = new DataGridView();
        readonly TextBox whereBox = new TextBox();
        readonly ListView histList = new ListView();
        readonly ToolStripComboBox filter = new ToolStripComboBox();
        readonly ToolStripTextBox search = new ToolStripTextBox();
        readonly ToolStripStatusLabel lblStatus = new ToolStripStatusLabel();
        readonly ToolStripLabel lblUser = new ToolStripLabel();
        readonly ToolStripStatusLabel lblCounts = new ToolStripStatusLabel();
        readonly ToolStripMenuItem miAuto = new ToolStripMenuItem("Iniciar com o Windows");
        readonly DarkTabs tabs = new DarkTabs();
        readonly Button detailBar = new Button();
        readonly CheckBox chkServer = new CheckBox();
        readonly CheckBox chkConf = new CheckBox();
        readonly System.Windows.Forms.Timer srvTimer = new System.Windows.Forms.Timer();
        readonly DataGridView srvGrid = new DataGridView();
        readonly ContextMenuStrip projMenu = new ContextMenuStrip();
        SplitContainer rightSplit;
        readonly ToolStripMenuItem miCheck = new ToolStripMenuItem("Conferir se PDF/DXF estão atualizados");
        readonly ToolStripStatusLabel lgPend = new ToolStripStatusLabel();
        readonly ToolStripStatusLabel lblPendN = new ToolStripStatusLabel();
        readonly ToolStripStatusLabel lblOkN = new ToolStripStatusLabel();
        readonly System.Windows.Forms.Timer updTimer = new System.Windows.Forms.Timer();
        DateTime updTried = DateTime.MinValue;
        bool exiting, hintShown;
        Ev lastBalloon;
        Icon icoOk, icoPend;
        int sortCol = -1;
        SortOrder sortDir = SortOrder.None;
        Project current;
        readonly Dictionary<Project, HashSet<string>> collapsed = new Dictionary<Project, HashSet<string>>();

        static readonly Color Purple = Theme.Purple;
        static readonly Color PurpleBg = Theme.PurpleBg;
        static readonly Color RedBg = Theme.PendRow;
        static readonly Color OrangeBg = Theme.MissRow;
        static readonly Color AsmBg = Theme.AsmRow;

        // colunas (montadas conforme ColunasLista do config.ini)
        int C_TOG, C_NUM, C_ITEM, C_DESC, C_QTD = -1, C_NEED, C_SIT, C_DES, C_PDF, C_DXF, C_APR, C_BLQ, C_WHO, C_MOD, C_DRW, C_PDFD, C_DXFD, C_DIR;
        readonly Dictionary<int, string> propCols = new Dictionary<int, string>();
        readonly List<string> procCols = new List<string>();
        int C_ACAB = -1;
        readonly FlowLayoutPanel procPanel = new FlowLayoutPanel();
        readonly ContextMenuStrip cellMenu = new ContextMenuStrip();

        public MainForm(Engine e, Indexer ix)
        {
            engine = e;
            indexer = ix;
            Text = "Monitor";
            Theme.Style(this);
            Size = new Size(1400, 850);
            WindowState = FormWindowState.Maximized;
            if (Util.Origin != null) try { originStamp = File.GetLastWriteTime(Util.Origin); } catch { }
            StartPosition = FormStartPosition.CenterScreen;
            icoOk = MakeIcon(Color.FromArgb(46, 140, 70));
            icoPend = MakeIcon(Color.FromArgb(200, 45, 45));
            Icon = icoOk;
            BuildUi();
            BuildTray();
            LoadHistory();
            engine.Updated += OnEngineUpdated;
            engine.Progress += OnEngineProgress;
        }

        public void StartEngine()
        {
            RefreshAll();
            engine.Start();
            indexer.Progress += s => { if (IsHandleCreated) BeginInvoke(new Action(() => { lblIndex.ToolTipText = s; lblIndex.Text = ShortIndex(s); })); };
            updTimer.Interval = 20000; updTimer.Tick += (s, a) => { bool vis = Visible; if (updBusy) return; updBusy = true; System.Threading.ThreadPool.QueueUserWorkItem(_ => { try { formVisible = vis; CheckSelfUpdate(); } finally { updBusy = false; } }); }; updTimer.Start();
            indexer.Start();
        }

        // opções do Filtro -> modo interno da lista
        // 0 BOM completa, 10 comerciais, 2 todas as pendências, 11/12/13 pendências laser/usinagem/submontagens,
        // 4 fabricadas, 6 exceções, 7 pendente, 8 revisado
        static readonly int[] FilterModes = { 0, 10, 2, 11, 12, 13, 6, 7, 8 };
        int Mode { get { int i = filter.SelectedIndex; return i >= 0 && i < FilterModes.Length ? FilterModes[i] : 0; } }
        bool TreeMode { get { return Mode <= 2; } }

        // ------------------------------------------------------------ montagem da tela
        void BuildUi()
        {
            var ts = new ToolStrip();
            Theme.Style(ts);
            ts.GripStyle = ToolStripGripStyle.Hidden;
            ts.Padding = new Padding(10, 6, 10, 6);
            // ---- barra principal: só o que se usa o tempo todo
            ts.Items.Add(new ToolStripLabel("Buscar:"));
            search.Width = 190;
            search.BorderStyle = BorderStyle.FixedSingle;
            search.BackColor = Theme.Surface;
            search.ForeColor = Theme.Text;
            search.ToolTipText = "Procura por código ou descrição na BOM";
            search.TextChanged += (s, a) => { if (chkServer.Checked) { srvTimer.Stop(); srvTimer.Start(); } else FillGrid(); };
            search.KeyDown += (s, a) => { if (a.KeyCode == Keys.Enter) { a.SuppressKeyPress = true; srvTimer.Stop(); ApplySearchMode(); } else if (a.KeyCode == Keys.Escape) { a.SuppressKeyPress = true; ClearSearch(); } };
            ts.Items.Add(search);
            var clr = Btn("✕", (s, a) => ClearSearch());
            clr.ToolTipText = "Limpar a busca e voltar à lista normal";
            ts.Items.Add(clr);
            chkServer.Text = "Todo o servidor";
            chkServer.ForeColor = Theme.Text;
            chkServer.BackColor = Color.Transparent;
            chkServer.Font = Theme.UiFont;
            chkServer.AutoSize = true;
            chkServer.Margin = new Padding(6, 3, 0, 0);
            chkServer.CheckedChanged += (s, a) => { search.ToolTipText = chkServer.Checked ? "Procura em TODAS as máquinas do servidor (índice)" : "Procura só na montagem aberta à esquerda"; ApplySearchMode(); };
            var chkHost = new ToolStripControlHost(chkServer);
            chkHost.ToolTipText = "Marcado: procura em todas as máquinas do servidor. Desmarcado: só no projeto aberto à esquerda";
            ts.Items.Add(chkHost);
            srvTimer.Interval = 600;
            srvTimer.Tick += (s, a) => { srvTimer.Stop(); ApplySearchMode(); };
            ts.Items.Add(new ToolStripSeparator());
            ts.Items.Add(Btn("Abrir modelo", (s, a) => OpenSel(0)));
            ts.Items.Add(Btn("Abrir detalhamento", (s, a) => OpenSel(1)));
            ts.Items.Add(Btn("PDF", (s, a) => OpenSel(2)));
            ts.Items.Add(Btn("DXF", (s, a) => OpenSel(4)));
            ts.Items.Add(new ToolStripSeparator());
            var gen = Btn("Gerar detalhamento", (s, a) => GenerateDetail());
            gen.ForeColor = Theme.Accent;
            ts.Items.Add(gen);
            ts.Items.Add(new ToolStripSeparator { Margin = new Padding(14, 0, 6, 0) });
            var upd = Btn("⟳  Atualizar lista", (s, a) => ForceRefreshList());
            upd.ToolTipText = "Confere de novo agora se cada item tem desenho, PDF e DXF (F5)";
            ts.Items.Add(upd);
            // liga/desliga mostrar a conferência (desatualizados) na lista; o resultado da conferência fica guardado
            chkConf.Text = "Mostrar conferência";
            chkConf.ForeColor = Theme.WarnText;
            chkConf.BackColor = Color.Transparent;
            chkConf.Font = Theme.UiFont;
            chkConf.AutoSize = true;
            chkConf.Margin = new Padding(8, 3, 0, 0);
            chkConf.CheckedChanged += (s, a) => { if (miCheck.Checked != chkConf.Checked) miCheck.Checked = chkConf.Checked; };
            var confHost = new ToolStripControlHost(chkConf);
            confHost.ToolTipText = "Marcado: mostra também o que está desatualizado (PDF/DXF antigos, divergências da Conferência). Desmarcado: só se tem ou não tem detalhamento";
            ts.Items.Add(confHost);
            var conf = Btn("✔  Conferência", (s, a) => ConferirProjeto());
            conf.ForeColor = Theme.WarnText;
            conf.ToolTipText = "Confere a montagem aberta: datas de 3D/desenho/PDF/DXF, carimbo do PDF e descrição/escala do DXF";
            ts.Items.Add(conf);
            var mail = Btn("✉  E-mail", (s, a) => GerarEmail());
            mail.ToolTipText = "E-mail de alteração de cadastro: o que SAIU e o que ENTROU nas montagens entre duas datas";
            // ts.Items.Add(mail);   // botão E-mail desligado por enquanto (não está sendo usado)

            // filtro de visualização (fica no menu Ferramentas)
            filter.DropDownStyle = ComboBoxStyle.DropDownList;
            filter.Items.AddRange(new object[] {
                "LISTA DE PEÇAS (BOM completa)",
                "LISTA DE PEÇAS (Comercial)",
                "Todas as pendências",
                "Pendências LASER",
                "Pendências USINAGEM",
                "Pendências SUBMONTAGENS",
                "Exceções (roxo - não precisam detalhamento)",
                "Marcados para revisão (pendente)",
                "Marcados como revisado" });
            filter.SelectedIndex = 0;
            filter.SelectedIndexChanged += (s, a) => { ApplySortMode(); FillGrid(); };

            // ---- menu Ferramentas (lado direito)
            var toolsMenu = new ContextMenuStrip();
            var tools = new ToolStripButton("Opções  ▾");
            tools.Alignment = ToolStripItemAlignment.Right;
            tools.Click += (s, a) => toolsMenu.Show(ts, new Point(Math.Max(0, tools.Bounds.Right - toolsMenu.Width), tools.Bounds.Bottom));

            var mProj = new ToolStripMenuItem("Projeto");
            mProj.DropDownItems.Add(Mi("Abrir projeto...", (s, a) => AddProject()));
            mProj.DropDownItems.Add(Mi("Fechar projeto", (s, a) => RemoveProject()));
            mProj.DropDownItems.Add(Mi("Verificar agora", (s, a) => engine.Kick()));
            toolsMenu.Items.Add(mProj);

            var viewMenu = new ContextMenuStrip();
            var viewItems = new List<ToolStripMenuItem>();
            for (int i = 0; i < filter.Items.Count; i++)
            {
                int idx = i;
                var vi = Mi(filter.Items[i].ToString(), (s, a) => { filter.SelectedIndex = idx; });
                vi.Checked = i == 0;
                viewItems.Add(vi);
                if (i == 2 || i == 6) viewMenu.Items.Add(new ToolStripSeparator());
                viewMenu.Items.Add(vi);
            }
            filter.SelectedIndexChanged += (s, a) => { for (int i = 0; i < viewItems.Count; i++) viewItems[i].Checked = i == filter.SelectedIndex; };
            DarkMenus(viewMenu);
            if (viewItems.Count > 8) { viewItems[6].ForeColor = Purple; viewItems[7].ForeColor = Theme.WarnText; viewItems[8].ForeColor = Theme.OkText; }   // exceção roxo, pendente laranja, revisado verde
            var filterBtn = new ToolStripButton("Filtro");
            filterBtn.Image = FunnelIcon(Theme.Text);
            filterBtn.DisplayStyle = ToolStripItemDisplayStyle.ImageAndText;
            filterBtn.TextImageRelation = TextImageRelation.ImageBeforeText;
            filterBtn.Alignment = ToolStripItemAlignment.Right;
            filterBtn.ToolTipText = "Visualização: " + filter.Items[0];
            filterBtn.Click += (s, a) => viewMenu.Show(ts, new Point(Math.Max(0, filterBtn.Bounds.Right - viewMenu.Width), filterBtn.Bounds.Bottom));
            filter.SelectedIndexChanged += (s, a) =>
            {
                bool on = filter.SelectedIndex != 0;
                filterBtn.ToolTipText = "Visualização: " + filter.SelectedItem;
                filterBtn.ForeColor = on ? Theme.Accent : Theme.Text;
                filterBtn.Image = FunnelIcon(on ? Theme.Accent : Theme.Text);
                filterBtn.Text = on ? "Filtro •" : "Filtro";
            };

            var mOpen = new ToolStripMenuItem("Abrir");
            mOpen.DropDownItems.Add(Mi("Modelo (peça/montagem)", (s, a) => OpenSel(0)));
            mOpen.DropDownItems.Add(Mi("Pasta no Explorer", (s, a) => OpenSel(3)));
            toolsMenu.Items.Add(mOpen);

            var mCheck = new ToolStripMenuItem("Conferência");
            miCheck.CheckOnClick = true;
            miCheck.CheckedChanged += (s, a) => { if (chkConf.Checked != miCheck.Checked) chkConf.Checked = miCheck.Checked; SetCheckMode(miCheck.Checked); };
            mCheck.DropDownItems.Add(miCheck);
            toolsMenu.Items.Add(mCheck);

            toolsMenu.Items.Add(Mi("Exportar LISTA DE PEÇAS (Excel)", (s, a) => Export()));
            toolsMenu.Items.Add(Mi("Histórico geral de alterações...", (s, a) => HistoricoGeral()));

            var mIdx = new ToolStripMenuItem("Índice de todas as máquinas");
            mIdx.DropDownItems.Add(Mi("Atualizar índice agora", (s, a) => indexer.Kick()));
            mIdx.DropDownItems.Add(Mi("Abrir pasta do índice", (s, a) => { try { Directory.CreateDirectory(indexer.Dir); Process.Start("explorer.exe", "\"" + indexer.Dir + "\""); } catch { } }));
            toolsMenu.Items.Add(mIdx);

            toolsMenu.Items.Add(new ToolStripSeparator());
            var mUser = new ToolStripMenuItem("Usuário: " + Users.Me);
            Action atualizaUser = () => { mUser.Text = "Usuário: " + Users.Me; lblUser.Text = "👤  " + Users.Me; };
            mUser.DropDownItems.Add(Mi("Meus dados (nome, legenda, e-mail)...", (s, a) =>
            {
                if (Users.Current == null) return;
                var r = LoginUi.Editar(this, Users.Current);
                if (r != null) { Users.Current = r; atualizaUser(); lblStatus.Text = "Dados de " + r.Nome + " gravados."; }
            }));
            mUser.DropDownItems.Add(Mi("Trocar usuário...", (s, a) =>
            {
                if (LoginUi.Escolher(this))
                {
                    atualizaUser(); lblStatus.Text = "Usando como " + Users.Me + ".";
                    // cada usuário tem o seu tema: se o novo usuário usa outro, reabre já com o tema dele
                    if (Theme.EscuroDe(Users.Current.Login) != Theme.Escuro) { Users.Remember(Users.Current.Login); Reiniciar(); }
                }
            }));
            toolsMenu.Items.Add(mUser);
            toolsMenu.Items.Add(Mi("Notificações...", (s, a) => { Notificacoes.Editar(this); var np = Notificacoes.Minha(); lblStatus.Text = np.Todos ? "Notificações: de todos os usuários." : "Notificações: de " + np.Logins.Count + " usuário(s) escolhido(s)."; }));
            toolsMenu.Items.Add(Mi("Testar aviso", (s, a) => Aviso(8000, "Teste de aviso", "Se você está vendo isto, os avisos do Monitor funcionam neste PC (" + Users.Me + ").", ToolTipIcon.Info)));
            var mCfg = new ToolStripMenuItem("Configurações");
            mCfg.DropDownItems.Add(Mi("Configurações do Monitor...", (s, a) => OpenConfig()));
            mCfg.DropDownItems.Add(Mi("Alterar login e senha...", (s, a) =>
            {
                if (Users.Current == null) return;
                var r = LoginUi.AlterarLogin(this, Users.Current);
                if (r != null) { Users.Current = r; atualizaUser(); lblStatus.Text = "Login e senha de " + r.Nome + " gravados."; }
            }));
            toolsMenu.Items.Add(mCfg);
            var mTema = new ToolStripMenuItem("Tema");
            var miEscuro = Mi("Escuro", (s, a) => TrocarTema(true));
            var miClaro = Mi("Claro", (s, a) => TrocarTema(false));
            miEscuro.Checked = Theme.Escuro; miClaro.Checked = !Theme.Escuro;
            mTema.DropDownItems.Add(miEscuro);
            mTema.DropDownItems.Add(miClaro);
            toolsMenu.Items.Add(mTema);
            DarkMenus(toolsMenu);
            ts.Items.Add(tools);
            ts.Items.Add(filterBtn);
            // apelido de quem está usando o Monitor (clique = meus dados)
            lblUser.Text = "👤  " + Users.Me;
            lblUser.Alignment = ToolStripItemAlignment.Right;
            lblUser.ForeColor = Theme.Accent;
            lblUser.ToolTipText = "Usuário do Monitor (vai no \"conferido por\" e nas marcações). Clique para ver seus dados.";
            lblUser.Margin = new Padding(0, 0, 10, 0);
            lblUser.Click += (s, a) => { if (Users.Current == null) return; var r = LoginUi.Editar(this, Users.Current); if (r != null) { Users.Current = r; atualizaUser(); } };
            ts.Items.Add(lblUser);

            var ss = new StatusStrip();
            Theme.Style(ss);
            ss.SizingGrip = false;
            ss.Padding = new Padding(10, 3, 10, 3);
            // rodape minimalista: pendentes / ok do projeto aberto · mensagens · índice
            lblPendN.ForeColor = Theme.WarnText;
            lblPendN.ToolTipText = "Itens sem detalhamento (falta PDF/DXF).\nLaser = PDF + DXF · Usinagem = PDF · Solda = PDF";
            lblOkN.ForeColor = Theme.OkText;
            lblOkN.ToolTipText = "Itens com detalhamento";
            lblOkN.Margin = new Padding(14, 0, 0, 0);
            lblCounts.ForeColor = Theme.Muted;
            lblCounts.Margin = new Padding(14, 0, 0, 0);
            lblStatus.ForeColor = Theme.Muted;
            lblStatus.Spring = true;
            lblStatus.TextAlign = ContentAlignment.MiddleRight;
            lblIndex.ForeColor = Theme.Muted;
            lblIndex.Text = "índice: aguardando";
            lblIndex.Margin = new Padding(14, 0, 0, 0);
            lgPend.Visible = false;
            ss.Items.Add(lblPendN);
            ss.Items.Add(lblOkN);
            ss.Items.Add(lblCounts);
            ss.Items.Add(lblStatus);
            ss.Items.Add(lblIndex);

            projList.View = View.Details;
            projList.FullRowSelect = true;
            projList.HideSelection = false;
            projList.MultiSelect = false;
            projList.ShowItemToolTips = true;
            projList.Columns.Add("Projetos", 280);
            projList.HeaderStyle = ColumnHeaderStyle.None;
            projList.Dock = DockStyle.Fill;
            Theme.Style(projList);
            projList.Resize += (s, a) => { int w = projList.ClientSize.Width - 4; if (w > 80) projList.Columns[0].Width = w; };
            projList.SelectedIndexChanged += (s, a) =>
            {
                if (projList.SelectedItems.Count == 0) return;
                var novo = projList.SelectedItems[0].Tag as Project;
                bool trocou = novo != null && novo != current;
                current = novo;
                // trocou de montagem: a busca anterior (ou "Todo o servidor") escondia os itens da montagem nova
                if (trocou && search.Text.Trim().Length > 0) { srvTimer.Stop(); search.Text = ""; ApplySearchMode(); }
                else FillGrid();
                if (current != null) ShowPreview(current.MainPath, current.Name);
            };

            grid.Dock = DockStyle.Fill;
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToResizeRows = false;
            grid.RowHeadersVisible = false;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.MultiSelect = true;   // Ctrl / Shift selecionam vários itens (conferido / pendente / exceção em lote)
            grid.BackgroundColor = Theme.Surface;
            grid.BorderStyle = BorderStyle.None;
            grid.RowTemplate.Height = 26;
            grid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            grid.GridColor = Theme.Border;
            grid.EnableHeadersVisualStyles = false;
            grid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
            grid.ColumnHeadersDefaultCellStyle.BackColor = Theme.Surface2;
            grid.ColumnHeadersDefaultCellStyle.ForeColor = Theme.Muted;
            grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = Theme.Surface2;
            grid.ColumnHeadersDefaultCellStyle.SelectionForeColor = Theme.Muted;
            grid.ColumnHeadersDefaultCellStyle.Font = Theme.UiBold;
            grid.ColumnHeadersDefaultCellStyle.Padding = new Padding(4, 6, 4, 6);
            grid.DefaultCellStyle.BackColor = Theme.Surface;
            grid.DefaultCellStyle.ForeColor = Theme.Text;
            grid.DefaultCellStyle.SelectionBackColor = Theme.Sel;
            grid.DefaultCellStyle.SelectionForeColor = Theme.SelText;
            grid.DefaultCellStyle.Padding = new Padding(4, 0, 4, 0);
            grid.DefaultCellStyle.Font = Theme.UiFont;
            Theme.DarkScroll(grid);
            grid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            typeof(DataGridView).GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(grid, true, null);
            C_TOG = AddCol("", 28, typeof(string));
            C_NUM = AddCol("Nº DO ITEM", 70, typeof(string));
            C_ITEM = AddCol("Nº DA PEÇA", 300, typeof(string));
            C_DESC = AddCol("DESCRIÇÃO", 230, typeof(string));
            foreach (var pc in engine.Cfg.ListCols)
            {
                string up = pc.ToUpperInvariant();
                if (up == "QDT." || up == "QDT" || up == "QTD" || up == "QTD.") { C_QTD = AddCol("QDT.", 45, typeof(int)); continue; }
                if (up != "ACABAMENTO") { procCols.Add(pc); continue; } // processos vão para a aba Processos
                int w = up.Length <= 6 ? 55 : up.Length <= 10 ? 75 : 95;
                if (up == "ACABAMENTO") { w = 130; C_ACAB = grid.Columns.Count; }
                int ci = AddCol(up, w, typeof(string));
                propCols[ci] = pc;
                grid.Columns[ci].DefaultCellStyle.Alignment = up == "ACABAMENTO" ? DataGridViewContentAlignment.MiddleLeft : DataGridViewContentAlignment.MiddleCenter;
            }
            if (C_QTD < 0) C_QTD = AddCol("QDT.", 45, typeof(int));
            C_NEED = AddCol("EXIGE", 120, typeof(string));
            grid.Columns[C_NEED].Visible = false; // agora fica na aba Processos, colorido
            C_SIT = AddCol("SITUAÇÃO", 210, typeof(string));
            C_DES = AddCol("DESENHO", 90, typeof(string)); // tem ou não tem o .SLDDRW
            C_PDF = AddCol("PDF", 100, typeof(string));
            C_DXF = AddCol("DXF", 100, typeof(string));
            C_APR = AddCol("APROV.", 55, typeof(string));
            C_BLQ = AddCol("BLOQ.", 50, typeof(string));
            C_WHO = AddCol("SALVO POR", 85, typeof(string));
            C_MOD = AddCol("MODELO SALVO", 100, typeof(DateTime));
            C_DRW = AddCol("DESENHO SALVO", 100, typeof(DateTime));
            C_PDFD = AddCol("PDF GERADO", 100, typeof(DateTime));
            C_DXFD = AddCol("DXF GERADO", 100, typeof(DateTime));
            C_DIR = AddCol("PASTA", 230, typeof(string));
            grid.Columns[C_NUM].DefaultCellStyle.Font = Theme.UiBold;
            grid.Columns[C_NUM].DefaultCellStyle.ForeColor = Theme.Muted;
            grid.Columns[C_NUM].Frozen = true;
            grid.Columns[C_TOG].DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleCenter;
            grid.Columns[C_TOG].DefaultCellStyle.Font = new Font("Segoe UI", 8f);
            grid.Columns[C_TOG].DefaultCellStyle.Padding = new Padding(0);
            grid.Columns[C_TOG].Frozen = true;
            grid.Columns[C_ITEM].Frozen = true;
            grid.SortCompare += GridSortCompare;
            grid.CellMouseUp += (s, a) => GridRightClick(a);
            grid.Resize += (s, a) => FitColumns();
            grid.CellPainting += PaintTreeGuides;
            grid.ColumnHeaderMouseClick += (s, a) => { sortCol = a.ColumnIndex; sortDir = grid.SortOrder; };
            grid.SelectionChanged += (s, a) => { if (fillingGrid) return; ShowDetail(); var it = SelItem(); ShowPreview(it != null ? it.Path : null, it != null ? it.Name : null); };
            grid.CellClick += (s, a) => { if (a.RowIndex >= 0 && a.ColumnIndex == C_TOG) Toggle(a.RowIndex); };
            grid.CellDoubleClick += (s, a) =>
            {
                if (a.RowIndex < 0 || a.ColumnIndex == C_TOG) return;
                var t = grid.Rows[a.RowIndex].Tag as NodeTag;
                if (TreeMode && t != null && t.HasKids && a.ColumnIndex == C_ITEM) Toggle(a.RowIndex); else OpenSel(1);
            };
            grid.KeyDown += (s, a) =>
            {
                if (grid.CurrentRow == null || !TreeMode) return;
                var t = grid.CurrentRow.Tag as NodeTag;
                if (t == null || !t.HasKids) return;
                bool isOpen = t.Open;
                if ((a.KeyCode == Keys.Right && !isOpen) || (a.KeyCode == Keys.Left && isOpen)) { Toggle(grid.CurrentRow.Index); a.Handled = true; }
            };
            ApplySortMode();

            whereBox.Multiline = true;
            whereBox.ReadOnly = true;
            whereBox.ScrollBars = ScrollBars.Both;
            whereBox.WordWrap = false;
            whereBox.Font = new Font("Consolas", 9.5f);
            whereBox.BackColor = Theme.Surface;
            whereBox.ForeColor = Theme.Text;
            whereBox.BorderStyle = BorderStyle.None;
            whereBox.Dock = DockStyle.Fill;
            Theme.DarkScroll(whereBox);

            histList.View = View.Details;
            histList.FullRowSelect = true;
            histList.Dock = DockStyle.Fill;
            Theme.Style(histList);
            histList.Columns.Add("Data", 120);
            histList.Columns.Add("Projeto", 150);
            histList.Columns.Add("Item", 140);
            histList.Columns.Add("Evento", 230);
            histList.Columns.Add("Salvo por", 90);
            histList.Columns.Add("Detalhe", 700);
            histList.DoubleClick += (s, a) => { if (histList.SelectedItems.Count > 0) GoTo(histList.SelectedItems[0].SubItems[1].Text, histList.SelectedItems[0].SubItems[2].Text); };

            var wherePad = new Panel(); wherePad.BackColor = Theme.Surface; wherePad.Padding = new Padding(12, 8, 8, 4); wherePad.Controls.Add(whereBox);
            procPanel.Dock = DockStyle.Top;
            procPanel.Height = 122;
            procPanel.AutoScroll = true;
            procPanel.BackColor = Theme.Surface;
            procPanel.WrapContents = true;
            procPanel.Padding = new Padding(0, 0, 0, 6);
            wherePad.Controls.Add(procPanel);
            tabs.AddPage("Processos", wherePad);
            tabs.AddPage("Histórico de alterações", histList);
            tabs.Dock = DockStyle.Fill;

            var right = new SplitContainer();
            right.Dock = DockStyle.Fill;
            right.Orientation = Orientation.Horizontal;
            right.Panel1.Controls.Add(grid);
            BuildServerGrid();
            right.Panel1.Controls.Add(srvGrid);
            right.Panel2.Controls.Add(tabs);
            Theme.Style(right);

            // barra inferior: clica para mostrar/ocultar detalhes e histórico (começa oculto)
            detailBar.Dock = DockStyle.Bottom;
            detailBar.Height = 28;
            detailBar.FlatStyle = FlatStyle.Flat;
            detailBar.FlatAppearance.BorderSize = 0;
            detailBar.FlatAppearance.MouseOverBackColor = Theme.Sel;
            detailBar.BackColor = Theme.Surface2;
            detailBar.ForeColor = Theme.Muted;
            detailBar.Font = Theme.UiFont;
            detailBar.TextAlign = ContentAlignment.MiddleLeft;
            detailBar.Padding = new Padding(10, 0, 0, 0);
            detailBar.Cursor = Cursors.Hand;
            detailBar.TabStop = false;
            detailBar.Click += (s, a) => SetDetailOpen(right.Panel2Collapsed);
            rightSplit = right;
            var rightHost = new Panel();
            rightHost.Dock = DockStyle.Fill;
            rightHost.Controls.Add(right);
            rightHost.Controls.Add(detailBar);

            var main = new SplitContainer();
            main.Dock = DockStyle.Fill;
            var pbar = new ToolStrip();
            Theme.Style(pbar);
            pbar.GripStyle = ToolStripGripStyle.Hidden;
            pbar.Padding = new Padding(4, 2, 4, 2);
            pbar.Dock = DockStyle.Top;
            pbar.Items.Add(Btn("+ Abrir projeto", (s, a) => AddProject()));
            pbar.Items.Add(Btn("Fechar", (s, a) => RemoveProject()));
            pbar.Items.Add(Btn("Verificar", (s, a) => engine.Kick()));
            projMenu.Items.Add(Mi("Abrir projeto (adicionar montagem)...", (s, a) => AddProject()));
            projMenu.Items.Add(Mi("Fechar projeto", (s, a) => RemoveProject()));
            projMenu.Items.Add(new ToolStripSeparator());
            projMenu.Items.Add(Mi("Abrir montagem no SolidWorks", (s, a) => OpenProjectFile(false)));
            projMenu.Items.Add(Mi("Abrir pasta do projeto", (s, a) => OpenProjectFile(true)));
            projMenu.Items.Add(Mi("Verificar agora", (s, a) => engine.Kick()));
            projMenu.Items.Add(Mi("Exportar LISTA DE PEÇAS (Excel)", (s, a) => Export()));
            DarkMenus(projMenu);
            projList.MouseUp += (s, a) =>
            {
                if (a.Button != MouseButtons.Right) return;
                var hit = projList.HitTest(a.Location);
                if (hit.Item != null) hit.Item.Selected = true;
                bool has = projList.SelectedItems.Count > 0;
                for (int i = 1; i < projMenu.Items.Count; i++) projMenu.Items[i].Enabled = has;
                projMenu.Show(projList, a.Location);
            };
            // miniatura da peça/montagem selecionada (embaixo da lista de projetos)
            BuildPreview();
            var leftSplit = new SplitContainer();
            leftSplit.Dock = DockStyle.Fill;
            leftSplit.Orientation = Orientation.Horizontal;
            leftSplit.Panel1.Controls.Add(projList);
            leftSplit.Panel2.Controls.Add(prevHost);
            leftSplit.FixedPanel = FixedPanel.Panel2;
            Theme.Style(leftSplit);
            Load += (s, a) => { try { leftSplit.SplitterDistance = Math.Max(120, leftSplit.Height - 300); } catch { } };
            main.Panel1.Controls.Add(leftSplit);
            main.Panel1.Controls.Add(pbar);
            main.Panel2.Controls.Add(rightHost);
            Theme.Style(main);

            Controls.Add(main);
            Controls.Add(ts);
            Controls.Add(ss);
            Load += (s, a) => { main.SplitterDistance = 300; SetDetailOpen(false); };
        }

        static string ShortIndex(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            int i = s.IndexOf("atualizado ", StringComparison.OrdinalIgnoreCase);
            if (i >= 0)
            {
                var rest = s.Substring(i + 11).Trim();
                int sp = rest.IndexOf(' ');
                var m = System.Text.RegularExpressions.Regex.Match(rest, @"\d{1,2}:\d{2}");
                return "índice ok " + (m.Success ? m.Value : "");
            }
            return "índice: atualizando…";
        }

        // atualizacao automatica: se aparecer MonitorSW_atualizacao.exe na pasta, roda o ATUALIZAR.bat
        DateTime originStamp = DateTime.MinValue;
        long updSize = -1;
        volatile bool updBusy, formVisible = true;

        void CheckSelfUpdate()
        {
            if (Util.Origin != null) { CheckSharedUpdate(); return; }
            try
            {
                string upd = Path.Combine(Util.AppDir, "MonitorSW_atualizacao.exe");
                if (!File.Exists(upd)) upd = Path.Combine(Util.AppDir, "Monitor_atualizacao.exe");
                string bat = Path.Combine(Util.AppDir, "ATUALIZAR.bat");
                if (!File.Exists(upd) || !File.Exists(bat)) return;
                var t = File.GetLastWriteTime(upd);
                if (t == updTried || (DateTime.Now - t).TotalSeconds < 10) return; // espera terminar de copiar
                updTried = t;
                var psi = new ProcessStartInfo("cmd.exe", "/c \"" + bat + "\"");
                psi.WorkingDirectory = Util.AppDir;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch { }
        }

        // modo compartilhado (programa na rede): qualquer PC aplica a atualizacao e todos reabrem com a versao nova
        void CheckSharedUpdate()
        {
            try
            {
                string orig = Util.Origin;
                string upd = Path.Combine(Path.GetDirectoryName(orig), "Monitor_atualizacao.exe");
                // o relogio do servidor pode estar diferente do PC: espera o tamanho do arquivo ficar igual entre duas conferencias
                long size = File.Exists(upd) ? new FileInfo(upd).Length : -1;
                bool ready = size > 0 && size == updSize;
                updSize = size;
                if (ready)
                {
                    try
                    {
                        // a atualização é igual ao programa atual: só apaga (não reinicia à toa)
                        if (new FileInfo(orig).Length == size && File.ReadAllBytes(orig).SequenceEqual(File.ReadAllBytes(upd))) { File.Delete(upd); updSize = -1; ready = false; }
                    }
                    catch { }
                }
                if (ready)
                {
                    try
                    {
                        var bak = Path.Combine(Path.GetDirectoryName(orig), "Monitor_antigo.exe");
                        if (File.Exists(bak)) File.Delete(bak);
                        File.Move(orig, bak);
                        File.Move(upd, orig);
                    }
                    catch { }
                }
                var t = File.GetLastWriteTime(orig);
                if (originStamp == DateTime.MinValue) { originStamp = t; return; }
                if (t == originStamp) return;
                originStamp = t;
                // abre a versao nova a partir de uma copia local (assim o Windows nao mostra aviso de arquivo da rede)
                Program.LaunchShadow(orig, formVisible ? new[] { "/substituir" } : new[] { "/substituir", "/bandeja" });
            }
            catch { }
        }

        bool ServerMode { get { return chkServer.Checked && search.Text.Trim().Length > 0; } }

        void ClearSearch()
        {
            srvTimer.Stop();
            search.Text = "";
            ApplySearchMode();
            grid.Focus();
        }

        void ApplySearchMode()
        {
            bool srv = ServerMode;
            srvGrid.Visible = srv;
            grid.Visible = !srv;
            if (srv) srvGrid.BringToFront(); else grid.BringToFront();
            if (srv) RunServerSearch(); else FillGrid();
        }

        void BuildServerGrid()
        {
            srvGrid.Dock = DockStyle.Fill;
            srvGrid.Visible = false;
            srvGrid.ReadOnly = true;
            srvGrid.AllowUserToAddRows = false;
            srvGrid.AllowUserToDeleteRows = false;
            srvGrid.AllowUserToResizeRows = false;
            srvGrid.RowHeadersVisible = false;
            srvGrid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            srvGrid.MultiSelect = false;
            srvGrid.BackgroundColor = Theme.Surface;
            srvGrid.BorderStyle = BorderStyle.None;
            srvGrid.RowTemplate.Height = 26;
            srvGrid.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            srvGrid.GridColor = Theme.Border;
            srvGrid.EnableHeadersVisualStyles = false;
            srvGrid.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None;
            srvGrid.ColumnHeadersDefaultCellStyle = grid.ColumnHeadersDefaultCellStyle.Clone();
            srvGrid.DefaultCellStyle = grid.DefaultCellStyle.Clone();
            srvGrid.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            Theme.DarkScroll(srvGrid);
            foreach (var c in new[] { new[] { "ITEM (código)", "300" }, new[] { "DESCRIÇÃO", "240" }, new[] { "DESENHO", "85" }, new[] { "PDF", "70" }, new[] { "DXF", "70" }, new[] { "MÁQUINA / PROJETO", "330" }, new[] { "QTD", "60" }, new[] { "ONDE (submontagem > ... > máquina)", "520" } })
            {
                var col = new DataGridViewTextBoxColumn();
                col.HeaderText = c[0]; col.Width = int.Parse(c[1]); col.SortMode = DataGridViewColumnSortMode.Automatic;
                srvGrid.Columns.Add(col);
            }
            srvGrid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            foreach (DataGridViewColumn c in srvGrid.Columns) { c.FillWeight = c.Width; c.MinimumWidth = Math.Min(c.Width, 60); }
            srvGrid.Columns[6].ValueType = typeof(int);
            srvGrid.Columns[6].DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleCenter;
            for (int ci = 2; ci <= 4; ci++) srvGrid.Columns[ci].DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleCenter;
                        srvGrid.SelectionChanged += (s, a) => { if (!fillingSrv && srvGrid.CurrentRow != null) ShowServerPreview(srvGrid.CurrentRow.Index); };
            srvGrid.CellClick += (s, a) => { if (a.RowIndex >= 0 && srvGrid.Rows[a.RowIndex].Tag is string) ToggleServerRow(a.RowIndex); };
            srvGrid.KeyDown += (s, a) => { if ((a.KeyCode == Keys.Enter || a.KeyCode == Keys.Right || a.KeyCode == Keys.Left) && srvGrid.CurrentRow != null && srvGrid.CurrentRow.Tag is string) { ToggleServerRow(srvGrid.CurrentRow.Index); a.Handled = true; } };
            // botão direito na busca do servidor: abrir modelo / detalhamento / PDF / DXF do item ou da montagem
            srvGrid.CellMouseClick += (s, a) =>
            {
                if (a.Button != MouseButtons.Right || a.RowIndex < 0) return;
                try { srvGrid.CurrentCell = srvGrid.Rows[a.RowIndex].Cells[Math.Max(0, a.ColumnIndex)]; } catch { }
                MenuServidor(a);
            };
            srvGrid.CellDoubleClick += (s, a) =>
            {
                if (a.RowIndex < 0) return;
                var w = srvGrid.Rows[a.RowIndex].Tag as WhereRow;
                if (w == null || string.IsNullOrEmpty(w.Path)) return;
                try { Process.Start("explorer.exe", "/select,\"" + engine.Cfg.Map(w.Path) + "\""); } catch { }
            };
        }

        List<WhereRow> srvHits = new List<WhereRow>();
        string srvQuery = "";
        readonly HashSet<string> srvOpen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        int srvReq;
        bool fillingSrv;

        void RunServerSearch()
        {
            if (!ServerMode) return;
            string q = search.Text.Trim();
            if (q.Length < 3)
            {
                srvHits = new List<WhereRow>();
                FillServerGrid();
                lblCounts.Text = "digite pelo menos 3 letras";
                return;
            }
            int req = ++srvReq;
            lblCounts.Text = "procurando no servidor…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                var hits = indexer.Search(q, 20000);
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var list = hits.Where(h => seen.Add(h.Code + "|" + h.Machine)).ToList();
                if (!IsHandleCreated) return;
                BeginInvoke(new Action(() =>
                {
                    if (req != srvReq || !ServerMode) return;
                    srvHits = list;
                    if (!string.Equals(q, srvQuery, StringComparison.OrdinalIgnoreCase)) { srvOpen.Clear(); srvQuery = q; }
                    var codes = srvHits.Select(h => h.Code).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                    if (codes.Count == 1) srvOpen.Add(codes[0]);
                    FillServerGrid();
                    CheckServerStatus(req);
                    int machines = srvHits.Select(h => h.Machine).Distinct(StringComparer.OrdinalIgnoreCase).Count();
                    if (indexer.Machines == 0) lblCounts.Text = "índice ainda sendo montado";
                    else if (srvHits.Count == 0) lblCounts.Text = "\"" + q + "\" não aparece em nenhuma máquina";
                    else lblCounts.Text = "servidor: " + codes.Count + " item(ns) em " + machines + " máquina(s)" + (hits.Count >= 20000 ? " · refine a busca" : "");
                    if (srvGrid.Rows.Count > 0) ShowServerPreview(0);
                }));
            });
        }

        void FillServerGrid()
        {
            int first = srvGrid.FirstDisplayedScrollingRowIndex;
            fillingSrv = true;
            srvGrid.SuspendLayout();
            srvGrid.Rows.Clear();
            var rows = new List<DataGridViewRow>();
            foreach (var g in srvHits.GroupBy(h => h.Code, StringComparer.OrdinalIgnoreCase).OrderBy(g => g.Key))
            {
                var f = g.First();
                bool open = srvOpen.Contains(g.Key);
                var list = g.OrderBy(h => h.Machine.StartsWith("[avulsa]") ? 1 : 0).ThenBy(h => h.Machine).ToList();
                int nMaq = list.Count;
                int tot = list.Sum(h => h.Qty);
                var hr = new DataGridViewRow();
                string[] st;
                lock (srvStatus) srvStatus.TryGetValue(g.Key, out st);
                hr.CreateCells(srvGrid, (open ? "▼  " : "▶  ") + f.Code, f.Desc, st != null ? st[0] : "…", st != null ? st[1] : "…", st != null ? st[2] : "…", "usado em " + nMaq + (nMaq == 1 ? " máquina" : " máquinas"), tot, f.Proc);
                hr.Tag = g.Key;
                hr.DefaultCellStyle.BackColor = Theme.AsmRow;
                hr.DefaultCellStyle.Font = Theme.UiBold;
                hr.Cells[5].Style.ForeColor = Theme.Accent;
                ColorStatus(hr);
                rows.Add(hr);
                if (!open) continue;
                foreach (var h in list)
                {
                    var r = new DataGridViewRow();
                    r.CreateCells(srvGrid, "", "", "", "", "", "      " + h.Machine, h.Qty, h.Chains);
                    r.Tag = h;
                    if (h.Machine.StartsWith("[avulsa]")) r.DefaultCellStyle.ForeColor = Theme.Muted;
                    rows.Add(r);
                }
            }
            srvGrid.Rows.AddRange(rows.ToArray());
            if (first >= 0 && first < srvGrid.Rows.Count) try { srvGrid.FirstDisplayedScrollingRowIndex = first; } catch { }
            srvGrid.ResumeLayout();
            fillingSrv = false;
        }

        // situação (desenho / PDF / DXF) conferida direto na pasta de cada item achado, sem precisar abrir a montagem
        readonly Dictionary<string, string[]> srvStatus = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);

        void CheckServerStatus(int req)
        {
            var items = srvHits.GroupBy(h => h.Code, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).Take(400).ToList();
            lock (srvStatus) srvStatus.Clear();
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                int n = 0;
                foreach (var f in items)
                {
                    if (req != srvReq) return;
                    string[] st = { "?", "?", "?" };
                    try
                    {
                        string model = engine.Cfg.Map(f.Path ?? "");
                        if (model.Length > 0 && File.Exists(model))
                        {
                            bool ign = engine.Cfg.IsIgnored(model);
                            string dir = Path.GetDirectoryName(model), stem = Path.GetFileNameWithoutExtension(model);
                            var apr = new List<string>();
                            try { apr = Directory.GetFiles(dir, stem + "*APR*").ToList(); } catch { }
                            Func<string, bool> has = ext => File.Exists(Path.Combine(dir, stem + ext));   // APR-XXX = revisão antiga, não conta
                            if (ign) st = new[] { "-", "-", "-" };
                            else st = new[] { has(".SLDDRW") ? "✓ Tem" : "✗ Falta", has(".PDF") ? "✓ Tem" : "✗ Falta", has(".DXF") ? "✓ Tem" : "-" };
                        }
                        else st = new[] { "arquivo?", "", "" };
                    }
                    catch { }
                    lock (srvStatus) srvStatus[f.Code] = st;
                    if (++n % 15 == 0 || n == items.Count)
                    {
                        if (!IsHandleCreated) return;
                        try { BeginInvoke(new Action(() => { if (req == srvReq && ServerMode) UpdateServerStatusCells(); })); } catch { }
                    }
                }
            });
        }

        void UpdateServerStatusCells()
        {
            foreach (DataGridViewRow r in srvGrid.Rows)
            {
                var code = r.Tag as string;
                if (code == null) continue;
                string[] st;
                lock (srvStatus) if (!srvStatus.TryGetValue(code, out st)) continue;
                for (int i = 0; i < 3; i++) r.Cells[2 + i].Value = st[i];
                ColorStatus(r);
            }
        }

        static void ColorStatus(DataGridViewRow r)
        {
            for (int i = 2; i <= 4; i++)
            {
                var v = r.Cells[i].Value as string ?? "";
                r.Cells[i].Style.ForeColor = v.StartsWith("✓") ? Theme.OkText : v.StartsWith("✗") ? Theme.PendText : Theme.Muted;
            }
        }

        // linha do item: miniatura da peca. Linha de maquina: miniatura da maquina
        void ShowServerPreview(int row)
        {
            if (row < 0 || row >= srvGrid.Rows.Count) return;
            var tag = srvGrid.Rows[row].Tag;
            var w = tag as WhereRow;
            if (w != null)
            {
                var mp = indexer.MachinePath(w.Machine);
                if (!string.IsNullOrEmpty(mp)) ShowPreview(engine.Cfg.Map(mp), w.Machine);
                return;
            }
            var code = tag as string;
            if (code == null) return;
            var f = srvHits.FirstOrDefault(x => string.Equals(x.Code, code, StringComparison.OrdinalIgnoreCase));
            // aba de baixo: não mostrar dados de um item da montagem aberta (a busca é no servidor todo)
            try
            {
                FillProcPanel(null);
                string[] st; lock (srvStatus) srvStatus.TryGetValue(code, out st);
                whereBox.Text = code + (f != null && !string.IsNullOrEmpty(f.Desc) ? "  -  " + f.Desc : "") +
                    (st != null ? "\r\nDesenho: " + st[0] + "    PDF: " + st[1] + "    DXF: " + st[2] : "\r\nConferindo desenho/PDF/DXF na pasta…") +
                    (f != null ? "\r\n" + engine.Cfg.Map(f.Path) : "") +
                    "\r\n\r\nClique na seta para ver em quais máquinas é usado.";
            }
            catch { }
            if (f != null && !string.IsNullOrEmpty(f.Path)) ShowPreview(engine.Cfg.Map(f.Path), f.Code);
        }

        void ToggleServerRow(int row)
        {
            if (row < 0 || row >= srvGrid.Rows.Count) return;
            var code = srvGrid.Rows[row].Tag as string;
            if (code == null) return;
            if (!srvOpen.Remove(code)) srvOpen.Add(code);
            FillServerGrid();
            fillingSrv = true;
            int at = -1;
            for (int i = 0; i < srvGrid.Rows.Count; i++)
                if (string.Equals(srvGrid.Rows[i].Tag as string, code, StringComparison.OrdinalIgnoreCase)) { srvGrid.CurrentCell = srvGrid.Rows[i].Cells[0]; at = i; break; }
            fillingSrv = false;
            if (at >= 0) ShowServerPreview(at);
        }

        void OpenProjectFile(bool folder)
        {
            if (current == null) return;
            try
            {
                if (folder) Process.Start("explorer.exe", "/select,\"" + current.MainPath + "\"");
                else Process.Start(current.MainPath);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Monitor"); }
        }

        readonly Panel prevHost = new Panel();
        readonly PictureBox prevPic = new PictureBox();
        readonly Label prevLbl = new Label();
        readonly FlowLayoutPanel prevModes = new FlowLayoutPanel();
        readonly List<RadioButton> prevModeBtns = new List<RadioButton>();
        string prevPath;              // arquivo que está sendo mostrado (duplo clique abre)
        string prevModel, prevName;   // item selecionado
        int prevMode;                 // 0 = 3D, 1 = desenho, 2 = PDF, 3 = DXF
        static readonly string[] PrevModeNames = { "3D", "Desenho", "PDF", "DXF" };

        void BuildPreview()
        {
            prevHost.Dock = DockStyle.Fill;
            prevHost.BackColor = Theme.Surface;
            prevHost.Padding = new Padding(8, 6, 8, 8);
            prevLbl.Dock = DockStyle.Top;
            prevLbl.Height = 22;
            prevLbl.ForeColor = Theme.Muted;
            prevLbl.Font = Theme.UiFont;
            prevLbl.AutoEllipsis = true;
            prevLbl.Text = "Miniatura";
            try { int m; if (int.TryParse(File.ReadAllText(Path.Combine(Util.UserDir, "miniatura.txt")).Trim(), out m) && m >= 0 && m <= 3) prevMode = m; } catch { }
            prevModes.Dock = DockStyle.Top;
            prevModes.Height = 30;
            prevModes.WrapContents = false;
            prevModes.Padding = new Padding(0, 2, 0, 4);
            prevModes.BackColor = Theme.Surface;
            var tipM = new ToolTip();
            for (int i = 0; i < 4; i++)
            {
                int mode = i;
                var rb = new RadioButton();
                rb.Appearance = Appearance.Button;
                rb.Text = PrevModeNames[i];
                rb.AutoSize = false;
                rb.Size = new Size(i == 1 ? 66 : 44, 24);
                rb.Margin = new Padding(0, 0, 4, 0);
                rb.TextAlign = ContentAlignment.MiddleCenter;
                rb.FlatStyle = FlatStyle.Flat;
                rb.FlatAppearance.BorderColor = Theme.Border;
                rb.FlatAppearance.CheckedBackColor = Theme.Accent;
                rb.BackColor = Theme.Surface2;
                rb.ForeColor = Theme.Text;
                rb.Font = Theme.UiFont;
                rb.Cursor = Cursors.Hand;
                rb.Checked = i == prevMode;
                rb.CheckedChanged += (s, a) => { if (((RadioButton)s).Checked) SetPreviewMode(mode); };
                tipM.SetToolTip(rb, i == 0 ? "Miniatura do modelo 3D" : i == 1 ? "Folha do detalhamento (.SLDDRW)" : i == 2 ? "Primeira página do PDF" : "Desenho do DXF (corte laser)");
                prevModeBtns.Add(rb);
                prevModes.Controls.Add(rb);
            }
            prevPic.Dock = DockStyle.Fill;
            prevPic.SizeMode = PictureBoxSizeMode.Zoom;
            prevPic.BackColor = Color.FromArgb(236, 238, 241); // fundo claro: a imagem do SolidWorks vem em fundo branco
            prevPic.Cursor = Cursors.Hand;
            prevPic.DoubleClick += (s, a) => { if (prevPath != null) try { Process.Start(prevPath); } catch { } };
            var tip = new ToolTip(); tip.SetToolTip(prevPic, "Duplo clique abre o arquivo");
            prevHost.Controls.Add(prevPic);
            prevHost.Controls.Add(prevModes);
            prevHost.Controls.Add(prevLbl);
        }

        void SetPreviewMode(int mode)
        {
            if (mode == prevMode) return;
            prevMode = mode;
            try { Directory.CreateDirectory(Util.UserDir); File.WriteAllText(Path.Combine(Util.UserDir, "miniatura.txt"), mode.ToString()); } catch { }
            if (prevModel != null) RequestPreview();
        }

        int prevReq;
        class PrevEntry { public DateTime Mt; public Image Img; public string File; public string Miss; }
        static readonly Dictionary<string, PrevEntry> prevMem = new Dictionary<string, PrevEntry>(StringComparer.OrdinalIgnoreCase);

        // uma unica fila de miniaturas: so o ultimo pedido e carregado (passar rapido pelos itens nao acumula leituras na rede)
        string prevWantPath, prevWantLabel;
        int prevWantReq, prevWantMode;
        readonly object prevLock = new object();
        bool prevWorker;
        readonly System.Windows.Forms.Timer spinTimer = new System.Windows.Forms.Timer();
        int spinAngle;

        void ShowPreview(string path, string name)
        {
            if (string.IsNullOrEmpty(path)) return;
            string label = name ?? Util.NameOf(path);
            if (string.Equals(path, prevModel, StringComparison.OrdinalIgnoreCase) && label == prevName) return;
            prevModel = path; prevName = label;
            RequestPreview();
        }

        void RequestPreview()
        {
            string path = prevModel, label = prevName; int mode = prevMode;
            int req = ++prevReq;
            PrevEntry pe;
            lock (prevMem) prevMem.TryGetValue(mode + "|" + path, out pe);
            prevLbl.Text = label + (mode == 0 ? "" : "  ·  " + PrevModeNames[mode]);
            prevPath = mode == 0 ? path : null;
            if (pe != null) { StopSpin(); prevPic.Image = pe.Img ?? NoPreviewImage(pe.Miss); if (pe.File != null) prevPath = pe.File; }
            else StartSpin();
            lock (prevLock)
            {
                prevWantPath = path; prevWantLabel = label; prevWantReq = req; prevWantMode = mode;
                if (prevWorker) return;
                prevWorker = true;
            }
            System.Threading.ThreadPool.QueueUserWorkItem(_ => PreviewWorker());
        }

        void PreviewWorker()
        {
            while (true)
            {
                string path, label; int req, mode;
                lock (prevLock)
                {
                    if (prevWantPath == null) { prevWorker = false; return; }
                    path = prevWantPath; label = prevWantLabel; req = prevWantReq; mode = prevWantMode;
                    prevWantPath = null;
                }
                Image img = null; string file = null, miss = null;
                try
                {
                    file = ResolvePreviewFile(path, mode);
                    if (file == null) miss = mode == 1 ? "sem detalhamento (.SLDDRW)" : mode == 2 ? "sem PDF" : mode == 3 ? "sem DXF" : "arquivo não encontrado";
                    else
                    {
                        DateTime mt = Util.MTime(file);
                        string key = mode + "|" + path;
                        PrevEntry pe;
                        lock (prevMem) prevMem.TryGetValue(key, out pe);
                        if (pe != null && pe.Mt == mt && string.Equals(pe.File, file, StringComparison.OrdinalIgnoreCase)) { img = pe.Img; miss = pe.Miss; }
                        else
                        {
                            img = LoadPreview(file, mt, mode);
                            if (img == null) miss = mode == 2 ? "PDF sem miniatura" : mode == 3 ? "DXF vazio ou não reconhecido" : "sem miniatura";
                        }
                    }
                    lock (prevMem) { if (prevMem.Count > 400) prevMem.Clear(); prevMem[mode + "|" + path] = new PrevEntry { Mt = file == null ? DateTime.MinValue : Util.MTime(file), Img = img, File = file, Miss = miss }; }
                }
                catch { }
                if (!IsHandleCreated) continue;
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        if (req != prevReq) return;
                        StopSpin();
                        prevPath = file;
                        prevPic.Image = img ?? NoPreviewImage(miss);
                    }));
                }
                catch { }
            }
        }

        // acha o arquivo do tipo escolhido na pasta da peça (com revisão APR, a de maior número)
        static string ResolvePreviewFile(string model, int mode)
        {
            if (mode == 0) return File.Exists(model) ? model : null;
            string ext = mode == 1 ? ".SLDDRW" : mode == 2 ? ".PDF" : ".DXF";
            string dir = Path.GetDirectoryName(model), stem = Path.GetFileNameWithoutExtension(model);
            string exact = Path.Combine(dir, stem + ext);
            List<string> cands;
            try
            {
                cands = Directory.GetFiles(dir, stem + "*" + ext).Where(f => Path.GetExtension(f).Equals(ext, StringComparison.OrdinalIgnoreCase)).ToList();
            }
            catch { return File.Exists(exact) ? exact : null; }
            // revisões antigas "... APR-XXX" não são o arquivo atual
            cands = cands.Where(f => Util.AprNumber(f, stem) < 0).ToList();
            var ex = cands.FirstOrDefault(f => string.Equals(Path.GetFileNameWithoutExtension(f), stem, StringComparison.OrdinalIgnoreCase));
            if (ex != null) return ex;
            string code = stem.Split(' ')[0];
            if (code != stem) try { cands.AddRange(Directory.GetFiles(dir, code + "*" + ext)); } catch { }
            return cands.Where(f => Path.GetExtension(f).Equals(ext, StringComparison.OrdinalIgnoreCase)).OrderByDescending(f => File.GetLastWriteTime(f)).FirstOrDefault();
        }

        void StartSpin()
        {
            if (!spinTimer.Enabled)
            {
                spinTimer.Interval = 60;
                spinTimer.Tick -= SpinTick; spinTimer.Tick += SpinTick;
                spinTimer.Start();
            }
            SpinTick(null, null);
        }
        void StopSpin() { spinTimer.Stop(); }

        // simbolo de "atualizando" enquanto a miniatura carrega (a tela continua livre)
        void SpinTick(object s, EventArgs e)
        {
            spinAngle = (spinAngle + 24) % 360;
            int w = Math.Max(60, prevPic.Width), h = Math.Max(60, prevPic.Height);
            var bmp = new Bitmap(w, h);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(prevPic.BackColor);
                int r = 18, cx = w / 2, cy = h / 2 - 8;
                using (var pBg = new Pen(Color.FromArgb(200, 205, 212), 4))
                using (var pFg = new Pen(Theme.Accent, 4))
                {
                    g.DrawEllipse(pBg, cx - r, cy - r, 2 * r, 2 * r);
                    pFg.StartCap = System.Drawing.Drawing2D.LineCap.Round; pFg.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                    g.DrawArc(pFg, cx - r, cy - r, 2 * r, 2 * r, spinAngle, 100);
                }
                using (var f = new Font("Segoe UI", 8.5f))
                using (var b = new SolidBrush(Color.FromArgb(110, 115, 125)))
                {
                    var sz = g.MeasureString("carregando miniatura…", f);
                    g.DrawString("carregando miniatura…", f, b, cx - sz.Width / 2, cy + r + 8);
                }
            }
            var old = prevPic.Image;
            prevPic.Image = bmp;
            if (old != null && old.Tag as string == "spin") old.Dispose();
            bmp.Tag = "spin";
        }

        readonly Dictionary<string, Image> noPrev = new Dictionary<string, Image>();
        Image NoPreviewImage(string text = null)
        {
            text = text ?? "sem miniatura";
            Image im;
            if (noPrev.TryGetValue(text, out im)) return im;
            var bmp = new Bitmap(220, 160);
            using (var g = Graphics.FromImage(bmp))
            using (var f = new Font("Segoe UI", 9f))
            using (var b = new SolidBrush(Color.FromArgb(120, 125, 135)))
            {
                g.Clear(prevPic.BackColor);
                var sz = g.MeasureString(text, f);
                g.DrawString(text, f, b, 110 - sz.Width / 2, 80 - sz.Height / 2);
            }
            return noPrev[text] = bmp;
        }

        // cache em disco por usuario: o mesmo arquivo nao e lido de novo pela rede enquanto nao mudar
        static Image LoadPreview(string path, DateTime mt, int mode)
        {
            try
            {
                string dir = Path.Combine(Util.UserDir, "miniaturas");
                uint h = 2166136261;
                foreach (char ch in path.ToUpperInvariant()) { h ^= ch; h *= 16777619; }
                string file = Path.Combine(dir, h.ToString("x8") + "_" + mt.Ticks + ".png");
                byte[] png = null;
                if (File.Exists(file)) png = File.ReadAllBytes(file);
                else
                {
                    png = mode == 2 ? PdfPng(path) : mode == 3 ? DxfPng(path) : SwReader.ReadPreview(path);
                    if (png != null)
                    {
                        Directory.CreateDirectory(dir);
                        foreach (var old in Directory.GetFiles(dir, h.ToString("x8") + "_*.png")) try { File.Delete(old); } catch { }
                        File.WriteAllBytes(file, png);
                    }
                }
                if (png == null) return null;
                using (var ms = new MemoryStream(png)) using (var im = Image.FromStream(ms)) return new Bitmap(im);
            }
            catch { return null; }
        }

        static byte[] ToPng(Image im)
        {
            if (im == null) return null;
            using (im) using (var ms = new MemoryStream()) { im.Save(ms, System.Drawing.Imaging.ImageFormat.Png); return ms.ToArray(); }
        }

        static byte[] DxfPng(string path) { return ToPng(DxfRender.Render(path, 1000, 720)); }

        // PDF: o Windows 10/11 desenha a 1ª página (Windows.Data.Pdf) num PowerShell escondido; se falhar, tenta a miniatura do Explorer
        const string PdfScript =
"param($pdf,$png)\r\n" +
"$ErrorActionPreference='Stop'\r\n" +
"Add-Type -AssemblyName System.Runtime.WindowsRuntime\r\n" +
"$m = [System.WindowsRuntimeSystemExtensions].GetMethods()\r\n" +
"$asOp = ($m | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]\r\n" +
"$asAc = ($m | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]\r\n" +
"function Op($op,[Type]$t){ $k=$asOp.MakeGenericMethod($t).Invoke($null,@($op)); $k.Wait(-1)|Out-Null; $k.Result }\r\n" +
"function Ac($a){ $k=$asAc.Invoke($null,@($a)); $k.Wait(-1)|Out-Null }\r\n" +
"[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]|Out-Null\r\n" +
"[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]|Out-Null\r\n" +
"[Windows.Data.Pdf.PdfPageRenderOptions,Windows.Data.Pdf,ContentType=WindowsRuntime]|Out-Null\r\n" +
"[Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]|Out-Null\r\n" +
"$f = Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($pdf)) ([Windows.Storage.StorageFile])\r\n" +
"$d = Op ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($f)) ([Windows.Data.Pdf.PdfDocument])\r\n" +
"$p = $d.GetPage(0)\r\n" +
"$o = New-Object Windows.Data.Pdf.PdfPageRenderOptions\r\n" +
"$o.DestinationWidth = 1200\r\n" +
"$s = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream\r\n" +
"Ac ($p.RenderToStreamAsync($s,$o))\r\n" +
"$r = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($s.GetInputStreamAt(0))\r\n" +
"$w = [IO.File]::Create($png); $r.CopyTo($w); $w.Close()\r\n";

        static byte[] PdfPng(string pdf)
        {
            string tmp = Path.Combine(Path.GetTempPath(), "MonitorPdf");
            try
            {
                Directory.CreateDirectory(tmp);
                string ps = Path.Combine(Util.UserDir, "pdf_miniatura.ps1");
                if (!File.Exists(ps) || File.ReadAllText(ps) != PdfScript) { Directory.CreateDirectory(Util.UserDir); File.WriteAllText(ps, PdfScript); }
                string id = Guid.NewGuid().ToString("N").Substring(0, 8);
                string local = Path.Combine(tmp, id + ".pdf"), png = Path.Combine(tmp, id + ".png");
                File.Copy(pdf, local, true);
                try
                {
                    var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps + "\" \"" + local + "\" \"" + png + "\"");
                    psi.UseShellExecute = false; psi.CreateNoWindow = true;
                    using (var p = Process.Start(psi)) { if (!p.WaitForExit(30000)) try { p.Kill(); } catch { } }
                    if (File.Exists(png) && new FileInfo(png).Length > 0) return File.ReadAllBytes(png);
                }
                finally { try { File.Delete(local); } catch { } try { File.Delete(png); } catch { } }
            }
            catch { }
            return ToPng(ShellThumb.Get(pdf, 600));
        }

        void SetDetailOpen(bool open)
        {
            if (rightSplit == null) return;
            if (open)
            {
                rightSplit.Panel2Collapsed = false;
                try { rightSplit.SplitterDistance = Math.Max(150, rightSplit.Height - 230); } catch { }
                detailBar.Text = "▼  Ocultar detalhes / onde é usado / histórico";
            }
            else
            {
                rightSplit.Panel2Collapsed = true;
                detailBar.Text = "▲  Detalhes / onde é usado / histórico de alterações";
            }
        }

        static Bitmap FunnelIcon(Color c)
        {
            var bmp = new Bitmap(16, 16);
            using (var g = Graphics.FromImage(bmp))
            using (var b = new SolidBrush(c))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.FillPolygon(b, new[] { new PointF(1.5f, 2.5f), new PointF(14.5f, 2.5f), new PointF(9.5f, 8.5f), new PointF(9.5f, 14f), new PointF(6.5f, 12.5f), new PointF(6.5f, 8.5f) });
            }
            return bmp;
        }

        static ToolStripMenuItem Mi(string text, EventHandler h)
        {
            var m = new ToolStripMenuItem(text);
            m.Click += h;
            return m;
        }

        static void DarkMenus(ToolStripDropDown dd)
        {
            dd.Renderer = new DarkRenderer();
            dd.BackColor = Theme.Surface2;
            dd.ForeColor = Theme.Text;
            dd.Font = Theme.UiFont;
            foreach (ToolStripItem i in dd.Items)
            {
                i.ForeColor = Theme.Text;
                var mi = i as ToolStripMenuItem;
                if (mi != null && mi.HasDropDownItems) DarkMenus(mi.DropDown);
            }
        }

        // modo normal: só mostra se TEM ou NÃO TEM detalhamento. Conferência: também se está atualizado
        void SetCheckMode(bool on)
        {
            lgPend.Visible = on;
            Text = on ? "Monitor - conferindo se PDF/DXF estão atualizados" : "Monitor";
            lblStatus.Text = on ? "Conferência ligada: peças com PDF/DXF mais antigo que o modelo aparecem em vermelho." : "Mostrando só se tem ou não tem detalhamento.";
            System.Threading.ThreadPool.QueueUserWorkItem(_ => engine.SetCheckUpdates(on));
        }

        // botão Gerar detalhamento: janela para escolher Desenho SolidWorks / PDF / DXF e roda o DetalharSW.ps1
        // (pasta Detalhamento ao lado do config.ini). Grava na pasta da peça no servidor.
        bool genRunning;

        void GenerateDetail()
        {
            string model = null, name = null, sdesc = ""; Item it = null;
            if (ServerMode && srvGrid.CurrentRow != null)
            {
                var tag = srvGrid.CurrentRow.Tag;
                var code = tag as string;
                var w = tag as WhereRow;
                if (w != null) code = w.Code;
                var f = srvHits.FirstOrDefault(x => string.Equals(x.Code, code, StringComparison.OrdinalIgnoreCase));
                if (f != null && !string.IsNullOrEmpty(f.Path)) { model = engine.Cfg.Map(f.Path); name = f.Code; sdesc = f.Desc ?? ""; }
            }
            else
            {
                it = SelItem();
                if (it != null) { model = it.Path; name = it.Name; }
            }
            if (model == null) { MessageBox.Show("Selecione uma peça ou submontagem na lista.", "Gerar detalhamento", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (genRunning) { MessageBox.Show("Já tem um detalhamento sendo gerado. Espere terminar (janela preta do detalhamento).", "Gerar detalhamento", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }

            string cmd = (engine.Cfg.GenCmd ?? "").Trim();
            if (cmd.Length > 0) { RunCustomGen(cmd, model, name); return; }

            string script = Path.Combine(Path.GetDirectoryName(engine.Cfg.FilePath) ?? Util.AppDir, "Detalhamento", "DetalharSW.ps1");
            if (!File.Exists(script)) { MessageBox.Show("Não encontrei o gerador de detalhamento:\n" + script, "Gerar detalhamento", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

            bool isAsm = model.EndsWith(".SLDASM", StringComparison.OrdinalIgnoreCase);
            bool isDrw = model.EndsWith(".SLDDRW", StringComparison.OrdinalIgnoreCase);
            if (isDrw) { MessageBox.Show("Selecione a peça ou a montagem (não o desenho).", "Gerar detalhamento"); return; }
            bool hasDrw = ResolvePreviewFile(model, 1) != null, hasPdf = ResolvePreviewFile(model, 2) != null, hasDxf = ResolvePreviewFile(model, 3) != null;
            bool laser = it != null ? it.IsLaser || it.NeedDxf : engine.Cfg.LaserWords.Any(w => sdesc.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0);

            bool wDrw, wPdf, wDxf, recriar;
            using (var f = new Form())
            {
                f.Text = "Gerar detalhamento - " + name;
                f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(460, 300); Theme.Style(f);
                var t = new Label(); t.Text = "O que você quer gerar para " + name + "?"; t.SetBounds(14, 12, 432, 22); t.ForeColor = Theme.Text; t.Font = new Font(Theme.UiFont, FontStyle.Bold);
                var d = new Label(); d.SetBounds(14, 36, 432, 34); d.ForeColor = Theme.Muted;
                d.Text = (it != null && it.Desc.Length > 0 ? it.Desc + "\n" : sdesc.Length > 0 ? sdesc + "\n" : "") + (it != null && it.Need.Length > 0 ? "Exige: " + it.Need : (isAsm ? "Montagem" : "Peça"));
                Func<string, bool, string, int, CheckBox> Ck = (txt, has, extra, y) =>
                {
                    var c = new CheckBox(); c.Text = txt + (has ? "   (já existe)" : "   (não tem)") + extra; c.SetBounds(22, y, 420, 24);
                    c.ForeColor = Theme.Text; c.FlatStyle = FlatStyle.Flat; c.Cursor = Cursors.Hand; return c;
                };
                var cDrw = Ck("Detalhamento do SolidWorks (.SLDDRW)", hasDrw, "", 80);
                var cPdf = Ck("PDF", hasPdf, "", 108);
                var cDxf = Ck("DXF (corte laser)", hasDxf, isAsm ? " - só peças" : "", 136);
                cDxf.Enabled = !isAsm;
                var cRec = new CheckBox(); cRec.Text = "Recriar o que já existe (substitui desenho / PDF / DXF marcados)"; cRec.SetBounds(22, 172, 420, 24); cRec.ForeColor = Theme.WarnText; cRec.FlatStyle = FlatStyle.Flat;
                // sugestão: o que está faltando
                cDrw.Checked = !hasDrw;
                cPdf.Checked = !hasPdf;
                cDxf.Checked = !isAsm && laser && !hasDxf;
                if (!cDrw.Checked && !cPdf.Checked && !cDxf.Checked) { cPdf.Checked = true; }
                // "Recriar" vale para tudo que estiver marcado e já existir; marcar um que já existe liga o Recriar
                bool travar = false;
                Action atualizaRec = () =>
                {
                    bool algum = (cDrw.Checked && hasDrw) || (cPdf.Checked && hasPdf) || (cDxf.Checked && cDxf.Enabled && hasDxf);
                    cRec.Enabled = algum;
                    if (!algum) cRec.Checked = false;
                };
                foreach (var cb in new[] { cDrw, cPdf, cDxf })
                {
                    var c0 = cb;
                    c0.CheckedChanged += (s, a) =>
                    {
                        if (travar) return;
                        bool existe = c0 == cDrw ? hasDrw : c0 == cPdf ? hasPdf : hasDxf;
                        if (c0.Checked && existe) cRec.Checked = true;
                        atualizaRec();
                    };
                }
                cRec.CheckedChanged += (s, a) =>
                {
                    if (cRec.Checked || travar) return;
                    // sem Recriar: desmarca o que já existe (não vai ser substituído)
                    travar = true;
                    if (hasDrw) cDrw.Checked = false; if (hasPdf) cPdf.Checked = false; if (hasDxf) cDxf.Checked = false;
                    travar = false;
                    atualizaRec();
                };
                if ((cPdf.Checked && hasPdf) || (cDrw.Checked && hasDrw)) cRec.Checked = true;
                atualizaRec();
                var n = new Label(); n.SetBounds(14, 204, 432, 44); n.ForeColor = Theme.Muted;
                n.Text = "Grava na pasta da peça no servidor. Usa o SolidWorks deste computador (abre se estiver fechado).\nPDF sem desenho: marque também o detalhamento. Revise as cotas antes de liberar.";
                var ok = new Button(); ok.Text = "Gerar"; ok.DialogResult = DialogResult.OK; ok.SetBounds(270, 256, 84, 30);
                var ca = new Button(); ca.Text = "Cancelar"; ca.DialogResult = DialogResult.Cancel; ca.SetBounds(362, 256, 84, 30);
                foreach (var b in new[] { ok, ca }) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Theme.Border; b.BackColor = Theme.Surface2; b.ForeColor = Theme.Text; }
                ok.BackColor = Theme.Accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderColor = Theme.Accent;
                f.Controls.AddRange(new Control[] { t, d, cDrw, cPdf, cDxf, cRec, n, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                if (f.ShowDialog(this) != DialogResult.OK) return;
                wDrw = cDrw.Checked; wPdf = cPdf.Checked; wDxf = cDxf.Checked && cDxf.Enabled; recriar = cRec.Checked && cRec.Enabled;
            }
            if (!wDrw && !wPdf && !wDxf) return;
            // -Recriar do gerador = substituir o desenho; PDF e DXF marcados são sempre gerados de novo (substituem o arquivo)
            if (!(wDrw && hasDrw)) recriar = recriar && wDrw;
            if (wPdf && !wDrw && !hasDrw)
            {
                MessageBox.Show("Para gerar o PDF é preciso o detalhamento (.SLDDRW).\nMarque também \"Detalhamento do SolidWorks\".", "Gerar detalhamento", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            var saidas = new List<string>();
            if (wDrw) saidas.Add("drw"); if (wPdf) saidas.Add("pdf"); if (wDxf) saidas.Add("dxf");
            string args = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\" -Modo gerar -Saidas " + string.Join(",", saidas) + " -Destino servidor" + (recriar ? " -Recriar" : "") + (Users.Carimbo.Length > 0 ? " -Desenhista \"" + Users.Carimbo.Replace("\"", "") + "\"" : "") + " \"" + model + "\"";
            string what = string.Join(" + ", saidas.Select(x => x == "drw" ? "desenho" : x.ToUpperInvariant()));
            Process p;
            try
            {
                var psi = new ProcessStartInfo("powershell.exe", args);
                psi.UseShellExecute = true; psi.WindowStyle = ProcessWindowStyle.Minimized;   // janela do gerador só na barra de tarefas
                psi.WorkingDirectory = Path.GetDirectoryName(script);
                p = Process.Start(psi);
            }
            catch (Exception ex) { MessageBox.Show("Não consegui rodar o gerador:\n" + ex.Message, "Gerar detalhamento"); return; }
            genRunning = true;
            DateTime started = DateTime.Now;
            lblStatus.Text = "Gerando " + what + " de " + name + "… (janela do detalhamento aberta; o SolidWorks vai trabalhar)";
            Aviso(4000, "Gerando detalhamento", name + ": " + what, ToolTipIcon.Info);
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                try { p.WaitForExit(); } catch { }
                string res = GenResult(Path.GetDirectoryName(script), model, started);
                bool marcou = false;
                if (res.StartsWith("pronto"))
                {
                    // o que foi gerado automaticamente precisa ser conferido: fica PENDENTE até alguém marcar como revisado
                    string key = Path.GetFileNameWithoutExtension(model);
                    marcou = Marks.Set(key, "PENDENTE - gerado automaticamente (" + what + ") - " + Users.Me + " " + DateTime.Now.ToString("dd/MM/yy")) == null;
                    res += marcou ? " - marcado PENDENTE para conferir" : "";
                }
                if (marcou) engine.SetCheckUpdates(engine.CheckUpdates);
                engine.Kick();
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        genRunning = false;
                        bool erro = res.StartsWith("erro", StringComparison.OrdinalIgnoreCase);
                        lblStatus.Text = name + ": " + res;
                        Aviso(8000, erro ? "Detalhamento com erro" : "Detalhamento pronto", name + ": " + res, erro ? ToolTipIcon.Warning : ToolTipIcon.Info);
                        lock (prevMem) prevMem.Clear();
                        if (prevModel != null) RequestPreview();
                    }));
                }
                catch { genRunning = false; }
            });
        }

        // botão E-mail: escolhe o período, compara as listas das montagens e abre o texto no Bloco de Notas
        void GerarEmail()
        {
            var p = current;
            if (p == null) { MessageBox.Show("Abra (selecione) uma montagem na lista da esquerda.", "E-mail", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            DateTime ini, fim;
            using (var f = new Form())
            {
                f.Text = "E-mail de alteração de cadastro - " + p.Name;
                f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, 210); Theme.Style(f);
                var t = new Label(); t.Text = "Compara a lista de cada montagem no INÍCIO com a do FIM do período\ne gera o e-mail com o que SAIU e o que ENTROU."; t.SetBounds(14, 10, 412, 36); t.ForeColor = Theme.Muted;
                var l1 = new Label(); l1.Text = "Início (comecei a mexer):"; l1.SetBounds(14, 58, 170, 22); l1.ForeColor = Theme.Text;
                var d1 = new DateTimePicker(); d1.Format = DateTimePickerFormat.Custom; d1.CustomFormat = "dd/MM/yyyy  HH:mm"; d1.SetBounds(190, 54, 236, 26);
                d1.Value = DateTime.Today.AddDays(-7);
                var l2 = new Label(); l2.Text = "Fim (terminei):"; l2.SetBounds(14, 96, 170, 22); l2.ForeColor = Theme.Text;
                var d2 = new DateTimePicker(); d2.Format = DateTimePickerFormat.Custom; d2.CustomFormat = "dd/MM/yyyy  HH:mm"; d2.SetBounds(190, 92, 236, 26);
                d2.Value = DateTime.Now;
                var n = new Label(); n.SetBounds(14, 128, 412, 34); n.ForeColor = Theme.Muted;
                n.Text = "O Monitor guarda a lista de cada montagem sempre que ela muda. Períodos antes do início desse registro aparecem como \"conferir manualmente\".";
                var ok = new Button(); ok.Text = "Gerar"; ok.DialogResult = DialogResult.OK; ok.SetBounds(250, 170, 84, 30);
                var ca = new Button(); ca.Text = "Cancelar"; ca.DialogResult = DialogResult.Cancel; ca.SetBounds(342, 170, 84, 30);
                foreach (var b in new[] { ok, ca }) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Theme.Border; b.BackColor = Theme.Surface2; b.ForeColor = Theme.Text; }
                ok.BackColor = Theme.Accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderColor = Theme.Accent;
                f.Controls.AddRange(new Control[] { t, l1, d1, l2, d2, n, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                if (f.ShowDialog(this) != DialogResult.OK) return;
                ini = d1.Value; fim = d2.Value;
            }
            if (fim <= ini) { MessageBox.Show("O fim precisa ser depois do início.", "E-mail"); return; }
            lblStatus.Text = "Comparando as montagens de " + p.Name + "…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string texto = null, resumo = "", err = null, file = null;
                try
                {
                    texto = EmailCadastro.Gerar(p, engine.Cfg, ini, fim, engine.Sync, out resumo);
                    string dir = Path.Combine(Util.AppDir, "relatorios");
                    Directory.CreateDirectory(dir);
                    string safe = new string(p.Name.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch).ToArray());
                    file = Path.Combine(dir, "EMAIL CADASTRO - " + safe + " - " + DateTime.Now.ToString("yyyy-MM-dd HHmm") + ".txt");
                    File.WriteAllText(file, texto, new UTF8Encoding(true));
                }
                catch (Exception ex) { err = ex.Message; }
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        if (err != null) { MessageBox.Show("Não consegui gerar o e-mail:\n" + err, "E-mail"); return; }
                        lblStatus.Text = "E-mail gerado (" + resumo + ").";
                        try { Process.Start("notepad.exe", "\"" + file + "\""); } catch { }
                    }));
                }
                catch { }
            });
        }

        // confirma que o item está em dia: vale até alguém mexer no 3D, desenho, PDF ou DXF
        void MarcarConferido(Item it)
        {
            if (MessageBox.Show("Confirmar que " + it.Name + " está em dia (3D, desenho, PDF e DXF batem)?\n\nVale até alguém alterar algum desses arquivos.",
                    "Conferência", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string name = it.Name;
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string err = Conf.SaveMany(new List<KeyValuePair<Item, string>> { new KeyValuePair<Item, string>(it, "✓ Conferido por " + Users.Me + " em " + DateTime.Now.ToString("dd/MM/yy")) });
                // conferido por alguém = a marcação PENDENTE (inclusive a automática de "gerado automaticamente") sai
                if (err == null && it.Mark.StartsWith("PEND", StringComparison.OrdinalIgnoreCase)) { string e2 = Marks.Set(name, ""); if (e2 != null && !e2.StartsWith("AVISO")) err = e2; }
                if (err == null) engine.SetCheckUpdates(true);
                try { BeginInvoke(new Action(() => { if (err == null) { if (!miCheck.Checked) miCheck.Checked = true; lblStatus.Text = name + ": conferido."; } else MessageBox.Show("Não gravou: " + err, "Conferência"); })); } catch { }
            });
        }

        // botão Conferência: confere cada item da montagem aberta (sem abrir o SolidWorks) e liga o modo conferência
        bool conferindo;
        void ConferirProjeto()
        {
            if (current == null) { MessageBox.Show("Abra (selecione) uma montagem na lista da esquerda.", "Conferência", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (conferindo) { lblStatus.Text = "Conferência já em andamento…"; return; }
            conferindo = true;
            var proj = current;
            List<Item> itens;
            lock (engine.Sync) itens = proj.Items.Values.Where(i => !i.Ignored && !i.Missing && !i.IsException && (i.NeedPdf || i.Pdf != DateTime.MinValue || i.Dxf != DateTime.MinValue)).ToList();
            lblStatus.Text = "Conferindo " + proj.Name + "… 0/" + itens.Count;
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                var res = new List<KeyValuePair<Item, string>>();
                var limpar = new List<string>();   // PENDENTE automático ("gerado automaticamente") de item que passou na conferência
                int k = 0, prob = 0;
                foreach (var it in itens)
                {
                    // já marcado como conferido e nada mudou desde então: mantém (não volta a ficar pendente)
                    var antes = Conf.Get(it);
                    bool auto = it.Mark.IndexOf("gerado automaticamente", StringComparison.OrdinalIgnoreCase) >= 0;
                    if (antes != null && antes.StartsWith("✓")) { if (auto) limpar.Add(it.Name); k++; continue; }
                    string r = "";
                    try { r = Conf.Check(it); } catch (Exception ex) { r = ""; System.Diagnostics.Debug.WriteLine(ex.Message); }
                    if (r.Length > 0) prob++;
                    else if (auto) limpar.Add(it.Name);
                    res.Add(new KeyValuePair<Item, string>(it, r));
                    if (++k % 10 == 0) { int kk = k; try { BeginInvoke(new Action(() => lblStatus.Text = "Conferindo " + proj.Name + "… " + kk + "/" + itens.Count)); } catch { } }
                }
                string err = Conf.SaveMany(res);
                foreach (var nm in limpar.Distinct(StringComparer.OrdinalIgnoreCase)) { try { Marks.Set(nm, ""); } catch { } }
                if (limpar.Count > 0) { try { engine.SetCheckUpdates(engine.CheckUpdates); } catch { } }
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        conferindo = false;
                        if (!miCheck.Checked) miCheck.Checked = true;   // liga o modo conferência (datas + resultado)
                        else System.Threading.ThreadPool.QueueUserWorkItem(__ => engine.SetCheckUpdates(true));
                        string msg = itens.Count + " item(ns) conferido(s): " + (prob == 0 ? "nenhuma divergência nos PDF/DXF." : prob + " com divergência.");
                        if (err != null) msg += " (não gravou o resultado: " + err + ")";
                        lblStatus.Text = "Conferência de " + proj.Name + ": " + msg;
                        Aviso(10000, "Conferência - " + proj.Name, msg + (prob > 0 ? " Veja os itens em vermelho / filtro de pendências." : ""), prob > 0 ? ToolTipIcon.Warning : ToolTipIcon.Info);
                    }));
                }
                catch { conferindo = false; }
            });
        }

        // força conferir de novo (arquivos apagados/criados por outra pessoa, marcações, propriedades)
        void ForceRefreshList()
        {
            if (ServerMode) { lock (prevMem) prevMem.Clear(); lblStatus.Text = "Conferindo de novo os itens achados no servidor…"; RunServerSearch(); if (prevModel != null) RequestPreview(); return; }
            lock (prevMem) prevMem.Clear();
            // texto de busca na caixa filtra a lista: avisa (senão parece que a montagem está vazia)
            if (search.Text.Trim().Length > 0 && grid.Rows.Count == 0) { srvTimer.Stop(); search.Text = ""; ApplySearchMode(); }
            lblStatus.Text = "Atualizando " + (current != null ? current.Name : "projetos") + "… confere desenho, PDF e DXF de todos os itens.";
            var only = current;
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                try { ReloadSharedConfig(); } catch { }
                engine.ForceRefresh(only);
            });
            if (prevModel != null) RequestPreview();
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == Keys.F5) { ForceRefreshList(); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        // última linha do relatório do gerador para este arquivo (depois do início)
        static string GenResult(string dir, string model, DateTime started)
        {
            try
            {
                var files = Directory.GetFiles(dir, "relatorio_*.csv").OrderByDescending(x => x).Take(2);
                foreach (var file in files)
                {
                    var lines = File.ReadAllLines(file, System.Text.Encoding.UTF8);
                    for (int i = lines.Length - 1; i > 0; i--)
                    {
                        var c = lines[i].Split(';');
                        if (c.Length < 6) continue;
                        DateTime dt;
                        if (!DateTime.TryParseExact(c[0], "dd/MM/yyyy HH:mm", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out dt)) continue;
                        if (dt < started.AddMinutes(-1)) break;
                        if (!string.Equals(Path.GetFileNameWithoutExtension(c[1]), Path.GetFileNameWithoutExtension(model), StringComparison.OrdinalIgnoreCase)) continue;
                        string msg = string.Join(";", c.Skip(5)).Trim();
                        return c[4] == "ok" ? "pronto (" + msg + ")" : c[4] == "erro" ? "erro - " + msg + " (veja log.txt na pasta Detalhamento)" : c[4] + " - " + msg;
                    }
                }
            }
            catch { }
            return "gerador terminou (sem resultado no relatório - a janela pode ter sido fechada)";
        }

        void RunCustomGen(string cmd, string model, string name)
        {
            string drw = Path.ChangeExtension(model, ".SLDDRW");
            string line = cmd.Replace("{arquivo}", model).Replace("{desenho}", drw).Replace("{pasta}", Path.GetDirectoryName(model) ?? "");
            if (line == cmd) line = cmd + " \"" + model + "\"";
            try
            {
                string exe, args;
                line = line.Trim();
                if (line.StartsWith("\"")) { int q = line.IndexOf('"', 1); exe = line.Substring(1, q - 1); args = line.Substring(q + 1).Trim(); }
                else { int sp = line.IndexOf(' '); exe = sp < 0 ? line : line.Substring(0, sp); args = sp < 0 ? "" : line.Substring(sp + 1); }
                var psi = new ProcessStartInfo(exe, args);
                psi.UseShellExecute = true;
                psi.WorkingDirectory = Util.AppDir;
                Process.Start(psi);
                lblStatus.Text = "Gerando detalhamento de " + name + "...";
                engine.Kick();
            }
            catch (Exception ex) { MessageBox.Show("Não consegui rodar o gerador:\n" + ex.Message, "Gerar detalhamento"); }
        }

        static ToolStripButton Btn(string text, EventHandler h)
        {
            var b = new ToolStripButton(text);
            b.Click += h;
            return b;
        }

        int AddCol(string name, int width, Type t)
        {
            var c = new DataGridViewTextBoxColumn();
            c.HeaderText = name;
            c.Name = "c" + grid.Columns.Count;
            c.Width = width;
            c.ValueType = t;
            if (t == typeof(DateTime)) c.DefaultCellStyle.Format = "dd/MM/yy HH:mm";
            if (t == typeof(int)) c.DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleCenter;
            return grid.Columns.Add(c);
        }

        const int IndentStep = 26;

        // linhas-guia da arvore (como no SolidWorks): mostram a qual submontagem cada item pertence
        void PaintTreeGuides(object sender, DataGridViewCellPaintingEventArgs e)
        {
            if (e.RowIndex < 0 || e.ColumnIndex != C_ITEM || !TreeMode) return;
            var t = grid.Rows[e.RowIndex].Tag as NodeTag;
            if (t == null) return;
            int level = t.Id.Count(ch => ch == '>') - 1;
            if (level <= 0) return;
            e.Paint(e.CellBounds, DataGridViewPaintParts.All);
            using (var pen = new Pen(Theme.Border))
            using (var acc = new Pen(Color.FromArgb(70, Theme.Accent)))
            {
                for (int i = 0; i < level; i++)
                {
                    int x = e.CellBounds.Left + 6 + i * IndentStep + IndentStep / 2;
                    e.Graphics.DrawLine(i == level - 1 ? acc : pen, x, e.CellBounds.Top, x, e.CellBounds.Bottom - 1);
                }
                // perninha ligando a linha ao item
                int xl = e.CellBounds.Left + 6 + (level - 1) * IndentStep + IndentStep / 2;
                int ym = e.CellBounds.Top + e.CellBounds.Height / 2;
                e.Graphics.DrawLine(acc, xl, ym, xl + IndentStep / 2 - 2, ym);
            }
            e.Handled = true;
        }

        // tela responsiva: se sobrar espaço, alarga Nº DA PEÇA e DESCRIÇÃO para ocupar a largura do monitor
        bool fitting;
        void FitColumns()
        {
            if (fitting || grid.Columns.Count == 0) return;
            fitting = true;
            try
            {
                const int baseItem = 300, baseDesc = 230;
                int others = 0;
                foreach (DataGridViewColumn c in grid.Columns)
                    if (c.Visible && c.Index != C_ITEM && c.Index != C_DESC) others += c.Width;
                int avail = grid.ClientSize.Width - SystemInformation.VerticalScrollBarWidth - 2;
                int extra = avail - others - baseItem - baseDesc;
                if (extra > 0)
                {
                    grid.Columns[C_ITEM].Width = baseItem + extra * 55 / 100;
                    grid.Columns[C_DESC].Width = baseDesc + extra - extra * 55 / 100;
                }
                else
                {
                    grid.Columns[C_ITEM].Width = baseItem;
                    grid.Columns[C_DESC].Width = baseDesc;
                }
            }
            finally { fitting = false; }
        }

        void ApplySortMode()
        {
            bool tree = TreeMode;
            foreach (DataGridViewColumn c in grid.Columns)
                c.SortMode = tree || c.Index == C_TOG ? DataGridViewColumnSortMode.NotSortable : DataGridViewColumnSortMode.Automatic;
            grid.Columns[C_TOG].Visible = tree;
            grid.Columns[C_QTD].HeaderText = tree ? "QDT." : "QDT. TOTAL";
            grid.Columns[C_NUM].Visible = tree;
            FitColumns();
            if (tree) { sortCol = -1; sortDir = SortOrder.None; }
        }

        // coluna DESENHO: ✓ tem .SLDDRW / ✗ falta (quando o item precisa de detalhamento) / - não precisa
        static string DesSt(Item it)
        {
            if (it.Drw != DateTime.MinValue) return "✓ Tem";
            if (it.Missing || it.IsException || (it.Ignored && !it.NeedPdf)) return "-";
            if (it.NeedPdf || it.NeedDxf || it.Status.StartsWith("Sem")) return "✗ Falta";
            return "Não tem";
        }

        void GridSortCompare(object sender, DataGridViewSortCompareEventArgs e)
        {
            var a = e.CellValue1; var b = e.CellValue2;
            if (a == null && b == null) e.SortResult = 0;
            else if (a == null) e.SortResult = -1;
            else if (b == null) e.SortResult = 1;
            else if (a is IComparable && a.GetType() == b.GetType()) e.SortResult = ((IComparable)a).CompareTo(b);
            else e.SortResult = string.Compare(a.ToString(), b.ToString(), StringComparison.CurrentCultureIgnoreCase);
            e.Handled = true;
        }

        void BuildTray()
        {
            tray.Icon = icoOk;
            tray.Text = "Monitor - iniciando";
            tray.Visible = true;
            var menu = new ContextMenuStrip();
            menu.Renderer = new DarkRenderer();
            menu.BackColor = Theme.Surface2;
            menu.ForeColor = Theme.Text;
            menu.Font = Theme.UiFont;
            menu.Items.Add("Abrir Monitor", null, (s, a) => ShowWindow());
            menu.Items.Add("Verificar agora", null, (s, a) => engine.Kick());
            menu.Items.Add(new ToolStripSeparator());
            miAuto.Checked = IsAutoStart();
            miAuto.Click += (s, a) => { SetAutoStart(!IsAutoStart()); miAuto.Checked = IsAutoStart(); };
            menu.Items.Add(miAuto);
            menu.Items.Add("Configurações (config.ini)", null, (s, a) => OpenConfig());
            menu.Items.Add("Atualizar índice de todas as máquinas", null, (s, a) => indexer.Kick());
            menu.Items.Add("Abrir pasta do índice", null, (s, a) => { try { System.IO.Directory.CreateDirectory(indexer.Dir); Process.Start("explorer.exe", "\"" + indexer.Dir + "\""); } catch { } });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Sair do monitor", null, (s, a) => ExitApp());
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += (s, a) => ShowWindow();
            tray.BalloonTipClicked += (s, a) =>
            {
                ShowWindow();
                if (lastBalloon != null) GoTo(lastBalloon.Project, lastBalloon.Item);
            };
        }

        // aviso próprio do Monitor (canto da tela, por cima de tudo, sem roubar o foco).
        // Não depende das notificações do Windows, que em alguns PCs ficam desligadas / no "Não perturbe".
        Toast toast;
        void Aviso(int ms, string title, string text, ToolTipIcon icon, bool irPara = false)
        {
            if (InvokeRequired) { try { BeginInvoke(new Action(() => Aviso(ms, title, text, icon, irPara))); } catch { } return; }
            try
            {
                if (toast != null && !toast.IsDisposed) toast.Close();
                toast = new Toast(title, text, icon == ToolTipIcon.Warning || icon == ToolTipIcon.Error, Math.Max(ms, 6000));
                toast.Clicked += () =>
                {
                    ShowWindow();
                    if (irPara && lastBalloon != null) GoTo(lastBalloon.Project, lastBalloon.Item);
                };
                toast.ShowNoFocus();
            }
            catch { try { tray.ShowBalloonTip(ms, title, text, icon); } catch { } }
        }

        static Icon MakeIcon(Color c)
        {
            using (var bmp = new Bitmap(32, 32))
            {
                using (var g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    g.Clear(Color.Transparent);
                    using (var br = new SolidBrush(c)) g.FillEllipse(br, 1, 1, 30, 30);
                    using (var f = new Font("Segoe UI", 11f, FontStyle.Bold, GraphicsUnit.Pixel))
                    using (var sf = new StringFormat())
                    {
                        sf.Alignment = StringAlignment.Center;
                        sf.LineAlignment = StringAlignment.Center;
                        g.DrawString("SW", f, Brushes.White, new RectangleF(0, 0, 32, 32), sf);
                    }
                }
                return Icon.FromHandle(bmp.GetHicon());
            }
        }

        // ------------------------------------------------------------ janela / bandeja
        public void ShowWindow()
        {
            Show();
            if (WindowState != FormWindowState.Maximized) WindowState = FormWindowState.Maximized;
            Activate();
            BringToFront();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!exiting && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
                if (!hintShown)
                {
                    hintShown = true;
                    tray.ShowBalloonTip(5000, "Monitor continua rodando", "Ele segue vigiando os projetos aqui perto do relógio. Clique duas vezes no ícone para abrir.", ToolTipIcon.Info);
                }
                return;
            }
            base.OnFormClosing(e);
        }

        // grava o tema escolhido e reabre o Monitor (as cores são aplicadas quando as telas são montadas)
        void TrocarTema(bool escuro)
        {
            if (escuro == Theme.Escuro) return;
            if (MessageBox.Show(this, "O Monitor vai reiniciar para aplicar o tema " + (escuro ? "escuro" : "claro") + ".\n\nContinuar?", "Tema",
                MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            try { Theme.GravarEscolha(escuro); }
            catch (Exception ex) { MessageBox.Show(this, "Não foi possível gravar o tema:\n" + ex.Message, "Tema", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            Reiniciar();
        }

        // reabre o Monitor (mesmos argumentos) e fecha este - usado para aplicar o tema
        void Reiniciar()
        {
            try
            {
                var args = Environment.GetCommandLineArgs().Skip(1).Where(x => !x.Equals("/bandeja", StringComparison.OrdinalIgnoreCase)).Select(x => "\"" + x + "\"").ToArray();
                var psi = new ProcessStartInfo(Application.ExecutablePath, string.Join(" ", args));
                psi.UseShellExecute = false;
                psi.WorkingDirectory = Path.GetDirectoryName(Application.ExecutablePath);
                Process.Start(psi);
            }
            catch (Exception ex) { MessageBox.Show(this, "Tema gravado. Feche e abra o Monitor para aplicar.\n\n" + ex.Message, "Tema", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            ExitApp();
        }

        void ExitApp()
        {
            exiting = true;
            engine.Stop();
            indexer.Stop();
            tray.Visible = false;
            tray.Dispose();
            Application.Exit();
        }

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        public static bool IsAutoStart()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue("MonitorSW") != null;
            }
            catch { return false; }
        }

        public static void SetAutoStart(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (on)
                    {
                        string cmd;
                        if (Util.Origin != null)
                        {
                            string local = Path.Combine(Path.Combine(Util.UserDir, "bin"), "Monitor.exe");
                            cmd = "\"" + local + "\" \"/dados=" + Util.AppDir.TrimEnd('\\') + "\" \"/origem=" + Util.Origin + "\" /bandeja";
                        }
                        else cmd = "\"" + Application.ExecutablePath + "\" /bandeja";
                        k.SetValue("MonitorSW", cmd);
                    }
                    else k.DeleteValue("MonitorSW", false);
                }
            }
            catch { }
        }

        // ------------------------------------------------------------ atualizacoes vindas do motor (outra thread)
        void OnEngineProgress(string s)
        {
            if (!IsHandleCreated) return;
            BeginInvoke(new Action(() => { lblStatus.Text = s; }));
        }

        void OnEngineUpdated(List<Ev> evs)
        {
            if (evs.Count > 0)
            {
                try { Engine.AppendHistory(engine.Cfg.HistoryPath, evs); } catch { }
            }
            if (!IsHandleCreated) return;
            BeginInvoke(new Action(() =>
            {
                foreach (var e in evs) AddHistRow(e, true);
                Notify(evs);
                RefreshAll();
            }));
        }

        int TotalPend()
        {
            int n = 0;
            lock (engine.Sync) foreach (var p in engine.Projects) n += p.Pend;
            return n;
        }

        void Notify(List<Ev> evs)
        {
            var list = evs;
            if (engine.Cfg.NotifyOthersOnly)
                list = evs.Where(e => string.IsNullOrEmpty(e.Who) || !e.Who.Equals(Environment.UserName, StringComparison.OrdinalIgnoreCase) && !e.Who.Equals(Users.Me, StringComparison.OrdinalIgnoreCase)).ToList();
            list = list.Where(Notificacoes.Aceita).ToList();   // Opções > Notificações: só dos usuários escolhidos
            if (list.Count == 0) return;
            list = list.OrderByDescending(e => e.Sev).ToList();
            lastBalloon = list[0];
            string title = list.Count == 1 ? list[0].Kind + ": " + list[0].Item : list.Count + " alterações nos projetos";
            var sb = new StringBuilder();
            foreach (var e in list.Take(4))
            {
                if (list.Count == 1)
                {
                    sb.Append(e.Who.Length > 0 ? "Salvo por " + e.Who + ". " : "");
                    sb.Append(e.Detail);
                }
                else
                {
                    sb.Append(e.Item + " - " + e.Kind + (e.Who.Length > 0 ? " (" + e.Who + ")" : "") + (e.Sev == 2 ? " -> PENDENTE" : "") + "\n");
                }
            }
            if (list.Count > 4) sb.Append("... e mais " + (list.Count - 4) + ". Clique para ver.");
            string text = sb.ToString();
            if (text.Length > 250) text = text.Substring(0, 247) + "...";
            if (title.Length > 60) title = title.Substring(0, 57) + "...";
            Aviso(15000, title, text, list[0].Sev == 2 ? ToolTipIcon.Warning : ToolTipIcon.Info, true);
        }

        void RefreshAll()
        {
            FillProjects();
            FillGrid();
            int pend = TotalPend();
            tray.Icon = pend > 0 ? icoPend : icoOk;
            Icon = tray.Icon;
            string t = "Monitor - " + (pend == 0 ? "tudo em dia" : pend + " pendência(s) de PDF/DXF");
            tray.Text = t.Length > 63 ? t.Substring(0, 63) : t;
        }

        void FillProjects()
        {
            List<Project> list;
            lock (engine.Sync) list = new List<Project>(engine.Projects);
            projList.BeginUpdate();
            var sel = current;
            projList.Items.Clear();
            foreach (var p in list)
            {
                var li = new ListViewItem(p.Name);
                li.Tag = p;
                li.ToolTipText = p.MainPath;
                if (p.Error != null) { li.ForeColor = Theme.PendText; li.ToolTipText = p.Error; }
                else if (p.LastScan == DateTime.MinValue) li.ForeColor = Theme.Muted;
                else { li.ForeColor = p.Pend > 0 ? Theme.WarnText : Theme.Text; li.ToolTipText = p.MainPath + "\n" + p.Pend + " sem detalhamento · " + p.Ok + " ok"; }
                projList.Items.Add(li);
                if (p == sel) li.Selected = true;
            }
            if (sel == null || !list.Contains(sel))
            {
                current = list.FirstOrDefault();
                if (projList.Items.Count > 0) projList.Items[0].Selected = true;
            }
            projList.EndUpdate();
        }

        // ------------------------------------------------------------ BOM
        HashSet<string> Collapsed()
        {
            HashSet<string> s;
            if (current == null) return new HashSet<string>();
            if (!collapsed.TryGetValue(current, out s))
            {
                s = new HashSet<string>(StringComparer.OrdinalIgnoreCase); // tudo aberto, igual a LISTA DE PEÇAS
                collapsed[current] = s;
            }
            return s;
        }

        void Toggle(int rowIndex)
        {
            if (!TreeMode || rowIndex < 0) return;
            var t = grid.Rows[rowIndex].Tag as NodeTag;
            if (t == null || !t.HasKids) return;
            var cl = Collapsed();
            if (!cl.Remove(t.Id)) cl.Add(t.Id);
            // a linha clicada (a submontagem que abriu/fechou) fica selecionada e e ela que aparece na miniatura
            fillingGrid = true;
            try
            {
                FillGridCore();
                foreach (DataGridViewRow r in grid.Rows)
                {
                    var rt = r.Tag as NodeTag;
                    if (rt != null && rt.Id == t.Id) { grid.CurrentCell = r.Cells[C_ITEM]; r.Selected = true; break; }
                }
            }
            finally { fillingGrid = false; }
            ShowDetail();
            Item ti;
            lock (engine.Sync) current.Items.TryGetValue(t.Key, out ti);
            if (ti != null) ShowPreview(ti.Path, ti.Name);
        }

        void ExpandAll(bool open)
        {
            var p = current;
            if (p == null) return;
            var cl = Collapsed();
            cl.Clear();
            if (open)
            {
                lock (engine.Sync)
                {
                    AddIds(p, p.MainPath, p.MainPath, cl, 0);
                    cl.RemoveWhere(id => { Item x; return p.Items.TryGetValue(id.Substring(id.LastIndexOf('>') + 1), out x) && x.Ignored; });
                }
            }
            if (!TreeMode) filter.SelectedIndex = 0; else FillGrid();
        }

        static void AddIds(Project p, string key, string id, HashSet<string> ex, int depth)
        {
            if (depth > 20) return;
            foreach (var c in p.Kids(key))
            {
                var cid = id + ">" + c.Child;
                if (p.Kids(c.Child).Count > 0) { ex.Add(cid); AddIds(p, c.Child, cid, ex, depth + 1); }
            }
        }

        class RowData
        {
            public Item It; public int Level; public int Qty; public NodeTag Tag; public bool Open; public string Num = "";
        }

        bool fillingGrid;

        void FillGrid()
        {
            fillingGrid = true;
            try { FillGridCore(); }
            finally { fillingGrid = false; }
            var sel = SelItem();
            if (sel != null) ShowPreview(sel.Path, sel.Name);
        }

        void FillGridCore()
        {
            var p = current;
            var selTag = grid.CurrentRow != null ? grid.CurrentRow.Tag as NodeTag : null;
            var selIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (DataGridViewRow sr in grid.SelectedRows) { var st = sr.Tag as NodeTag; if (st != null) selIds.Add(st.Id); }
            int firstRow = grid.FirstDisplayedScrollingRowIndex;
            grid.SuspendLayout();
            grid.Rows.Clear();
            if (p == null) { grid.ResumeLayout(); lblCounts.Text = ""; lblPendN.Text = ""; lblOkN.Text = ""; return; }
            if (p.Error != null) lblStatus.Text = p.Name + ": " + p.Error;
            int mode = Mode;
            string q = ServerMode ? "" : search.Text.Trim();
            var data = new List<RowData>();
            int itemCount;
            lock (engine.Sync)
            {
                itemCount = p.Items.Count;
                if (TreeMode)
                {
                    bool filtered = mode == 2 || q.Length > 0;
                    Item root;
                    if (p.Items.TryGetValue(p.MainPath, out root))
                    {
                        // primeira linha: a montagem principal (código + descrição); depois os itens dela
                        var rt = new NodeTag(); rt.Id = p.MainPath; rt.Key = root.Key; rt.HasKids = false;
                        var rr = new RowData(); rr.It = root; rr.Level = 0; rr.Qty = 1; rr.Tag = rt; rr.Num = "";
                        data.Add(rr);
                        BuildKids(p, root, p.MainPath, 0, "", mode, q, filtered, Collapsed(), data, new HashSet<string>(StringComparer.OrdinalIgnoreCase));
                    }
                }
                else
                {
                    foreach (var it in p.Items.Values.OrderByDescending(i => i.Sev).ThenBy(i => i.Name))
                    {
                        if (string.Equals(it.Key, p.MainPath, StringComparison.OrdinalIgnoreCase)) continue;
                        if (q.Length > 0 && !Match(it, q)) continue;
                        if (q.Length == 0)
                        {
                            if (mode == 3 && (it.Ignored || it.Sev < 2)) continue;
                            if (mode == 4 && (it.Ignored || it.IsAsm && !it.IsWeld)) continue;
                            if (mode == 10 && !it.Ignored) continue;
                            if (mode == 11 && (it.Ignored || it.Sev < 2 || !it.IsLaser)) continue;
                            if (mode == 12 && (it.Ignored || it.Sev < 2 || !it.IsMach)) continue;
                            if (mode == 13 && (it.Ignored || it.Sev < 2 || !it.IsAsm)) continue;
                            if (mode == 6 && !it.IsException) continue;
                            if (mode == 7 && !it.Mark.StartsWith("PEND", StringComparison.OrdinalIgnoreCase)) continue;
                            if (mode == 8 && !it.Mark.StartsWith("REVIS", StringComparison.OrdinalIgnoreCase)) continue;
                        }
                        var t = new NodeTag(); t.Id = it.Key; t.Key = it.Key;
                        var rd = new RowData(); rd.It = it; rd.Level = 0; rd.Qty = it.TotQty; rd.Tag = t;
                        data.Add(rd);
                    }
                }
            }
            var rows = new List<DataGridViewRow>(data.Count);
            foreach (var d in data) rows.Add(MakeRow(d));
            grid.Rows.AddRange(rows.ToArray());
            if (!TreeMode && sortCol >= 0 && sortDir != SortOrder.None)
                grid.Sort(grid.Columns[sortCol], sortDir == SortOrder.Ascending ? System.ComponentModel.ListSortDirection.Ascending : System.ComponentModel.ListSortDirection.Descending);
            if (selTag != null)
            {
                foreach (DataGridViewRow r in grid.Rows)
                {
                    var t = r.Tag as NodeTag;
                    if (t != null && (t.Id == selTag.Id || (!TreeMode && t.Key == selTag.Key))) { grid.CurrentCell = r.Cells[C_ITEM]; r.Selected = true; break; }
                }
                // mantém a seleção múltipla depois de atualizar a lista
                if (selIds.Count > 1)
                    foreach (DataGridViewRow r in grid.Rows) { var t = r.Tag as NodeTag; if (t != null && selIds.Contains(t.Id)) r.Selected = true; }
            }
            if (firstRow >= 0 && firstRow < grid.Rows.Count) { try { grid.FirstDisplayedScrollingRowIndex = firstRow; } catch { } }
            grid.ResumeLayout();
            string reading = p.PropsPending > 0 ? "   (lendo propriedades: faltam " + p.PropsPending + ")" : "";
            if (!ServerMode)
            {
                lblPendN.Text = "● " + p.Pend + (engine.CheckUpdates ? " pendentes" : " sem detalhamento");
                lblOkN.Text = "● " + p.Ok + " ok";
                lblCounts.Text = itemCount + " itens" + (p.PropsPending > 0 ? " · lendo " + p.PropsPending : "");
            }
            ShowDetail();
        }

        static bool Match(Item it, string q)
        {
            return it.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 || it.Desc.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        // filhos na ordem da LISTA DE PEÇAS: primeiro as peças, depois as submontagens (cada grupo na ordem da árvore do SolidWorks)
        bool BuildKids(Project p, Item it, string id, int level, string num, int mode, string q, bool filtered, HashSet<string> collapsedIds, List<RowData> outRows, HashSet<string> stack)
        {
            bool any = false;
            int n = 0;
            var kids = p.Kids(it.Key).Select((k, i) => new { k, i })
                .OrderBy(x => { Item ci; return p.Items.TryGetValue(x.k.Child, out ci) && ci.IsAsm ? 1 : 0; }).ThenBy(x => x.i).Select(x => x.k).ToList();
            foreach (var c in kids)
            {
                Item ci;
                if (!p.Items.TryGetValue(c.Child, out ci)) continue;
                if (mode == 1 && ci.Ignored && !filtered) continue;
                n++;
                string cnum = num.Length == 0 ? n.ToString() : num + "." + n;
                if (BuildTree(p, ci, id + ">" + c.Child, level, c.Qty, cnum, mode, q, filtered, collapsedIds, outRows, stack)) any = true;
            }
            return any;
        }

        // devolve true se o no (ou algo abaixo dele) entrou na lista
        bool BuildTree(Project p, Item it, string id, int level, int qty, string num, int mode, string q, bool filtered, HashSet<string> collapsedIds, List<RowData> outRows, HashSet<string> stack)
        {
            if (level > 20 || !stack.Add(it.Key)) return false;
            var t = new NodeTag(); t.Id = id; t.Key = it.Key; t.HasKids = p.Kids(it.Key).Count > 0;
            var me = new RowData(); me.It = it; me.Level = level; me.Qty = qty; me.Tag = t; me.Num = num;
            int pos = outRows.Count;
            outRows.Add(me);
            bool selfMatch = !filtered || (q.Length > 0 ? Match(it, q) : (!it.Ignored && it.Sev == 2));
            // todas as submontagens começam fechadas (como no SolidWorks); o conjunto guarda as que o usuário abriu
            bool inSet = collapsedIds.Contains(id);
            bool open = filtered || inSet;
            me.Open = open && t.HasKids;
            t.Open = me.Open;
            bool anyKid = false;
            if (open && t.HasKids) anyKid = BuildKids(p, it, id, level + 1, num, mode, q, filtered, collapsedIds, outRows, stack);
            stack.Remove(it.Key);
            if (filtered && !selfMatch && !anyKid)
            {
                outRows.RemoveRange(pos, outRows.Count - pos);
                return false;
            }
            return true;
        }

        DataGridViewRow MakeRow(RowData d)
        {
            var it = d.It;
            var r = new DataGridViewRow();
            r.CreateCells(grid);
            string tog = "";
            if (TreeMode && d.Tag.HasKids) tog = d.Open ? "▼" : "▶";
            string need = it.Need;
            if (it.NeedPdf && it.Process.Length > 0 && it.Process != "Fabricada" && it.Process != "não lido" && it.Process != "lendo...") need += " (" + it.Process.ToLowerInvariant() + ")";
            bool principal = current != null && string.Equals(it.Key, current.MainPath, StringComparison.OrdinalIgnoreCase);
            string desc = it.IsAsm ? AsmDesc(it, principal) : it.Desc;
            r.Cells[C_TOG].Value = tog;
            r.Cells[C_NUM].Value = d.Num;
            r.Cells[C_ITEM].Value = it.Name + (TreeMode && it.IsAsm && it.PendBelow > 0 ? "   (" + it.PendBelow + " pend.)" : "");
            r.Cells[C_DESC].Value = desc;
            r.Cells[C_QTD].Value = d.Qty;
            foreach (var kv in propCols) r.Cells[kv.Key].Value = it.P(kv.Value);
            r.Cells[C_NEED].Value = need;
            r.Cells[C_SIT].Value = it.Status + (it.OldFormat ? " (formato antigo)" : "");
            string des = DesSt(it);
            r.Cells[C_DES].Value = des;
            r.Cells[C_PDF].Value = it.PdfSt;
            r.Cells[C_DXF].Value = it.DxfSt;
            r.Cells[C_APR].Value = it.Aprov;
            r.Cells[C_BLQ].Value = it.IsBlocked ? "Sim" : "";
            r.Cells[C_WHO].Value = it.LastBy ?? "";
            r.Cells[C_MOD].Value = D(it.Model);
            r.Cells[C_DRW].Value = D(it.Drw);
            r.Cells[C_PDFD].Value = D(it.Pdf);
            r.Cells[C_DXFD].Value = D(it.Dxf);
            r.Cells[C_DIR].Value = it.Folder;
            r.Tag = d.Tag;
            // recuo da arvore: cada nivel anda para a direita; pecas ficam um pouco mais para dentro que as submontagens do mesmo nivel
            int indent = d.Level * IndentStep + (TreeMode && !it.IsAsm && d.Level > 0 ? 10 : 0);
            r.Cells[C_ITEM].Style.Padding = new Padding(indent, 0, 0, 0);
            if (TreeMode && d.Level > 0) r.Cells[C_NUM].Style.Padding = new Padding(d.Level * 8, 0, 0, 0);
            if (it.IsAsm)
            {
                var bold = Theme.UiBold;
                r.Cells[C_ITEM].Style.Font = bold;
                r.Cells[C_DESC].Style.Font = bold;
                r.Cells[C_QTD].Style.Font = bold;
                r.DefaultCellStyle.BackColor = AsmBg;
            }
            if (it.Ignored) { r.Cells[C_NEED].Style.ForeColor = Theme.Muted; r.Cells[C_SIT].Style.ForeColor = Theme.Muted; }
            if (it.Sev == 1) r.Cells[C_SIT].Style.ForeColor = Theme.Muted;
            if (it.Sev == 2)
            {
                var bg = it.Status.StartsWith("Sem") ? OrangeBg : RedBg;
                foreach (var ci in new int[] { C_NEED, C_SIT, C_DES, C_PDF, C_DXF }) r.Cells[ci].Style.BackColor = bg;
                r.Cells[C_ITEM].Style.BackColor = bg;
            }
            if (it.Sev == 2) r.Cells[C_SIT].Style.ForeColor = it.Status.StartsWith("Sem") ? Theme.WarnText : Theme.PendText;
            if (it.Sev == 0 && !it.Ignored && it.NeedPdf) r.Cells[C_SIT].Style.ForeColor = Theme.OkText;
            if (it.PdfSt.StartsWith("Desatualizado") || it.PdfSt == "Falta") r.Cells[C_PDF].Style.ForeColor = Theme.PendText;
            if (it.DxfSt.StartsWith("Desatualizado") || it.DxfSt == "Falta") r.Cells[C_DXF].Style.ForeColor = Theme.PendText;
            if (it.PdfSt.StartsWith("Tem")) r.Cells[C_PDF].Style.ForeColor = Theme.OkText;
            r.Cells[C_DES].Style.ForeColor = des.StartsWith("✓") ? Theme.OkText : des.StartsWith("✗") ? Theme.PendText : Theme.Muted;
            if (it.DxfSt.StartsWith("Tem")) r.Cells[C_DXF].Style.ForeColor = Theme.OkText;
            if (it.IsException)
            {
                // item de exceção (representação etc.) fica roxo
                foreach (DataGridViewCell c in r.Cells) { c.Style.BackColor = PurpleBg; c.Style.ForeColor = Purple; }
            }
            else if (it.Mark.StartsWith("PEND", StringComparison.OrdinalIgnoreCase)) r.Cells[C_SIT].Style.ForeColor = Theme.WarnText;
            else if (it.Mark.StartsWith("REVIS", StringComparison.OrdinalIgnoreCase)) r.Cells[C_SIT].Style.ForeColor = Theme.OkText;
            if (it.IsBlocked) r.Cells[C_BLQ].Style.ForeColor = Theme.WarnText;
            if (it.NeedDxf) r.Cells[C_NEED].Style.ForeColor = Theme.LaserTxt;
            r.Cells[C_TOG].Style.ForeColor = Theme.Accent;
            return r;
        }

        static object D(DateTime d) { return d == DateTime.MinValue ? (object)null : d; }

        // itens das linhas selecionadas (Ctrl / Shift), sem repetir
        List<Item> SelItems()
        {
            var res = new List<Item>();
            if (current == null) return res;
            var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var rows = grid.SelectedRows.Cast<DataGridViewRow>().OrderBy(r => r.Index).ToList();
            lock (engine.Sync)
                foreach (var r in rows)
                {
                    var t = r.Tag as NodeTag; Item it;
                    if (t == null || !keys.Add(t.Key)) continue;
                    if (current.Items.TryGetValue(t.Key, out it) && !string.Equals(it.Key, current.MainPath, StringComparison.OrdinalIgnoreCase)) res.Add(it);
                }
            return res;
        }

        // seleção múltipla: só conferido / pendente / exceção
        void MenuVarios(List<Item> its, DataGridViewCellMouseEventArgs a)
        {
            cellMenu.Items.Clear();
            var titulo = new ToolStripMenuItem(its.Count + " itens selecionados"); titulo.Enabled = false;
            cellMenu.Items.Add(titulo);
            cellMenu.Items.Add(new ToolStripSeparator());
            cellMenu.Items.Add(Mi("Marcar como conferido (está em dia)   ✔", (s, e) => MarcarConferidoVarios(its)));
            cellMenu.Items.Add(Mi("Marcar como pendente (revisar depois)", (s, e) => SetMarkVarios(its, "PENDENTE")));
            cellMenu.Items.Add(Mi("Exceção (não precisa detalhamento)", (s, e) => SetMarkVarios(its, "EXCECAO")));
            DarkMenus(cellMenu);
            var r = grid.GetCellDisplayRectangle(a.ColumnIndex, a.RowIndex, false);
            cellMenu.Show(grid, new Point(r.Left + a.X, r.Top + a.Y));
        }

        static string ListaNomes(List<Item> its)
        {
            var nomes = its.Take(12).Select(i => i.Name).ToList();
            return string.Join(", ", nomes.ToArray()) + (its.Count > 12 ? " … (+" + (its.Count - 12) + ")" : "");
        }

        void MarcarConferidoVarios(List<Item> its)
        {
            its = its.Where(i => !i.Ignored && !i.Missing).ToList();
            if (its.Count == 0) return;
            if (MessageBox.Show("Confirmar que estes " + its.Count + " itens estão em dia (3D, desenho, PDF e DXF batem)?\n\n" + ListaNomes(its) + "\n\nVale até alguém alterar algum desses arquivos.",
                    "Conferência", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string quem = "✓ Conferido por " + Users.Me + " em " + DateTime.Now.ToString("dd/MM/yy");
            lblStatus.Text = "Gravando conferência de " + its.Count + " itens…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string err = Conf.SaveMany(its.Select(i => new KeyValuePair<Item, string>(i, quem)).ToList());
                // conferido = sai a marcação PENDENTE
                var tirar = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var i in its) if (i.Mark.StartsWith("PEND", StringComparison.OrdinalIgnoreCase)) tirar[i.Name] = "";
                if (err == null && tirar.Count > 0) err = Marks.SetMany(tirar);
                if (err == null) engine.SetCheckUpdates(true);
                try { BeginInvoke(new Action(() => { if (err == null) { if (!miCheck.Checked) miCheck.Checked = true; lblStatus.Text = its.Count + " itens conferidos."; Aviso(3000, "Monitor", its.Count + " itens marcados como conferidos.", ToolTipIcon.Info); } else MessageBox.Show("Não gravou: " + err, "Conferência"); })); } catch { }
            });
        }

        void SetMarkVarios(List<Item> its, string kind)
        {
            if (its.Count == 0) return;
            string label = kind == "EXCECAO" ? "EXCEÇÃO (não precisa detalhamento)" : "PENDENTE (revisar depois)";
            if (MessageBox.Show("Marcar estes " + its.Count + " itens como " + label + "?\n\n" + ListaNomes(its) + "\n\nVale para todos que usam o Monitor e em todas as montagens que usam estes itens.",
                    "Confirmar", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string value = kind + " - " + Users.Me + " " + DateTime.Now.ToString("dd/MM/yy");
            var vals = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var i in its) vals[i.Name] = value;
            lblStatus.Text = "Gravando marcação de " + its.Count + " itens…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string err = Marks.SetMany(vals);
                if (err == null) engine.SetCheckUpdates(engine.CheckUpdates);
                try { BeginInvoke(new Action(() => { if (err == null) { lblStatus.Text = its.Count + " itens: " + label; Aviso(3000, "Monitor", its.Count + " itens marcados como " + label + ".", ToolTipIcon.Info); } else MessageBox.Show("Não gravou: " + err, "Marcação", MessageBoxButtons.OK, MessageBoxIcon.Warning); })); } catch { }
            });
        }

        Item SelItem()
        {
            if (current == null || grid.CurrentRow == null) return null;
            var t = grid.CurrentRow.Tag as NodeTag;
            if (t == null) return null;
            Item it;
            lock (engine.Sync) current.Items.TryGetValue(t.Key, out it);
            return it;
        }

        void ShowDetail()
        {
            var it = SelItem();
            FillProcPanel(it);
            if (it == null || histItem == null || !string.Equals(it.Key, histItem.Key, StringComparison.OrdinalIgnoreCase) || it.Model != histItem.Model || it.LastBy != histItem.LastBy) ShowHistory(it);
            if (it == null) { whereBox.Text = "Selecione um item na BOM para ver detalhes e onde ele é usado."; return; }
            whereBox.Text = Describe(it.Key);
        }

        // caixinhas com os processos da peça (TORNO, TORNO CNC, FRESA...) no topo da aba Processos
        void FillProcPanel(Item it)
        {
            procPanel.SuspendLayout();
            foreach (Control c in procPanel.Controls) c.Dispose();
            procPanel.Controls.Clear();
            if (it != null)
            {
                Color laser = Theme.LaserTxt, ok = Theme.OkText, bad = Theme.PendText, mute = Theme.Muted;
                string proc = it.Process ?? "";
                Color pcol = proc.StartsWith("Laser") ? laser : proc == "Solda" ? Theme.Solda : proc == "Usinagem" ? Theme.Accent : proc == "Comercial" ? mute : Theme.Text;
                AddProcBox("PROCESSO", proc.Length > 0 ? proc : "–", pcol, 130);
                AddProcBox("EXIGE", string.IsNullOrEmpty(it.Need) ? "–" : it.Need, it.NeedDxf ? laser : it.NeedPdf ? Theme.Accent : mute, 110);
                AddProcBox("PDF", ReqText(it.NeedPdf, it.PdfSt), ReqColor(it.NeedPdf, it.PdfSt), 96);
                AddProcBox("DXF", ReqText(it.NeedDxf, it.DxfSt), ReqColor(it.NeedDxf, it.DxfSt), 96);
                if (it.Mark.Length > 0)
                {
                    string mk = it.Mark.ToUpperInvariant();
                    AddProcBox("MARCAÇÃO", mk.StartsWith("EXCE") ? "Exceção" : mk.StartsWith("PEND") ? "Pendente" : mk.StartsWith("REVIS") ? "Revisado" : it.Mark,
                        mk.StartsWith("EXCE") ? Purple : mk.StartsWith("PEND") ? Theme.WarnText : Theme.OkText, 110);
                }
                AddProcBox("DETALHAMENTO", it.Drw != DateTime.MinValue ? "Tem" : (it.NeedPdf ? "Falta" : "–"), it.Drw != DateTime.MinValue ? ok : (it.NeedPdf ? bad : mute), 120);
                // processos de fabricação (TORNO, FRESA...) ficam na linha de baixo
                procPanel.SetFlowBreak(procPanel.Controls[procPanel.Controls.Count - 1], true);
            }
            foreach (var pc in procCols)
            {
                string v = it == null ? "" : it.P(pc);
                var box = new Panel(); box.Width = 96; box.Height = 48; box.Margin = new Padding(0, 0, 8, 8);
                box.BackColor = v.Length > 0 ? Theme.AsmRow : Theme.Surface2;
                var t = new Label(); t.Text = pc.ToUpperInvariant(); t.Dock = DockStyle.Top; t.Height = 20; t.ForeColor = Theme.Muted; t.Font = Theme.UiFont; t.TextAlign = ContentAlignment.MiddleCenter;
                var val = new Label(); val.Text = v.Length > 0 ? v : "–"; val.Dock = DockStyle.Fill; val.ForeColor = v.Length > 0 ? Theme.Text : Theme.Muted; val.Font = Theme.UiBold; val.TextAlign = ContentAlignment.MiddleCenter;
                box.Controls.Add(val); box.Controls.Add(t);
                procPanel.Controls.Add(box);
            }
            procPanel.ResumeLayout();
        }

        // grava a marcação na propriedade do arquivo (feito uma vez; vale para todos e para todas as montagens)
        void SetMark(Item it, string kind)
        {
            if (it == null) return;
            string label = kind == "EXCECAO" ? "EXCEÇÃO (não precisa detalhamento)" : kind == "PENDENTE" ? "PENDENTE (revisar depois)" : kind == "REVISADO" ? "REVISADO" : "sem marcação";
            string value = kind.Length == 0 ? "" : kind + " - " + Users.Me + " " + DateTime.Now.ToString("dd/MM/yy");
            string msg = kind.Length == 0
                ? "Limpar a marcação de " + it.Name + "?\n\n(Atual: " + it.Mark + ")"
                : "Marcar " + it.Name + " como " + label + "?";
            msg += "\n\nVale para todos que usam o Monitor e em todas as montagens que usam este item.";
            if (MessageBox.Show(msg, "Confirmar", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string name = it.Name;
            lblStatus.Text = "Gravando marcação de " + name + "…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string err = Marks.Set(name, value);
                if (err == null) engine.SetCheckUpdates(engine.CheckUpdates); // reclassifica e atualiza a tela na hora
                if (!IsHandleCreated) return;
                BeginInvoke(new Action(() =>
                {
                    if (err == null)
                    {
                        lblStatus.Text = name + ": " + label;
                        Aviso(3000, "Monitor", name + " marcado como " + label + ".", ToolTipIcon.Info);
                    }
                    else
                    {
                        lblStatus.Text = "Não gravou a marcação de " + name + ".";
                        MessageBox.Show(err, "Marcação", MessageBoxButtons.OK, err.StartsWith("AVISO") ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                    }
                }));
            });
        }

        static string ReqText(bool need, string st)
        {
            st = st ?? "";
            if (st.StartsWith("Tem") || st.StartsWith("OK")) return st.StartsWith("OK") ? "Em dia" : "Tem";
            if (st.StartsWith("Desatualizado")) return "Desatualizado";
            if (st == "Falta") return "Falta";
            return need ? "Falta" : "Não exige";
        }
        static Color ReqColor(bool need, string st)
        {
            var t = ReqText(need, st);
            return t == "Tem" || t == "Em dia" ? Theme.OkText : t == "Falta" || t == "Desatualizado" ? Theme.PendText : Theme.Muted;
        }

        void AddProcBox(string title, string value, Color color, int width)
        {
            var box = new Panel(); box.Width = width; box.Height = 48; box.Margin = new Padding(0, 0, 8, 8);
            box.BackColor = Theme.Surface2;
            var bar = new Panel(); bar.Dock = DockStyle.Left; bar.Width = 4; bar.BackColor = color;
            var t = new Label(); t.Text = title; t.Dock = DockStyle.Top; t.Height = 20; t.ForeColor = Theme.Muted; t.Font = Theme.UiFont; t.TextAlign = ContentAlignment.MiddleCenter;
            var v = new Label(); v.Text = value; v.Dock = DockStyle.Fill; v.ForeColor = color; v.Font = Theme.UiBold; v.TextAlign = ContentAlignment.MiddleCenter;
            box.Controls.Add(v); box.Controls.Add(t); box.Controls.Add(bar);
            procPanel.Controls.Add(box);
        }

        // ---- edição de descrição / acabamento (clique direito na célula)
        void GridRightClick(DataGridViewCellMouseEventArgs a)
        {
            if (a.Button != MouseButtons.Right || a.RowIndex < 0) return;
            // clicou com o direito numa linha que faz parte de uma seleção múltipla: menu reduzido para todos
            if (grid.Rows[a.RowIndex].Selected && grid.SelectedRows.Count > 1)
            {
                var its = SelItems();
                if (its.Count > 1) { MenuVarios(its, a); return; }
            }
            grid.CurrentCell = grid.Rows[a.RowIndex].Cells[Math.Max(C_ITEM, Math.Min(a.ColumnIndex, grid.Columns.Count - 1))];
            var it = SelItem();
            if (it == null) return;
            cellMenu.Items.Clear();
            if (a.ColumnIndex == C_DESC || a.ColumnIndex == C_ACAB || a.ColumnIndex == C_ITEM)
            {
                cellMenu.Items.Add(Mi("Editar descrição...", (s, e) => EditProp(it, engine.Cfg.DescProp, "Descrição", false)));
                cellMenu.Items.Add(Mi("Editar acabamento...", (s, e) => EditProp(it, "ACABAMENTO", "Acabamento", true)));
                cellMenu.Items.Add(new ToolStripSeparator());
            }
            // marcações valem para qualquer item (peça, submontagem ou comercial), pendente ou não
            {
                cellMenu.Items.Add(Mi(it.IsException ? "Desfazer exceção" : "Exceção (não precisa detalhamento)", (s, e) => SetMark(it, it.IsException ? "" : "EXCECAO")));
                cellMenu.Items.Add(Mi("Marcar como pendente (revisar depois)", (s, e) => SetMark(it, "PENDENTE")));
                if (it.Mark.Length > 0) cellMenu.Items.Add(Mi("Limpar marcação", (s, e) => SetMark(it, "")));
                cellMenu.Items.Add(new ToolStripSeparator());
            }
            if (it != null && !it.Ignored && !it.Missing)
                cellMenu.Items.Add(Mi("Marcar como conferido (está em dia)   ✔", (s, e) => MarcarConferido(it)));
            cellMenu.Items.Add(Mi("Gerar detalhamento...", (s, e) => GenerateDetail()));
            cellMenu.Items.Add(new ToolStripSeparator());
            cellMenu.Items.Add(Mi("Abrir detalhamento", (s, e) => OpenSel(1)));
            cellMenu.Items.Add(Mi("Abrir PDF", (s, e) => OpenSel(2)));
            cellMenu.Items.Add(Mi("Abrir DXF", (s, e) => OpenSel(4)));
            cellMenu.Items.Add(Mi("Abrir modelo no SolidWorks", (s, e) => OpenSel(0)));
            cellMenu.Items.Add(Mi("Mostrar na pasta", (s, e) => OpenSel(3)));
            DarkMenus(cellMenu);
            var r = grid.GetCellDisplayRectangle(a.ColumnIndex, a.RowIndex, false);
            cellMenu.Show(grid, new Point(r.Left + a.X, r.Top + a.Y));
        }

        List<string> AcabList()
        {
            var set = new List<string>();
            Action<string> add = v => { v = (v ?? "").Trim(); if (v.Length > 0 && !set.Any(x => x.Equals(v, StringComparison.OrdinalIgnoreCase))) set.Add(v); };
            foreach (var o in engine.Cfg.AcabOptions) add(o);
            lock (engine.Sync) foreach (var p in engine.Projects) foreach (var i in p.Items.Values) add(i.P("ACABAMENTO"));
            try { foreach (var v in indexer.AcabValues()) add(v); } catch { }
            return set.OrderBy(x => x).ToList();
        }

        void EditProp(Item it, string prop, string label, bool list)
        {
            string old = prop == engine.Cfg.DescProp ? it.Desc : it.P(prop);
            string nv;
            using (var f = new Form())
            {
                f.Text = "Editar " + label.ToLowerInvariant() + " - " + it.Name;
                f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(480, 130); Theme.Style(f);
                var l = new Label(); l.Text = label + " de " + it.Name + ":"; l.SetBounds(12, 12, 456, 20); l.ForeColor = Theme.Muted;
                Control input;
                if (list)
                {
                    var cb = new ComboBox(); cb.DropDownStyle = ComboBoxStyle.DropDown; cb.SetBounds(12, 38, 456, 24);
                    cb.Items.AddRange(AcabList().Cast<object>().ToArray()); cb.Text = old;
                    cb.AutoCompleteMode = AutoCompleteMode.SuggestAppend; cb.AutoCompleteSource = AutoCompleteSource.ListItems;
                    cb.BackColor = Theme.Surface; cb.ForeColor = Theme.Text; cb.FlatStyle = FlatStyle.Flat;
                    input = cb;
                    f.Shown += (s, a) => { cb.Focus(); cb.DroppedDown = true; };
                }
                else
                {
                    var tb = new TextBox(); tb.Text = old; tb.SetBounds(12, 38, 456, 24);
                    tb.BackColor = Theme.Surface; tb.ForeColor = Theme.Text; tb.BorderStyle = BorderStyle.FixedSingle;
                    input = tb;
                    f.Shown += (s, a) => { tb.Focus(); tb.SelectAll(); };
                }
                var ok = new Button(); ok.Text = "Salvar"; ok.DialogResult = DialogResult.OK; ok.SetBounds(292, 86, 84, 30);
                var ca = new Button(); ca.Text = "Cancelar"; ca.DialogResult = DialogResult.Cancel; ca.SetBounds(384, 86, 84, 30);
                foreach (var b in new[] { ok, ca }) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Theme.Border; b.BackColor = Theme.Surface2; b.ForeColor = Theme.Text; }
                ok.BackColor = Theme.Accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderColor = Theme.Accent;
                f.Controls.AddRange(new Control[] { l, input, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                if (f.ShowDialog(this) != DialogResult.OK) return;
                nv = input.Text.Trim();
            }
            if (nv == (old ?? "").Trim()) return;
            if (MessageBox.Show("Alterar " + label.ToUpperInvariant() + " de " + it.Name + "?\n\nDe:   " + (string.IsNullOrEmpty(old) ? "(vazio)" : old) + "\nPara: " + (nv.Length == 0 ? "(vazio)" : nv) +
                    "\n\nIsso grava no arquivo do SolidWorks e vale para todas as montagens que usam esta peça.",
                    "Confirmar alteração", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string path = it.Path, name = it.Name;
            lblStatus.Text = "Gravando " + label.ToLowerInvariant() + " em " + name + " (pelo SolidWorks)…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string err = SwWriter.SetProps(path, new Dictionary<string, string> { { prop, nv } });
                if (!IsHandleCreated) return;
                BeginInvoke(new Action(() =>
                {
                    if (err == null)
                    {
                        lblStatus.Text = label + " de " + name + " atualizado(a): " + nv;
                        Aviso(3000, "Monitor", label + " de " + name + " atualizado(a).", ToolTipIcon.Info);
                        engine.Kick();
                    }
                    else
                    {
                        lblStatus.Text = "Não gravou " + label.ToLowerInvariant() + " de " + name + ".";
                        MessageBox.Show(err, "Editar " + label.ToLowerInvariant(), MessageBoxButtons.OK, err.StartsWith("AVISO") ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                    }
                }));
            });
        }

        string Describe(string key)
        {
            var sb = new StringBuilder();
            List<Project> list;
            lock (engine.Sync) list = new List<Project>(engine.Projects);
            Item it = null;
            foreach (var p in list) { lock (engine.Sync) { if (p.Items.TryGetValue(key, out it)) break; } }
            if (it != null)
            {
                sb.AppendLine(it.Name + "   " + it.Desc + "   (" + (it.IsAsm ? (it.IsWeld ? "submontagem de solda" : "montagem") : "peça") + ")");
                sb.AppendLine(it.Path);
                sb.AppendLine("Processo: " + it.Process + (it.MachSteps.Length > 0 ? " [" + it.MachSteps + "]" : "") + "   |  Exige: " + it.Need
                    + (it.Aprov.Length > 0 ? "   |  Aprovado: " + it.Aprov : "") + (it.IsBlocked ? "   |  BLOQUEADO" : ""));
                sb.AppendLine("Situação: " + it.Status + (it.Reason.Length > 0 ? "  <- " + it.Reason : ""));
                sb.AppendLine("Modelo salvo: " + Util.Fmt(it.Model) + (string.IsNullOrEmpty(it.LastBy) ? "" : " por " + it.LastBy)
                    + "   |  Desenho: " + (it.Drw == DateTime.MinValue ? "não existe" : Util.Fmt(it.Drw))
                    + "   |  PDF: " + (it.Pdf == DateTime.MinValue ? "não existe" : Util.Fmt(it.Pdf) + (it.PdfVer.Length > 0 ? " (" + it.PdfVer + ")" : ""))
                    + "   |  DXF: " + (it.Dxf == DateTime.MinValue ? "não existe" : Util.Fmt(it.Dxf) + (it.DxfVer.Length > 0 ? " (" + it.DxfVer + ")" : "")));
                if (it.OldFormat) sb.AppendLine("Arquivo em formato antigo (antes do SolidWorks 2015): abra e salve no 2016 para o monitor ler as propriedades.");
                sb.AppendLine();
            }
            int total = 0;
            foreach (var p in list)
            {
                List<List<string>> chains;
                Item pi;
                lock (engine.Sync)
                {
                    if (!p.Items.TryGetValue(key, out pi)) continue;
                    chains = p.Chains(key, 40);
                }
                total++;
                sb.AppendLine("ONDE É USADO em " + p.Name + "  (" + chains.Count + (chains.Count >= 40 ? "+" : "") + " caminho(s), " + pi.TotQty + " un. na máquina):");
                foreach (var c in chains)
                {
                    sb.Append("   ");
                    for (int i = 0; i < c.Count; i++)
                    {
                        Item ci; string extra = "";
                        lock (engine.Sync) { if (i > 0 && p.Items.TryGetValue(c[i], out ci) && ci.Sev == 2) extra = " [" + ci.Status + "]"; }
                        sb.Append((i > 0 ? "  >  " : "") + Util.NameOf(c[i]) + extra);
                    }
                    sb.AppendLine();
                }
                if (pi.IsAsm)
                {
                    List<TreeRef> ch;
                    lock (engine.Sync) ch = p.Kids(key);
                    sb.AppendLine("   Componentes diretos (" + ch.Count + "): " + string.Join(", ", ch.Select(x => Util.NameOf(x.Child) + (x.Qty > 1 ? " x" + x.Qty : "")).Take(40).ToArray()) + (ch.Count > 40 ? "..." : ""));
                }
                sb.AppendLine();
            }
            if (total == 0) sb.AppendLine("Não aparece em nenhum dos projetos abertos.");
            else if (list.Count > 1) sb.AppendLine("Aparece em " + total + " de " + list.Count + " projetos abertos no monitor. Antes de alterar, confira se a mudança serve para todos.");
            return sb.ToString();
        }

        void AskWhereUsed()
        {
            string q = Prompt("Onde é usado", "Digite o código (ou parte do nome/descrição) da peça ou submontagem:", search.Text);
            if (string.IsNullOrWhiteSpace(q)) return;
            q = q.Trim();
            var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            lock (engine.Sync)
                foreach (var p in engine.Projects)
                    foreach (var it in p.Items.Values)
                        if (it.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0) keys.Add(it.Key);
            var sb = new StringBuilder();
            // 1) todas as maquinas do servidor (indice)
            var hits = indexer.Search(q, 300);
            sb.AppendLine("EM TODAS AS MÁQUINAS DO SERVIDOR (índice" + (indexer.LastBuild == DateTime.MinValue ? "" : " de " + indexer.LastBuild.ToString("dd/MM HH:mm")) + "):");
            if (hits.Count == 0) sb.AppendLine(indexer.Machines == 0 ? "   O índice ainda está sendo montado (veja o rodapé). Tente de novo em alguns minutos." : "   \"" + q + "\" não aparece em nenhuma máquina.");
            foreach (var g in hits.GroupBy(h => h.Code))
            {
                var first = g.First();
                sb.AppendLine("   " + first.Code + "   " + first.Desc + "   [" + first.Proc + "]");
                foreach (var h in g) sb.AppendLine("      " + h.Machine.PadRight(45) + " qtd " + h.Qty.ToString().PadLeft(4) + "   via: " + h.Chains);
            }
            if (hits.Count >= 300) sb.AppendLine("   ... muitos resultados, refine a busca.");
            sb.AppendLine();
            sb.AppendLine(new string('=', 100));
            // 2) detalhes nos projetos abertos no monitor
            if (keys.Count == 0) sb.AppendLine("Nos projetos abertos no monitor: \"" + q + "\" não aparece.");
            if (keys.Count > 15) sb.AppendLine(keys.Count + " itens encontrados; mostrando os 15 primeiros. Refine a busca.\n");
            foreach (var k in keys.OrderBy(x => x).Take(15)) { sb.AppendLine(Describe(k)); sb.AppendLine(new string('-', 100)); }
            tabs.SelectedIndex = 0;
            whereBox.Text = sb.ToString();
        }

        static string Prompt(string title, string label, string def)
        {
            using (var f = new Form())
            {
                f.Text = title; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(440, 116); Theme.Style(f);
                var l = new Label(); l.Text = label; l.SetBounds(12, 12, 420, 20);
                var t = new TextBox(); t.Text = def ?? ""; t.SetBounds(12, 36, 416, 24);
                t.BackColor = Theme.Surface; t.ForeColor = Theme.Text; t.BorderStyle = BorderStyle.FixedSingle;
                var ok = new Button(); ok.Text = "Buscar"; ok.DialogResult = DialogResult.OK; ok.SetBounds(262, 74, 80, 30);
                var ca = new Button(); ca.Text = "Cancelar"; ca.DialogResult = DialogResult.Cancel; ca.SetBounds(348, 74, 80, 30);
                foreach (var b in new[] { ok, ca }) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Theme.Border; b.BackColor = Theme.Surface2; b.ForeColor = Theme.Text; }
                ok.BackColor = Theme.Accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderColor = Theme.Accent;
                f.Controls.AddRange(new Control[] { l, t, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                return f.ShowDialog() == DialogResult.OK ? t.Text : null;
            }
        }

        void GoTo(string projectName, string itemName)
        {
            lock (engine.Sync)
            {
                var p = engine.Projects.FirstOrDefault(x => x.Name == projectName);
                if (p != null) current = p;
            }
            search.Text = "";
            filter.SelectedIndex = 0;
            FillProjects();
            FillGrid();
            foreach (DataGridViewRow r in grid.Rows)
            {
                var t = r.Tag as NodeTag;
                if (t != null && string.Equals(Util.NameOf(t.Key), itemName, StringComparison.OrdinalIgnoreCase))
                {
                    grid.CurrentCell = r.Cells[C_ITEM];
                    r.Selected = true;
                    tabs.SelectedIndex = 0;
                    break;
                }
            }
        }

        // ------------------------------------------------------------ acoes
        // abre modelo (0), detalhamento (1), PDF (2), pasta (3) ou DXF (4) do item selecionado.
        // Se não achar o arquivo com o nome exato, procura na pasta versões com o mesmo código (ex.: "02033093 APR-002.SLDDRW")
        // modelo da linha selecionada: item da montagem aberta ou, na busca do servidor, a peça achada / a máquina
        bool SelModel(out string model, out string name, out Item it)
        {
            model = null; name = null; it = null;
            if (ServerMode)
            {
                if (srvGrid.CurrentRow == null) return false;
                var tag = srvGrid.CurrentRow.Tag;
                var w = tag as WhereRow;
                if (w != null) { var mp = indexer.MachinePath(w.Machine); if (!string.IsNullOrEmpty(mp)) model = engine.Cfg.Map(mp); }
                else
                {
                    var code = tag as string;
                    var f = srvHits.FirstOrDefault(x => string.Equals(x.Code, code, StringComparison.OrdinalIgnoreCase));
                    if (f != null && !string.IsNullOrEmpty(f.Path)) model = engine.Cfg.Map(f.Path);
                }
                if (model != null) name = Util.NameOf(model);
                return model != null;
            }
            it = SelItem();
            if (it == null) return false;
            model = it.Path; name = it.Name;
            return true;
        }

        // arquivo do modelo com outra extensão (mesma pasta, mesmo nome; APR-XXX não conta)
        static string Irmao(string model, string ext)
        {
            try { string f = Path.Combine(Path.GetDirectoryName(model), Path.GetFileNameWithoutExtension(model) + ext); return File.Exists(f) ? f : null; } catch { return null; }
        }

        // menu do botão direito na busca do servidor (um item por vez)
        void MenuServidor(DataGridViewCellMouseEventArgs a)
        {
            if (srvGrid.CurrentRow == null) return;
            var menu = new ContextMenuStrip();
            var tag = srvGrid.CurrentRow.Tag;
            var w = tag as WhereRow;
            Action<ToolStripItemCollection, string> addOpen = (items, model) =>
            {
                string nm = Util.NameOf(model);
                items.Add(Mi("Abrir modelo no SolidWorks", (s, e) => OpenFile(model, nm, 0, null)));
                var d = Mi("Abrir detalhamento", (s, e) => OpenFile(model, nm, 1, null)); d.Enabled = Irmao(model, ".SLDDRW") != null; items.Add(d);
                var p = Mi("Abrir PDF", (s, e) => OpenFile(model, nm, 2, null)); p.Enabled = Irmao(model, ".PDF") != null; items.Add(p);
                var x = Mi("Abrir DXF", (s, e) => OpenFile(model, nm, 4, null)); x.Enabled = Irmao(model, ".DXF") != null; items.Add(x);
                items.Add(Mi("Mostrar na pasta", (s, e) => OpenFile(model, nm, 3, null)));
            };
            if (w == null)
            {
                var code = tag as string;
                var f = srvHits.FirstOrDefault(x => string.Equals(x.Code, code, StringComparison.OrdinalIgnoreCase));
                if (f == null || string.IsNullOrEmpty(f.Path)) return;
                string model = engine.Cfg.Map(f.Path);
                var t = new ToolStripMenuItem(Util.NameOf(model)); t.Enabled = false; menu.Items.Add(t);
                menu.Items.Add(new ToolStripSeparator());
                addOpen(menu.Items, model);
                menu.Items.Add(new ToolStripSeparator());
                menu.Items.Add(Mi("Gerar detalhamento...", (s, e) => GenerateDetail()));
            }
            else
            {
                // submontagem que usa a peça (primeiro nome do caminho "submontagem > ... > máquina") e a máquina
                string sub = ((w.Chains ?? "").Split('|')[0].Split('>')[0]).Trim();
                if (sub.Length > 0 && !sub.Equals(w.Machine, StringComparison.OrdinalIgnoreCase) && sub != "...")
                {
                    var hit = indexer.Search(sub, 5000).FirstOrDefault(r => string.Equals(r.Code, sub, StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(r.Path));
                    if (hit != null)
                    {
                        var mSub = new ToolStripMenuItem("Submontagem " + sub);
                        addOpen(mSub.DropDownItems, engine.Cfg.Map(hit.Path));
                        menu.Items.Add(mSub);
                    }
                }
                var mp = indexer.MachinePath(w.Machine);
                if (!string.IsNullOrEmpty(mp))
                {
                    var mMaq = new ToolStripMenuItem("Máquina " + w.Machine);
                    addOpen(mMaq.DropDownItems, engine.Cfg.Map(mp));
                    menu.Items.Add(mMaq);
                }
                if (menu.Items.Count == 0) return;
            }
            DarkMenus(menu);
            var rc = srvGrid.GetCellDisplayRectangle(a.ColumnIndex, a.RowIndex, false);
            menu.Show(srvGrid, new Point(rc.Left + a.X, rc.Top + a.Y));
        }

        void OpenSel(int what)
        {
            string model, name; Item it;
            if (!SelModel(out model, out name, out it)) { MessageBox.Show("Selecione uma peça ou montagem na lista.", "Monitor"); return; }
            OpenFile(model, name, what, it);
        }

        void OpenFile(string model, string name, int what, Item it)
        {
            string exact = it == null ? (what == 1 ? Irmao(model, ".SLDDRW") : what == 2 ? Irmao(model, ".PDF") : what == 4 ? Irmao(model, ".DXF") : null)
                : what == 1 ? it.DrwPath : what == 2 ? it.PdfPath : what == 4 ? it.DxfPath : null;
            string ext = what == 1 ? ".SLDDRW" : what == 2 ? ".PDF" : what == 4 ? ".DXF" : null;
            string label = what == 1 ? "detalhamento (desenho .SLDDRW)" : what == 2 ? "PDF" : "DXF";
            if (what == 3) { try { Process.Start("explorer.exe", "/select,\"" + model + "\""); } catch { } return; }
            if (what == 0) { try { Process.Start(model); lblStatus.Text = "Abrindo " + name + " no SolidWorks…"; } catch (Exception ex) { MessageBox.Show(ex.Message, "Monitor"); } return; }
            lblStatus.Text = "Procurando " + label + " de " + name + "…";
            System.Threading.ThreadPool.QueueUserWorkItem(_ =>
            {
                string found = null;
                try
                {
                    if (!string.IsNullOrEmpty(exact) && File.Exists(exact)) found = exact;
                    else
                    {
                        string dir = Path.GetDirectoryName(model);
                        string code = name.Split(' ')[0];
                        var cands = Directory.GetFiles(dir, code + "*" + ext)
                            .Where(f => Path.GetExtension(f).Equals(ext, StringComparison.OrdinalIgnoreCase) && Util.AprNumber(f, name) < 0)   // APR-XXX = revisão antiga
                            .OrderByDescending(f => Path.GetFileNameWithoutExtension(f).Equals(name, StringComparison.OrdinalIgnoreCase) ? 1 : 0)
                            .ThenByDescending(f => File.GetLastWriteTime(f)).ToList();
                        found = cands.FirstOrDefault();
                    }
                }
                catch { }
                BeginInvoke(new Action(() =>
                {
                    if (found == null)
                    {
                        lblStatus.Text = name + ": sem " + label + ".";
                        MessageBox.Show(name + " ainda não tem " + label + " na pasta da peça." + (what == 1 ? "\n\nUse \"Gerar detalhamento\" quando o gerador estiver pronto." : ""), "Monitor", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return;
                    }
                    try { Process.Start(found); lblStatus.Text = "Abrindo " + Path.GetFileName(found) + (what == 1 ? " no SolidWorks…" : "…"); }
                    catch (Exception ex) { MessageBox.Show(ex.Message, "Monitor"); }
                }));
            });
        }

        // lista de projetos e compartilhada: le a versao mais nova antes de mexer, para nao apagar o que outra pessoa fez
        void ReloadSharedConfig()
        {
            try
            {
                var n = Config.Load(engine.Cfg.FilePath);
                lock (engine.Sync) engine.Cfg = n;
            }
            catch { }
        }

        // abrir projeto: lista das máquinas do índice com filtro (rápido); "Procurar arquivo..." usa a janela do Windows
        void AddProject()
        {
            var picked = PickProjectFiles();
            if (picked == null || picked.Count == 0) return;
            ReloadSharedConfig();
            foreach (var f in picked)
                if (!engine.Cfg.Projects.Any(x => engine.Cfg.Map(x).Equals(f, StringComparison.OrdinalIgnoreCase))) engine.Cfg.Projects.Add(engine.Cfg.Unmap(f));
            engine.Cfg.Save();
            engine.SyncProjects();
            lock (engine.Sync) current = engine.Projects.FirstOrDefault(x => x.MainPath.Equals(picked[0], StringComparison.OrdinalIgnoreCase))
                ?? engine.Projects.FirstOrDefault(x => Path.GetFileName(x.MainPath).Equals(Path.GetFileName(picked[0]), StringComparison.OrdinalIgnoreCase));
            if (search.Text.Trim().Length > 0) { srvTimer.Stop(); search.Text = ""; ApplySearchMode(); }   // busca antiga escondia os itens
            RefreshAll();
            engine.ForceRefresh(current);   // a montagem aberta é conferida primeiro (não espera as outras)
            if (current != null) ShowPreview(current.MainPath, current.Name);
            lblStatus.Text = "Lendo o projeto... a BOM aparece em alguns segundos.";
        }

        // janela normal do Windows (Explorer): mostra tudo que existe no servidor
        List<string> PickProjectFiles()
        {
            using (var d = new OpenFileDialog())
            {
                d.Title = "Abrir projeto (montagem principal)";
                d.Filter = "Montagens SolidWorks (*.SLDASM)|*.SLDASM|Peças e montagens|*.SLDASM;*.SLDPRT";
                d.Multiselect = true;
                d.RestoreDirectory = true;
                try
                {
                    string dir = Path.Combine(engine.Cfg.Root, "01 (MONTAGEM)");
                    d.InitialDirectory = Directory.Exists(dir) ? dir : engine.Cfg.Root;
                }
                catch { }
                if (d.ShowDialog(this) != DialogResult.OK) return null;
                return d.FileNames.Select(x => engine.Cfg.Map(x)).ToList();
            }
        }

        List<string> PickProjects()
        {
            var all = indexer.MachineList();
            using (var f = new Form())
            {
                f.Text = "Abrir projeto";
                f.StartPosition = FormStartPosition.CenterParent;
                f.Size = new Size(760, 560);
                f.MinimizeBox = false;
                Theme.Style(f);
                var top = new Panel(); top.Dock = DockStyle.Top; top.Height = 44; top.Padding = new Padding(10, 10, 10, 6);
                var lbl = new Label(); lbl.Text = "Procurar:"; lbl.AutoSize = true; lbl.ForeColor = Theme.Muted; lbl.Location = new Point(10, 15);
                var tb = new TextBox(); tb.Location = new Point(80, 11); tb.Width = 400; tb.BackColor = Theme.Surface; tb.ForeColor = Theme.Text; tb.BorderStyle = BorderStyle.FixedSingle;
                top.Controls.Add(lbl); top.Controls.Add(tb);
                var lv = new ListView(); lv.Dock = DockStyle.Fill; lv.View = View.Details; lv.FullRowSelect = true; lv.MultiSelect = true; lv.HideSelection = false;
                Theme.Style(lv);
                lv.Columns.Add("Máquina / montagem", 330); lv.Columns.Add("Pasta", 380);
                var bottom = new Panel(); bottom.Dock = DockStyle.Bottom; bottom.Height = 50;
                var ok = new Button(); ok.Text = "Abrir"; ok.SetBounds(f.ClientSize.Width - 200, 10, 90, 30); ok.Anchor = AnchorStyles.Right | AnchorStyles.Top;
                var ca = new Button(); ca.Text = "Cancelar"; ca.SetBounds(f.ClientSize.Width - 104, 10, 90, 30); ca.Anchor = AnchorStyles.Right | AnchorStyles.Top; ca.DialogResult = DialogResult.Cancel;
                var br = new Button(); br.Text = "Procurar arquivo..."; br.SetBounds(10, 10, 150, 30);
                foreach (var b in new[] { ok, ca, br }) { b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Theme.Border; b.BackColor = Theme.Surface2; b.ForeColor = Theme.Text; }
                ok.BackColor = Theme.Accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderColor = Theme.Accent;
                bottom.Controls.AddRange(new Control[] { br, ok, ca });
                f.Controls.Add(lv); f.Controls.Add(top); f.Controls.Add(bottom);
                f.CancelButton = ca;
                Action fill = () =>
                {
                    var toks = tb.Text.ToUpperInvariant().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    lv.BeginUpdate(); lv.Items.Clear();
                    foreach (var kv in all)
                    {
                        string hay = (kv.Key + " " + kv.Value).ToUpperInvariant();
                        if (toks.Any(t => hay.IndexOf(t, StringComparison.Ordinal) < 0)) continue;
                        var li = new ListViewItem(kv.Key); li.SubItems.Add(Path.GetDirectoryName(kv.Value) ?? ""); li.Tag = kv.Value;
                        lv.Items.Add(li);
                        if (lv.Items.Count >= 500) break;
                    }
                    lv.EndUpdate();
                };
                tb.TextChanged += (s, a) => fill();
                tb.KeyDown += (s, a) => { if (a.KeyCode == Keys.Down && lv.Items.Count > 0) { lv.Focus(); lv.Items[0].Selected = true; a.Handled = true; } if (a.KeyCode == Keys.Enter && lv.Items.Count > 0) { if (lv.SelectedItems.Count == 0) lv.Items[0].Selected = true; f.DialogResult = DialogResult.OK; } };
                List<string> result = null;
                ok.Click += (s, a) => { if (lv.SelectedItems.Count > 0) f.DialogResult = DialogResult.OK; };
                lv.DoubleClick += (s, a) => { if (lv.SelectedItems.Count > 0) f.DialogResult = DialogResult.OK; };
                br.Click += (s, a) =>
                {
                    using (var d = new OpenFileDialog())
                    {
                        d.Title = "Escolha a montagem principal do projeto";
                        d.Filter = "Montagens SolidWorks (*.sldasm)|*.sldasm";
                        try { d.InitialDirectory = Path.Combine(engine.Cfg.Root, "01 (MONTAGEM)"); } catch { }
                        d.Multiselect = true;
                        if (d.ShowDialog(f) == DialogResult.OK) { result = d.FileNames.ToList(); f.DialogResult = DialogResult.OK; }
                    }
                };
                fill();
                f.Shown += (s, a) => tb.Focus();
                if (f.ShowDialog(this) != DialogResult.OK) return null;
                if (result != null) return result;
                return lv.SelectedItems.Cast<ListViewItem>().Select(x => engine.Cfg.Map((string)x.Tag)).ToList();
            }
        }

        void RemoveProject()
        {
            if (current == null) return;
            if (MessageBox.Show("Fechar o projeto " + current.Name + "?\n\nEle sai da lista à esquerda (para todos que usam o Monitor).\nNenhum arquivo é apagado; dá para abrir de novo quando quiser.", "Monitor", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            ReloadSharedConfig();
            engine.Cfg.Projects.RemoveAll(x => engine.Cfg.Map(x).Equals(current.MainPath, StringComparison.OrdinalIgnoreCase));
            engine.Cfg.Save();
            engine.SyncProjects();
            current = null;
            RefreshAll();
        }

        void OpenConfig()
        {
            try { Process.Start("notepad.exe", "\"" + engine.Cfg.FilePath + "\""); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Monitor"); }
        }

        // exporta a BOM em arvore (com nivel e quantidade) para abrir no Excel
        // descrição da montagem: 1301 (ou pasta de solda) = SOLDA, 1302 = ENCAIXE; principal = descrição dela
        static string AsmDesc(Item it, bool principal)
        {
            if (principal)
            {
                if (it.Desc.Length > 0) return it.Desc;
                var m = System.Text.RegularExpressions.Regex.Match(it.Name, @"^\s*\S+\s*[-–]?\s*(.*)$");
                return m.Success && m.Groups[1].Value.Trim().Length > 0 ? m.Groups[1].Value.Trim() : it.Name;
            }
            if (it.IsWeld || it.Name.StartsWith("1301")) return "SOLDA";
            if (it.Name.StartsWith("1302")) return "ENCAIXE";
            return it.Desc.Length > 0 ? it.Desc : "ENCAIXE";
        }

        // LISTA DE PEÇAS em Excel no formato da lista de cadastro: tudo aberto (montagem principal, peças e submontagens)
        void Export()
        {
            var p = current;
            if (p == null) return;
            try
            {
                string dir = Path.Combine(Util.AppDir, "relatorios");
                Directory.CreateDirectory(dir);
                string safe = new string(p.Name.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch).ToArray());
                string file = Path.Combine(dir, "LISTA DE PEÇAS - " + safe + " - " + DateTime.Now.ToString("yyyy-MM-dd HHmm") + ".xlsx");
                var procs = engine.Cfg.ListCols.Where(c => { var u = c.ToUpperInvariant(); return u != "ACABAMENTO" && !u.StartsWith("QDT") && !u.StartsWith("QTD"); }).ToList();
                const int CA = 1, CB = 2, CF = 6, CG = 7, CH = 8, CI = 9, CJ = 10;
                int last = CJ + procs.Count - 1;
                var sh = new XlsxSheet();
                sh.Name = "LISTA DE PEÇAS";
                // larguras como na lista de referência
                sh.ColWidths[1] = 13.9; sh.ColWidths[2] = 12.1; sh.ColWidths[3] = 8.4; sh.ColWidths[4] = 8.4; sh.ColWidths[5] = 8.4; sh.ColWidths[6] = 60; sh.ColWidths[7] = 60; sh.ColWidths[8] = 17.6; sh.ColWidths[9] = 7.6;
                for (int i = 0; i < procs.Count; i++) sh.ColWidths[CJ + i] = Math.Max(8.3, procs[i].Length * 1.25 + 1);
                // cabeçalho
                sh.RowHeights[1] = 27.6;
                sh.Set(1, CA, "Nº DO ITEM", XlsxSheet.BoldCenter);
                sh.Set(1, CB, "Nº DA PEÇA", XlsxSheet.BoldLeft); sh.Merge(1, CB, 1, CF);
                sh.Set(1, CG, "DESCRIÇÃO", XlsxSheet.BoldLeft);
                sh.Set(1, CH, "ACABAMENTO", XlsxSheet.BoldCenter);
                sh.Set(1, CI, "QDT.", XlsxSheet.BoldCenter);
                for (int i = 0; i < procs.Count; i++) sh.Set(1, CJ + i, procs[i].ToUpperInvariant(), XlsxSheet.BoldCenter);
                int row = 2;
                Item root;
                lock (engine.Sync)
                {
                    if (!p.Items.TryGetValue(p.MainPath, out root)) throw new Exception("montagem principal ainda não lida");
                    // montagem principal (código + descrição)
                    WriteLine(sh, row, root, 1, CB, null, 0, true, procs, true);
                    sh.Merge(row, CB, row, CF);
                    row++;
                    sh.Merge(row, CA, row, last); row++;   // linha em branco
                    var stack = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root.Key };
                    ExportKids(sh, p, root, 0, "", ref row, last, procs, stack);
                }
                sh.Save(file);
                lblStatus.Text = "Lista de peças exportada: " + file;
                Process.Start(file);
            }
            catch (Exception ex) { MessageBox.Show("Não foi possível exportar a lista:\n" + ex.Message, "Monitor"); }
        }

        // e = quantos "encaixes" acima (0 = filhos diretos da principal). Coluna do código: B até o 1º nível de encaixe, depois C, D...
        void ExportKids(XlsxSheet sh, Project p, Item parent, int e, string prefix, ref int row, int last, List<string> procs, HashSet<string> stack)
        {
            const int CA = 1, CF = 6;
            int codeCol = 2 + Math.Max(0, e - 1);
            var kids = p.Kids(parent.Key).Select((kk, i) => new { kk, i })
                .OrderBy(x => { Item ci; return p.Items.TryGetValue(x.kk.Child, out ci) && ci.IsAsm ? 1 : 0; }).ThenBy(x => x.i).Select(x => x.kk).ToList();
            int n = 0, k = 0;
            foreach (var c in kids)
            {
                Item it;
                if (!p.Items.TryGetValue(c.Child, out it)) continue;
                n++;
                bool asm = it.IsAsm && p.Kids(it.Key).Count > 0 && !stack.Contains(it.Key);
                bool solda = it.IsWeld || it.Name.StartsWith("1301");
                if (!asm)
                {
                    WriteLine(sh, row, it, c.Qty, codeCol, e == 0 ? (object)n : null, e == 0 ? CA : 0, it.IsAsm, procs);
                    sh.Merge(row, codeCol, row, CF);
                    row++;
                    continue;
                }
                // submontagem: linha em branco antes, cabeçalho em negrito, filhos logo abaixo
                stack.Add(it.Key);
                if (e == 0)
                {
                    sh.Merge(row, CA, row, last); row++;
                    int head = row;
                    WriteLine(sh, row, it, c.Qty, 2, n, CA, true, procs);
                    sh.Merge(row, 2, row, CF); row++;
                    if (!solda) { sh.Merge(row, 2, row, last); row++; }
                    ExportKids(sh, p, it, 1, n.ToString(), ref row, last, procs, stack);
                    if (row - 1 > head) sh.Merge(head, CA, row - 1, CA);   // nº do item ocupa o bloco todo
                }
                else if (solda)
                {
                    sh.Merge(row, codeCol, row, last); row++;
                    WriteLine(sh, row, it, c.Qty, codeCol, null, 0, true, procs);
                    sh.Merge(row, codeCol, row, CF); row++;
                    ExportKids(sh, p, it, e, prefix, ref row, last, procs, stack);
                }
                else
                {
                    k++;
                    string num = prefix + "." + k;
                    sh.Merge(row, codeCol, row, last); row++;
                    int head = row;
                    WriteLine(sh, row, it, c.Qty, codeCol + 1, num, codeCol, true, procs);
                    sh.Merge(row, codeCol + 1, row, CF); row++;
                    sh.Merge(row, codeCol + 1, row, last); row++;
                    ExportKids(sh, p, it, e + 1, num, ref row, last, procs, stack);
                    if (row - 1 > head) sh.Merge(head, codeCol, row - 1, codeCol);
                }
                stack.Remove(it.Key);
            }
        }

        static void WriteLine(XlsxSheet sh, int row, Item it, int qty, int codeCol, object num, int numCol, bool bold, List<string> procs, bool principal = false)
        {
            const int CG = 7, CH = 8, CI = 9, CJ = 10;
            if (num != null && numCol > 0) sh.Set(row, numCol, num, XlsxSheet.BoldCenter);
            // código sempre como texto: mantém o zero da frente (01 montagem, 02 peça, 03 comercial, 1301 solda, 1302 encaixe...)
            object code = it.Name;
            sh.Set(row, codeCol, code, bold ? XlsxSheet.BoldLeft : XlsxSheet.Left);
            string desc = it.IsAsm ? AsmDesc(it, principal) : it.Desc;
            sh.Set(row, CG, desc, bold ? XlsxSheet.BoldLeft : XlsxSheet.Left);
            sh.Set(row, CH, it.P("ACABAMENTO"), XlsxSheet.Center);
            sh.Set(row, CI, (double)qty, XlsxSheet.Center);
            for (int i = 0; i < procs.Count; i++)
            {
                string v = (it.P(procs[i]) ?? "").Trim();
                double d;
                object o = double.TryParse(v.Replace(",", "."), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out d) ? (object)d : v;
                sh.Set(row, CJ + i, o, XlsxSheet.Center);
            }
        }

        // ------------------------------------------------------------ historico
        // histórico: todas as linhas em memória (mais nova primeiro); a aba mostra só as do item selecionado
        class HistRow { public string When, Proj, Item, Kind, Who, Detail; public bool Pend; }
        readonly List<HistRow> histAll = new List<HistRow>();
        Item histItem;   // item selecionado na lista (null = mostra tudo)

        void AddHistRow(Ev e, bool top)
        {
            AddHistRow(e.When.ToString("dd/MM/yy HH:mm:ss"), e.Project, e.Item, e.Kind, e.Who, e.Detail, e.Sev == 2, top);
        }

        void AddHistRow(string when, string proj, string item, string kind, string who, string detail, bool pend, bool top)
        {
            var h = new HistRow { When = when, Proj = proj ?? "", Item = item ?? "", Kind = kind ?? "", Who = Users.Display(who ?? ""), Detail = detail ?? "", Pend = pend };
            if (top) histAll.Insert(0, h); else histAll.Add(h);
            if (histAll.Count > 50000) histAll.RemoveAt(histAll.Count - 1);
            if (top && HistMatch(h)) { histList.Items.Insert(0, HistItem(h)); while (histList.Items.Count > 1000) histList.Items.RemoveAt(histList.Items.Count - 1); }
        }

        // janela com o log de alterações de tudo (todos os projetos), com busca
        void HistoricoGeral()
        {
            var f = new Form();
            f.Text = "Histórico geral de alterações"; f.StartPosition = FormStartPosition.CenterParent; f.Size = new Size(1200, 680); f.MinimumSize = new Size(700, 400);
            Theme.Style(f);
            var top = new Panel(); top.Dock = DockStyle.Top; top.Height = 40; top.BackColor = Theme.Surface2;
            var lb = new Label(); lb.Text = "Buscar (item, projeto, pessoa, evento):"; lb.SetBounds(12, 11, 230, 20); lb.ForeColor = Theme.Muted;
            var tb = new TextBox(); tb.SetBounds(246, 8, 320, 24); tb.BackColor = Theme.Surface; tb.ForeColor = Theme.Text; tb.BorderStyle = BorderStyle.FixedSingle;
            var cnt = new Label(); cnt.SetBounds(580, 11, 400, 20); cnt.ForeColor = Theme.Muted;
            top.Controls.AddRange(new Control[] { lb, tb, cnt });
            var lv = new ListView(); lv.View = View.Details; lv.FullRowSelect = true; lv.Dock = DockStyle.Fill; Theme.Style(lv);
            foreach (var c in new[] { new object[] { "Data", 120 }, new object[] { "Projeto", 220 }, new object[] { "Item", 150 }, new object[] { "Evento", 240 }, new object[] { "Salvo por", 120 }, new object[] { "Detalhe", 700 } })
                lv.Columns.Add((string)c[0], (int)c[1]);
            Action encher = () =>
            {
                var toks = tb.Text.ToUpperInvariant().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                lv.BeginUpdate(); lv.Items.Clear();
                int n = 0, tot = 0;
                foreach (var h in histAll)
                {
                    if (toks.Length > 0)
                    {
                        string hay = (h.When + " " + h.Proj + " " + h.Item + " " + h.Kind + " " + h.Who + " " + h.Detail).ToUpperInvariant();
                        if (toks.Any(t => hay.IndexOf(t, StringComparison.Ordinal) < 0)) continue;
                    }
                    tot++;
                    if (n < 3000) { lv.Items.Add(HistItem(h)); n++; }
                }
                lv.EndUpdate();
                cnt.Text = tot + " registro(s)" + (tot > n ? " - mostrando os " + n + " mais recentes" : "");
            };
            var tmr = new System.Windows.Forms.Timer(); tmr.Interval = 300; tmr.Tick += (s, a) => { tmr.Stop(); encher(); };
            tb.TextChanged += (s, a) => { tmr.Stop(); tmr.Start(); };
            lv.DoubleClick += (s, a) => { if (lv.SelectedItems.Count > 0) GoTo(lv.SelectedItems[0].SubItems[1].Text, lv.SelectedItems[0].SubItems[2].Text); };
            f.Controls.Add(lv); f.Controls.Add(top);
            f.FormClosed += (s, a) => tmr.Dispose();
            encher();
            f.Show(this);
        }

        static string FmtOu(DateTime d) { var s = Util.Fmt(d); return s.Length > 0 ? s : "não tem"; }

        bool HistMatch(HistRow h)
        {
            if (histItem == null) return true;
            return string.Equals(h.Item, histItem.Name, StringComparison.OrdinalIgnoreCase);
        }

        ListViewItem HistItem(HistRow h)
        {
            var li = new ListViewItem(new string[] { h.When, h.Proj, h.Item, h.Kind, h.Who.Length > 0 ? h.Who : "-", h.Detail });
            li.ForeColor = h.Pend ? Theme.PendText : Theme.Text;
            return li;
        }

        // mostra o histórico do item selecionado (ou de tudo, sem seleção)
        void ShowHistory(Item it)
        {
            histItem = it;
            histList.BeginUpdate();
            histList.Items.Clear();
            if (it != null)
            {
                // primeira linha: quem salvou o 3D por último (vem do próprio arquivo do SolidWorks)
                if (it.Model != DateTime.MinValue)
                {
                    var li0 = new ListViewItem(new string[] { it.Model.ToString("dd/MM/yy HH:mm:ss"), "", it.Name, "Último salvamento do 3D", it.LastBy.Length > 0 ? Users.Display(it.LastBy) : "-",
                        "Desenho: " + FmtOu(it.Drw) + "   PDF: " + FmtOu(it.Pdf) + "   DXF: " + FmtOu(it.Dxf) });
                    li0.ForeColor = Theme.Accent;
                    histList.Items.Add(li0);
                }
            }
            int n = 0;
            foreach (var h in histAll)
            {
                if (!HistMatch(h)) continue;
                histList.Items.Add(HistItem(h));
                if (++n >= 1000) break;
            }
            if (it != null && n == 0)
                histList.Items.Add(new ListViewItem(new string[] { "", "", it.Name, "Sem alterações registradas pelo Monitor", "", "" }) { ForeColor = Theme.Muted });
            histList.EndUpdate();
        }

        void LoadHistory()
        {
            try
            {
                string f = engine.Cfg.HistoryPath;
                if (!File.Exists(f)) return;
                string[] lines;
                using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (var r = new StreamReader(fs, Encoding.UTF8))
                    lines = r.ReadToEnd().Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = lines.Length - 1; i >= 1 && histAll.Count < 50000; i--)
                {
                    var c = SplitCsv(lines[i]);
                    if (c.Count < 7) continue;
                    string when = c[0];
                    if (when.Length >= 19) when = when.Substring(0, 6) + when.Substring(8);
                    AddHistRow(when, c[2], c[3], c[4], c[5], c[6], c[6].Contains("desatualizado") || c[6].Contains("Sem PDF") || c[4].StartsWith("ATEN"), false);
                }
                ShowHistory(histItem);
            }
            catch { }
        }

        static List<string> SplitCsv(string line)
        {
            var res = new List<string>();
            var sb = new StringBuilder();
            bool q = false;
            for (int i = 0; i < line.Length; i++)
            {
                char ch = line[i];
                if (q)
                {
                    if (ch == '"' && i + 1 < line.Length && line[i + 1] == '"') { sb.Append('"'); i++; }
                    else if (ch == '"') q = false;
                    else sb.Append(ch);
                }
                else if (ch == '"') q = true;
                else if (ch == ';') { res.Add(sb.ToString()); sb.Length = 0; }
                else sb.Append(ch);
            }
            res.Add(sb.ToString());
            return res;
        }
    }
}
