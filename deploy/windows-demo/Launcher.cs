using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

internal sealed class DemoLauncher : Form
{
    readonly TextBox output = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill };
    readonly Button install = new Button { Text = "설치 / 실행", Width = 140, Height = 36 };
    readonly Button stop = new Button { Text = "시연 종료", Width = 110, Height = 36 };
    readonly Button accounts = new Button { Text = "시연 계정 보기", Width = 140, Height = 36 };
    Process worker;
    string bundle;
    readonly string state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UniversityPathDemo", "state");

    DemoLauncher()
    {
        Text = "UniversityPath 시연 설치 및 실행";
        Size = new Size(780, 540);
        MinimumSize = new Size(620, 440);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Malgun Gothic", 10);
        var description = new Label { Dock = DockStyle.Top, Height = 100, Padding = new Padding(12), Text =
            "학교 기준 · 수강 · 요건 체크가 포함된 독립 시연본입니다.\r\n처음에는 Docker/WSL 설치에 인터넷 · Windows 권한 승인 · 재부팅이 필요할 수 있습니다.\r\n재부팅 후 이 파일을 다시 실행하면 이어서 준비합니다. 기존 시연 기록은 보존됩니다." };
        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 60, Padding = new Padding(10) };
        actions.Controls.AddRange(new Control[] {install, stop, accounts});
        Controls.Add(output); Controls.Add(description); Controls.Add(actions);
        install.Click += delegate { Run(false); };
        stop.Click += delegate { Run(true); };
        accounts.Click += delegate {
            string path = Path.Combine(state, "Demo-Accounts.txt");
            if (!File.Exists(path)) { MessageBox.Show("먼저 설치 / 실행을 완료해 주세요."); return; }
            Process.Start(new ProcessStartInfo("notepad.exe", "\"" + path + "\"") { UseShellExecute = true });
        };
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (worker != null && !worker.HasExited) { e.Cancel = true; MessageBox.Show("현재 단계가 끝난 뒤 창을 닫아 주세요."); }
        };
    }

    void Log(string text)
    {
        if (text == null || IsDisposed) return;
        BeginInvoke((Action)delegate { output.AppendText(text + Environment.NewLine); });
    }

    string Extract()
    {
        // Content-addressed extraction keeps resumed installation files in a stable directory.
        string digest;
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DemoBundle"))
        using (var sha = SHA256.Create()) { digest = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").Substring(0,16); }
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "UniversityPathDemo", "packages", digest);
        Directory.CreateDirectory(root);
        string prefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DemoBundle"))
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
        {
            foreach (var entry in zip.Entries)
            {
                string target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                if (!target.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid package path");
                if (entry.FullName.EndsWith("/")) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                using (var input = entry.Open())
                using (var destination = File.Create(target)) { input.CopyTo(destination); }
            }
        }
        return root;
    }

    async void Run(bool stopping)
    {
        install.Enabled = stop.Enabled = false;
        try
        {
            if (bundle == null) { Log("시연 묶음을 준비합니다..."); bundle = await System.Threading.Tasks.Task.Run((Func<string>)Extract); }
            var script = Path.Combine(bundle, "Setup.ps1");
            var start = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"" + (stopping ? " -Stop" : "")) {
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            worker = new Process { StartInfo = start, EnableRaisingEvents = true };
            worker.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { Log(e.Data); };
            worker.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { Log(e.Data); };
            worker.Start(); worker.BeginOutputReadLine(); worker.BeginErrorReadLine();
            await System.Threading.Tasks.Task.Run((Action)worker.WaitForExit);
            if (worker.ExitCode == 3010) MessageBox.Show("Windows를 재부팅한 뒤 이 설치 파일을 다시 실행해 주세요.", "재부팅 필요");
            else if (worker.ExitCode != 0) MessageBox.Show("설치가 완료되지 않았습니다. 위 메시지를 확인하고 다시 실행해 주세요.", "확인 필요");
        }
        catch (Exception e) { Log(e.Message); MessageBox.Show(e.Message, "시연 실행 오류"); }
        finally { install.Enabled = stop.Enabled = true; }
    }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--verify-bundle")
        {
            try {
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DemoBundle"))
                using (var zip = new ZipArchive(stream, ZipArchiveMode.Read)) {
                    string[] required = {"Setup.ps1", "Enable-Wsl.ps1", "compose.yaml", "manifest.json", "demo-data.json", "images.tar"};
                    foreach (string name in required) if (zip.GetEntry(name) == null) return 2;
                    foreach (var entry in zip.Entries) using (var input = entry.Open()) using (var sha = SHA256.Create()) { sha.ComputeHash(input); }
                }
                return 0;
            } catch { return 1; }
        }
        using (var mutex = new System.Threading.Mutex(false, "Local\\UniversityPathDemoLauncher"))
        {
            if (!mutex.WaitOne(0)) { MessageBox.Show("이미 실행 중인 UniversityPath 시연 설치 창을 확인해 주세요."); return 1; }
            try { Application.EnableVisualStyles(); Application.Run(new DemoLauncher()); }
            finally { mutex.ReleaseMutex(); }
        }
        return 0;
    }
}
