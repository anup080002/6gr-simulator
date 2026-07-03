function ok = testAntiPatternRegressionGuards()
%TESTANTIPATTERNREGRESSIONGUARDS Guard recurring truth/proxy drift patterns.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

repoRoot = fileparts(fileparts(mfilename("fullpath")));
sixgrRoot = fullfile(repoRoot, "+sixgr");
files = localMatlabFiles(sixgrRoot);

localAssertNoPattern(files, ...
    "hasExplicit\w*Contract\s*=\s*.*(isequal\s*\(\s*round|round\s*\(\s*double)", ...
    "Self-referential explicit-contract bypass found. Frozen grants must compare against exact physical math, not their own override.");

localAssertNoPattern(files, ...
    "(structGet|localGet|localBool)\s*\(\s*cfg[^;\n]*(fast|Fast|approx|Approx)[^;\n]*,\s*true", ...
    "Config fast/approx option defaults true in production code. Faithful paths must be the default.");

localAssertNoPattern(files, ...
    "(ReceiverHestSINRValueStatus|PostEqSINRValueStatus|MeasuredTrialSINRValueStatus|SINRValueStatus)[^;\n]*==\s*""OK""", ...
    "Measured-SINR status compared directly to OK. Use sixgr.util.isAcceptableSINRStatus instead.");

ok = true;
end

function files = localMatlabFiles(rootDir)
d = dir(fullfile(rootDir, "**", "*.m"));
files = strings(numel(d), 1);
for i = 1:numel(d)
    files(i) = string(fullfile(d(i).folder, d(i).name));
end
end

function localAssertNoPattern(files, expr, message)
hits = strings(0, 1);
for i = 1:numel(files)
    text = fileread(files(i));
    if ~isempty(regexp(text, expr, "once")) %#ok<RGXP1>
        hits(end+1, 1) = erase(files(i), pwd + filesep); %#ok<AGROW>
    end
end
assert(isempty(hits), "%s%s%s", message, newline, strjoin(hits, newline));
end
