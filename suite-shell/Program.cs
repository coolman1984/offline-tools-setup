using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Spectre.Console;

namespace OfflineToolsSuite;

internal static class Program
{
    private const string Version = "0.6.0";
    private static readonly string[] Tabs = { "SETUP", "SAFE REPAIR", "DEVICE DETAILS", "SKILLS HUB", "LOGS" };

    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = Encoding.UTF8;
        Console.Title = "Offline Automation & Development Suite";

        try
        {
            var bundleRoot = ResolveBundleRoot(args.FirstOrDefault());
            var care = LoadCareConfig(bundleRoot);
            var selected = 0;

            while (true)
            {
                RenderHome(selected, care);
                var key = Console.ReadKey(true);
                if (key.Key == ConsoleKey.LeftArrow) selected = (selected + Tabs.Length - 1) % Tabs.Length;
                else if (key.Key == ConsoleKey.RightArrow) selected = (selected + 1) % Tabs.Length;
                else if (key.Key == ConsoleKey.D1) selected = 0;
                else if (key.Key == ConsoleKey.D2) selected = 1;
                else if (key.Key == ConsoleKey.D3) selected = 2;
                else if (key.Key == ConsoleKey.D4) selected = 3;
                else if (key.Key == ConsoleKey.D5) selected = 4;
                else if (key.Key is ConsoleKey.Q or ConsoleKey.Escape) return 0;
                else if (key.Key == ConsoleKey.Enter)
                {
                    switch (selected)
                    {
                        case 0: RunSetup(bundleRoot); break;
                        case 1: RunSafeRepair(bundleRoot, care); break;
                        case 2: RunDeviceDetails(bundleRoot); break;
                        case 3: RunSkillsHub(bundleRoot); break;
                        case 4: RunLogs(); break;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.WriteException(ex, ExceptionFormats.ShortenPaths | ExceptionFormats.ShortenTypes);
            return 1;
        }
    }

    private static void RenderHome(int selected, CareConfiguration care)
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new FigletText("OFFLINE SUITE").Centered().Color(Color.Cyan1));
        AnsiConsole.Write(new Rule($"[grey]Automation • Office • PDF • Full Stack • Skills • Windows Care   v{Version}[/]").RuleStyle("grey"));
        AnsiConsole.WriteLine();

        var tabs = new StringBuilder();
        for (var i = 0; i < Tabs.Length; i++)
        {
            if (i > 0) tabs.Append("  ");
            tabs.Append(i == selected
                ? $"[black on cyan1 bold] {Tabs[i]} [/]"
                : $"[grey70 on grey15] {Tabs[i]} [/]" );
        }
        AnsiConsole.MarkupLine(tabs.ToString());
        AnsiConsole.MarkupLine("[grey]←/→ switch tabs   Enter open   1-5 jump   Esc/Q exit[/]\n");

        Panel content = selected switch
        {
            0 => new Panel(new Markup("[bold cyan]Professional Setup[/]\n\nInstall or repair the managed automation/development workstation: Python, Office/PDF tooling, databases, full-stack tooling, VS Code, Git, AI coding tools and native build prerequisites.\n\n[green]Existing projects and unrelated software remain isolated from the managed suite.[/]"))
            {
                Header = new PanelHeader("  WORKSTATION SETUP  "), Border = BoxBorder.Rounded, Padding = new Padding(2, 1)
            },
            1 => new Panel(new Markup($"[bold cyan]{Markup.Escape(care.ProductName)}[/]\n\nRun quick, deep or complete read-only diagnostics; inspect reclaimable space; verify Windows integrity; and execute only explicitly selected safe repairs.\n\n[red bold]RED LINE:[/] no boot/recovery/encryption changes, no security-policy bypass, no driver deletion, no manual WinSxS/Installer-cache deletion and no user-folder cleanup."))
            {
                Header = new PanelHeader("  SAFE WINDOWS CARE  "), Border = BoxBorder.Rounded, Padding = new Padding(2, 1)
            },
            2 => new Panel(new Markup("[bold cyan]Device Intelligence[/]\n\nRead-only hardware and Windows inventory with dedicated views for system overview, network/IP, storage health, security/recovery, problems and updates.\n\n[green]No settings are changed.[/]"))
            {
                Header = new PanelHeader("  DEVICE DETAILS  "), Border = BoxBorder.Rounded, Padding = new Padding(2, 1)
            },
            3 => new Panel(new Markup("[bold cyan]Developer Skills Hub[/]\n\nCreate, read, validate and manage one canonical skill library, then publish selected skills to detected AI development tools at user or project scope. Includes enterprise automation skills and local Project Brains.\n\n[green]Target workstations never download skill dependencies.[/]"))
            {
                Header = new PanelHeader("  SKILLS & PROJECT MEMORY  "), Border = BoxBorder.Rounded, Padding = new Padding(2, 1)
            },
            _ => new Panel(new Markup("[bold cyan]Logs & Evidence[/]\n\nReview installer logs, Windows Care results, skill deployment receipts, plans, state files and diagnostic evidence. Durable receipts make failures diagnosable instead of invoking the ancient Windows ritual of 'try it again'."))
            {
                Header = new PanelHeader("  LOGS & EVIDENCE  "), Border = BoxBorder.Rounded, Padding = new Padding(2, 1)
            }
        };
        AnsiConsole.Write(content);
    }

