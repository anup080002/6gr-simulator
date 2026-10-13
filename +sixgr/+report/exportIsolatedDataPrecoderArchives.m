function out=exportIsolatedDataPrecoderArchives(root,dl,ul)
% Joint CSVs from exact archived independent executions, including failures.
out=struct();
for kind=["Weights","Patterns"]
    field="AppliedDataPrecoder"+kind+"CSV";
    hashes=field+"SHA256";
    joint=table();
    ids=strings(0,1);
    for direction=["DL","UL"]
        if direction=="DL", trials=dl; else, trials=ul; end
        if isempty(trials) || ~ismember(field,string(trials.Properties.VariableNames)), continue; end
        for k=1:height(trials)
            relative=string(trials.(field)(k));
            if ismissing(relative) || strlength(relative)==0, continue; end
            file=fullfile(root,relative);
            assert(isfile(file) && string(sixgr.phy.waveform.WaveformHash.file(file))== ...
                string(trials.(hashes)(k)), ...
                'sixgr:report:AppliedPrecoderArchiveChanged','Retained executed matrix/pattern archive is missing or changed.');
            rows=sixgr.util.csvReadTable(file,'TextType','string');
            id=string(trials.AppliedDataPrecoderTransmissionID(k));
            assert(~isempty(rows) && all(rows.TransmissionID==id) && ...
                all(rows.Direction==direction) && ...
                all(rows.ConfiguredSNR_dB==trials.SNR_dB(k)) && ...
                all(rows.UEIndex==trials.UEIndex(k)), ...
                'sixgr:report:AppliedPrecoderTrialMismatch','Archived mapping must match the executed receiver row.');
            assert(~any(ids==id),'sixgr:report:DuplicateAppliedPrecoderExecution', ...
                'Do not silently duplicate or discard an executed transmission.');
            ids(end+1,1)=id; %#ok<AGROW>
            joint=[joint;rows]; %#ok<AGROW>
        end
    end
    if isempty(joint), continue; end
    target=fullfile(root,'beamforming','csv',"applied_data_precoder_"+lower(kind)+".csv");
    sixgr.util.csvWriteTable(target,joint,'PreserveSchema',true,'RoundTripNumericText',true);
    out.(kind+"CSV")=string(target);
end
end
