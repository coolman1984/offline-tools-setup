using System.Diagnostics;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;
using Spectre.Console;

namespace OfflineToolsSetup;

internal static class Program
{
    private const string Version = "0.2.0";

    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = Encoding.UTF8;
        Console.Title = "Offline Automation & Development Suite";

        try
        {
            var options = CommandLineOptions.Parse(args);
            var bundleRoot = ResolveBundleRoot(options.BundleRoot);
            var configPath = Path.Combine(bundleRoot, "config", "setup-profiles.json");
            var config = JsonSerializer.Deserialize<SetupConfiguration>(File.ReadAllText(configPath), JsonOptions())
                         ?? throw new InvalidOperationException("Setup profile configuration could not be loaded.");

            RenderHeader(config);
            var scan = RunPreflightScan(bundleRoot);
            RenderScan(scan);

            if (!scan.IsWindows || !scan.Is64Bit)
            {
                AnsiConsole.MarkupLine("\n[red bold]This package supports Windows 10/11 x64 only.[/]");
                return 3;
            }

            if (!scan.IsAdministrator)
            {
                AnsiConsole.MarkupLine("\n[red bold]Administrator rights are required.[/] The launcher should trigger UAC automatically.");
                return 5;
            }

            if (options.DiagnosticsOnly)
            {
                RenderDiagnosticsFooter(scan);
                return 0;
            }

            InstallSelection selection;
            if (!string.IsNullOrWhiteSpace(options.Preset))
            {
                selection = BuildPresetSelection(config, options.Preset!, includeAllSupportedComponents: options.Preset.Equals("complete", StringComparison.OrdinalIgnoreCase));
            }
            else
            {
                selection = RunInteractiveSelection(config, scan);
            }

            if (selection.ExitRequested)
                return 0;

            RenderPlan(config, selection, scan);

            if (!HasEnoughDisk(scan, selection.EstimatedMb))
            {
                AnsiConsole.MarkupLine("\n[red bold]Not enough free disk space for the selected plan.[/]");
                return 20;
            }

            if (options.PlanOnly)
            {
                var planOnlyPath = WritePlan(bundleRoot, selection, scan);
                AnsiConsole.MarkupLine($"\n[green]Plan created:[/] {Markup.Escape(planOnlyPath)}");
                return 0;
            }

            if (!options.NonInteractive)
            {
                if (scan.PendingReboot)
                {
                    AnsiConsole.MarkupLine("\n[yellow bold]A Windows restart is currently pending.[/] Installing now may increase file-lock and reboot risk.");
                    if (!AnsiConsole.Confirm("Continue anyway?", false))
                        return 10;
                }

                if (!AnsiConsole.Confirm("\n[bold]Apply this installation plan?[/]", true))
                    return 0;
            }

            var planPath = WritePlan(bundleRoot, selection, scan);
            return RunInstaller(bundleRoot, planPath);
        }
        catch (Exception ex)
        {
            AnsiConsole.WriteException(ex, ExceptionFormats.ShortenPaths | ExceptionFormats.ShortenTypes);
            return 1;
        }
    }

    private static JsonSerializerOptions JsonOptions() => new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private static string ResolveBundleRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var full = Path.GetFullPath(explicitRoot);
            if (File.Exists(Path.Combine(full, "config", "setup-profiles.json")))
                return full;
            throw new DirectoryNotFoundException($"Bundle root does not contain config/setup-profiles.json: {full}");
        }

        var current = AppContext.BaseDirectory;
        for (var i = 0; i < 6; i++)
        {
            if (File.Exists(Path.Combine(current, "config", "setup-profiles.json")))
                return current;
            current = Directory.GetParent(current)?.FullName ?? current;
        }

        current = Directory.GetCurrentDirectory();
        if (File.Exists(Path.Combine(current, "config", "setup-profiles.json")))
            return current;

        throw new DirectoryNotFoundException("Could not locate the offline bundle root.");
    }

    private static void RenderHeader(SetupConfiguration config)
    {
        AnsiConsole.Clear();
        var title = new FigletText("OFFLINE TOOLS").Centered().Color(Color.Cyan1);
        AnsiConsole.Write(title);
        var panel = new Panel(
            new Markup($"[bold white]{Markup.Escape(config.Ui.ProductName)}[/]\n[grey]{Markup.Escape(config.Ui.Subtitle)}[/]\n[deepskyblue1]Version {Version}[/]"))
        {
            Border = BoxBorder.Rounded,
            Header = new PanelHeader("  PROFESSIONAL SETUP  "),
            Padding = new Padding(2, 1)
        };
        AnsiConsole.Write(panel);
        AnsiConsole.MarkupLine("[grey]Arrow keys navigate  •  Space toggles  •  Enter confirms  •  Esc cancels where available[/]\n");
    }

    private static PreflightScan RunPreflightScan(string bundleRoot)
    {
        var scan = new PreflightScan();
        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots12)
            .SpinnerStyle(Style.Parse("cyan"))
            .Start("[cyan]Scanning workstation...[/]", ctx =>
            {
                scan.IsWindows = OperatingSystem.IsWindows();
                scan.Is64Bit = Environment.Is64BitOperatingSystem;
                scan.IsAdministrator = IsAdministrator();

                ctx.Status("[cyan]Reading Windows version and architecture...[/]");
                scan.WindowsName = ReadRegistryString(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductName") ?? Environment.OSVersion.VersionString;
                scan.WindowsBuild = ReadRegistryString(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuildNumber") ?? Environment.OSVersion.Version.Build.ToString();

                ctx.Status("[cyan]Checking disk capacity...[/]");
                var systemRoot = Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
                var drive = new DriveInfo(systemRoot);
                scan.FreeDiskGb = Math.Round(drive.AvailableFreeSpace / 1024d / 1024d / 1024d, 1);

                ctx.Status("[cyan]Checking Windows restart state...[/]");
                scan.PendingReboot = TestPendingReboot();
                scan.LongPathsEnabled = ReadRegistryDword(Registry.LocalMachine, @"SYSTEM\CurrentControlSet\Control\FileSystem", "LongPathsEnabled") == 1;

                ctx.Status("[cyan]Inspecting Microsoft Office...[/]");
                var office = DetectOffice();
                scan.OfficeInstalled = office.Installed;
                scan.OfficeVersion = office.Version;
                scan.OfficeArchitecture = office.Architecture;
                scan.OfficeProducts = office.Products;

                ctx.Status("[cyan]Inspecting existing developer tools...[/]");
                scan.PythonVersion = TryGetCommandVersion("python", "--version");
                scan.NodeVersion = TryGetCommandVersion("node", "--version");
                scan.GitVersion = TryGetCommandVersion("git", "--version");
                scan.PowerShell7Version = TryGetCommandVersion("pwsh", "-NoLogo", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()");
                scan.VsCodeVersion = TryGetCommandVersion("code", "--version");

                ctx.Status("[cyan]Checking local bundle control files...[/]");
                scan.BundleManifestPresent = File.Exists(Path.Combine(bundleRoot, "bundle-sha256.json"));
                scan.BundleInfoPresent = File.Exists(Path.Combine(bundleRoot, "bundle-info.json"));
                scan.NativeStatusPresent = File.Exists(Path.Combine(bundleRoot, "native-components.json"));
                Thread.Sleep(200);
            });
        return scan;
    }

    private static void RenderScan(PreflightScan scan)
    {
        var table = new Table().RoundedBorder().BorderColor(Color.Grey37);
        table.AddColumn(new TableColumn("[bold]Check[/]").NoWrap());
        table.AddColumn("[bold]Status[/]");
        table.AddColumn("[bold]Details[/]");

        AddScanRow(table, "Windows", scan.IsWindows && scan.Is64Bit, $"{scan.WindowsName} • build {scan.WindowsBuild} • {(scan.Is64Bit ? "x64" : "unsupported architecture")}");
        AddScanRow(table, "Administrator", scan.IsAdministrator, scan.IsAdministrator ? "Elevated session" : "Elevation required");
        AddScanRow(table, "Disk", scan.FreeDiskGb >= 12, $"{scan.FreeDiskGb:0.0} GB free on system drive");
        AddScanRow(table, "Restart", !scan.PendingReboot, scan.PendingReboot ? "Windows restart pending" : "No restart marker detected");
        AddScanRow(table, "Long paths", scan.LongPathsEnabled, scan.LongPathsEnabled ? "Enabled" : "Disabled; setup can enable it");
        AddScanRow(table, "Microsoft Office", scan.OfficeInstalled, scan.OfficeInstalled ? $"{scan.OfficeProducts} • {scan.OfficeArchitecture} • {scan.OfficeVersion}" : "Not detected; file-level automation still works");
        AddScanRow(table, "Python", !string.IsNullOrWhiteSpace(scan.PythonVersion), scan.PythonVersion ?? "Managed runtimes will be installed");
        AddScanRow(table, "Node.js", !string.IsNullOrWhiteSpace(scan.NodeVersion), scan.NodeVersion ?? "LTS runtime will be installed");
        AddScanRow(table, "Git", !string.IsNullOrWhiteSpace(scan.GitVersion), scan.GitVersion ?? "MinGit will be installed");
        AddScanRow(table, "PowerShell 7", !string.IsNullOrWhiteSpace(scan.PowerShell7Version), scan.PowerShell7Version ?? "Portable PowerShell 7 will be installed");
        AddScanRow(table, "VS Code", !string.IsNullOrWhiteSpace(scan.VsCodeVersion), scan.VsCodeVersion?.Split('\n').FirstOrDefault() ?? "Portable VS Code will be installed");
        AddScanRow(table, "Bundle manifest", scan.BundleManifestPresent, scan.BundleManifestPresent ? "Integrity manifest found" : "Final bundle manifest not found yet");

        AnsiConsole.Write(new Panel(table).Header("  PREFLIGHT SCAN  ").Border(BoxBorder.Rounded));
    }

    private static void AddScanRow(Table table, string name, bool good, string details)
    {
        var icon = good ? "[green]● READY[/]" : "[yellow]● ACTION[/]";
        table.AddRow(Markup.Escape(name), icon, Markup.Escape(details));
    }

    private static InstallSelection RunInteractiveSelection(SetupConfiguration config, PreflightScan scan)
    {
        var menuChoices = new[]
        {
            "Recommended Professional Setup",
            "Automation & Office Workstation",
            "Full-Stack Development Workstation",
            "Complete Workstation",
            "Custom Selection",
            "Diagnostics Only",
            "Exit"
        };

        var action = AnsiConsole.Prompt(new SelectionPrompt<string>()
            .Title("\n[bold cyan]Choose setup mode[/]")
            .PageSize(10)
            .HighlightStyle(new Style(Color.Black, Color.Cyan1, Decoration.Bold))
            .AddChoices(menuChoices));

        if (action == "Exit") return InstallSelection.Exit();
        if (action == "Diagnostics Only")
        {
            RenderDiagnosticsFooter(scan);
            return InstallSelection.Exit();
        }
        if (action == "Recommended Professional Setup") return BuildPresetSelection(config, "recommended", false);
        if (action == "Automation & Office Workstation") return BuildPresetSelection(config, "automation", false);
        if (action == "Full-Stack Development Workstation") return BuildPresetSelection(config, "webdev", false);
        if (action == "Complete Workstation") return BuildPresetSelection(config, "complete", true);

        var profilePrompt = new MultiSelectionPrompt<ProfileDefinition>()
            .Title("[bold cyan]Select professional profiles[/]")
            .InstructionsText("[grey](↑/↓ move, [cyan]<space>[/] toggle, [green]<enter>[/] confirm)[/]")
            .PageSize(12)
            .UseConverter(p => $"[bold]{Markup.Escape(p.DisplayName)}[/] [grey]- {Markup.Escape(p.Description)}[/]");

        profilePrompt.AddChoices(config.Profiles);
        foreach (var profile in config.Profiles.Where(p => p.Recommended))
            profilePrompt.Select(profile);

        var chosenProfiles = AnsiConsole.Prompt(profilePrompt);
        var components = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

        foreach (var profile in chosenProfiles)
        {
            var selectable = profile.Components.Where(c => c.Supported != false).ToList();
            if (selectable.Count == 0) continue;

            var componentPrompt = new MultiSelectionPrompt<ComponentDefinition>()
                .Title($"[bold cyan]{Markup.Escape(profile.DisplayName)}[/] - choose components")
                .InstructionsText("[grey](Space toggles optional components. Recommended items start selected.)[/]")
                .PageSize(15)
                .NotRequired()
                .UseConverter(c => $"{Markup.Escape(c.Name)}{(string.IsNullOrWhiteSpace(c.Description) ? "" : $" [grey]- {Markup.Escape(c.Description)}[/]")}");
            componentPrompt.AddChoices(selectable);
            foreach (var component in selectable.Where(c => c.SelectedByDefault))
                componentPrompt.Select(component);

            var selectedComponents = AnsiConsole.Prompt(componentPrompt).Select(c => c.Id).ToList();
            components[profile.Id] = selectedComponents;

            foreach (var unsupported in profile.Components.Where(c => c.Supported == false))
                AnsiConsole.MarkupLine($"[yellow]Skipped unsupported:[/] {Markup.Escape(unsupported.Name)} [grey]{Markup.Escape(unsupported.Reason ?? string.Empty)}[/]");
        }

        return BuildSelection(config, chosenProfiles.Select(p => p.Id).ToList(), components);
    }

    private static InstallSelection BuildPresetSelection(SetupConfiguration config, string presetId, bool includeAllSupportedComponents)
    {
        var preset = config.Presets.FirstOrDefault(p => p.Id.Equals(presetId, StringComparison.OrdinalIgnoreCase))
                     ?? throw new InvalidOperationException($"Unknown preset: {presetId}");
        var components = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var profileId in preset.Profiles)
        {
            var profile = config.Profiles.First(p => p.Id.Equals(profileId, StringComparison.OrdinalIgnoreCase));
            components[profile.Id] = profile.Components
                .Where(c => c.Supported != false && (includeAllSupportedComponents || c.SelectedByDefault))
                .Select(c => c.Id)
                .ToList();
        }
        return BuildSelection(config, preset.Profiles, components);
    }

    private static InstallSelection BuildSelection(SetupConfiguration config, List<string> profileIds, Dictionary<string, List<string>> components)
    {
        var selectedProfiles = config.Profiles.Where(p => profileIds.Contains(p.Id, StringComparer.OrdinalIgnoreCase)).ToList();
        var packageProfiles = new HashSet<string>(config.Core.PythonRequirementProfiles, StringComparer.OrdinalIgnoreCase);
        foreach (var p in selectedProfiles)
            foreach (var req in p.PythonRequirementProfiles)
                packageProfiles.Add(req);

        var allComponentIds = components.Values.SelectMany(x => x).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var estimate = config.Core.EstimatedMb + selectedProfiles.Sum(p => p.EstimatedMb);

        return new InstallSelection
        {
            ProfileIds = selectedProfiles.Select(p => p.Id).ToList(),
            Components = components,
            PythonRequirementProfiles = packageProfiles.ToList(),
            IncludeTesseract = allComponentIds.Contains("tesseract"),
            IncludeSqlServerExpress = allComponentIds.Contains("sql-server-express"),
            InstallAiTools = profileIds.Contains("ai-dev", StringComparer.OrdinalIgnoreCase),
            EstimatedMb = estimate
        };
    }

    private static void RenderPlan(SetupConfiguration config, InstallSelection selection, PreflightScan scan)
    {
        var table = new Table().RoundedBorder();
        table.AddColumn("[bold]Layer[/]");
        table.AddColumn("[bold]Selection[/]");
        table.AddColumn("[bold]Action[/]");

        table.AddRow("Core", Markup.Escape(config.Core.DisplayName), "[cyan]Required[/]");
        foreach (var id in selection.ProfileIds)
        {
            var profile = config.Profiles.First(p => p.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
            var count = selection.Components.TryGetValue(id, out var list) ? list.Count : 0;
            table.AddRow("Profile", Markup.Escape(profile.DisplayName), $"[green]Install / repair[/] [grey]({count} components selected)[/]");
        }

        if (selection.IncludeTesseract)
            table.AddRow("Native", "Tesseract OCR", "[yellow]Install if approved media is present[/]");
        if (selection.IncludeSqlServerExpress)
            table.AddRow("Native", "SQL Server Express", "[yellow]Install if full offline media is present[/]");

        var requiredGb = Math.Ceiling((selection.EstimatedMb / 1024d) * 1.25 + 2);
        var footer = $"Estimated installed footprint: ~{selection.EstimatedMb / 1024d:0.0} GB  •  Safe free-space target: {requiredGb:0} GB  •  Current free: {scan.FreeDiskGb:0.0} GB";
        AnsiConsole.Write(new Panel(table)
            .Header("  INSTALLATION PLAN  ")
            .Footer(new PanelHeader(Markup.Escape(footer)))
            .Border(BoxBorder.Double));
    }

    private static bool HasEnoughDisk(PreflightScan scan, long estimatedMb)
    {
        var requiredGb = (estimatedMb / 1024d) * 1.25 + 2;
        return scan.FreeDiskGb >= requiredGb;
    }

    private static string WritePlan(string bundleRoot, InstallSelection selection, PreflightScan scan)
    {
        var planDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "OfflineToolsSetup", "plans");
        Directory.CreateDirectory(planDir);
        var planPath = Path.Combine(planDir, $"plan-{DateTime.Now:yyyyMMdd-HHmmss}.json");
        var payload = new InstallationPlan
        {
            SchemaVersion = 1,
            CreatedAtUtc = DateTime.UtcNow,
            BundleRoot = bundleRoot,
            InstallRoot = @"C:\OfflineTools",
            Profiles = selection.ProfileIds,
            Components = selection.Components,
            PythonRequirementProfiles = selection.PythonRequirementProfiles,
            IncludeTesseract = selection.IncludeTesseract,
            IncludeSqlServerExpress = selection.IncludeSqlServerExpress,
            InstallAiTools = selection.InstallAiTools,
            Scan = scan
        };
        File.WriteAllText(planPath, JsonSerializer.Serialize(payload, JsonOptions()), new UTF8Encoding(false));
        return planPath;
    }

    private static int RunInstaller(string bundleRoot, string planPath)
    {
        var script = Path.Combine(bundleRoot, "scripts", "Install-SelectedProfiles.ps1");
        if (!File.Exists(script))
            throw new FileNotFoundException("Selected-profile installer backend is missing.", script);

        var bundledPwsh = Path.Combine(bundleRoot, "payload", "developer", "powershell", "pwsh.exe");
        var shell = File.Exists(bundledPwsh) ? bundledPwsh : "powershell.exe";
        var args = $"-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"{script}\" -PlanPath \"{planPath}\" -BundleRoot \"{bundleRoot}\"";

        var psi = new ProcessStartInfo(shell, args)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = bundleRoot
        };

        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Installer process could not be started.");
        var errors = new List<string>();
        var finalExit = 1;

        AnsiConsole.Progress()
            .AutoClear(false)
            .HideCompleted(false)
            .Columns(new TaskDescriptionColumn(), new ProgressBarColumn(), new PercentageColumn(), new SpinnerColumn())
            .Start(ctx =>
            {
                var task = ctx.AddTask("[cyan]Preparing installation[/]", maxValue: 100);
                while (!process.StandardOutput.EndOfStream)
                {
                    var line = process.StandardOutput.ReadLine();
                    if (line is null) continue;
                    if (line.StartsWith("@@EVENT|", StringComparison.Ordinal))
                    {
                        var parts = line.Split('|', 3);
                        if (parts.Length == 3 && double.TryParse(parts[1], out var value))
                        {
                            task.Value = Math.Clamp(value, 0, 100);
                            task.Description = $"[cyan]{Markup.Escape(parts[2])}[/]";
                        }
                    }
                }
                process.WaitForExit();
                var stderr = process.StandardError.ReadToEnd();
                if (!string.IsNullOrWhiteSpace(stderr)) errors.Add(stderr.Trim());
                finalExit = process.ExitCode;
                if (finalExit == 0)
                {
                    task.Value = 100;
                    task.Description = "[green]Installation completed[/]";
                }
                else
                {
                    task.Description = $"[red]Installation failed (code {finalExit})[/]";
                }
            });

        if (finalExit == 0)
        {
            AnsiConsole.Write(new Panel("[green bold]Setup completed successfully.[/]\nOpen a new terminal before using newly added command paths.")
                .Header("  COMPLETE  ").Border(BoxBorder.Double));
        }
        else
        {
            AnsiConsole.MarkupLine($"\n[red bold]Installation ended with code {finalExit}.[/]");
            foreach (var error in errors.Take(5)) AnsiConsole.MarkupLine($"[red]{Markup.Escape(error)}[/]");
        }

        return finalExit;
    }

    private static void RenderDiagnosticsFooter(PreflightScan scan)
    {
        AnsiConsole.MarkupLine("\n[cyan]Diagnostics complete.[/] No installation changes were made.");
        if (scan.PendingReboot)
            AnsiConsole.MarkupLine("[yellow]Recommendation:[/] restart Windows before a large installation session.");
    }

    private static bool IsAdministrator()
    {
        if (!OperatingSystem.IsWindows()) return false;
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static bool TestPendingReboot()
    {
        if (!OperatingSystem.IsWindows()) return false;
        return RegistryKeyExists(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
               || RegistryKeyExists(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
               || ReadRegistryValue(Registry.LocalMachine, @"SYSTEM\CurrentControlSet\Control\Session Manager", "PendingFileRenameOperations") is not null;
    }

    private static OfficeInfo DetectOffice()
    {
        var result = new OfficeInfo();
        if (!OperatingSystem.IsWindows()) return result;

        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var key = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Office\ClickToRun\Configuration");
            if (key is null) continue;
            result.Installed = true;
            result.Version = key.GetValue("VersionToReport")?.ToString();
            result.Architecture = key.GetValue("Platform")?.ToString();
            result.Products = key.GetValue("ProductReleaseIds")?.ToString();
            return result;
        }

        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var uninstall = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall is null) continue;
            foreach (var subName in uninstall.GetSubKeyNames())
            {
                using var sub = uninstall.OpenSubKey(subName);
                var name = sub?.GetValue("DisplayName")?.ToString();
                if (name is null) continue;
                if (name.Contains("Microsoft 365", StringComparison.OrdinalIgnoreCase) || name.Contains("Microsoft Office", StringComparison.OrdinalIgnoreCase))
                {
                    result.Installed = true;
                    result.Products = name;
                    result.Version = sub?.GetValue("DisplayVersion")?.ToString();
                    result.Architecture = view == RegistryView.Registry64 ? "x64 registry" : "x86 registry";
                    return result;
                }
            }
        }
        return result;
    }

    private static string? TryGetCommandVersion(string command, params string[] arguments)
    {
        try
        {
            var psi = new ProcessStartInfo(command)
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            foreach (var arg in arguments) psi.ArgumentList.Add(arg);
            using var process = Process.Start(psi);
            if (process is null) return null;
            if (!process.WaitForExit(2200))
            {
                try { process.Kill(true); } catch { }
                return null;
            }
            var text = (process.StandardOutput.ReadToEnd() + " " + process.StandardError.ReadToEnd()).Trim();
            return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(text) ? text : null;
        }
        catch { return null; }
    }

    private static bool RegistryKeyExists(RegistryKey root, string path)
    {
        try { using var key = root.OpenSubKey(path); return key is not null; }
        catch { return false; }
    }

    private static object? ReadRegistryValue(RegistryKey root, string path, string name)
    {
        try { using var key = root.OpenSubKey(path); return key?.GetValue(name); }
        catch { return null; }
    }

    private static string? ReadRegistryString(RegistryKey root, string path, string name) => ReadRegistryValue(root, path, name)?.ToString();

    private static int? ReadRegistryDword(RegistryKey root, string path, string name)
    {
        var value = ReadRegistryValue(root, path, name);
        return value is int i ? i : value is not null && int.TryParse(value.ToString(), out var parsed) ? parsed : null;
    }
}

