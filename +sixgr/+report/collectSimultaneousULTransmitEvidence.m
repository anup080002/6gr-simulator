function [pairs,population,trials,cohorts]=collectSimultaneousULTransmitEvidence(pusch,pucch)
% Exact posthoc pre-node-RF component coexistence, not an NR procedure test.
% Input-table coverage is not a census of a campaign or proof that no TX was
% ever scheduled. Missing receipt/identity is unavailable, never no-signal.
arguments
    pusch table
    pucch table
end
prototype=struct('Channel',"",'InputRow',NaN,'TransmissionID',"", ...
    'ObservationID',"",'UEIndex',NaN,'RNTI',NaN,'ServingCell',NaN, ...
    'RunFolder',"",'ExecutionID',"",'ConfigHash',"",'RunID',"",'ScenarioID',"", ...
    'RandomSeed',NaN,'ChannelSeed',NaN,'SweepPointIndex',NaN,'ConfiguredSNR_dB',NaN, ...
    'TransmitterID',"",'ClockDomain',"",'ClockEpoch',NaN,'SampleRateHz',NaN, ...
    'EvidenceSHA256',"",'InputWaveformSHA256',"",'ActiveIntervalsJSON',"", ...
    'ActiveSampleCount',NaN,'Qualified',false,'ExcludedNoTransmission',false, ...
    'Outcome',NaN,'OutcomeStatus',"unavailable",'EvidenceStatus',"missing_TX_occupancy_receipt", ...
    'InputPopulationMetadataJSON',"",'ReceiverBindingJSON',"",'JoinKey',"");
trials=struct2table(prototype,'AsArray',true); trials=trials([],:);
sources={pusch,pucch}; channels=["PUSCH","PUCCH"];
for c=1:2
    input=sources{c};
    for k=1:height(input)
        r=table2struct(input(k,:)); out=prototype; out.Channel=channels(c); out.InputRow=k;
        out.InputPopulationMetadataJSON=localMetadata(r);
        out=localAudit(out,r);
        trials=[trials;struct2table(out,'AsArray',true)]; %#ok<AGROW>
    end
end
% Repeated source rows cannot multiply one actual physical attempt. IDs may
% repeat in another independently qualified run/point; never deduplicate them.
keys=trials.JoinKey+"|"+trials.Channel+"|"+trials.TransmissionID;
for k=find(trials.Qualified).'
    if nnz(trials.Qualified & keys==keys(k))>1
        same=trials.Qualified & keys==keys(k);
        trials.Qualified(same)=false;
        trials.EvidenceStatus(same)="ambiguous_duplicate_transmission_rows";
    end
end
pair=struct('PUSCHInputRow',NaN,'PUCCHInputRow',NaN, ...
    'PUSCHTransmissionID',"",'PUCCHTransmissionID',"", ...
    'PUSCHObservationID',"",'PUCCHObservationID',"", ...
    'PUSCHEvidenceSHA256',"",'PUCCHEvidenceSHA256',"", ...
    'PUSCHWaveformSHA256',"",'PUCCHWaveformSHA256',"", ...
    'RunFolder',"",'ExecutionID',"",'ConfigHash',"",'RunID',"",'ScenarioID',"", ...
    'RandomSeed',NaN,'ChannelSeed',NaN,'SweepPointIndex',NaN,'ConfiguredSNR_dB',NaN, ...
    'UEIndex',NaN,'RNTI',NaN,'ServingCell',NaN,'TransmitterID',"", ...
    'ClockDomain',"",'ClockEpoch',NaN,'SampleRateHz',NaN, ...
    'OverlapIntervalsJSON',"",'OverlapSamples',NaN,'PUSCHOutcome',NaN, ...
    'PUCCHOutcome',NaN,'PUSCHOutcomeStatus',"",'PUCCHOutcomeStatus',"", ...
    'JointSuccess',NaN,'OutcomeQualified',false, ...
    'PUSCHPopulationMetadataJSON',"",'PUCCHPopulationMetadataJSON',"", ...
    'PUSCHReceiverBindingJSON',"",'PUCCHReceiverBindingJSON',"",'CohortKey',"", ...
    'Scope',"pre_node_RF_physical_contribution_nonzero_sample_coexistence_not_RE_collision_or_NR_conformance");
