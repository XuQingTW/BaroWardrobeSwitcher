using MoonSharp.Interpreter;
using MoonSharp.Interpreter.Loaders;

if (args.Length == 0)
{
    Console.Error.WriteLine("Usage: LuaSyntaxCheck [--execute] <file-or-directory> [...]");
    return 64;
}

bool execute = args[0] == "--execute";
string[] paths = execute ? args.Skip(1).ToArray() : args;
if (paths.Length == 0)
{
    Console.Error.WriteLine("At least one Lua path is required.");
    return 64;
}

var files = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
foreach (string argument in paths)
{
    string path = Path.GetFullPath(argument);
    if (File.Exists(path))
    {
        files.Add(path);
    }
    else if (Directory.Exists(path))
    {
        foreach (string file in Directory.EnumerateFiles(path, "*.lua", SearchOption.AllDirectories))
        {
            files.Add(file);
        }
    }
    else
    {
        Console.Error.WriteLine($"Path not found: {path}");
        return 66;
    }
}

int failures = 0;
foreach (string file in files)
{
    try
    {
        string source = File.ReadAllText(file);
        var script = new Script(CoreModules.Preset_Complete);
        if (execute)
        {
            script.Options.ScriptLoader = new FileSystemScriptLoader();
            script.DoFile(file);
        }
        else
        {
            script.LoadString(source, codeFriendlyName: file);
        }
        Console.WriteLine($"PASS {file}");
    }
    catch (SyntaxErrorException exception)
    {
        failures++;
        Console.Error.WriteLine($"FAIL {file}: {exception.DecoratedMessage}");
    }
    catch (InterpreterException exception)
    {
        failures++;
        Console.Error.WriteLine($"FAIL {file}: {exception.DecoratedMessage}");
    }
}

return failures == 0 ? 0 : 1;