internal sealed class SetupConfiguration
{
    public UiConfiguration Ui { get; set; } = new();
    public CoreDefinition Core { get; set; } = new();
    public List<ProfileDefinition> Profiles { get; set; } = new();
    public List<PresetDefinition> Presets { get; set; } = new();
}

internal sealed class UiConfiguration
{
    public string ProductName { get; set; } = "Offline Tools Setup";
    public string Subtitle { get; set; } = "Professional Windows setup";
}

internal sealed class CoreDefinition
{
    public string Id { get; set; } = "core";
    public string DisplayName { get; set; } = "Core Foundation";
    public long EstimatedMb { get; set; }
    public List<string> PythonRequirementProfiles { get; set; } = new();
    public List<ComponentDefinition> Components { get; set; } = new();
}

internal sealed class ProfileDefinition
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public bool Recommended { get; set; }
    public long EstimatedMb { get; set; }
    public List<string> PythonRequirementProfiles { get; set; } = new();
    public List<ComponentDefinition> Components { get; set; } = new();
}

internal sealed class ComponentDefinition
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool SelectedByDefault { get; set; }
    public bool? Supported { get; set; }
    public string? Reason { get; set; }
}

internal sealed class PresetDefinition
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public List<string> Profiles { get; set; } = new();
}