pairs=struct2table(pair,'AsArray',true); pairs=pairs([],:);
for i=find(trials.Qualified & trials.Channel=="PUSCH").'
    for j=find(trials.Qualified & trials.Channel=="PUCCH" & trials.JoinKey==trials.JoinKey(i)).'
        a=localIntervals(jsondecode(trials.ActiveIntervalsJSON(i)));
        b=localIntervals(jsondecode(trials.ActiveIntervalsJSON(j)));
        overlap=localIntersection(a,b);
        if isempty(overlap), continue; end
        p=pair;
        for name=["RunFolder","ExecutionID","ConfigHash","RunID","ScenarioID", ...
                "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB", ...
                "UEIndex","RNTI","ServingCell","TransmitterID","ClockDomain","ClockEpoch","SampleRateHz"]
            p.(name)=trials.(name)(i);
        end
        for index=[i j]
            channel=trials.Channel(index);
            p.(channel+"InputRow")=trials.InputRow(index);
            p.(channel+"TransmissionID")=trials.TransmissionID(index);
            p.(channel+"ObservationID")=trials.ObservationID(index);
            p.(channel+"EvidenceSHA256")=trials.EvidenceSHA256(index);
            p.(channel+"WaveformSHA256")=trials.InputWaveformSHA256(index);
            p.(channel+"Outcome")=trials.Outcome(index);
            p.(channel+"OutcomeStatus")=trials.OutcomeStatus(index);
            p.(channel+"PopulationMetadataJSON")=trials.InputPopulationMetadataJSON(index);
            p.(channel+"ReceiverBindingJSON")=trials.ReceiverBindingJSON(index);
        end
        p.CohortKey=trials.JoinKey(i);
        p.OverlapIntervalsJSON=string(jsonencode(overlap));
        p.OverlapSamples=sum(overlap(:,2)-overlap(:,1));
        p.OutcomeQualified=isfinite(p.PUSCHOutcome) && isfinite(p.PUCCHOutcome);
        if p.OutcomeQualified, p.JointSuccess=double(p.PUSCHOutcome==1 && p.PUCCHOutcome==1); end
        pairs=[pairs;struct2table(p,'AsArray',true)]; %#ok<AGROW>
    end
end
schema=["TransmitOccupancyEvidenceJSON","TransmitOccupancyEvidenceSHA256"];
schemaKnown=all(ismember(schema,string(pusch.Properties.VariableNames))) && ...
    all(ismember(schema,string(pucch.Properties.VariableNames)));
complete=schemaKnown && all(trials.Qualified | trials.ExcludedNoTransmission);
population=localPopulation(trials,pairs,complete,height(pusch),height(pucch));
cohortTemplate=population; cohortTemplate.CohortKey=""; cohortTemplate.IdentityJSON="";
cohorts=struct2table(cohortTemplate,'AsArray',true); cohorts=cohorts([],:);
for key=unique(trials.JoinKey(trials.Qualified),'stable').'
    selected=trials(trials.Qualified & trials.JoinKey==key,:);
    p=localPopulation(selected,pairs(pairs.CohortKey==key,:),complete, ...
        nnz(selected.Channel=="PUSCH"),nnz(selected.Channel=="PUCCH"));
    p.CohortKey=key;
    fields=["RunFolder","ExecutionID","ConfigHash","RunID","ScenarioID", ...
        "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB", ...
        "UEIndex","RNTI","ServingCell","TransmitterID","ClockDomain","ClockEpoch","SampleRateHz"];
    p.IdentityJSON=string(jsonencode(table2struct(selected(1,cellstr(fields)))));
    cohorts=[cohorts;struct2table(p,'AsArray',true)]; %#ok<AGROW>
