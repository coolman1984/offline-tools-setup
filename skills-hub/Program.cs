using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace OfflineSkillsHub;

internal static class Program
{
    private const string Version = "0.1.0";
    private static readonly Regex SkillNamePattern = new("^[a-z0-9]+(-[a-z0-9]+)*$", RegexOptions.Compiled);
    private static readonly string[] ExecutableExtensions = { ".ps1", ".cmd", ".bat", ".sh", ".py", ".js", ".ts", ".mjs", ".cjs" };
    private static readonly string[] NetworkCommandMarkers = { "invoke-webrequest", "invoke-restmethod", "curl ", "wget ", "requests.get(", "fetch(", "httpclient", "git clone", "gh repo clone" };
    private static readonly string[] PackageInstallMarkers = { "pip install", "python -m pip install", "npm install", "npm i ", "pnpm add", "yarn add", "winget install", "choco install", "scoop install" };

    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = Encoding.UTF8;
        Console.Title = "Developer Skills Hub";

        try
        {
            var bundleRoot = ResolveBundleRoot(args.FirstOrDefault());
            var config = LoadConfig(bundleRoot);
            var managedRoot = Environment.ExpandEnvironmentVariables(config.ManagedRoot);
            var libraryRoot = Path.Combine(managedRoot, "library");
            Directory.CreateDirectory(libraryRoot);
            Directory.CreateDirectory(Path.Combine(managedRoot, "state"));
            Directory.CreateDirectory(Path.Combine(managedRoot, "backups"));
            SeedBuiltInLibrary(bundleRoot, config, libraryRoot);

            while (true)
            {
                var skills = DiscoverSkills(libraryRoot, config);
                var targets = DetectTargets(config);
                RenderHome(config, skills, targets, libraryRoot);
                var choice = AnsiConsole.Prompt(new SelectionPrompt<string>()
                    .Title("[bold cyan]Choose Skills Hub area[/]")
                    .PageSize(12)
                    .HighlightStyle(new Style(Color.Black, Color.Cyan1, Decoration.Bold))
                    .AddChoices(
                        "Skill Library",
                        "Deploy / Sync Skills",
                        "AI Tool Detection",
                        "Create / Import Skill",
                        "Project Brains",
                        "Curated Sources",
                        "Exit"));

                switch (choice)
                {
                    case "Skill Library": RunLibrary(config, libraryRoot); break;
                    case "Deploy / Sync Skills": RunDeploy(config, libraryRoot, managedRoot); break;
                    case "AI Tool Detection": RunToolDetection(config); break;
                    case "Create / Import Skill": RunCreateImport(config, libraryRoot); break;
                    case "Project Brains": RunProjectBrains(managedRoot); break;
                    case "Curated Sources": RunCuratedSources(config); break;
                    default: return 0;
                }
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.WriteException(ex, ExceptionFormats.ShortenPaths | ExceptionFormats.ShortenTypes);
            return 1;
        }
    }

    private static HubConfig LoadConfig(string bundleRoot)
    {
        var path = Path.Combine(bundleRoot, "config", "skills-hub.json");
        return JsonSerializer.Deserialize<HubConfig>(File.ReadAllText(path), JsonOptions())
               ?? throw new InvalidOperationException("Skills Hub configuration could not be loaded.");
    }

