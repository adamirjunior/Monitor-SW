// Monitor - Revisão: o que marca um item como DESATUALIZADO (amarelo, "precisa revisar").
// Cada usuário escolhe em Opções > Revisão (preferencias.tsv, chave "revisao", segue o usuário em qualquer PC).
// A verificação de datas é sempre automática: ao salvar o 3D no SolidWorks o Monitor vê a data nova (só conta se a
// geometria/propriedades mudaram de verdade - assinatura) e o item fica amarelo com o motivo.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace MonitorSW
{
    public static class RegrasRevisao
    {
        // código, texto, padrão
        public static readonly string[][] Lista = {
            new[] { "md", "3D alterado depois do DESENHO (detalhamento .SLDDRW não atualizado)", "1" },
            new[] { "mp", "3D alterado depois do PDF", "1" },
            new[] { "mx", "3D alterado depois do DXF (laser)", "1" },
            new[] { "dp", "Desenho salvo depois do PDF (PDF não exportado de novo)", "1" },
            new[] { "dx", "Desenho salvo depois do DXF", "0" },
            new[] { "cf", "Divergências da Conferência (carimbo do PDF, descrição/escala do DXF)", "1" },
        };

        static HashSet<string> ativas;
        static string carregadoPara;

        static string Login { get { return Users.Current != null ? Users.Current.Login : ""; } }

        static HashSet<string> Atuais()
        {
            string lg = Login;
            if (ativas != null && carregadoPara == lg) return ativas;
            var h = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string v = null;
            try { if (lg.Length > 0) v = Preferencias.Get(lg, "revisao"); } catch { }
            if (v == null) { foreach (var r in Lista) if (r[2] == "1") h.Add(r[0]); }
            else foreach (var c in v.Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries)) h.Add(c.Trim());
            ativas = h; carregadoPara = lg;
            return h;
        }

        public static bool Ativa(string codigo) { return Atuais().Contains(codigo); }

        public static void Editar(IWin32Window dono, Action depois)
        {
            var at = Atuais();
            using (var f = new Form())
            {
                f.Text = "Monitor - o que marcar para revisão"; f.FormBorderStyle = FormBorderStyle.FixedDialog; f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false; f.MaximizeBox = false; f.ClientSize = new Size(520, 330);
                Theme.Style(f);
                var t = new Label(); t.Text = "Marcar o item como DESATUALIZADO (amarelo) quando:"; t.SetBounds(16, 14, 488, 20);
                t.Font = new Font(f.Font, FontStyle.Bold);
                var lista = new CheckedListBox(); lista.SetBounds(16, 42, 488, 150); lista.CheckOnClick = true; lista.IntegralHeight = false;
                lista.BackColor = Theme.Surface; lista.ForeColor = Theme.Text; lista.BorderStyle = BorderStyle.FixedSingle;
                foreach (var r in Lista) lista.Items.Add(r[1], at.Contains(r[0]));
                var n = new Label(); n.SetBounds(16, 200, 488, 80); n.ForeColor = Theme.Muted;
                n.Text = "A conferência é automática: ao salvar a peça no SolidWorks a lista atualiza e o item fica amarelo com o motivo " +
                         "(ex.: \"3D alterado depois do PDF\"). Salvar sem mudar nada não conta. Item marcado como conferido/revisado " +
                         "sai do amarelo até alguém alterar de novo. A escolha segue o seu usuário em qualquer PC.";
                var ok = new Button(); ok.Text = "Salvar"; ok.SetBounds(320, 290, 86, 28); ok.FlatStyle = FlatStyle.Flat; ok.BackColor = Theme.Accent; ok.ForeColor = Color.White;
                var ca = new Button(); ca.Text = "Cancelar"; ca.SetBounds(414, 290, 86, 28); ca.FlatStyle = FlatStyle.Flat; ca.DialogResult = DialogResult.Cancel;
                f.Controls.AddRange(new Control[] { t, lista, n, ok, ca });
                f.AcceptButton = ok; f.CancelButton = ca;
                ok.Click += (s, a) =>
                {
                    var cods = new List<string>();
                    for (int i = 0; i < lista.Items.Count; i++) if (lista.GetItemChecked(i)) cods.Add(Lista[i][0]);
                    try { Preferencias.Set(Login, "revisao", cods.Count == 0 ? "-" : string.Join(",", cods.ToArray())); }
                    catch (Exception ex) { MessageBox.Show(f, "Não gravou: " + ex.Message, "Revisão", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                    ativas = null;
                    f.DialogResult = DialogResult.OK; f.Close();
                };
                if (f.ShowDialog(dono) == DialogResult.OK && depois != null) depois();
            }
        }
    }
}