    private static void RunSetup(string bundleRoot)
    {
        AnsiConsole.Clear();
        var exe = Path.Combine(bundleRoot, "payload", "bootstrap", "OfflineToolsSetup.exe");
        if (!File.Exists(exe)) { ShowError("Setup engine is missing from the bundle.", exe); return; }
        RunConsoleProcess(exe, new[] { "--bundle-root", bundleRoot }, bundleRoot);
        Pause("Setup engine returned to the suite.");
    }

    private static void RunSkillsHub(string bundleRoot)
    {
        AnsiConsole.Clear();
        var exe = Path.Combine(bundleRoot, "payload", "bootstrap", "OfflineSkillsHub.exe");
        if (!File.Exists(exe)) { ShowError("Developer Skills Hub is missing from the bundle.", exe); return; }
        RunConsoleProcess(exe, new[] { bundleRoot }, bundleRoot);
        Pause("Skills Hub returned to the suite.");
    }

    private static void RunSafeRepair(string bundleRoot, CareConfiguration config)
    {
        while (true)
        {
            AnsiConsole.Clear();
            RenderSectionHeader("SAFE REPAIR", "Diagnostics first. Repairs are explicit, conservative and separately confirmed.");
            var choice = AnsiConsole.Prompt(new SelectionPrompt<string>()
                .Title("[bold cyan]Choose Windows Care mode[/]")
                .PageSize(10)
                .HighlightStyle(new Style(Color.Black, Color.Cyan1, Decoration.Bold))
                .AddChoices(
                    "Quick Health Check",
                    "Deep Diagnostics  [LONG]",
                    "All Diagnostics  [LONG / READ ONLY]",
                    "Custom checks / repairs",
                    "Back"));

            if (choice == "Back") return;
            List<CareAction> actions;
            if (choice == "Quick Health Check") actions = ActionsForPreset(config, "quick-health");
            else if (choice.StartsWith("Deep Diagnostics", StringComparison.Ordinal))
            {
                AnsiConsole.MarkupLine("[yellow]Deep diagnostics can take a long time because component-store, system-file and storage checks may scan large parts of Windows.[/]");
                if (!AnsiConsole.Confirm("Run deep read-only diagnostics now?", true)) continue;
                actions = ActionsForPreset(config, "deep-diagnostics");
            }
            else if (choice.StartsWith("All Diagnostics", StringComparison.Ordinal))
            {
                AnsiConsole.MarkupLine("[yellow]All Diagnostics includes every read-only check, including long-running checks. It performs no cleanup or repair.[/]");
                if (!AnsiConsole.Confirm("Run every read-only diagnostic?", true)) continue;
                actions = ActionsForPreset(config, "all-diagnostics");
            }
            else
            {
                var prompt = new MultiSelectionPrompt<CareAction>()
                    .Title("[bold cyan]Select diagnostics and repairs[/]")
                    .InstructionsText("[grey](↑/↓ move, Space toggle, Enter confirm)[/]")
                    .PageSize(20)
                    .NotRequired()
                    .UseConverter(FormatCareAction);
                prompt.AddChoices(config.Actions);
                foreach (var action in config.Actions.Where(a => a.DefaultSelected && a.Mode == "diagnostic")) prompt.Select(action);
                actions = AnsiConsole.Prompt(prompt);
                if (actions.Count == 0) continue;
            }

            RenderCarePlan(actions);
            var repairs = actions.Where(a => a.Mode == "repair").ToList();
            if (repairs.Count > 0)
            {
                AnsiConsole.MarkupLine("\n[red bold]Selected actions will change Windows maintenance state.[/] These actions are bounded and conservative, but they are not read-only.");
                if (!AnsiConsole.Confirm("Apply the selected repair actions?", false)) continue;
            }
            else if (!AnsiConsole.Confirm("Run the selected diagnostics?", true)) continue;

            RunCareEngine(bundleRoot, actions);
            Pause("Windows Care finished. Review its summary/evidence before applying further repairs.");
        }
    }

