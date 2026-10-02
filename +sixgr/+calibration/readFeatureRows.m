function T=readFeatureRows(folder,caseID,role,attempt,key)
% Read one fitting population without retaining full decoded episodes.
files=dir(fullfile(folder,'episodes','episode_*.mat')); rows=cell(0,1);
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    sixgr.calibration.verifyEpisodeFile(path);
    saved=load(path,'episode'); e=saved.episode;
    if e.CaseID~=caseID || e.Role~=role || numel(e.Attempts)<attempt, continue; end
    history={e.Attempts(1:attempt).SINRLinear};
    rows{end+1,1}=struct('TrialID',e.EpisodeID+"_"+attempt, ...
        'NoiseSeed',e.Attempts(attempt).NoiseSeed,'ChannelSeed',e.Attempts(attempt).ChannelSeed, ...
        'CRCError',e.Attempts(attempt).CRCError,'SINRHistory',{{history}}, ...
        'GroupID',string(jsonencode(e.PlannedSNRHistory_dB(1:attempt))), ...
        'ConfigurationSHA256',key); %#ok<AGROW>
end
T=table(); if ~isempty(rows), T=struct2table(vertcat(rows{:})); end
end
