function ok=testCommonSignalEnergyObservations()
% Identity/accounting fixtures, not statistical receiver or RF qualification.
setup6GRSimToolkit('Verbose',false);
cfg.phy.carrier=struct('NSizeGrid',24,'SubcarrierSpacing',30,'CyclicPrefix',"normal");
hash=string(repmat('a',1,64)); source=string(repmat('b',1,64));
cfg.meta.configHash=hash;
P=table("ra_capture",1,1,1,"absolute_zero_based",hash,3,4,5,6, ...
    0,1,1,1,1,1,"execution_fixture","run_fixture", ...
    'VariableNames',{'RARunId','RACellId','RAUEId','RAAttemptId','RASlotTimeBase', ...
    'ConfigHash','Msg2ScheduledSlot','Msg3ScheduledSlot','Msg4ScheduledSlot', ...
    'SetupCompleteScheduledSlot','Msg2DCICrcPass','Msg2PDSCHCrcPass','Msg3PUSCHCrcPass', ...
    'Msg4PDCCHCrcPass','Msg4PDSCHCrcPass','RRCSetupCompleteCRC','ExecutionID','RunID'});
B=table(1,1,1,hash,0,0,4000,1e6,0,1,"execution_fixture","run_fixture", ...
    'VariableNames',{'Slot','UEIndex','CellID','ConfigHash','SSBIndex', ...
    'ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz', ...
    'SIB1DCICrcPass','SIB1DLSCHCrcPass','ExecutionID','RunID'});
names=["Msg2","Msg3","Msg4","RRCSetupComplete"];
S=table(); R=table();
for k=1:4
    name=names(k); slot=k+2; direction="UL"; channels="PUSCH";
    if any(name==["Msg2","Msg4"]), direction="DL"; channels=["PDCCH","PDSCH"]; end
    stage=table("ra_capture",1,1,1,name,slot,direction,500,520, ...
        slot*500-10,(slot+1)*500+10,1e6,1,0, ...
        "shared_physical_stream_received_post_adc_gain_compensated", ...
        'VariableNames',{'RunId','CellId','UEId','AttemptId','StageName','StageSlot', ...
        'Direction','TxSampleCount','RxSampleCount','ObservationStartSample', ...
        'ObservationEndSampleExclusive','ObservationSampleRateHz', ...
        'RuntimeStageWaveformUsed','SelfLoopWaveformUsed','WaveformSource'});
    S=[S;stage]; %#ok<AGROW>
    for channel=channels
        id="ra_capture_cell1_ue1_attempt1_"+name+"_slot"+slot+"_"+channel;
        scope=struct('ConfigHash',hash,'ra_stage',name,'ra_attempt_id',"1");
        part=resource(channel,id,slot,0,1,scope,source);
        R=[R;part]; %#ok<AGROW>
    end
end
for channel=["PDCCH","PDSCH"]
    part=resource(channel,"sib1_"+lower(channel)+"_cell_1_burst_0_ssb_0",2,0,NaN,struct('ConfigHash',hash),source);
    R=[R;part]; %#ok<AGROW>
end
raw=struct('PRACH',P,'PBCH',B,'RAEvidenceTables',struct('ra_runtime_stage_waveforms',S));
original=raw;
[empty,~,~]=sixgr.truth.buildCommonSignalEnergyObservations(raw,cfg,R([],:),hash,source);
assert(isempty(empty)&&isstring(empty.AllocationID)&&isstring(empty.ExecutionID));
[C,A,U]=sixgr.truth.buildCommonSignalEnergyObservations(raw,cfg,R,hash,source);
assert(isequaln(raw,original) && height(C)==8 && height(A)==8 && isempty(U));
assert(nnz(C.RecordedReceiverOutcome==0)==2 && ...
    ~any(ismember({'TBSBits','TBSize_bits','UniqueDeliveredTBBits'},C.Properties.VariableNames)), ...
    'Access outcomes/allocations must never manufacture application payload credit.');