    private static string FormatCareAction(CareAction action)
    {
        var mode = action.Mode == "repair" ? "[yellow]REPAIR[/]" : "[green]CHECK[/]";
        var duration = action.Duration == "long" ? "[yellow]LONG[/]" : $"[grey]{Markup.Escape(action.Duration.ToUpperInvariant())}[/]";
        return $"{mode}  [bold]{Markup.Escape(action.Name)}[/]  {duration}  [grey]- {Markup.Escape(action.Description)}[/]";
    }

    private static void RenderCarePlan(List<CareAction> actions)
    {
        var table = new Table().RoundedBorder().BorderColor(Color.Grey37);
        table.AddColumn("[bold]Type[/]");
        table.AddColumn("[bold]Action[/]");
        table.AddColumn("[bold]Time[/]");
        table.AddColumn("[bold]Risk[/]");
        foreach (var action in actions)
            table.AddRow(action.Mode == "repair" ? "[yellow]Repair[/]" : "[green]Diagnostic[/]", Markup.Escape(action.Name), Markup.Escape(action.Duration), Markup.Escape(action.Risk));
        AnsiConsole.Write(new Panel(table) { Header = new PanelHeader("  EXECUTION PLAN  "), Border = BoxBorder.Double });
    }

    private static void RunCareEngine(string bundleRoot, List<CareAction> actions)
    {
        var script = Path.Combine(bundleRoot, "scripts", "Invoke-SafeWindowsCare.ps1");
        if (!File.Exists(script)) { ShowError("Windows Care backend is missing.", script); return; }
        var ids = string.Join(',', actions.Select(a => a.Id));
        AnsiConsole.Clear();
        RenderSectionHeader("WINDOWS CARE RUN", "Do not close the window while a selected Windows servicing check is active.");
        RunConsoleProcess(ResolvePowerShell(bundleRoot), new[] { "-NoLogo", "-NoProfile", "-File", script, "-Actions", ids, "-BundleRoot", bundleRoot }, bundleRoot);
    }

