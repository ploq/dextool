import std.array : appender;
import std.stdio;
import std.file;
import std.algorithm: canFind;

import application.compilation_db;

string[] getHeaders()
{
    string dummy_path = "/home/pc022838/ip_2016_fuzzy/build/compile_commands.json";
    auto app = appender!(CompileCommand[])();
    auto rval = appender!(string[])();
    auto directories = appender!(string[])();
    fromFile(CompileDbJsonPath(dummy_path), app);
    for (int i = 0 ; i < app.capacity; i++)
    {
        auto flags = parseFlag(app.data[i]);
        for (int n = 0; n < flags.length; n+=2) {
            if(flags[n] == "-I" && !directories.data.canFind(flags[n+1]))
            {
                writeln("directory" ~ flags[n+1]);
                directories.put(flags[n+1]);
                auto iFiles = dirEntries(flags[n+1], "*.{h,hpp}", SpanMode.depth);
                foreach(d; iFiles)
                    rval.put(d.name);
            }
        }

    }

    return rval.data;
}

void main() {
    getHeaders;
}
