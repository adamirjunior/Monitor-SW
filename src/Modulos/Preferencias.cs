// Monitor - preferências por USUÁRIO do Monitor (login), na pasta compartilhada: valem em qualquer PC.
// preferencias.tsv: LOGIN, CHAVE, VALOR (ex.: adamir  tema  claro)
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace MonitorSW
{
    public static class Preferencias
    {
        public static string FilePath { get { return Path.Combine(Util.AppDir, "preferencias.tsv"); } }
        static readonly object sync = new object();

        static List<string[]> Ler()
        {
            var l = new List<string[]>();
            try
            {
                if (File.Exists(FilePath))
                    foreach (var line in File.ReadAllLines(FilePath, Encoding.UTF8))
                    {
                        if (line.StartsWith("#") || line.StartsWith("LOGIN\t") || line.Trim().Length == 0) continue;
                        var c = line.Split('\t');
                        if (c.Length >= 3) l.Add(new[] { c[0].Trim(), c[1].Trim(), c[2].Trim() });
                    }
            }
            catch { }
            return l;
        }

        public static string Get(string login, string chave)
        {
            if (string.IsNullOrEmpty(login)) return null;
            lock (sync)
            {
                var r = Ler().FirstOrDefault(c => c[0].Equals(login, StringComparison.OrdinalIgnoreCase) && c[1].Equals(chave, StringComparison.OrdinalIgnoreCase));
                return r == null ? null : r[2];
            }
        }

        public static void Set(string login, string chave, string valor)
        {
            if (string.IsNullOrEmpty(login)) return;
            lock (sync)
            {
                var l = Ler().Where(c => !(c[0].Equals(login, StringComparison.OrdinalIgnoreCase) && c[1].Equals(chave, StringComparison.OrdinalIgnoreCase))).ToList();
                l.Add(new[] { login, chave, valor });
                var sb = new StringBuilder();
                sb.AppendLine("# Preferências de cada usuário do Monitor (tema etc.) - valem em qualquer PC");
                sb.AppendLine("LOGIN\tCHAVE\tVALOR");
                foreach (var c in l.OrderBy(c => c[0]).ThenBy(c => c[1])) sb.AppendLine(c[0] + "\t" + c[1] + "\t" + c[2]);
                File.WriteAllText(FilePath, sb.ToString(), new UTF8Encoding(true));
            }
        }
    }
}