    private static void RunDeviceDetails(string bundleRoot)
    {
        AnsiConsole.Clear();
        RenderSectionHeader("DEVICE DETAILS", "Collecting read-only inventory and health evidence.");
        var script = Path.Combine(bundleRoot, "scripts", "Get-DeviceInventory.ps1");
        if (!File.Exists(script)) { ShowError("Device inventory backend is missing.", script); return; }
        var output = @"C:\OfflineTools\state\device-inventory.json";
        RunConsoleProcess(ResolvePowerShell(bundleRoot), new[] { "-NoLogo", "-NoProfile", "-File", script, "-OutputPath", output, "-SummaryOnly" }, bundleRoot);
        if (!File.Exists(output)) { ShowError("Device inventory did not produce its structured output.", output); return; }

        while (true)
        {
            AnsiConsole.Clear();
            RenderSectionHeader("DEVICE DETAILS", "Read-only subviews. Reopen this tab to refresh the inventory.");
            var choice = AnsiConsole.Prompt(new SelectionPrompt<string>()
                .Title("[bold cyan]Choose device detail view[/]")
                .PageSize(12)
                .HighlightStyle(new Style(Color.Black, Color.Cyan1, Decoration.Bold))
                .AddChoices(
                    "Overview",
                    "Network & IP",
                    "Storage & Disk Health",
                    "Security & Policy",
                    "Problems & Events",
                    "Updates & Services",
                    "Open Full JSON",
                    "Back"));
            if (choice == "Back") return;
            if (choice == "Open Full JSON")
            {
                Process.Start(new ProcessStartInfo("notepad.exe", $"\"{output}\"") { UseShellExecute = true });
                continue;
            }

            using var doc = JsonDocument.Parse(File.ReadAllText(output));
            var root = doc.RootElement;
            switch (choice)
            {
                case "Overview":
                    RenderDeviceSections(root, "OVERVIEW", new[] { "computer", "windows", "bios", "cpu", "memoryModules", "gpu" });
                    RenderWindowsLifecycleNotice(root);
                    break;
                case "Network & IP": RenderDeviceSections(root, "NETWORK & IP", new[] { "networkAdapters", "network" }); break;
                case "Storage & Disk Health": RenderDeviceSections(root, "STORAGE & DISK HEALTH", new[] { "volumes", "disks", "partitions", "physicalDiskHealth" }); break;
                case "Security & Policy": RenderDeviceSections(root, "SECURITY & POLICY", new[] { "security", "recovery", "environment" }); break;
                case "Problems & Events": RenderDeviceSections(root, "PROBLEMS & EVENTS", new[] { "deviceProblems", "recentCriticalAndErrorEvents" }); break;
                case "Updates & Services": RenderDeviceSections(root, "UPDATES & SERVICES", new[] { "updates", "autoServicesNotRunning", "startupItems" }); break;
            }
            AnsiConsole.MarkupLine("\n[cyan]Press any key to return to Device Details.[/]");
            Console.ReadKey(true);
        }
    }