assert(all(startsWith(C.Domain,["RA_","SI_"])) && all(C.ObservationSampleRateHz==1e6));
assert(all(C.Frame==1) && all(C.SlotIndexBase==1));
numericC=C; numericA=A; numericU=U;
% Native RA producers retain logical flags and CRCs. Their CSV form is
% numeric 1/0; both must preserve failed-decode energy without new credit.
native=raw;
for name=["RuntimeStageWaveformUsed","SelfLoopWaveformUsed"]
    native.RAEvidenceTables.ra_runtime_stage_waveforms.(name)=logical(S.(name));
end
for name=["Msg2DCICrcPass","Msg2PDSCHCrcPass","Msg3PUSCHCrcPass", ...
        "Msg4PDCCHCrcPass","Msg4PDSCHCrcPass","RRCSetupCompleteCRC"]
    native.PRACH.(name)=logical(P.(name));
end
for name=["SIB1DCICrcPass","SIB1DLSCHCrcPass"]
    native.PBCH.(name)=logical(B.(name));
end
[C,A,U]=sixgr.truth.buildCommonSignalEnergyObservations(native,cfg,R,hash,source);
assert(isequaln(C,numericC)&&isequaln(A,numericA)&&isequaln(U,numericU));
assert(nnz(C.RecordedReceiverOutcome==0)==2 && nnz(C.RecordedReceiverOutcome==1)==6);
roundtripRoot=string(tempname); mkdir(roundtripRoot);
roundtripCleanup=onCleanup(@()cleanupFixture(roundtripRoot)); %#ok<NASGU>
csvRaw=native;
for name=["PRACH","PBCH"]
    path=fullfile(roundtripRoot,name+".csv");
    sixgr.util.csvWriteTable(path,native.(name));
    csvRaw.(name)=sixgr.util.csvReadTable(path,'TextType','string');
end
path=fullfile(roundtripRoot,'stages.csv');
sixgr.util.csvWriteTable(path,native.RAEvidenceTables.ra_runtime_stage_waveforms);
csvRaw.RAEvidenceTables.ra_runtime_stage_waveforms=sixgr.util.csvReadTable(path,'TextType','string');
[C,A,U]=sixgr.truth.buildCommonSignalEnergyObservations(csvRaw,cfg,R,hash,source);
assert(isequaln(C,numericC)&&isequaln(A,numericA)&&isequaln(U,numericU));
for fault=["prepared","self_loop","missing_runtime","malformed_text","nonbinary","vector"]
    bad=native;
    switch fault
        case "prepared"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.WaveformSource(1)="prepared_not_received";
        case "self_loop"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.SelfLoopWaveformUsed(1)=true;
        case "missing_runtime"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.RuntimeStageWaveformUsed(1)=false;
        case "malformed_text"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.RuntimeStageWaveformUsed=repmat("true",height(S),1);
        case "nonbinary"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.RuntimeStageWaveformUsed=2*ones(height(S),1);
        case "vector"
            bad.RAEvidenceTables.ra_runtime_stage_waveforms.RuntimeStageWaveformUsed=true(height(S),2);
    end
    reject(@()sixgr.truth.buildCommonSignalEnergyObservations(bad,cfg,R,hash,source), ...
        'sixgr:truth:UnexecutedCommonSignalObservation');
end
missing=raw; missing.RAEvidenceTables=struct();
[C,~,U]=sixgr.truth.buildCommonSignalEnergyObservations(missing,cfg,R,hash,source);
assert(height(C)==2 && height(U)==6);
bad=raw; bad.RAEvidenceTables.ra_runtime_stage_waveforms.SelfLoopWaveformUsed(1)=1;
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(bad,cfg,R,hash,source), ...
    'sixgr:truth:UnexecutedCommonSignalObservation');
bad=raw; bad.PRACH.Msg2ScheduledSlot=99;
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(bad,cfg,R,hash,source), ...
    'sixgr:truth:CommonResourceClock');
bad=raw; bad.PBCH=[B;B];
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(bad,cfg,R,hash,source), ...
    'sixgr:truth:DuplicateCommonSignalObservation');
badR=R; badR.UEID(1)=2;
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(raw,cfg,badR,hash,source), ...
    'sixgr:truth:CommonResourceIdentity');
bad=raw; bad.PBCH.ObservationEndSampleExclusive=1000;
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(bad,cfg,R,hash,source), ...
    'sixgr:truth:CommonResourceClock');
