function sources=writeTrialDiagnosticPlotSources(root,raw)
% Freeze exactly the tables used by trial diagnostic plots, before hashing.
% Primary trial CSVs gain metadata later; they are not immutable plot inputs.
% Constellation previews may have a configured name and a bounded population.
% Read that actual persisted population instead of inventing a samples alias.
sources=struct();
folder=fullfile(root,'air_interface','csv');
for direction=["DL","UL"]
    T=sixgr.util.structGet(raw,direction,table());
    sources.(direction)=T;
    sources.(direction+"Path")="";
    if istable(T) && ~isempty(T)
        file=fullfile(folder,lower(direction)+"_trial_diagnostic_source.csv");
        sixgr.util.csvWriteTable(file,T,'PreserveSchema',true,'RoundTripNumericText',true);
        sources.(direction+"Path")=string(file);
    end
    sources.(direction+"Constellation")=table();
    sources.(direction+"ConstellationPath")="";
    file=string(sixgr.util.structGet(raw,direction+"ConstellationPath",""));
    if isscalar(file) && ~ismissing(file) && strlength(file)>0
        assert(isfile(file),'sixgr:report:TrialConstellationSourceMissing', ...
            'The selected receiver constellation source is missing: %s',file);
        sources.(direction+"Constellation")=sixgr.util.csvReadTable(file,'TextType','string');
        sources.(direction+"ConstellationPath")=file;
    elseif ~isempty(sixgr.util.structGet(raw,direction+"Constellation",table()))
        error('sixgr:report:TrialConstellationSourceMissing', ...
            'Nonempty receiver samples need their actual persisted source path.');
    end
end
end