    private static void RenderDeviceSections(JsonElement root, string title, IEnumerable<string> properties)
    {
        AnsiConsole.Clear();
        RenderSectionHeader(title, "Structured inventory captured locally from Windows.");
        foreach (var property in properties)
        {
            if (!root.TryGetProperty(property, out var value)) continue;
            var formatted = JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true });
            if (formatted.Length > 14000) formatted = formatted[..14000] + "\n... output shortened; full JSON contains the remaining data.";
            AnsiConsole.Write(new Panel(new Text(formatted))
            {
                Header = new PanelHeader($"  {property.ToUpperInvariant()}  "), Border = BoxBorder.Rounded, Padding = new Padding(1, 0)
            });
        }
    }

    private static void RenderWindowsLifecycleNotice(JsonElement root)
    {
        if (!root.TryGetProperty("windows", out var windows)) return;
        var caption = windows.TryGetProperty("caption", out var c) ? c.GetString() ?? string.Empty : string.Empty;
        if (caption.Contains("Windows 10", StringComparison.OrdinalIgnoreCase) &&
            !caption.Contains("LTSC", StringComparison.OrdinalIgnoreCase) &&
            !caption.Contains("LTSB", StringComparison.OrdinalIgnoreCase))
        {
            AnsiConsole.MarkupLine("\n[yellow bold]Lifecycle advisory:[/] Standard Windows 10 servicing ended on 2025-10-14. Corporate ESU or a long-term servicing edition can change the applicable lifecycle; verify the workstation's managed servicing status.");
        }
    }

    private static void RunLogs()
    {
        AnsiConsole.Clear();
        RenderSectionHeader("LOGS & EVIDENCE", "Latest installer, repair, diagnostics and skill deployment evidence.");
        var roots = new[]
        {
            @"C:\OfflineTools\logs",
            @"C:\OfflineTools\state\windows-care",
            @"C:\OfflineTools\state",
            @"C:\OfflineTools\SkillsHub\state"
        };
        var files = roots.Where(Directory.Exists)
            .SelectMany(r => Directory.EnumerateFiles(r, "*", SearchOption.TopDirectoryOnly))
            .Select(p => new FileInfo(p))
            .OrderByDescending(f => f.LastWriteTimeUtc)
            .Take(35)
            .ToList();

        var table = new Table().RoundedBorder();
        table.AddColumn("[bold]Modified[/]");
        table.AddColumn("[bold]File[/]");
        table.AddColumn("[bold]Size[/]");
        foreach (var file in files)
            table.AddRow(file.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), Markup.Escape(file.FullName), $"{file.Length / 1024d:N0} KB");
        if (files.Count == 0) table.AddRow("-", "No suite logs yet", "-");
        AnsiConsole.Write(table);

        var choice = AnsiConsole.Prompt(new SelectionPrompt<string>().Title("\n[bold cyan]Logs[/]").AddChoices("Open suite folder", "Back"));
        if (choice == "Open suite folder")
        {
            Directory.CreateDirectory(@"C:\OfflineTools\logs");
            Process.Start(new ProcessStartInfo("explorer.exe", @"C:\OfflineTools") { UseShellExecute = true });
        }
    }

    private static int RunConsoleProcess(string file, IEnumerable<string> arguments, string workingDirectory)
    {
        var psi = new ProcessStartInfo(file) { UseShellExecute = false, WorkingDirectory = workingDirectory };
        foreach (var arg in arguments) psi.ArgumentList.Add(arg);
        using var process = Process.Start(psi);
        if (process is null) return 1;
        process.WaitForExit();
        return process.ExitCode;
    }

    private static string ResolvePowerShell(string bundleRoot)
    {
        var bundled = Path.Combine(bundleRoot, "payload", "developer", "powershell", "pwsh.exe");
        return File.Exists(bundled) ? bundled : "powershell.exe";
    }

    private static void RenderSectionHeader(string title, string subtitle)
    {
        AnsiConsole.Write(new Rule($"[bold cyan]{Markup.Escape(title)}[/]").RuleStyle("cyan"));
        if (!string.IsNullOrWhiteSpace(subtitle)) AnsiConsole.MarkupLine($"[grey]{Markup.Escape(subtitle)}[/]\n");
    }

    private static void Pause(string message)
    {
        AnsiConsole.MarkupLine($"\n[grey]{Markup.Escape(message)}[/]");
        AnsiConsole.MarkupLine("[cyan]Press any key to return.[/]");
        Console.ReadKey(true);
    }

    private static void ShowError(string message, string detail)
    {
        AnsiConsole.Write(new Panel($"[red bold]{Markup.Escape(message)}[/]\n[grey]{Markup.Escape(detail)}[/]")
        {
            Border = BoxBorder.Double, Header = new PanelHeader("  ERROR  ")
        });
        Pause("No changes were made.");
    }

    private static string ResolveBundleRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var p = Path.GetFullPath(explicitRoot.Trim('"'));
            if (File.Exists(Path.Combine(p, "config", "windows-care.json"))) return p;
        }

        var current = AppContext.BaseDirectory;
        for (var i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(current, "config", "windows-care.json"))) return current;
            var parent = Directory.GetParent(current);
            if (parent is null) break;
            current = parent.FullName;
        }

        current = Directory.GetCurrentDirectory();
        if (File.Exists(Path.Combine(current, "config", "windows-care.json"))) return current;
        throw new DirectoryNotFoundException("Could not locate the complete offline suite bundle.");
    }

    private static CareConfiguration LoadCareConfig(string bundleRoot)
    {
        var path = Path.Combine(bundleRoot, "config", "windows-care.json");
        return JsonSerializer.Deserialize<CareConfiguration>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
               ?? throw new InvalidOperationException("Windows Care configuration could not be loaded.");
    }

    private static List<CareAction> ActionsForPreset(CareConfiguration config, string id)
    {
        var preset = config.Presets.First(p => p.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
        return preset.Actions.Select(actionId => config.Actions.First(a => a.Id.Equals(actionId, StringComparison.OrdinalIgnoreCase))).ToList();
    }
}

internal sealed class CareConfiguration
{
    public int SchemaVersion { get; set; }
    public string ProductName { get; set; } = "Windows Safe Care Center";
    public List<CarePreset> Presets { get; set; } = new();
    public List<CareAction> Actions { get; set; } = new();
}

internal sealed class CarePreset
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public List<string> Actions { get; set; } = new();
}

internal sealed class CareAction
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Mode { get; set; } = "diagnostic";
    public string Duration { get; set; } = "short";
    public string Risk { get; set; } = "none";
    public bool DefaultSelected { get; set; }
    public string Description { get; set; } = string.Empty;
}
