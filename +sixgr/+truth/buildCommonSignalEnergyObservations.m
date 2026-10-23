function [observations,audit,unbound]=buildCommonSignalEnergyObservations(raw,cfg,R,configHash,sourceHash)
% Actual SI/RA resource observations for an engineering energy model only.
% Never append these rows to connected PDSCH/PUSCH trials or award payload
% goodput. A failed decode still consumed the executed waveform interval.
% R is the caller's hash-verified, compact executed-occupancy ledger.
arguments
    raw (1,1) struct
    cfg (1,1) struct
    R table
    configHash (1,1) string
    sourceHash (1,1) string
end
% struct2table(emptyStruct) loses string column types in MATLAB. Preserve
% the declared scalar schema before slicing to an empty observation table.
observations=struct2table(prototype()); observations=observations([],:);
audit=table('Size',[0 5],'VariableTypes',{'string','string','double','string','string'}, ...
    'VariableNames',{'AllocationID','Domain','BoundIntervalCount','Status','SourceSHA256'});
used=false(height(R),1);
if isempty(R), unbound=R; return; end
assert(all(string(R.Source)=="retained_executed_TX_RE_occupancy_not_RF_activity") && ...
    all(string(R.SourceSHA256)==sourceHash), ...
    'sixgr:truth:CommonResourceAuthority','Common energy needs verified executed occupancy.');
scope=cell(height(R),1);
for k=1:height(R)
    scope{k}=jsondecode(string(R.PopulationScopeJSON(k)));
    assert(isfield(scope{k},'ConfigHash') && string(scope{k}.ConfigHash)==configHash, ...
        'sixgr:truth:CommonResourceScope','Common resource configuration differs.');
end
stages=sixgr.util.structGet(raw,'RAEvidenceTables.ra_runtime_stage_waveforms',table());
prach=sixgr.util.structGet(raw,'PRACH',table());
for k=1:height(stages)
    stage=stages(k,:); name=txt(stage,"StageName");
    if ~any(name==["Msg2","Msg3","Msg4","RRCSetupComplete"]), continue; end
    matches=false(height(prach),1);
    for p=1:height(prach)
        matches(p)=txt(prach(p,:),"RARunId")==txt(stage,"RunId") && ...
            num(prach(p,:),"RACellId")==num(stage,"CellId") && ...
            num(prach(p,:),"RAUEId")==num(stage,"UEId") && ...
            num(prach(p,:),"RAAttemptId")==num(stage,"AttemptId");
    end
    if nnz(matches)~=1, continue; end % no nearest-slot/UE guessing
    receiver=prach(matches,:);
    assert(txt(receiver,"ConfigHash")==configHash && ...
        txt(receiver,"RASlotTimeBase")=="absolute_zero_based", ...
        'sixgr:truth:CommonResourceScope','RA identity or clock authority is missing.');
    slotField=name+"ScheduledSlot";
    if name=="RRCSetupComplete", slotField="SetupCompleteScheduledSlot"; end
    slot=num(stage,"StageSlot");
    assert(slot==num(receiver,slotField), ...
        'sixgr:truth:CommonResourceClock','RA stage and receiver resource slots disagree.');
    validateCapture(stage);
    assert(num(stage,"TxSampleCount")>0 && num(stage,"RxSampleCount")>0 && ...
        num(stage,"RxSampleCount")==num(stage,"ObservationEndSampleExclusive")-num(stage,"ObservationStartSample") && ...
        num(stage,"RuntimeStageWaveformUsed")==1 && num(stage,"SelfLoopWaveformUsed")==0 && ...
        startsWith(txt(stage,"WaveformSource"),"shared_physical_stream_received"), ...
        'sixgr:truth:UnexecutedCommonSignalObservation','Prepared/self-loop stages are not shared executed observations.');
    channels="PUSCH"; direction="UL";
    if any(name==["Msg2","Msg4"]), channels=["PDCCH","PDSCH"]; direction="DL"; end
    assert(txt(stage,"Direction")==direction, ...
        'sixgr:truth:CommonResourceDirection','Actual RA direction differs from the stage.');
    for channel=channels
        id=txt(stage,"RunId")+"_cell"+num(stage,"CellId")+"_ue"+num(stage,"UEId")+ ...
            "_attempt"+num(stage,"AttemptId")+"_"+name+"_slot"+slot+"_"+channel;
        selected=string(R.AllocationID)==id;
        if ~any(selected), continue; end
        assert(all(R.AbsoluteSlotIndex0(selected)==slot) && ...
            all(R.CellID(selected)==num(stage,"CellId")) && ...
            all(R.UEID(selected)==num(stage,"UEId")) && ...
            all(string(R.Channel(selected))==channel) && all(string(R.Direction(selected))==direction), ...
            'sixgr:truth:CommonResourceIdentity','RA resource ownership differs from its stage.');
        for j=reshape(find(selected),1,[])
            assert(isfield(scope{j},'ra_stage') && string(scope{j}.ra_stage)==name && ...
                isfield(scope{j},'ra_attempt_id') && str2double(string(scope{j}.ra_attempt_id))==num(stage,"AttemptId"), ...
                'sixgr:truth:CommonResourceIdentity','RA resource attempt/stage differs.');
        end
        outcome=name+channel+"CrcPass";
        if name=="Msg2" && channel=="PDCCH", outcome="Msg2DCICrcPass"; end
        if name=="RRCSetupComplete", outcome="RRCSetupCompleteCRC"; end
        append(receiver,stage,selected,"RA_"+name+"_"+channel, ...
            "control/csv/ra_runtime_stage_waveforms.csv",k,outcome);
    end
