function summary=summarizeInstalledReceiverCampaign(events,p)
% One waveform per trial. Fixed sample, final-only Bonferroni bounds across
% case events. Hypotheses are correlated and never enlarge the denominator.
schema=sixgr.phy.pdcch.validateInstalledReceiverCampaign(p);
id='sixgr:pdcch:InvalidCampaignPopulation';
assert(istable(events),id,'Require retained episode rows, not candidate/bit counters.');
cases=p.cases; nc=numel(cases); planned=nc*p.episodes_per_case;
assert(height(events)<=planned,id,'More observations than the frozen design.');
if height(events)>0
    required=["EpisodeID","CaseID","Sequence","Replicate","ChannelSeed","NoiseSeed", ...
        "SignalPresent","Scope","IndependentWaveformCount","HypothesesAreIndependentTrials", ...
        "FalseCRCEpisode","FalseContextAcceptanceEpisode","MissedPayloadEpisode", ...
        "WrongPayloadAcceptanceEpisode","ReceiverAccepted","ExactPayloadRecovered"];
    assert(all(ismember(required,string(events.Properties.VariableNames))),id,'Missing episode evidence.');
    n=height(events); seq=(1:n).'; ci=mod(seq-1,nc)+1;
    ids=string({cases.id}); expected=ids(ci); expected=expected(:);
    present=logical([cases.signal_present]); present=present(ci); present=present(:);
    assert(isequal(double(events.Sequence),seq)&& ...
        isequal(double(events.Replicate),floor((seq-1)/nc)+1)&& ...
        isequal(string(events.CaseID),expected)&&binary(events.SignalPresent)&& ...
        isequal(logical(events.SignalPresent),present),id,'Frozen order or presence differs.');
    seed=p.seed_base+(seq-1)*p.seed_stride;
    assert(isequal(double(events.ChannelSeed),seed)&& ...
        isequal(double(events.NoiseSeed),seed+p.noise_seed_offset)&& ...
        numel(unique(string(events.EpisodeID)))==n,id,'Duplicate/replaced seed or episode.');
    assert(all(string(events.Scope)==string(p.scope))&&all(events.IndependentWaveformCount==1)&& ...
        binary(events.HypothesesAreIndependentTrials)&&~any(events.HypothesesAreIndependentTrials), ...
        id,'Count physical waveforms, not blind-decoding hypotheses.');
    for key=["FalseCRCEpisode","FalseContextAcceptanceEpisode"]
        v=events.(key); assert(binary(v(~present))&&all(isnan(v(present))),id,'Invalid H0 outcomes.');
    end
    for key=["MissedPayloadEpisode","WrongPayloadAcceptanceEpisode","ExactPayloadRecovered"]
        v=events.(key); assert(binary(v(present))&&all(isnan(v(~present))),id,'Invalid H1 outcomes.');
    end
    assert(binary(events.ReceiverAccepted)&& ...
        all(events.FalseContextAcceptanceEpisode(~present)<=events.FalseCRCEpisode(~present))&& ...
        all(events.MissedPayloadEpisode(present)==1-events.ExactPayloadRecovered(present))&& ...
        all(events.WrongPayloadAcceptanceEpisode(present)== ...
            events.ReceiverAccepted(present).*(1-events.ExactPayloadRecovered(present)))&& ...
        all(events.ExactPayloadRecovered(present)<=events.ReceiverAccepted(present)), ...
        id,'CRC, acceptance, exact-payload and missed-payload events disagree.');
end
final=height(events)==planned; alpha=p.family_alpha/(2*nc); rows=cell(nc,1);
for k=1:nc
    c=cases(k); metric=string(schema.primary_h0_event);
    if c.signal_present, metric=string(schema.primary_h1_event); end
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
        if upper<=p.event_error_limit, decision="BOUND_MEETS_CONFIGURED_LIMIT";
        elseif lower>p.event_error_limit, decision="BOUND_EXCEEDS_CONFIGURED_LIMIT";
        else, decision="INCONCLUSIVE"; end
    end
    rows{k}=table(string(c.id),logical(c.signal_present),metric,count,errors, ...
        p.episodes_per_case,estimate,lower,upper,alpha,p.event_error_limit, ...
        final,decision,string(p.stage),string(p.scope),false,false, ...
        'VariableNames',{'CaseID','SignalPresent','PrimaryEvent','IndependentEpisodes','EventCount', ...
        'PlannedEpisodes','Estimate','CILower','CIUpper','DirectionalAlpha','ConfiguredErrorLimit', ...
        'FinalFixedSampleLook','StatisticalDecision','Stage','Scope','DetectorQualified','ScenarioAccepted'});
end
summary=vertcat(rows{:});
end
function yes=binary(x)
yes=(isnumeric(x)||islogical(x))&&isreal(x)&&all(isfinite(x(:)))&&all(x(:)==0|x(:)==1);
end
