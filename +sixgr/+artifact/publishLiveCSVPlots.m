function receipt=publishLiveCSVPlots(cfg,runFolder)
% Runtime checkpoints use the same source-bound builders as final plots.
% Immutable partial snapshots are not terminal qualification artifacts.
receipt=struct('Enabled',false,'Status',"disabled_by_output_policy");
if ~logical(sixgr.util.structGet(cfg,'outputs.liveCSVPNGEnabled',false)) || ...
        ~sixgr.util.persistenceEnabled(), return; end
runtime=sixgr.lls6g.runners.resolveWebGUIContractPython('RequireMySQL',false);
assert(runtime.Ok,'sixgr:artifact:LivePlotPythonUnavailable','%s',runtime.Message);
repo=fileparts(fileparts(fileparts(mfilename('fullpath'))));
script=fullfile(repo,'scripts','publish_lls_live_csv_plots.py');
values=[string(runtime.Executable),string(script),string(runFolder)];
assert(~any(arrayfun(@(v)any(ismember(char(v),[34 10 13])),values)), ...
    'sixgr:artifact:UnsafeLivePlotArgument','Live plot paths cannot contain quotes or newlines.');
command=sprintf('"%s" "%s" --run-folder "%s"',values(1),values(2),values(3));
[status,output]=system(command);
assert(status==0,'sixgr:artifact:LivePlotPublicationFailed','%s',output);
receipt=jsondecode(output);
receipt.Enabled=true;
end