end
pbch=sixgr.util.structGet(raw,'PBCH',table());
slotSec=1e-3/(double(cfg.phy.carrier.SubcarrierSpacing)/15);
for k=1:height(pbch)
    receiver=pbch(k,:);
    if ~all(ismember({'SIB1DCICrcPass','SIB1DLSCHCrcPass'},pbch.Properties.VariableNames)), continue; end
    assert(txt(receiver,"ConfigHash")==configHash, ...
        'sixgr:truth:CommonResourceScope','Broadcast receiver configuration differs.');
    start=num(receiver,"ObservationStartSample"); fs=num(receiver,"ObservationSampleRateHz");
    if ~all(isfinite([start fs])) || fs<=0, continue; end
    base=start/(fs*slotSec);
    if base<0 || abs(base-round(base))>1e-9, continue; end
    base=round(base); cellID=num(receiver,["CellID","BaseStationID","ServingCell"]);
    beam=num(receiver,"SSBIndex");
    validateCapture(receiver);
    for channel=["PDCCH","PDSCH"]
        id="sib1_"+lower(channel)+"_cell_"+cellID+"_burst_"+base+"_ssb_"+beam;
        selected=string(R.AllocationID)==id;
        if ~any(selected), continue; end
        assert(all(R.CellID(selected)==cellID) && all(isnan(R.UEID(selected))) && ...
            all(string(R.Channel(selected))==channel) && all(string(R.Direction(selected))=="DL"), ...
            'sixgr:truth:CommonResourceIdentity','SI allocation differs from broadcast ownership.');
        % The retained capture bounds the transmitted resource occasion;
        % do not bind a different burst carrying the same SSB index.
        spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(cfg.phy.carrier);
        for j=reshape(find(selected),1,[])
            a=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(R.AbsoluteSlotIndex0(j),R.SymbolIndex0(j),spec);
            b=a.plusSymbols(1,spec);
            assert(a.seconds()*fs>=start-1e-6 && ...
                b.seconds()*fs<=num(receiver,"ObservationEndSampleExclusive")+1e-6, ...
                'sixgr:truth:CommonResourceClock','SI resource is outside the recorded broadcast observation.');
        end
        outcome="SIB1DLSCHCrcPass";
        if channel=="PDCCH", outcome="SIB1DCICrcPass"; end
        append(receiver,receiver,selected,"SI_"+channel,"air_interface/csv/pbch_trials.csv",k,outcome);
    end
end
% Optional population dimensions absent from every source are not declared
% dimensions. Do not hand the strict RF collector a fabricated blank index.
for field=["SweepPointIndex","SweepRealizationIndex","ScenarioID"]
    values=string(observations.(field));
    if all(ismissing(values)|strlength(strtrim(values))==0|lower(values)=="nan")
        observations=removevars(observations,field);
    end
