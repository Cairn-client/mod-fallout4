// Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: GPL-3.0-only (as the project it is part of)
//
// The Cairn launcher's program for Fallout 4 (the pack's `optionsProgram`, with `"setup": true`; docs: the launcher repository's docs/PACKS.md).
// The launcher runs it with a list of arguments and reads one JSON object per line from its standard output:
//
//   setup check [--game-exe EXE]        the steps this mod needs on the PC, then {"done":...} and where the game is
//   setup do <action> [--game-exe EXE]  install-f4se | enable-plugin | set-ini | unplace-mod; {"say"}/{"progress"} lines, then {"ok","message"}
//   logs collect --out DIR              copies the game's script extender log and the mod's into DIR
//
// What F4MP needs: Fallout 4 at 1.10.163 (the "classic" build; the Next-Gen update is not supported by F4SE 0.6.23 nor by the plugin),
// F4SE 0.6.23 (downloaded from its author's site, checked against a pinned hash), the plugin switched on in plugins.txt, and loose files
// switched on in Fallout4Custom.ini (the mod's Papyrus scripts are loose files).
using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

return await Bridge.RunAsync(args);

static class Bridge
{
    const string RequiredVersion = "1.10.163";
    const string F4seUrl = "https://f4se.silverlock.org/beta/f4se_0_06_23.7z";
    const string F4seSha256 = "39575BBB688FC40598496E28AFAFB5270A6E44C00656A160A30F467EFBADE21C";
    const string Plugin = "f4mp.esp";

    public static async Task<int> RunAsync(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string? exe = Opt(args, "--game-exe");
        try
        {
            return args switch
            {
                ["setup", "check", ..] => Check(exe),
                ["setup", "do", var action, ..] => await DoAsync(action, exe),
                ["logs", "collect", ..] => Logs(args),
                _ => 2,
            };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or HttpRequestException or TaskCanceledException)
        {
            Console.WriteLine("{\"ok\":false,\"message\":" + Q(ex.Message) + "}");
            return 1;
        }
    }

    static string? Opt(string[] a, string name)
    {
        int i = Array.IndexOf(a, name);
        return i >= 0 && i + 1 < a.Length ? a[i + 1] : null;
    }

    // ---- where the game and the player's files are ----

