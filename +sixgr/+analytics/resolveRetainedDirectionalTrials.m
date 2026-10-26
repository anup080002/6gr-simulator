function [dl,ul]=resolveRetainedDirectionalTrials(runFolder,dl,ul)
% Empty callback inputs must not erase already persisted receiver evidence.
% Missing files remain unavailable. Present unreadable files are errors.
layout=sixgr.report.resultLayout(runFolder);
dl=localResolve(dl,fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'));
ul=localResolve(ul,fullfile(layout.AirInterfaceCSVDir,'ul_pusch_trials.csv'));
end

function T=localResolve(T,path)
if istable(T) && height(T)>0, return; end
T=table();
if ~isfile(path), return; end
try
    T=sixgr.util.csvReadTable(path,'TextType','string');
catch ME
    failure=MException('sixgr:analytics:UnreadableRetainedArtifact', ...
        'Existing primary receiver CSV could not be read: %s',path);
    throwAsCaller(addCause(failure,ME));
end
% A nonempty import with generated Var1... columns is not an empty run.
% Require only the primary receiver fields needed to identify attempts;
% optional legacy measurement columns remain optional.
if height(T)>0 && ~all(ismember(["Slot","CRCPass"],string(T.Properties.VariableNames)))
    error('sixgr:analytics:InvalidRetainedPrimarySchema', ...
        'Existing primary receiver CSV lacks named Slot/CRCPass columns: %s',path);
end
end
