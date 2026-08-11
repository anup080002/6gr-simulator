function capabilities = discoverPrachCapabilities()
%DISCOVERPRACHCAPABILITIES Record executable PRACH waveform dependencies.

names = ["nrPRACHConfig";"nrPRACH";"nrPRACHDetect"; ...
    "sixgr.phy.prach.generatePRACHWaveform";"sixgr.phy.prach.detectPRACHWaveform"];
available = false(size(names));
for index=1:numel(names)
    % exist() can return zero for package-qualified functions even when the
    % MATLAB resolver can call them.  which() is the correct callable-path
    % check for both +package functions and toolbox symbols.
    available(index)=~isempty(which(char(names(index)))) || ...
        exist(char(names(index)),"class")==8;
end
capabilities=table(names,available, ...
    repmat("CALIBRATED_LLS",numel(names),1), ...
    'VariableNames',{'Capability','Available','Provenance'});
if ~all(available)
    missing=strjoin(names(~available),", ");
    error("sixgr:ntn:resilientsync:MissingPRACHCapability", ...
        "Calibrated PRACH campaign requires %s.",char(missing));
end
end