end
unbound=R(~used,:);

    function append(receiver,capture,selected,domain,artifact,sourceRow,outcomeField)
        S=R(selected,:); id=unique(string(S.AllocationID));
        assert(isscalar(id),'sixgr:truth:CommonResourceIdentity','One observation requires one exact allocation.');
        r=prototype();
        r.Domain=domain; r.Direction=string(S.Direction(1)); r.Channel=string(S.Channel(1));
        r.CellID=S.CellID(1); r.BaseStationID=r.CellID;
        r.UEID=num(receiver,["RAUEId","UEIndex","UEID"]);
        r.Slot=min(S.AbsoluteSlotIndex0)+1; r.SlotIndexBase=1;
        slotsPerFrame=10*double(cfg.phy.carrier.SubcarrierSpacing)/15;
        r.Frame=floor(min(S.AbsoluteSlotIndex0)/slotsPerFrame)+1;
        r.ConfigHash=configHash; r.AllocationID=id;
        r.SourceArtifact=artifact; r.SourceRow=sourceRow; r.ResourceSourceSHA256=sourceHash;
        r.RecordedReceiverOutcomeField=outcomeField;
        r.RecordedReceiverOutcome=num(receiver,outcomeField);
        for field=["RunID","ExecutionID","ScenarioID","SweepPointIndex","SweepRealizationIndex"]
            r.(field)=txt(receiver,field);
        end
        for j=reshape(find(selected),1,[])
            for field=["RunID","ExecutionID","ScenarioID","SweepPointIndex","SweepRealizationIndex"]
                if isfield(scope{j},field) && present(string(scope{j}.(field))) && present(r.(field))
                    assert(string(scope{j}.(field))==r.(field), ...
                        'sixgr:truth:CommonResourceScope','Common resource and receiver populations differ.');
                end
            end
        end
        for field=["ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"]
            r.(field)=num(capture,field);
        end
        for field=["TxRFEndpointMetadataAuditJSON","RxRFEndpointMetadataAuditJSON"]
            r.(field)=txt(capture,field);
        end
        entries=repmat(struct('AbsoluteSlotIndex0',NaN,'SymbolIndex0',NaN,'PRBSet0Based',[]),height(S),1);
        for j=1:height(S)
            entries(j).AbsoluteSlotIndex0=S.AbsoluteSlotIndex0(j);
            entries(j).SymbolIndex0=S.SymbolIndex0(j);
            entries(j).PRBSet0Based=jsondecode(string(S.PRBSet0BasedJSON(j)));
        end
        r.ExecutedResourceIntervalsJSON=string(jsonencode(entries));
        r.ExecutedResourceIntervalSource="retained_executed_TX_RE_occupancy_not_RF_activity";
        r.ResourceGridPRBCount=S.ResourceGridPRBCount(1); r.ResourceSymbolsPerSlot=S.ResourceSymbolsPerSlot(1);
        T=struct2table(r);
        sixgr.truth.expandExecutedResourceIntervals(T,cfg); % canonical validation, including duplicates
        % Several UEs can observe one broadcast; their RX energy is distinct,
        % while the endpoint integrator charges the shared gNB state once.
        duplicate=observations.AllocationID==id & observations.UEID==r.UEID & ...
            observations.ExecutionID==r.ExecutionID;
        assert(~any(duplicate),'sixgr:truth:DuplicateCommonSignalObservation','Duplicate common receiver identity.');
        observations=[observations;T]; %#ok<AGROW>
        audit(end+1,:)={id,domain,height(S),"bound_executed_common_signal_no_application_goodput",sourceHash};
        used(selected)=true;
    end
end

function r=prototype()
r=struct('Domain',"",'Channel',"",'Direction',"",'Frame',NaN,'Slot',NaN,'SlotIndexBase',1, ...
    'UEID',NaN,'CellID',NaN,'BaseStationID',NaN,'ConfigHash',"",'RunID',"",'ExecutionID',"", ...
    'ScenarioID',"",'SweepPointIndex',"",'SweepRealizationIndex',"",'AllocationID',"", ...
    'ObservationStartSample',NaN,'ObservationEndSampleExclusive',NaN,'ObservationSampleRateHz',NaN, ...
    'TxRFEndpointMetadataAuditJSON',"",'RxRFEndpointMetadataAuditJSON',"", ...
    'RecordedReceiverOutcomeField',"",'RecordedReceiverOutcome',NaN, ...
    'SourceArtifact',"",'SourceRow',NaN,'ResourceSourceSHA256',"", ...
    'Status',"executed_common_signal_not_connected_data_or_qualification", ...
    'ExecutedResourceIntervalsJSON',"",'ExecutedResourceIntervalSource',"", ...
    'ResourceGridPRBCount',NaN,'ResourceSymbolsPerSlot',NaN);
end

function validateCapture(T)
a=num(T,"ObservationStartSample"); b=num(T,"ObservationEndSampleExclusive"); fs=num(T,"ObservationSampleRateHz");
assert(all(isfinite([a b fs])) && a>=0 && b>a && fs>0 && all([a b]==fix([a b])), ...
    'sixgr:truth:CommonResourceClock','Require the actual receiver sample clock.');
end

function value=num(T,names)
value=NaN;
for name=names
    candidate=str2double(txt(T,name));
    if isscalar(candidate)&&isfinite(candidate), value=candidate; return; end
end
end

function value=txt(T,name)
value="";
if ismember(name,T.Properties.VariableNames), value=string(T.(name)); end
end

function yes=present(value)
yes=isscalar(value)&&~ismissing(value)&&strlength(strtrim(value))>0&&lower(value)~="nan";
end