end
end

function population=localPopulation(trials,pairs,complete,puschCount,pucchCount)
cohortCount=numel(unique(trials.JoinKey(trials.Qualified)));
population=struct('CoverageComplete',complete, ...
    'CoverageScope',"all_supplied_trial_rows_not_emission_census_or_campaign_qualification", ...
    'CohortCount',cohortCount,'RateScope',"one_exact_population_UE_cell_endpoint_clock_cohort_no_cross_cohort_pooling", ...
    'PUSCHInputRows',puschCount,'PUCCHInputRows',pucchCount, ...
    'QualifiedPUSCHTransmissions',nnz(trials.Qualified & trials.Channel=="PUSCH"), ...
    'QualifiedPUCCHTransmissions',nnz(trials.Qualified & trials.Channel=="PUCCH"), ...
    'ExcludedNoTransmissionRows',nnz(trials.ExcludedNoTransmission), ...
    'UnqualifiedRows',nnz(~trials.Qualified & ~trials.ExcludedNoTransmission), ...
    'QualifiedPairCount',height(pairs),'ObservedOverlapCount',NaN, ...
    'OverlappingPUCCHCount',NaN,'OverlapRate',NaN, ...
    'OutcomePairCount',nnz(pairs.OutcomeQualified), ...
    'UnknownOutcomePairCount',nnz(~pairs.OutcomeQualified), ...
    'SuccessfulPairCount',sum(pairs.JointSuccess==1), ...
    'FailedPairCount',sum(pairs.JointSuccess==0), ...
    'ConditionalSuccessRate',NaN,'Status',"unavailable_incomplete_transmit_population");
if complete
    population.ObservedOverlapCount=height(pairs);
    population.OverlappingPUCCHCount=numel(unique(pairs.PUCCHInputRow));
    if cohortCount==1 && population.QualifiedPUCCHTransmissions>0
        population.OverlapRate=population.OverlappingPUCCHCount/population.QualifiedPUCCHTransmissions;
    end
    population.Status="no_qualifying_overlap_in_supplied_complete_population";
    if ~isempty(pairs)
        population.Status="unavailable_incomplete_pair_receiver_outcomes";
        if cohortCount==1 && all(pairs.OutcomeQualified)
            population.ConditionalSuccessRate=mean(pairs.JointSuccess);
            population.Status="complete_pair_population_and_receiver_outcomes";
        end
    end
    if cohortCount>1
        population.Status="rates_unavailable_multiple_exact_population_cohorts";
    elseif cohortCount==0
        population.Status="not_exercised_no_qualified_transmission";
    end
end
end

function out=localAudit(out,r)
json=string(sixgr.util.structGet(r,'TransmitOccupancyEvidenceJSON',""));
if ismissing(json) || strlength(strtrim(json))==0
    % An independent receiver hypothesis is not an emitted contribution.
    if out.Channel=="PUCCH" && localNumber(r,'ReceiverOnlyAssignment')==1 && ...
            localNumber(r,'PUCCHTransmissionPrepared')==0
        out.ExcludedNoTransmission=true;
        out.EvidenceStatus="explicit_receiver_only_not_a_transmission";
    end
    return;
end
try, e=jsondecode(json); catch
    out.EvidenceStatus="invalid_transmit_occupancy_JSON"; return;