    private static JsonSerializerOptions JsonOptions() => new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    private static void RenderHome(HubConfig config, List<SkillInfo> skills, List<TargetStatus> targets, string libraryRoot)
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new FigletText("SKILLS HUB").Centered().Color(Color.Cyan1));
        AnsiConsole.Write(new Rule($"[grey]{Markup.Escape(config.ProductName)}   v{Version}[/]").RuleStyle("grey"));
        AnsiConsole.WriteLine();

        var valid = skills.Count(s => s.Validation.Errors.Count == 0);
        var installed = targets.Count(t => t.Installed);
        var grid = new Grid().AddColumn().AddColumn().AddColumn();
        grid.AddRow(
            new Panel($"[bold cyan]{skills.Count}[/]\n[grey]Managed skills[/]") { Border = BoxBorder.Rounded },
            new Panel($"[bold green]{valid}[/]\n[grey]Ready to deploy[/]") { Border = BoxBorder.Rounded },
            new Panel($"[bold cyan]{installed}/{targets.Count}[/]\n[grey]AI targets detected[/]") { Border = BoxBorder.Rounded });
        AnsiConsole.Write(grid);
        AnsiConsole.MarkupLine($"\n[grey]Canonical editable library:[/] [white]{Markup.Escape(libraryRoot)}[/]");
        AnsiConsole.MarkupLine("[grey]One skill source can be validated, previewed and published to several supported agents without rewriting it for each client.[/]\n");
    }

    private static void SeedBuiltInLibrary(string bundleRoot, HubConfig config, string libraryRoot)
    {
        var source = Path.Combine(bundleRoot, config.CanonicalLibraryRelativePath);
        if (!Directory.Exists(source)) return;
        foreach (var dir in Directory.GetDirectories(source))
        {
            if (!File.Exists(Path.Combine(dir, "SKILL.md"))) continue;
            var destination = Path.Combine(libraryRoot, Path.GetFileName(dir));
            if (!Directory.Exists(destination))
                CopyDirectory(dir, destination, overwrite: false);
        }
    }

    private static List<SkillInfo> DiscoverSkills(string libraryRoot, HubConfig config)
    {
        var result = new List<SkillInfo>();
        if (!Directory.Exists(libraryRoot)) return result;
        foreach (var dir in Directory.GetDirectories(libraryRoot).OrderBy(Path.GetFileName))
        {
            var skillPath = Path.Combine(dir, "SKILL.md");
            if (!File.Exists(skillPath)) continue;
            var parsed = ParseSkill(skillPath);
            parsed.DirectoryPath = dir;
            parsed.Validation = ValidateSkill(parsed, config);
            result.Add(parsed);
        }
        return result;
    }

    private static SkillInfo ParseSkill(string skillPath)
    {
        var text = File.ReadAllText(skillPath);
        var info = new SkillInfo { SkillPath = skillPath, RawText = text, DirectoryName = Path.GetFileName(Path.GetDirectoryName(skillPath)!) };
        var lines = text.Replace("\r\n", "\n").Split('\n');
        if (lines.Length > 0 && lines[0].Trim() == "---")
        {
            var frontmatter = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var i = 1;
            for (; i < lines.Length; i++)
            {
                if (lines[i].Trim() == "---") { i++; break; }
                var idx = lines[i].IndexOf(':');
                if (idx <= 0) continue;
                var key = lines[i][..idx].Trim();
                var value = lines[i][(idx + 1)..].Trim().Trim('"', '\'');
                if (!key.StartsWith(" ") && !frontmatter.ContainsKey(key)) frontmatter[key] = value;
            }
            info.Name = frontmatter.TryGetValue("name", out var n) ? n : info.DirectoryName;
            info.Description = frontmatter.TryGetValue("description", out var d) ? d : string.Empty;
            info.License = frontmatter.TryGetValue("license", out var l) ? l : null;
            info.Body = string.Join('\n', lines.Skip(i));
        }
        else
        {
            info.Name = info.DirectoryName;
            info.Body = text;
        }
        return info;
    }

    private static SkillValidation ValidateSkill(SkillInfo skill, HubConfig config)
    {
        var validation = new SkillValidation();
        if (string.IsNullOrWhiteSpace(skill.Name)) validation.Errors.Add("Missing skill name.");
        if (!SkillNamePattern.IsMatch(skill.Name ?? string.Empty)) validation.Errors.Add("Skill name must be lowercase letters/numbers with single hyphens.");
        if (!string.Equals(skill.Name, skill.DirectoryName, StringComparison.Ordinal)) validation.Errors.Add("Skill name must match the parent directory name for maximum client compatibility.");
        if (string.IsNullOrWhiteSpace(skill.Description)) validation.Errors.Add("Missing description. Agents use it to decide when the skill applies.");
        if ((skill.Description?.Length ?? 0) > config.Policies.MaxDescriptionCharacters) validation.Errors.Add($"Description exceeds {config.Policies.MaxDescriptionCharacters} characters.");
        else if ((skill.Description?.Length ?? 0) > config.Policies.RecommendedDescriptionCharacters) validation.Warnings.Add("Description is valid but long; shorter trigger descriptions preserve agent context budgets.");
        if (skill.RawText.Length > 40000) validation.Warnings.Add("SKILL.md is large. Move deep reference material into references/ for progressive loading.");

        foreach (var file in Directory.EnumerateFiles(skill.DirectoryPath, "*", SearchOption.AllDirectories))
        {
            var ext = Path.GetExtension(file).ToLowerInvariant();
            if (!ExecutableExtensions.Contains(ext)) continue;
            string content;
            try { content = File.ReadAllText(file).ToLowerInvariant(); } catch { continue; }
            if (NetworkCommandMarkers.Any(content.Contains))
                validation.Warnings.Add($"Network-capable command found in {Path.GetRelativePath(skill.DirectoryPath, file)}. Target PCs must not download skill dependencies.");
            if (PackageInstallMarkers.Any(content.Contains))
                validation.Warnings.Add($"Package-install command found in {Path.GetRelativePath(skill.DirectoryPath, file)}. Dependencies must already exist in the offline suite.");
        }
        return validation;
    }

    private static void RunLibrary(HubConfig config, string libraryRoot)
    {
        while (true)
        {
            var skills = DiscoverSkills(libraryRoot, config);
            AnsiConsole.Clear();
            RenderSection("SKILL LIBRARY", "Readable, auditable skills with progressive disclosure.");
            if (skills.Count == 0) { Pause("No skills are currently in the managed library."); return; }

            var choices = skills.Select(s => SkillLabel(s)).Concat(new[] { "← Back" }).ToList();
            var selected = AnsiConsole.Prompt(new SelectionPrompt<string>()
                .Title("[bold cyan]Select a skill[/]")
                .PageSize(18)
                .HighlightStyle(new Style(Color.Black, Color.Cyan1, Decoration.Bold))
                .AddChoices(choices));
            if (selected == "← Back") return;
            var skill = skills[choices.IndexOf(selected)];
            RunSkillDetail(config, skill);
        }
    }

    private static string SkillLabel(SkillInfo skill)
    {
        var state = skill.Validation.Errors.Count == 0 ? (skill.Validation.Warnings.Count == 0 ? "READY" : "WARN") : "BLOCKED";
        return $"{skill.Name}  [{state}]  - {skill.Description}";
    }

    private static void RunSkillDetail(HubConfig config, SkillInfo skill)
    {
        while (true)
        {
            AnsiConsole.Clear();
            RenderSection(skill.Name.ToUpperInvariant(), skill.Description ?? string.Empty);
            RenderValidation(skill.Validation);
            var action = AnsiConsole.Prompt(new SelectionPrompt<string>()
                .Title("[bold cyan]Skill actions[/]")
                .AddChoices("Beautiful Preview", "Open in Editor", "Show Files", "Validate Again", "Back"));
            if (action == "Back") return;
            if (action == "Beautiful Preview") { RenderMarkdownPreview(skill.Body); Pause("Preview complete."); }
            else if (action == "Open in Editor") OpenEditor(skill.SkillPath);
            else if (action == "Show Files")
            {
                var table = new Table().RoundedBorder().AddColumn("File").AddColumn("Size");
                foreach (var f in Directory.EnumerateFiles(skill.DirectoryPath, "*", SearchOption.AllDirectories).Select(p => new FileInfo(p)))
                    table.AddRow(Markup.Escape(Path.GetRelativePath(skill.DirectoryPath, f.FullName)), $"{f.Length / 1024d:N1} KB");
                AnsiConsole.Write(table); Pause("File inventory complete.");
            }
            else
            {
                skill = ParseSkill(skill.SkillPath); skill.DirectoryPath = Path.GetDirectoryName(skill.SkillPath)!; skill.Validation = ValidateSkill(skill, config);
                RenderValidation(skill.Validation); Pause("Validation complete.");
            }
        }
    }

    private static void RenderMarkdownPreview(string markdown)
    {
        var lines = markdown.Replace("\r\n", "\n").Split('\n');
        var inCode = false;
        var code = new StringBuilder();
        foreach (var raw in lines)
        {
            var line = raw.TrimEnd();
            if (line.TrimStart().StartsWith("```"))
            {
                if (!inCode) { inCode = true; code.Clear(); }
                else { inCode = false; AnsiConsole.Write(new Panel(new Text(code.ToString())) { Border = BoxBorder.Rounded, Header = new PanelHeader(" code ") }); }
                continue;
            }
            if (inCode) { code.AppendLine(line); continue; }
            if (line.StartsWith("# ")) { AnsiConsole.Write(new Rule($"[bold cyan]{Markup.Escape(line[2..])}[/]").RuleStyle("cyan")); continue; }
            if (line.StartsWith("## ")) { AnsiConsole.MarkupLine($"\n[bold deepskyblue1]{Markup.Escape(line[3..])}[/]"); continue; }
            if (line.StartsWith("### ")) { AnsiConsole.MarkupLine($"[bold]{Markup.Escape(line[4..])}[/]"); continue; }
            if (line.StartsWith("- ")) { AnsiConsole.MarkupLine($"  [cyan]•[/] {Markup.Escape(line[2..])}"); continue; }
            if (string.IsNullOrWhiteSpace(line)) { AnsiConsole.WriteLine(); continue; }
            AnsiConsole.MarkupLine(Markup.Escape(line));
        }
    }

    private static void RunDeploy(HubConfig config, string libraryRoot, string managedRoot)
    {
        var skills = DiscoverSkills(libraryRoot, config).Where(s => s.Validation.Errors.Count == 0).ToList();
        if (skills.Count == 0) { Pause("No valid skills are available for deployment."); return; }
        var targets = DetectTargets(config);

        AnsiConsole.Clear();
        RenderSection("DEPLOY / SYNC", "Publish one canonical skill to the selected AI clients with backups and receipts.");
        var skillPrompt = new MultiSelectionPrompt<SkillInfo>()
            .Title("[bold cyan]Select skills[/]")
            .PageSize(20)
            .UseConverter(s => $"{s.Name} [grey]- {s.Description}[/]");
        skillPrompt.AddChoices(skills);
        var selectedSkills = AnsiConsole.Prompt(skillPrompt);
        if (selectedSkills.Count == 0) return;

        var targetPrompt = new MultiSelectionPrompt<TargetStatus>()
            .Title("[bold cyan]Select AI targets[/]")
            .PageSize(12)
            .UseConverter(t => $"{t.Config.DisplayName} {(t.Installed ? "[green]DETECTED[/]" : "[yellow]NOT DETECTED[/]")}");
        targetPrompt.AddChoices(targets);
        foreach (var t in targets.Where(t => t.Installed)) targetPrompt.Select(t);
        var selectedTargets = AnsiConsole.Prompt(targetPrompt);
        if (selectedTargets.Count == 0) return;

        var scope = AnsiConsole.Prompt(new SelectionPrompt<string>().Title("[bold cyan]Deployment scope[/]").AddChoices("Global for this Windows user", "Project only", "Cancel"));
        if (scope == "Cancel") return;
        string? projectRoot = null;
        if (scope == "Project only")
        {
            projectRoot = AnsiConsole.Ask<string>("[cyan]Project root path:[/]");
            projectRoot = Path.GetFullPath(Environment.ExpandEnvironmentVariables(projectRoot.Trim('"')));
            if (!Directory.Exists(projectRoot)) { Pause("Project path does not exist. Nothing was deployed."); return; }
        }

        var plan = new Table().RoundedBorder().AddColumn("Skill").AddColumn("Target").AddColumn("Destination");
        foreach (var target in selectedTargets)
        foreach (var skill in selectedSkills)
            plan.AddRow(skill.Name, target.Config.DisplayName, Markup.Escape(GetDestination(target.Config, skill.Name, projectRoot)));
        AnsiConsole.Write(new Panel(plan) { Header = new PanelHeader("  DEPLOYMENT PLAN  "), Border = BoxBorder.Double });
        if (!AnsiConsole.Confirm("Apply this skill deployment plan?", true)) return;

        var receipts = new List<object>();
        foreach (var target in selectedTargets)
        foreach (var skill in selectedSkills)
        {
            var destination = GetDestination(target.Config, skill.Name, projectRoot);
            if (Directory.Exists(destination) && config.Policies.BackupBeforeReplace)
            {
                var backup = Path.Combine(managedRoot, "backups", DateTime.Now.ToString("yyyyMMdd-HHmmss"), target.Config.Id, skill.Name);
                CopyDirectory(destination, backup, overwrite: true);
            }
            if (Directory.Exists(destination)) Directory.Delete(destination, true);
            CopyDirectory(skill.DirectoryPath, destination, overwrite: true);
            receipts.Add(new
            {
                deployedAtUtc = DateTime.UtcNow.ToString("o"),
                skill = skill.Name,
                target = target.Config.Id,
                targetDetected = target.Installed,
                scope = projectRoot is null ? "global" : "project",
                destination,
                fingerprint = FingerprintDirectory(destination)
            });
        }
        var receiptPath = Path.Combine(managedRoot, "state", $"deployment-{DateTime.Now:yyyyMMdd-HHmmss}.json");
        File.WriteAllText(receiptPath, JsonSerializer.Serialize(receipts, JsonOptions()));
        AnsiConsole.MarkupLine($"\n[green bold]Deployment complete.[/] Receipt: {Markup.Escape(receiptPath)}");
        AnsiConsole.MarkupLine("[grey]Some clients discover changes live; others may require a new session or reload depending on their current version.[/]");
        Pause("Skills are synchronized to the selected targets.");
    }

    private static string GetDestination(HubTarget target, string skillName, string? projectRoot)
    {
        var basePath = projectRoot is null
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), target.GlobalSkillPath)
            : Path.Combine(projectRoot, target.ProjectSkillPath);
        return Path.Combine(basePath, skillName);
    }

    private static void RunToolDetection(HubConfig config)
    {
        AnsiConsole.Clear();
        RenderSection("AI TOOL DETECTION", "Detected runtimes and their native skill destinations.");
        var table = new Table().RoundedBorder().AddColumn("Target").AddColumn("Status").AddColumn("Global Skills").AddColumn("Evidence");
        foreach (var target in DetectTargets(config))
        {
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), target.Config.GlobalSkillPath);
            table.AddRow(target.Config.DisplayName, target.Installed ? "[green]DETECTED[/]" : "[yellow]NOT DETECTED[/]", Markup.Escape(path), Markup.Escape(target.Evidence ?? "-"));
        }
        AnsiConsole.Write(table);
        AnsiConsole.MarkupLine("\n[grey]Claude account-managed/Cowork skills are intentionally not modified by local filesystem deployment. Local Claude Code skills remain supported.[/]");
        Pause("Detection complete.");
    }

    private static List<TargetStatus> DetectTargets(HubConfig config)
    {
        var result = new List<TargetStatus>();
        foreach (var target in config.Targets)
        {
            string? evidence = target.ManagedExecutableHints.FirstOrDefault(File.Exists);
            if (evidence is null)
            {
                foreach (var executable in target.Executables)
                {
                    var found = FindOnPath(executable);
                    if (found is not null) { evidence = found; break; }
                }
            }
            result.Add(new TargetStatus { Config = target, Installed = evidence is not null, Evidence = evidence });
        }
        return result;
    }

    private static string? FindOnPath(string executable)
    {
        try
        {
            var psi = new ProcessStartInfo("where.exe", executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            using var p = Process.Start(psi); if (p is null) return null;
            if (!p.WaitForExit(1800)) { try { p.Kill(true); } catch { } return null; }
            if (p.ExitCode != 0) return null;
            return p.StandardOutput.ReadToEnd().Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        }
        catch { return null; }
    }

    private static void RunCreateImport(HubConfig config, string libraryRoot)
    {
        while (true)
        {
            AnsiConsole.Clear(); RenderSection("CREATE / IMPORT", "Author locally or bring an audited skill from approved offline media.");
            var choice = AnsiConsole.Prompt(new SelectionPrompt<string>().Title("[bold cyan]Choose action[/]").AddChoices("Create New Skill", "Import Skill Folder", "Back"));
            if (choice == "Back") return;
            if (choice == "Create New Skill") CreateNewSkill(config, libraryRoot);
            else ImportSkill(config, libraryRoot);
        }
    }

    private static void CreateNewSkill(HubConfig config, string libraryRoot)
    {
        var name = AnsiConsole.Ask<string>("[cyan]Skill name[/] [grey](lowercase-hyphen-format):[/]").Trim();
        if (!SkillNamePattern.IsMatch(name)) { Pause("Invalid skill name."); return; }
        var destination = Path.Combine(libraryRoot, name);
        if (Directory.Exists(destination)) { Pause("A skill with this name already exists."); return; }
        var description = AnsiConsole.Ask<string>("[cyan]When should an agent use this skill?[/]").Trim();
        var category = AnsiConsole.Prompt(new SelectionPrompt<string>().Title("[cyan]Category[/]").AddChoices(config.SkillCategories));
        Directory.CreateDirectory(destination);
        Directory.CreateDirectory(Path.Combine(destination, "references"));
        Directory.CreateDirectory(Path.Combine(destination, "assets"));
        var skill = $"---\nname: {name}\ndescription: {description}\ncompatibility: Windows 10/11 corporate workstation; required dependencies must already be bundled locally.\nmetadata:\n  category: {category}\n  version: 1.0.0\n---\n\n# {ToTitle(name)}\n\n## Purpose\n\nDescribe the repeatable outcome this skill owns.\n\n## Workflow\n\n1. Validate inputs and constraints.\n2. Preserve originals and create evidence before transformation.\n3. Perform deterministic processing with the installed offline toolchain.\n4. Validate outputs against source evidence.\n5. Record decisions, warnings, outputs and next actions.\n\n## Edge cases\n\nDocument failure modes and safe fallbacks here.\n";
        File.WriteAllText(Path.Combine(destination, "SKILL.md"), skill, new UTF8Encoding(false));
        OpenEditor(Path.Combine(destination, "SKILL.md"));
        Pause("Skill created in the managed library.");
    }

    private static void ImportSkill(HubConfig config, string libraryRoot)
    {
        var source = AnsiConsole.Ask<string>("[cyan]Offline skill folder path:[/]").Trim('"');
        source = Path.GetFullPath(Environment.ExpandEnvironmentVariables(source));
        if (!File.Exists(Path.Combine(source, "SKILL.md"))) { Pause("The selected folder does not contain SKILL.md."); return; }
        var parsed = ParseSkill(Path.Combine(source, "SKILL.md")); parsed.DirectoryPath = source; parsed.Validation = ValidateSkill(parsed, config);
        RenderValidation(parsed.Validation);
        if (parsed.Validation.Errors.Count > 0) { Pause("Import blocked until structural errors are fixed."); return; }
        if (parsed.Validation.Warnings.Count > 0 && !AnsiConsole.Confirm("Warnings were found. Import for review anyway?", false)) return;
        var destination = Path.Combine(libraryRoot, parsed.Name!);
        if (Directory.Exists(destination) && !AnsiConsole.Confirm("Replace the existing managed library copy?", false)) return;
        if (Directory.Exists(destination)) Directory.Delete(destination, true);
        CopyDirectory(source, destination, overwrite: true);
        Pause("Skill imported. Review it in the library before deployment.");
    }

    private static void RunProjectBrains(string managedRoot)
    {
        var brainsRoot = Path.Combine(Path.GetDirectoryName(managedRoot) ?? @"C:\OfflineTools", "Knowledge");
        Directory.CreateDirectory(brainsRoot);
        while (true)
        {
            AnsiConsole.Clear(); RenderSection("PROJECT BRAINS", "Local Markdown knowledge vaults kept separate per project.");
            var brains = Directory.GetDirectories(brainsRoot).Select(Path.GetFileName).Where(n => !string.IsNullOrWhiteSpace(n)).OrderBy(n => n).ToList();
            var choices = new List<string> { "Create Project Brain" };
            choices.AddRange(brains.Select(b => $"Open: {b}")); choices.Add("Back");
            var choice = AnsiConsole.Prompt(new SelectionPrompt<string>().Title("[bold cyan]Project Brain[/]").PageSize(15).AddChoices(choices));
            if (choice == "Back") return;
            if (choice == "Create Project Brain")
            {
                var name = AnsiConsole.Ask<string>("[cyan]Project name:[/]").Trim();
                var safe = Regex.Replace(name.ToLowerInvariant(), "[^a-z0-9-_]+", "-").Trim('-');
                if (string.IsNullOrWhiteSpace(safe)) { Pause("Project name is invalid."); continue; }
                CreateBrain(Path.Combine(brainsRoot, safe), name);
                Pause("Project Brain created.");
            }
            else
            {
                var name = choice[6..];
                var path = Path.Combine(brainsRoot, name);
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
            }
        }
    }

    private static void CreateBrain(string root, string displayName)
    {
        Directory.CreateDirectory(root);
        foreach (var folder in new[] { "facts", "entities", "decisions", "sources", "timeline", "reports", "skills" }) Directory.CreateDirectory(Path.Combine(root, folder));
        WriteIfMissing(Path.Combine(root, "PROJECT-BRAIN.md"), $"# {displayName}\n\n## Mission\n\nDescribe what this project exists to achieve.\n\n## Current state\n\n- Status: new\n- Last reviewed: {DateTime.Today:yyyy-MM-dd}\n\n## Knowledge rules\n\n- Every material fact should carry a source and date.\n- Separate observed facts from inference and recommendation.\n- Record decisions with rationale and alternatives.\n- Preserve superseded facts instead of silently overwriting history.\n- Store unknowns explicitly.\n");
        WriteIfMissing(Path.Combine(root, "README.md"), "# Project Brain\n\nA local Markdown knowledge vault for durable project facts, decisions, entities, sources, timelines, reports and project-specific skills.\n");
        var index = new { schemaVersion = 1, project = displayName, createdAtUtc = DateTime.UtcNow.ToString("o"), folders = new[] { "facts", "entities", "decisions", "sources", "timeline", "reports", "skills" } };
        WriteIfMissing(Path.Combine(root, "brain-index.json"), JsonSerializer.Serialize(index, JsonOptions()));
    }

    private static void RunCuratedSources(HubConfig config)
    {
        AnsiConsole.Clear(); RenderSection("CURATED SOURCES", "Reference catalogs for connected builder-side review. Target PCs never fetch from them.");
        var table = new Table().RoundedBorder().AddColumn("Source").AddColumn("Trust").AddColumn("Purpose").AddColumn("Repository");
        foreach (var source in config.CuratedSources)
            table.AddRow(Markup.Escape(source.Name), Markup.Escape(source.TrustTier), Markup.Escape(source.Purpose), Markup.Escape(source.Url));
        AnsiConsole.Write(table);
        AnsiConsole.MarkupLine("\n[yellow]Import policy:[/] popularity never bypasses license review, script inspection or offline-network policy. Curated repositories are idea/reference sources unless an approved snapshot is deliberately bundled.");
        Pause("Source catalog displayed.");
    }

    private static void RenderValidation(SkillValidation validation)
    {
        if (validation.Errors.Count == 0 && validation.Warnings.Count == 0) { AnsiConsole.MarkupLine("[green]● READY[/] Structure and offline policy checks passed.\n"); return; }
        foreach (var error in validation.Errors) AnsiConsole.MarkupLine($"[red]● BLOCK[/] {Markup.Escape(error)}");
        foreach (var warning in validation.Warnings.Distinct()) AnsiConsole.MarkupLine($"[yellow]● WARN[/] {Markup.Escape(warning)}");
        AnsiConsole.WriteLine();
    }

    private static void OpenEditor(string path)
    {
        var candidates = new[]
        {
            @"C:\OfflineTools\Developer\VSCode\Code.exe",
            @"C:\OfflineTools\Developer\VSCode\bin\code.cmd"
        };
        var editor = candidates.FirstOrDefault(File.Exists);
        try
        {
            if (editor is not null) Process.Start(new ProcessStartInfo(editor, $"\"{path}\"") { UseShellExecute = true });
            else Process.Start(new ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true });
        }
        catch { }
    }

    private static string FingerprintDirectory(string root)
    {
        using var sha = SHA256.Create();
        var aggregate = new StringBuilder();
        foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
        {
            using var stream = File.OpenRead(file);
            var hash = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
            aggregate.Append(Path.GetRelativePath(root, file).Replace('\\', '/')).Append(':').Append(hash).Append('\n');
        }
        return Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(aggregate.ToString()))).ToLowerInvariant();
    }

    private static void CopyDirectory(string source, string destination, bool overwrite)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite);
        foreach (var dir in Directory.GetDirectories(source)) CopyDirectory(dir, Path.Combine(destination, Path.GetFileName(dir)), overwrite);
    }

    private static void WriteIfMissing(string path, string content)
    {
        if (!File.Exists(path)) File.WriteAllText(path, content, new UTF8Encoding(false));
    }

    private static string ToTitle(string name) => string.Join(' ', name.Split('-').Select(p => p.Length == 0 ? p : char.ToUpperInvariant(p[0]) + p[1..]));

    private static void RenderSection(string title, string subtitle)
    {
        AnsiConsole.Write(new Rule($"[bold cyan]{Markup.Escape(title)}[/]").RuleStyle("cyan"));
        if (!string.IsNullOrWhiteSpace(subtitle)) AnsiConsole.MarkupLine($"[grey]{Markup.Escape(subtitle)}[/]\n");
    }

    private static void Pause(string message)
    {
        AnsiConsole.MarkupLine($"\n[grey]{Markup.Escape(message)}[/]");
        AnsiConsole.MarkupLine("[cyan]Press any key to continue.[/]");
        Console.ReadKey(true);
    }

    private static string ResolveBundleRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var p = Path.GetFullPath(explicitRoot.Trim('"'));
            if (File.Exists(Path.Combine(p, "config", "skills-hub.json"))) return p;
        }
        var current = AppContext.BaseDirectory;
        for (var i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(current, "config", "skills-hub.json"))) return current;
            var parent = Directory.GetParent(current); if (parent is null) break; current = parent.FullName;
        }
        current = Directory.GetCurrentDirectory();
        if (File.Exists(Path.Combine(current, "config", "skills-hub.json"))) return current;
        throw new DirectoryNotFoundException("Could not locate Skills Hub configuration in the offline bundle.");
    }
}

