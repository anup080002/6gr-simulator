function summary=summarizeInstalledReceiverCampaign(events,policy)
% Fixed-sample accounting only. This cannot certify input provenance or NR
% conformance; the campaign owner verifies every physical episode first.
sixgr.phy.pucch.validateInstalledReceiverCampaign(policy);
id='sixgr:pucch:InvalidCampaignPopulation';
assert(istable(events),id,'Supply retained episode rows, not aggregate bit counters.');
cases=policy.cases; nc=numel(cases); planned=nc*policy.episodes_per_case;
assert(height(events)<=planned,id,'More episodes than the frozen design.');
if height(events)>0
    required=["EpisodeID","CaseID","Sequence","Replicate","ChannelSeed","NoiseSeed", ...
        "SignalPresent","Scope","IndependentWaveformCount","HARQBitsAreIndependentTrials", ...
        "FalseAcceptanceEpisode","CompleteUCIErrorEpisode"];
    assert(all(ismember(required,string(events.Properties.VariableNames))),id,'Missing population identity.');
    n=height(events); seq=(1:n).'; ci=mod(seq-1,nc)+1;
    ids=string({cases.id}); expected=ids(ci); expected=expected(:);
    present=logical([cases.signal_present]); present=present(ci); present=present(:);
    assert(isequal(double(events.Sequence),seq) && ...
        isequal(double(events.Replicate),floor((seq-1)/nc)+1) && ...
        isequal(string(events.CaseID),expected) && binary(events.SignalPresent) && ...
        isequal(logical(events.SignalPresent),present),id,'Episode order/ownership differs from the frozen design.');
    seeds=policy.seed_base+(seq-1)*policy.seed_stride;
    assert(isequal(double(events.ChannelSeed),seeds) && ...
        isequal(double(events.NoiseSeed),seeds+policy.noise_seed_offset) && ...
        numel(unique(string(events.EpisodeID)))==n,id,'Duplicate or replaced seed/episode identity.');
    assert(all(string(events.Scope)==string(policy.scope)) && ...
        all(events.IndependentWaveformCount==1) && binary(events.HARQBitsAreIndependentTrials) && ...
        ~any(events.HARQBitsAreIndependentTrials), ...
        id,'Count each independently reset received waveform exactly once, not its HARQ bits.');
    h0=double(events.FalseAcceptanceEpisode); h1=double(events.CompleteUCIErrorEpisode);
    assert(all(ismember(h0(~present),[0 1])) && all(isnan(h0(present))) && ...
        all(ismember(h1(present),[0 1])) && all(isnan(h1(~present))), ...
        id,'H0/H1 primary events require actual binary outcomes; no missing/fallback outcomes.');
end
final=height(events)==planned;
alpha=policy.family_alpha/(2*nc);
rows=cell(nc,1);
for k=1:nc
    c=cases(k); metric="FalseAcceptanceEpisode";
    if c.signal_present, metric="CompleteUCIErrorEpisode"; end
    count=0; errors=0;
    if height(events)>0
        selected=string(events.CaseID)==string(c.id);
        count=nnz(selected); errors=sum(double(events.(metric)(selected)));
    end
    estimate=NaN; lower=NaN; upper=NaN; decision="PENDING_FIXED_SAMPLE";
    if count>0, estimate=errors/count; end
    if final
        lo=sixgr.validation.BinomialIntervalEngine.exactLower(errors,count,1-alpha);
        hi=sixgr.validation.BinomialIntervalEngine.exactUpper(errors,count,1-alpha);
        lower=lo.Lower; upper=hi.Upper;
        if upper<=policy.event_error_limit, decision="BOUND_MEETS_CONFIGURED_LIMIT";
        elseif lower>policy.event_error_limit, decision="BOUND_EXCEEDS_CONFIGURED_LIMIT";
        else, decision="INCONCLUSIVE"; end
    end
    rows{k}=table(string(c.id),logical(c.signal_present),metric,count,errors, ...
        policy.episodes_per_case,estimate,lower,upper,alpha,policy.event_error_limit, ...
        final,decision,string(policy.stage),string(policy.scope),false,false, ...
        'VariableNames',{'CaseID','SignalPresent','PrimaryEvent','IndependentEpisodes','EventCount', ...
        'PlannedEpisodes','Estimate','CILower','CIUpper','DirectionalAlpha','ConfiguredErrorLimit', ...
        'FinalFixedSampleLook','StatisticalDecision','Stage','Scope','DetectorQualified','ScenarioAccepted'});
end
summary=vertcat(rows{:});
end
function yes=binary(value)
yes=(isnumeric(value)||islogical(value))&&isreal(value)&& ...
    all(isfinite(value(:)))&&all(value(:)==0|value(:)==1);
end