end
try
    localRequire(isscalar(json) && isstruct(e) && isscalar(e) && ...
        string(sixgr.util.structGet(r,'TransmitOccupancyEvidenceSHA256',""))==sixgr.util.sha256Hex(json), ...
        'receipt_hash_mismatch');
    required={'Version','Source','Identity','PopulationIdentity','StartSample','EndSampleExclusive', ...
        'SampleRateHz','InputSampleCount','ActiveSampleCount','ActiveIntervals','HasNonzeroSamples', ...
        'InputWaveformSHA256','EmissionStatus','CommittedAtSample','CompletedAtSample','ReceiverBinding'};
    localRequire(all(isfield(e,required)),'incomplete_transmit_receipt');
    localRequire(string(e.Version)=="transmit_occupancy/v1" && ...
        string(e.Source)=="enqueued_physical_chain_nonzero_contribution_pre_node_RF" && ...
        string(e.EmissionStatus)=="completed_nonzero_contribution",'uncompleted_or_wrong_plane_receipt');
    id=e.Identity; pop=e.PopulationIdentity;
    idNames=["Channel","TransmissionID","ObservationID","UEIndex","RNTI","ServingCell", ...
        "TransmitterID","ClockDomain","ClockEpoch"];
    popNames=["RunFolder","ExecutionID","ConfigHash","RunID","ScenarioID", ...
        "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB","BoundAtSample","Source"];
    localRequire(isstruct(id) && isscalar(id) && all(isfield(id,idNames)) && ...
        isstruct(pop) && isscalar(pop) && all(isfield(pop,popNames)),'incomplete_identity');
    localRequire(string(id.Channel)==out.Channel && string(id.TransmitterID)=="ue_"+id.UEIndex && ...
        string(id.ClockDomain)=="shared_physical_sample_clock/v1",'wrong_channel_endpoint_or_clock');
    for name=["UEIndex","RNTI","ServingCell"]
        localRequire(localInteger(id.(name),1),'invalid_radio_identity');
    end
    localRequire(localInteger(id.ClockEpoch,0) && localText(id.TransmissionID) && ...
        localText(id.ObservationID) && localText(e.InputWaveformSHA256),'missing_clock_or_waveform_identity');
    localRequire(localText(pop.RunFolder) && localText(pop.ConfigHash) && ...
        localInteger(pop.SweepPointIndex,1) && localInteger(pop.RandomSeed,0) && ...
        localInteger(pop.ChannelSeed,0) && isnumeric(pop.ConfiguredSNR_dB) && ...
        isscalar(pop.ConfiguredSNR_dB) && isfinite(pop.ConfiguredSNR_dB), ...
        'unbound_execution_or_point_population');
    localRequire(string(pop.Source)=="actual_first_active_sample_commit_runtime_context" && ...
        isequal(pop.BoundAtSample,e.CommittedAtSample),'population_not_bound_at_TX_emission');
    localRequire(localInteger(e.StartSample,0) && localInteger(e.EndSampleExclusive,1) && ...
        e.EndSampleExclusive>e.StartSample && localInteger(e.InputSampleCount,1) && ...
        e.InputSampleCount==e.EndSampleExclusive-e.StartSample && isnumeric(e.SampleRateHz) && ...
        isscalar(e.SampleRateHz) && isfinite(e.SampleRateHz) && e.SampleRateHz>0,'invalid_transmit_clock');
    runs=localIntervals(e.ActiveIntervals);
    localRequire(isnumeric(runs) && ismatrix(runs) && size(runs,2)==2 && ~isempty(runs) && ...
        all(isfinite(runs)&runs==fix(runs),'all') && all(runs(:,1)>=e.StartSample) && ...
        all(runs(:,2)<=e.EndSampleExclusive) && all(runs(:,2)>runs(:,1)) && ...
        all(runs(2:end,1)>runs(1:end-1,2)), 'invalid_nonzero_sample_runs');
    localRequire(isequal(e.HasNonzeroSamples,true) && e.ActiveSampleCount==sum(runs(:,2)-runs(:,1)) && ...
        e.CommittedAtSample==runs(1,1)+1 && localInteger(e.CompletedAtSample,1) && ...
        e.CompletedAtSample>=e.EndSampleExclusive,'incomplete_emission_or_run_count');
    localReceiverBinding(r,e);
    for name=["UEIndex","RNTI"]
        localRequire(localNumber(r,name)==id.(name),'trial_radio_identity_mismatch');
    end
    for name=["BaseStationID","ServingCell"]
        if isfield(r,name) && isfinite(localNumber(r,name))
            localRequire(localNumber(r,name)==id.ServingCell,'trial_cell_identity_mismatch');
        end
    end
    % Row callback SweepPointIndex is retained as metadata, not relabeled as
    % the transmission point. Explicit lifecycle metadata cannot contradict.
    for name=["RunFolder","ExecutionID","ConfigHash","RunID","ScenarioID"]
        if isfield(r,name) && localText(r.(name))
            localRequire(string(r.(name))==string(pop.(name)),'trial_lifecycle_identity_mismatch');
        end
    end
    for name=idNames
        if isfield(out,name)
            if isstring(out.(name)), out.(name)=string(id.(name)); else, out.(name)=id.(name); end
        end
    end
    for name=popNames
        if isfield(out,name)
            if isstring(out.(name)), out.(name)=string(pop.(name)); else, out.(name)=pop.(name); end
        end
    end
    out.SampleRateHz=e.SampleRateHz;
    out.InputWaveformSHA256=string(e.InputWaveformSHA256);
    out.ActiveIntervalsJSON=string(jsonencode(runs)); out.ActiveSampleCount=e.ActiveSampleCount;
    out.EvidenceSHA256=sixgr.util.sha256Hex(json);
    out.ReceiverBindingJSON=string(jsonencode(e.ReceiverBinding));
    join=rmfield(pop,{'BoundAtSample','Source'});
    for name=["UEIndex","RNTI","ServingCell","TransmitterID","ClockDomain","ClockEpoch"]
        join.(name)=id.(name);
    end
    join.SampleRateHz=e.SampleRateHz;
    out.JoinKey=sixgr.util.sha256Hex(jsonencode(orderfields(join)));
    out.Qualified=true; out.EvidenceStatus="completed_identity_bound_nonzero_contribution";
    [out.Outcome,out.OutcomeStatus]=localOutcome(r,out.Channel);
