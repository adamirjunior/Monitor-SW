// Monitor - grava propriedades (descrição, acabamento...) nos arquivos SolidWorks usando o próprio SolidWorks (COM)
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

namespace MonitorSW
{
    public static class SwWriter
    {
        static object Call(object o, string m, params object[] a) { return o.GetType().InvokeMember(m, BindingFlags.InvokeMethod, null, o, a); }
        static object Get(object o, string p, params object[] a) { return o.GetType().InvokeMember(p, BindingFlags.GetProperty, null, o, a); }

        // roda numa thread STA (exigido pelo COM do SolidWorks). Retorna null se deu certo, ou a mensagem de erro/aviso
        public static string SetProps(string path, Dictionary<string, string> values)
        {
            string result = null;
            var t = new Thread(() => { result = SetPropsSta(path, values); });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            t.Join();
            return result;
        }

        static string[] Names(object o)
        {
            var arr = o as object[];
            if (arr != null) return arr.Select(x => x == null ? "" : x.ToString()).ToArray();
            var sa = o as string[];
            return sa ?? new string[0];
        }

        static string SetPropsSta(string path, Dictionary<string, string> values)
        {
            if (!File.Exists(path)) return "Arquivo não encontrado:\n" + path;
            object sw = null; bool started = false;
            try
            {
                try { sw = Marshal.GetActiveObject("SldWorks.Application"); } catch { }
                if (sw == null)
                {
                    var tp = Type.GetTypeFromProgID("SldWorks.Application");
                    if (tp == null) return "O SolidWorks não está instalado neste PC.";
                    sw = Activator.CreateInstance(tp);
                    started = true;
                    // abre o SolidWorks normalmente (visível) e deixa aberto no final
                    try { sw.GetType().InvokeMember("Visible", BindingFlags.SetProperty, null, sw, new object[] { true }); } catch { }
                }
                object doc = null;
                try { doc = Call(sw, "GetOpenDocumentByName", path); } catch { }
                bool wasOpen = doc != null;
                // já estava aberto (sozinho ou dentro de uma montagem aberta): só salva se não tinha outras alterações pendentes
                bool hadChanges = false;
                if (wasOpen) try { hadChanges = (bool)Call(doc, "GetSaveFlag"); } catch { }
                if (doc == null)
                {
                    string ext = Path.GetExtension(path).ToUpperInvariant();
                    int type = ext == ".SLDASM" ? 2 : ext == ".SLDDRW" ? 3 : 1;
                    var args = new object[] { path, type, 1 /*silencioso*/, "", 0, 0 };
                    var mod = new ParameterModifier(6); mod[4] = true; mod[5] = true;
                    doc = sw.GetType().InvokeMember("OpenDoc6", BindingFlags.InvokeMethod, null, sw, args, new[] { mod }, null, null);
                    if (doc == null) return "O SolidWorks não conseguiu abrir o arquivo (erro " + args[4] + ").";
                }
                bool ro = false;
                try { ro = (bool)Call(doc, "IsOpenedReadOnly"); } catch { }
                if (ro)
                {
                    if (!wasOpen) try { Call(sw, "CloseDoc", (string)Call(doc, "GetTitle")); } catch { }
                    return "O arquivo está aberto (somente leitura) — provavelmente outra pessoa está com ele aberto no SolidWorks.\nPeça para fechar e tente de novo.";
                }
                var ext2 = Get(doc, "Extension");
                var cfgs = new List<string> { "" };
                try { cfgs.AddRange(Names(Call(doc, "GetConfigurationNames"))); } catch { }
                foreach (var kv in values)
                {
                    bool done = false;
                    foreach (var c in cfgs)
                    {
                        var cpm = Get(ext2, "CustomPropertyManager", c);
                        if (cpm == null) continue;
                        string[] names;
                        try { names = Names(Call(cpm, "GetNames")); } catch { names = new string[0]; }
                        string real = names.FirstOrDefault(n => string.Equals(n, kv.Key, StringComparison.OrdinalIgnoreCase));
                        if (real == null) continue;
                        Call(cpm, "Add3", real, 30 /*texto*/, kv.Value, 2 /*substituir*/);
                        done = true;
                    }
                    if (!done) Call(Get(ext2, "CustomPropertyManager", ""), "Add3", kv.Key, 30, kv.Value, 2);
                }
                if (wasOpen && hadChanges)
                {
                    try { Call(doc, "SetSaveFlag"); } catch { }
                    return "AVISO: o arquivo está aberto no seu SolidWorks com outras alterações ainda não salvas.\nA alteração foi feita lá — salve o arquivo no SolidWorks quando terminar.";
                }
                var sargs = new object[] { 1 /*silencioso*/, 0, 0 };
                var smod = new ParameterModifier(3); smod[1] = true; smod[2] = true;
                bool ok = (bool)doc.GetType().InvokeMember("Save3", BindingFlags.InvokeMethod, null, doc, sargs, new[] { smod }, null, null);
                // fecha só o arquivo que o Monitor abriu; o SolidWorks e o que você já tinha aberto continuam
                if (!wasOpen) try { Call(sw, "CloseDoc", (string)Call(doc, "GetTitle")); } catch { }
                if (!ok) return "O SolidWorks não conseguiu salvar o arquivo (erro " + sargs[1] + ").";
                return null;
            }
            catch (Exception ex)
            {
                var inner = ex is TargetInvocationException && ex.InnerException != null ? ex.InnerException : ex;
                return "Não foi possível gravar: " + inner.Message;
            }
            finally
            {
                if (sw != null) try { Marshal.ReleaseComObject(sw); } catch { }
            }
        }
    }
}
