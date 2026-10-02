function T=summarizeCollection(folder)
% All configured conditional cells are audited, including unobserved cells.
m=load(fullfile(folder,'campaign.mat'),'p','cases','histories','identity');
roles=["reference","reference_validation","fit","validation"]; axes=cell(1,4);
for r=1:4, [~,axes{r}]=sixgr.calibration.historyGrid(m.p,roles(r)); end
nr=numel(m.p.rv_sequence); nc=numel(m.cases);
counts=cell(nc,4,nr); errors=counts;
for c=1:nc, for r=1:4, for a=1:nr
    counts{c,r,a}=zeros(numel(axes{r})^a,1); errors{c,r,a}=counts{c,r,a};
end, end, end
files=dir(fullfile(folder,'episodes','episode_*.mat'));
for k=1:numel(files)
    sixgr.calibration.verifyEpisodeFile(fullfile(files(k).folder,files(k).name));
    x=load(fullfile(files(k).folder,files(k).name),'episode'); e=x.episode;
    assert(e.CampaignIdentity==m.identity,'sixgr:calibration:ResumeIdentity','Mixed source identities.');
    c=find(string({m.cases.ID})==e.CaseID); r=find(roles==e.Role);
    assert(isscalar(c) && isscalar(r),'sixgr:calibration:History','Unknown case or role.');
    axis=axes{r}; na=numel(axis);
    for a=1:numel(e.Attempts)
        [present,digits]=ismember(e.PlannedSNRHistory_dB(1:a),axis);
        assert(all(present),'sixgr:calibration:History','Unexpected SNR history.');
        index=1+sum((digits-1).*na.^(0:a-1));
        counts{c,r,a}(index)=counts{c,r,a}(index)+1;
        errors{c,r,a}(index)=errors{c,r,a}(index)+e.Attempts(a).CRCError;
    end
end
rows=struct([]); q=m.p.qualification;
for c=1:nc, for r=1:4
axis=axes{r}; na=numel(axis);
for a=1:nr, for index=1:na^a
    n=counts{c,r,a}(index); ne=errors{c,r,a}(index); lo=NaN; hi=NaN; bler=NaN;
    if n>0, [lo,hi]=sixgr.lls.stats.wilsonInterval(ne,n,q.confidence_level); bler=ne/n; end
    digits=mod(floor((index-1)./na.^(0:a-1)),na)+1;
    record=struct('CaseID',m.cases(c).ID,'Direction',m.cases(c).Direction, ...
        'ConfigurationSHA256',string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(m.cases(c).Config),'UTF-8')))), ...
        'Role',roles(r),'Attempt',a,'History_dB',string(jsonencode(axis(digits))), ...
        'ConditionalTrials',n,'Errors',ne,'ConditionalBLER',bler,'CILower',lo,'CIUpper',hi, ...
        'PopulationSufficient',n>=q.minimum_conditional_trials && (hi-lo)/2<=q.maximum_wilson_half_width, ...
        'PrimaryStudyAccepted',false);
    if isempty(rows), rows=record; else, rows(end+1)=record; end %#ok<AGROW>
end, end, end, end
T=struct2table(rows); writetable(T,fullfile(folder,'conditional_population_audit.csv'));
end