internal sealed class PreflightScan
{
    public bool IsWindows { get; set; }
    public bool Is64Bit { get; set; }
    public bool IsAdministrator { get; set; }
    public string? WindowsName { get; set; }
    public string? WindowsBuild { get; set; }
    public double FreeDiskGb { get; set; }
    public bool PendingReboot { get; set; }
    public bool LongPathsEnabled { get; set; }
    public bool OfficeInstalled { get; set; }
    public string? OfficeVersion { get; set; }
    public string? OfficeArchitecture { get; set; }
    public string? OfficeProducts { get; set; }
    public string? PythonVersion { get; set; }
    public string? NodeVersion { get; set; }
    public string? GitVersion { get; set; }
    public string? PowerShell7Version { get; set; }
    public string? VsCodeVersion { get; set; }
    public bool BundleManifestPresent { get; set; }
    public bool BundleInfoPresent { get; set; }
    public bool NativeStatusPresent { get; set; }
}

internal sealed class OfficeInfo
{
    public bool Installed { get; set; }
    public string? Version { get; set; }
    public string? Architecture { get; set; }
    public string? Products { get; set; }
}

internal sealed class InstallSelection
{
    public bool ExitRequested { get; set; }
    public List<string> ProfileIds { get; set; } = new();
    public Dictionary<string, List<string>> Components { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<string> PythonRequirementProfiles { get; set; } = new();
    public bool IncludeTesseract { get; set; }
    public bool IncludeSqlServerExpress { get; set; }
    public bool InstallAiTools { get; set; }
    public long EstimatedMb { get; set; }
    public static InstallSelection Exit() => new() { ExitRequested = true };
}

internal sealed class InstallationPlan
{
    public int SchemaVersion { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public string BundleRoot { get; set; } = string.Empty;
    public string InstallRoot { get; set; } = string.Empty;
    public List<string> Profiles { get; set; } = new();
    public Dictionary<string, List<string>> Components { get; set; } = new();
    public List<string> PythonRequirementProfiles { get; set; } = new();
    public bool IncludeTesseract { get; set; }
    public bool IncludeSqlServerExpress { get; set; }
    public bool InstallAiTools { get; set; }
    public PreflightScan Scan { get; set; } = new();
}

internal sealed class CommandLineOptions
{
    public string? BundleRoot { get; set; }
    public string? Preset { get; set; }
    public bool DiagnosticsOnly { get; set; }
    public bool PlanOnly { get; set; }
    public bool NonInteractive { get; set; }

    public static CommandLineOptions Parse(string[] args)
    {
        var result = new CommandLineOptions();
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--bundle-root" when i + 1 < args.Length: result.BundleRoot = args[++i]; break;
                case "--preset" when i + 1 < args.Length: result.Preset = args[++i]; break;
                case "--diagnostics": result.DiagnosticsOnly = true; break;
                case "--plan-only": result.PlanOnly = true; break;
                case "--non-interactive": result.NonInteractive = true; break;
            }
        }
        return result;
    }
}