badR=R; badR.PopulationScopeJSON(end)=string(jsonencode(struct('ConfigHash',hash,'ExecutionID',"other")));
reject(@()sixgr.truth.buildCommonSignalEnergyObservations(raw,cfg,badR,hash,source), ...
    'sixgr:truth:CommonResourceScope');
% A second observing UE does not erase the common TX; endpoint union owns
% gNB deduplication, not an adapter that discards the second receiver.
other=B; other.UEIndex=2; multiple=raw; multiple.PBCH=[B;other];
[C,~,U]=sixgr.truth.buildCommonSignalEnergyObservations(multiple,cfg,R,hash,source);
assert(height(C)==10 && isempty(U) && nnz(C.UEID==2)==2);

% Exercise the NORMAL three-argument export path, not only the recovery API.
root=string(tempname); mkdir(root); cleanup=onCleanup(@()cleanupFixture(root)); %#ok<NASGU>
air=fullfile(root,'air_interface'); mkdir(air);
layout=sixgr.report.resultLayout(root); sixgr.util.ensureFolder(layout.ComponentCSVDirs.frame_grid);
ledger=table();
for k=1:height(R)
    row=R(k,:); scope=jsondecode(row.PopulationScopeJSON);
    stage=""; attempt=NaN;
    if isfield(scope,'ra_stage'), stage=string(scope.ra_stage); attempt=1; end
    L=table(row.AbsoluteSlotIndex0,row.SymbolIndex0,0,12,row.Direction,row.Channel, ...
        row.CellID,row.UEID,row.AllocationID,"carrier_cp_ofdm", ...
        "runtime_observed_tx_occupancy",1,"declared_accounting_fixture",hash,stage,attempt, ...
        'VariableNames',{'absolute_slot','symbol_index','subcarrier_start','subcarrier_count', ...
        'direction','channel','cell_id','ue_id','allocation_id','grid_domain','evidence_scope', ...
        'active_flag','authority','ConfigHash','ra_stage','ra_attempt_id'});
    ledger=[ledger;L]; %#ok<AGROW>
end
path=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv');
sixgr.util.csvWriteTable(path,ledger);
[e,~,first]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,air,raw);
[e2,~,second]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,air,raw);
assert(~first.CacheHit && second.CacheHit && isequaln(e,e2));
ledger.subcarrier_start(1)=12; sixgr.util.csvWriteTable(path,ledger);
[e3,~,changed]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,air,raw);
assert(~changed.CacheHit && e.SourceSHA256~=e3.SourceSHA256);
% Exporting with incomplete standalone PRACH operands is not qualified;
% common observations still must be present through the normal entry point.
% Restrict to the SI fixture here; separate native-PRACH physical tests own
% its sample clock rather than fabricating a PRACH waveform in this test.
normal=struct('PBCH',B);
out=sixgr.truth.exportLLSEnergyDiagnostics(cfg,air,normal);
assert(out.ResourceLoadAudit.CacheHit && height(out.CommonSignalObservations)==2 && ...
    ~out.ResourceCoverageComplete && ~out.CompleteRunEnergyAvailable);
assert(isfile(out.CommonSignalObservationsCSV) && height(out.UnboundResourceTable)==6);
ok=true;
fprintf('COMMON_SIGNAL_TYPED_PROVENANCE_PASS positive_representations=3 authority_negatives=6 original_regressions=retained\n');
end

function R=resource(channel,id,slot,symbol,ue,scope,source)
direction="DL"; if channel=="PUSCH", direction="UL"; end
R=table(direction,channel,1,ue,id,slot,symbol,24,14,"[0]",string(jsonencode(scope)), ...
    source,"retained_executed_TX_RE_occupancy_not_RF_activity", ...
    'VariableNames',{'Direction','Channel','CellID','UEID','AllocationID','AbsoluteSlotIndex0', ...
    'SymbolIndex0','ResourceGridPRBCount','ResourceSymbolsPerSlot','PRBSet0BasedJSON', ...
    'PopulationScopeJSON','SourceSHA256','Source'});
end

function reject(f,id)
try
    f(); error('test:ExpectedRejection','Expected rejection missing.');
catch failure
    assert(string(failure.identifier)==id,'%s: %s',failure.identifier,failure.message);
end
end

function cleanupFixture(root)
if isfolder(root), rmdir(root,'s'); end
end