    static string? GameDir(string? exe)
    {
        if (!string.IsNullOrWhiteSpace(exe) && File.Exists(exe)) return Path.GetDirectoryName(Path.GetFullPath(exe));
        foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4", @"SOFTWARE\Bethesda Softworks\Fallout4" })
        {
            try
            {
                if (Registry.LocalMachine.OpenSubKey(key)?.GetValue("installed path") is string p && File.Exists(Path.Combine(p, "Fallout4.exe"))) return p.TrimEnd('\\');
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException) { }
        }
        string? steam = null;
        try { steam = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")?.GetValue("SteamPath") as string; } catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException) { }
        steam ??= @"C:\Program Files (x86)\Steam";
        var libs = new List<string> { steam };
        string vdf = Path.Combine(steam, "steamapps", "libraryfolders.vdf");
        if (File.Exists(vdf))
            foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"(.+?)\"")) libs.Add(m.Groups[1].Value.Replace("\\\\", "\\"));
        foreach (var lib in libs)
        {
            string c = Path.Combine(lib, "steamapps", "common", "Fallout 4");
            if (File.Exists(Path.Combine(c, "Fallout4.exe"))) return c;
        }
        return null;
    }

    static string PluginsTxt => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Fallout4", "plugins.txt");
    static string CustomIni => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "My Games", "Fallout4", "Fallout4Custom.ini");

    static string? GameVersion(string dir)
    {
        string exe = Path.Combine(dir, "Fallout4.exe");
        return File.Exists(exe) ? FileVersionInfo.GetVersionInfo(exe).ProductVersion : null;
    }

    static bool PluginEnabled() =>
        File.Exists(PluginsTxt) && File.ReadAllLines(PluginsTxt).Any(l => Regex.IsMatch(l.Trim(), @"^\*?f4mp\.esp$", RegexOptions.IgnoreCase));

    static bool LooseFilesOn() =>
        File.Exists(CustomIni) && Regex.IsMatch(File.ReadAllText(CustomIni), @"bInvalidateOlderFiles\s*=\s*1", RegexOptions.IgnoreCase);

    // ---- setup check ----

    static int Check(string? exe)
    {
        string? dir = GameDir(exe);
        bool ready = true;
        string? note = null;

        // 1. the game's version
        string? ver = dir is null ? null : GameVersion(dir);
        if (dir is null)
        {
            Step("version", "Fallout 4 found", "needs-you", "Fallout 4 was not found. Install it from your Steam library, or point Cairn at it with Locate game.", null, null, ref ready);
        }
        else if (ver is not null && ver.StartsWith(RequiredVersion, StringComparison.Ordinal))
        {
            Step("version", "Fallout 4 " + RequiredVersion + " (the classic version)", "done", "Version " + ver + ".", null, null, ref ready);
        }
        else
        {
            string why = $"Your Fallout 4 is version {ver ?? "unknown"}. This mod needs {RequiredVersion}, the version from before the Next-Gen update. Steam cannot go back to it by itself: downgrade the game (Steam's console or a depot downgrader), then check again.";
            Step("version", "Fallout 4 " + RequiredVersion + " (the classic version)", "needs-you", why, null, null, ref ready);
            note = why;
        }

        // 2. F4SE
        bool f4se = dir is not null && File.Exists(Path.Combine(dir, "f4se_loader.exe")) && File.Exists(Path.Combine(dir, "f4se_1_10_163.dll"));
        if (f4se) Step("f4se", "F4SE 0.6.23 installed", "done", "The script extender is in the game's folder.", null, null, ref ready);
        else Step("f4se", "F4SE 0.6.23 installed", dir is null ? "waiting" : "needs-you",
            "The mod loads through the Fallout 4 Script Extender. Cairn downloads it from its author's site (f4se.silverlock.org) and puts it in the game's folder.", "install-f4se", "Install F4SE", ref ready);

        // 3. the mod's plugin, switched on (the mod's files are placed by the launcher first)
        bool placed = dir is not null && File.Exists(Path.Combine(dir, "Data", Plugin));
        if (PluginEnabled()) Step("plugin", "Mod plugin enabled", "done", "f4mp.esp is switched on in plugins.txt.", null, null, ref ready);
        else Step("plugin", "Mod plugin enabled", placed ? "needs-you" : "waiting",
            placed ? "Switches the mod's plugin on for Fallout 4." : "The mod is not in the game's folder yet: download it from the game's page first.", "enable-plugin", "Enable the plugin", ref ready, auto: placed ? "while" : null);

        // 4. loose files
        if (LooseFilesOn()) Step("loose", "Loose files enabled", "done", "Fallout4Custom.ini lets the game read the mod's scripts.", null, null, ref ready);
        else Step("loose", "Loose files enabled", "needs-you", "The mod's scripts are loose files, which Fallout 4 ignores until this is switched on in Fallout4Custom.ini.", "set-ini", "Enable loose files", ref ready, auto: placed ? "while" : null);

        Console.WriteLine("{\"done\":true,\"ready\":" + (ready ? "true" : "false") + ",\"optionalNeedsYou\":false}");
        if (note is not null) Console.WriteLine("{\"gameExeNote\":" + Q(note) + "}");
        if (dir is not null && File.Exists(Path.Combine(dir, "Fallout4.exe")))
            Console.WriteLine("{\"found\":{\"gameExe\":" + Q(Path.Combine(dir, "Fallout4.exe")) + ",\"gameDir\":" + Q(dir) + "}}");
        return 0;
    }

    static void Step(string id, string title, string status, string detail, string? action, string? label, ref bool ready, string? auto = null)
    {
        if (status != "done") ready = false;
        var sb = new StringBuilder("{\"step\":{\"id\":").Append(Q(id)).Append(",\"title\":").Append(Q(title)).Append(",\"status\":").Append(Q(status)).Append(",\"detail\":").Append(Q(detail));
        if (action is not null && status != "done") sb.Append(",\"action\":").Append(Q(action)).Append(",\"actionLabel\":").Append(Q(label ?? action));
        if (auto is not null && status != "done") sb.Append(",\"auto\":").Append(Q(auto));
        sb.Append(",\"optional\":false,\"system\":false}}");
        Console.WriteLine(sb.ToString());
    }

    // ---- setup do ----

    static async Task<int> DoAsync(string action, string? exe)
    {
        switch (action)
        {
            case "install-f4se": return await InstallF4seAsync(GameDir(exe));
            case "enable-plugin":
            {
                Directory.CreateDirectory(Path.GetDirectoryName(PluginsTxt)!);
                if (!PluginEnabled()) File.AppendAllText(PluginsTxt, (File.Exists(PluginsTxt) && !File.ReadAllText(PluginsTxt).EndsWith('\n') ? "\r\n" : "") + "*" + Plugin + "\r\n");
                return Ok("The mod's plugin is switched on.");
            }
            case "set-ini":
            {
                Directory.CreateDirectory(Path.GetDirectoryName(CustomIni)!);
                string text = File.Exists(CustomIni) ? File.ReadAllText(CustomIni) : "";
                if (!LooseFilesOn())
                {
                    if (text.Length > 0 && !text.EndsWith('\n')) text += "\r\n";
                    File.WriteAllText(CustomIni, text + "[Archive]\r\nbInvalidateOlderFiles=1\r\nsResourceDataDirsFinal=\r\n", Encoding.ASCII);
                }
                return Ok("Loose files are enabled.");
            }
            case "unplace-mod":
            {
                if (File.Exists(PluginsTxt))
                    File.WriteAllLines(PluginsTxt, File.ReadAllLines(PluginsTxt).Where(l => !Regex.IsMatch(l.Trim(), @"^\*?f4mp\.esp$", RegexOptions.IgnoreCase)));
                return Ok("The mod's plugin is switched off.");
            }
            default: return Fail("Unknown action " + action + ".");
        }
    }

    static async Task<int> InstallF4seAsync(string? dir)
    {
        if (dir is null) return Fail("Fallout 4 was not found.");
        string work = Path.Combine(Path.GetTempPath(), "cairn-f4se-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(work);
        try
        {
            Console.WriteLine("{\"say\":\"Downloading F4SE 0.6.23...\"}");
            string archive = Path.Combine(work, "f4se.7z");
            using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(3) })
            {
                http.DefaultRequestHeaders.UserAgent.ParseAdd("Cairn-launcher");
                using var resp = await http.GetAsync(F4seUrl, HttpCompletionOption.ResponseHeadersRead);
                resp.EnsureSuccessStatusCode();
                long total = resp.Content.Headers.ContentLength ?? 650275;
                using var src = await resp.Content.ReadAsStreamAsync();
                using var dst = File.Create(archive);
                var buf = new byte[64 * 1024]; long got = 0; int n;
                while ((n = await src.ReadAsync(buf)) > 0)
                {
                    await dst.WriteAsync(buf.AsMemory(0, n));
                    got += n;
                    Console.WriteLine("{\"progress\":" + Math.Min(0.8, 0.8 * got / Math.Max(1, total)).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "}");
                }
            }
            string have;
            using (var fs = File.OpenRead(archive)) have = Convert.ToHexString(SHA256.HashData(fs));
            if (!string.Equals(have, F4seSha256, StringComparison.OrdinalIgnoreCase)) return Fail("The F4SE download is not the file this mod expects (its checksum differs), so it was not installed.");

            Console.WriteLine("{\"say\":\"Unpacking F4SE...\"}");
            string tar = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "tar.exe");
            if (!File.Exists(tar)) return Fail("Windows' tar.exe is missing, so F4SE could not be unpacked. Install F4SE 0.6.23 by hand from f4se.silverlock.org.");
            string extract = Path.Combine(work, "x");
            Directory.CreateDirectory(extract);
            var psi = new ProcessStartInfo(tar) { WorkingDirectory = extract, UseShellExecute = false, CreateNoWindow = true };
            psi.ArgumentList.Add("-xf"); psi.ArgumentList.Add(archive);
            using (var p = Process.Start(psi)!) { await p.WaitForExitAsync(); if (p.ExitCode != 0) return Fail("F4SE could not be unpacked."); }
            string? inner = Directory.GetDirectories(extract).FirstOrDefault(d => Path.GetFileName(d).StartsWith("f4se_", StringComparison.OrdinalIgnoreCase));
            if (inner is null) return Fail("The F4SE archive is not laid out as expected.");

            foreach (var f in Directory.EnumerateFiles(inner, "*", SearchOption.AllDirectories))
            {
                string rel = Path.GetRelativePath(inner, f);
                if (rel.StartsWith("src" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;   // the archive carries F4SE's own source: not needed in the game's folder
                string target = Path.Combine(dir, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                File.Copy(f, target, overwrite: true);
            }
            Console.WriteLine("{\"progress\":1}");
            return File.Exists(Path.Combine(dir, "f4se_loader.exe")) ? Ok("F4SE 0.6.23 is installed.") : Fail("F4SE was copied, but f4se_loader.exe is not there.");
        }
        finally { try { Directory.Delete(work, recursive: true); } catch { } }
    }

    static int Ok(string message) { Console.WriteLine("{\"ok\":true,\"message\":" + Q(message) + "}"); return 0; }
    static int Fail(string message) { Console.WriteLine("{\"ok\":false,\"message\":" + Q(message) + "}"); return 1; }

    // ---- logs collect ----

    static int Logs(string[] args)
    {
        string? outDir = Opt(args, "--out");
        if (outDir is null) return 2;
        Directory.CreateDirectory(outDir);
        string docs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "My Games", "Fallout4", "F4SE");
        if (Directory.Exists(docs))
            foreach (var f in Directory.EnumerateFiles(docs, "*.log")) File.Copy(f, Path.Combine(outDir, "f4se-" + Path.GetFileName(f)), overwrite: true);
        string? dir = GameDir(Opt(args, "--game-exe"));
        if (dir is not null)
            foreach (var f in Directory.EnumerateFiles(dir, "f4mp*.log")) File.Copy(f, Path.Combine(outDir, Path.GetFileName(f)), overwrite: true);
        if (File.Exists(PluginsTxt)) File.Copy(PluginsTxt, Path.Combine(outDir, "plugins.txt"), overwrite: true);
        if (File.Exists(CustomIni)) File.Copy(CustomIni, Path.Combine(outDir, "Fallout4Custom.ini"), overwrite: true);
        return 0;
    }

    // a JSON string, written by hand: nothing here needs a serializer (and a native program stays small without one)
    static string Q(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case < ' ': sb.Append("\\u").Append(((int)c).ToString("x4")); break;
                default: sb.Append(c); break;
            }
        }
        return sb.Append('"').ToString();
    }
}
