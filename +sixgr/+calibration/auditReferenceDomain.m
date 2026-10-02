function T=auditReferenceDomain(folder)
% Fit-only diagnostic. Validation is assessed once against the frozen fit.
m=load(fullfile(folder,'campaign.mat'),'p','cases','identity');
[~,axis]=sixgr.calibration.historyGrid(m.p,"reference");
bounds=m.p.qualification.beta_linear_bounds; rows=cell(0,1);
files=dir(fullfile(folder,'episodes','episode_*.mat'));
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    sixgr.calibration.verifyEpisodeFile(path); x=load(path,'episode'); e=x.episode;
    assert(e.CampaignIdentity==m.identity,'sixgr:calibration:ResumeIdentity','Mixed campaign sources.');
    if e.Role~="fit", continue; end
    for a=1:numel(e.Attempts)
        values=zeros(1,2); g=double(e.Attempts(a).SINRLinear(:));
        assert(~isempty(g) && all(isfinite(g) & g>=0), ...
            'sixgr:calibration:FeatureHistory','Invalid physical SINR feature.');
        for b=1:2
            v=min(g)-bounds(b)*log(mean(exp(-(g-min(g))/bounds(b))));
            values(b)=10*log10(v);
        end
        rows{end+1,1}=struct('CaseID',e.CaseID,'Direction',e.Direction, ...
            'EpisodeID',e.EpisodeID,'Attempt',a,'EffectiveSINRLower_dB',min(values), ...
            'EffectiveSINRUpper_dB',max(values),'ReferenceMinimum_dB',min(axis), ...
            'ReferenceMaximum_dB',max(axis), ...
            'OutsideForEveryBeta',max(values)<min(axis) || min(values)>max(axis), ...
            'CoveredForEveryBeta',min(values)>=min(axis) && max(values)<=max(axis), ...
            'PrimaryStudyAccepted',false); %#ok<AGROW>
    end
end
T=table(); if ~isempty(rows), T=struct2table(vertcat(rows{:})); end
writetable(T,fullfile(folder,'reference_domain_audit.csv'));
end