internal sealed class HubConfig
{
    public int SchemaVersion { get; set; }
    public string ProductName { get; set; } = "Developer Skills Hub";
    public string ManagedRoot { get; set; } = @"C:\OfflineTools\SkillsHub";
    public string CanonicalLibraryRelativePath { get; set; } = @"skills\catalog";
    public HubPolicies Policies { get; set; } = new();
    public List<HubTarget> Targets { get; set; } = new();
    public List<CuratedSource> CuratedSources { get; set; } = new();
    public List<string> SkillCategories { get; set; } = new();
}

internal sealed class HubPolicies
{
    public bool TargetDownloadsAllowed { get; set; }
    public bool ExecuteImportedScriptsAutomatically { get; set; }
    public bool RequireValidationBeforeDeploy { get; set; } = true;
    public bool BackupBeforeReplace { get; set; } = true;
    public bool AllowNetworkReferencesInDocumentation { get; set; } = true;
    public bool AllowNetworkCommandsInSkillScripts { get; set; }
    public bool WarnOnPackageInstallCommands { get; set; } = true;
    public int MaxDescriptionCharacters { get; set; } = 1024;
    public int RecommendedDescriptionCharacters { get; set; } = 420;
}

internal sealed class HubTarget
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public List<string> Executables { get; set; } = new();
    public List<string> ManagedExecutableHints { get; set; } = new();
    public string GlobalSkillPath { get; set; } = string.Empty;
    public string ProjectSkillPath { get; set; } = string.Empty;
    public string DeploymentMode { get; set; } = "copy";
    public string Notes { get; set; } = string.Empty;
}

internal sealed class CuratedSource
{
    public string Name { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public string TrustTier { get; set; } = string.Empty;
    public string Purpose { get; set; } = string.Empty;
}

internal sealed class SkillInfo
{
    public string? Name { get; set; }
    public string? Description { get; set; }
    public string? License { get; set; }
    public string DirectoryName { get; set; } = string.Empty;
    public string DirectoryPath { get; set; } = string.Empty;
    public string SkillPath { get; set; } = string.Empty;
    public string RawText { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public SkillValidation Validation { get; set; } = new();
}

internal sealed class SkillValidation
{
    public List<string> Errors { get; } = new();
    public List<string> Warnings { get; } = new();
}

internal sealed class TargetStatus
{
    public HubTarget Config { get; set; } = new();
    public bool Installed { get; set; }
    public string? Evidence { get; set; }
}