catch cause
    if ~strcmp(cause.identifier,'sixgr:report:TransmitOccupancy'), rethrow(cause); end
    out.EvidenceStatus=string(cause.message);
end
end

function [value,status]=localOutcome(r,channel)
value=NaN; status="unavailable_receiver_outcome";
if localNumber(r,'Crash')==1 || upper(string(sixgr.util.structGet(r,'Status',"")))=="CRASH"
    status="receiver_crash_not_decode_failure"; return;
end
if localNumber(r,'Crash')~=0, return; end
if channel=="PUSCH"
    crc=localNumber(r,'CRCPass');
    if ismember(crc,[0 1])
        value=crc; status="actual_transport_block_CRC_outcome";
    end
else
    result=sixgr.truth.summarizePUCCHPayloadDelivery(struct2table(r,'AsArray',true));
    if result.Available
        value=double(result.FailedPayloadCount==0);
        status="complete_UCI_payload_delivery_including_erasure";
    end
end
end

function localReceiverBinding(r,e)
b=e.ReceiverBinding; id=e.Identity;
required=["ObservationID","ReceiverID","StartSample","EndSampleExclusive", ...
    "SampleRateHz","CompletedAtSample","SourceRowIdentityField","SourceRowIdentity"];
localRequire(isstruct(b) && isscalar(b) && all(isfield(b,required)), ...
    'incomplete_actual_receiver_binding');
field="FrozenGrantContextId";
if string(id.Channel)=="PUCCH", field="PhysicalPUCCHOccasionId"; end
localRequire(string(b.ObservationID)==string(id.ObservationID) && ...
    string(b.ReceiverID)=="gnb_"+id.ServingCell+"_rx:post_rf" && ...
    localInteger(b.StartSample,0) && localInteger(b.EndSampleExclusive,1) && ...
    b.EndSampleExclusive>b.StartSample && b.SampleRateHz==e.SampleRateHz && ...
    b.CompletedAtSample==e.CompletedAtSample && b.CompletedAtSample>=b.EndSampleExclusive && ...
    string(b.SourceRowIdentityField)==field && localText(b.SourceRowIdentity) && ...
    isfield(r,field) && string(r.(field))==string(b.SourceRowIdentity), ...
    'receiver_observation_or_grant_binding_mismatch');
binding=struct('TransmitOccupancyObservationID',string(b.ObservationID), ...
    'TransmitOccupancyTransmissionID',string(id.TransmissionID), ...
    'TransmitOccupancyTXEndpoint',string(id.TransmitterID)+":tx", ...
    'TransmitOccupancyRXEndpoint',string(b.ReceiverID), ...
    'TransmitOccupancyClockDomain',string(id.ClockDomain), ...
    'TransmitOccupancyClockEpoch',id.ClockEpoch, ...
    'TransmitOccupancyStartSample',e.StartSample, ...
    'TransmitOccupancyEndSampleExclusive',e.EndSampleExclusive, ...
    'TransmitOccupancySampleRateHz',e.SampleRateHz, ...
    'TransmitOccupancyRXStartSample',b.StartSample, ...
    'TransmitOccupancyRXEndSampleExclusive',b.EndSampleExclusive, ...
    'TransmitOccupancyRXSampleRateHz',b.SampleRateHz, ...
    'TransmitOccupancyCompletedAtSample',b.CompletedAtSample, ...
    'ObservationStartSample',b.StartSample, ...
    'ObservationEndSampleExclusive',b.EndSampleExclusive, ...
    'ObservationSampleRateHz',b.SampleRateHz);
for name=string(fieldnames(binding)).'
    localRequire(isfield(r,name),'missing_source_receiver_or_transmit_binding_column');
    expected=binding.(name);
    if isstring(expected)
        localRequire(isscalar(string(r.(name))) && string(r.(name))==expected, ...
            'source_receiver_or_transmit_identity_mismatch');
    else
        localRequire(localNumber(r,name)==expected,'source_receiver_or_transmit_clock_mismatch');
    end
end
end

function runs=localIntervals(runs)
% JSON has no distinction between a 1x2 row and a two-element column.
% Normalize only this exact one-interval case, never arbitrary flat arrays.
if isnumeric(runs) && isvector(runs) && numel(runs)==2
    runs=reshape(runs,1,2);
end
end

function intervals=localIntersection(a,b)
intervals=zeros(0,2); i=1; j=1;
while i<=size(a,1) && j<=size(b,1)
    first=max(a(i,1),b(j,1)); last=min(a(i,2),b(j,2));
    if first<last, intervals(end+1,:)=[first last]; end %#ok<AGROW>
    if a(i,2)<=b(j,2), i=i+1; else, j=j+1; end
end
end

function value=localNumber(r,name)
value=NaN;
if isfield(r,name) && (isnumeric(r.(name)) || islogical(r.(name))) && isscalar(r.(name))
    value=double(r.(name));
end
end

function value=localInteger(x,minimum)
value=isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x>=minimum && x==fix(x);
end

function value=localText(x)
x=string(x); value=isscalar(x) && ~ismissing(x) && strlength(strtrim(x))>0;
end

function localRequire(ok,reason)
assert(isscalar(ok) && ok,'sixgr:report:TransmitOccupancy','%s',reason);
end

function text=localMetadata(r)
names=string(fieldnames(r));
keep=ismember(names,["RunFolder","RunID","ExecutionID","ConfigHash","ScenarioID", ...
    "SourceCSV","SourceFile","SourceRow"]) | startsWith(names,["Sweep","Point"]) | endsWith(names,"Seed");
metadata=struct();
for name=names(keep).', metadata.(name)=r.(name); end
text=string(jsonencode(metadata));
end
