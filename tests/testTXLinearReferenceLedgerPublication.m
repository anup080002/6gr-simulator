function ok=testTXLinearReferenceLedgerPublication()
% Actual small RF calls and original owner; no channel/receiver qualification.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
cfg=struct(); cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.pa.enable=true; cfg.rf.tx.cfo_Hz=70;
cfg.rf.frontend.pa=struct('profile_id','ledger_rapp','version','1','model','rapp', ...
    'input_backoff_db',2,'reference_domain','waveform_samples','smoothness',2,'saturation_amplitude',.4);
cfg.rf.txLinearReference=struct('Enabled',true,'Model',"fixed_first_order_pa_identity_dac", ...
    'Classification',"optional_research_experiment",'RequirementClass',"IMPLEMENTATION_POLICY");
fs=7.68e6; origin=17; epoch=7; endpoint="declared_actual_tx";
stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,2,origin,epoch,false);
model=sixgr.rf.InstalledTXLinearReference.freeze(stream,endpoint,cfg.rf.txLinearReference);
library=model.capsule();
inventory=table(endpoint,"TX","DL",2,'VariableNames',{'EndpointID','Role','Direction','PhysicalPortCount'});
ledger=sixgr.truth.RFEndpointExecutionLedger(fs,origin,epoch,inventory);
ledger.installTXLinearReferenceLibrary(library);
e=ledger.read(); assert(isempty(e.TXLinearReferenceIntervals)&&~e.TXLinearReferenceCompleteFromOrigin);
badLibrary=library; badLibrary.NumAntennas=3;
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(sixgr.truth.txLinearReferenceInterval(),badLibrary,e.Intervals), ...
    'RF:TXLinearReferenceRegistration');
next=origin;
for n=[31 19]
    x=.7*exp(1j*((0:n-1).'/7+[0 .3]));
    if next>origin, x(:)=0; end
    chunk=sixgr.phy.waveform.WaveformChunk(x,next);
    [model,out,receipt]=model.apply(stream,endpoint,chunk,epoch);
    % Match the shared original ingress owner: amplitudes belong to the
    % installed PowerContext, not to a model's invented post-hoc unit.
    power=sixgr.rf.PowerContext(stream.Configuration,stream.Chain.Direction);
    out.Replay.WaveformAmplitudeUnit=string(power.WaveformAmplitudeUnit);
    execution=struct('StartSample',next,'EndSampleExclusive',next+n, ...
        'TX',struct('ID',endpoint,'Replay',out.Replay),'RX',struct('ID',{},'Replay',{}), ...
        'TXLinearReferences',struct('ID',endpoint,'Receipt',receipt));
    before=ledger.read();
    missing=execution; missing.TXLinearReferences=struct('ID',{},'Receipt',{});
    reject(@()ledger.append(missing),'sixgr:truth:TXLinearReferenceMissing');
    corrupted=execution;
    corrupted.TXLinearReferences.Receipt.Adapter.OriginalRFOutputSHA256=repmat('a',1,64);
    reject(@()ledger.append(corrupted),'sixgr:truth:TXLinearReferenceClosure');
    assert(isequaln(before,ledger.read()),'Failed model validation must not partly commit actual RF records.');
    ledger.append(execution); next=next+n;
end
e=ledger.read(); T=e.TXLinearReferenceIntervals;
assert(height(T)==2&&e.TXLinearReferenceCompleteFromOrigin&&all(T.PhysicalIntervalCommitted)&& ...
    all(T.OriginalOwnerBindingVerified)&&T.ResidualEnergy(1)>0&&T.ReferenceResidualCrossEnergy(1)<0&& ...
    ~any(T.StandardizedPowerAccuracyQualified|T.HardwareQualified|T.ReceiverEstimatorInput));
assert(T.ReferenceEnergy(2)==0&&T.ResidualEnergy(2)==0&&T.ReferenceResidualCrossEnergy(2)==0, ...
    'The all-zero original interval must remain represented without manufactured energy.');
for k=1:height(T)
    r=jsondecode(char(T.ReceiptJSON(k)));
    assert(~r.Adapter.OriginalOwnerVerified&&~r.Adapter.SharedRuntimeIntegrationQualified&& ...
        ~r.Adapter.StandardizedPowerAccuracyQualified&&r.OriginalOwnerBindingVerified);
end
reject(@()ledger.installTXLinearReferenceLibrary(library),'sixgr:truth:TXLinearReferenceInstallation');
bad=T; bad(2,:)=[];
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(bad,library,e.Intervals,e.ChainPowerIntervals),'sixgr:truth:TXLinearReferenceClosure');
bad=T; bad.ReferenceResidualCrossEnergy(1)=abs(bad.ReferenceResidualCrossEnergy(1));
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(bad,library,e.Intervals,e.ChainPowerIntervals),'sixgr:truth:TXLinearReferenceClosure');
bad=T; bad.StandardizedPowerAccuracyQualified(1)=true;
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(bad,library,e.Intervals,e.ChainPowerIntervals),'sixgr:truth:TXLinearReferenceClosure');
bad=T; r=jsondecode(char(bad.ReceiptJSON(1))); r.Adapter.Phase_rad=zeros(3,2);
bad.ReceiptJSON(1)=string(jsonencode(r));
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(bad,library,e.Intervals,e.ChainPowerIntervals),'sixgr:truth:TXLinearReferenceClosure');
wrongUnit=e.ChainPowerIntervals;
if string(library.WaveformAmplitudeUnit)=="sqrt_mW", otherUnit="normalized_complex_baseband";
else, otherUnit="sqrt_mW"; end
wrongUnit.WaveformAmplitudeUnit(:)=otherUnit;
assert(all(wrongUnit.WaveformAmplitudeUnit~=e.ChainPowerIntervals.WaveformAmplitudeUnit));
reject(@()sixgr.truth.validateTXLinearReferenceIntervals(T,library,e.Intervals,wrongUnit),'sixgr:truth:TXLinearReferenceClosure');
cfg.meta.configHash=repmat('b',1,64); cfg.run.executionID='actual_rf_linear_model_ledger';
cfg.run.scenarioID=cfg.run.executionID; cfg.run.runTag=cfg.run.executionID;
folder=tempname; airFolder=fullfile(folder,'air_interface'); mkdir(airFolder);
% Enabled output cannot silently vanish when neither original owner nor
% archive exists. Disabled legacy/report-only execution remains optional.
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct()), ...
    'sixgr:truth:TXLinearReferenceMissingOwner');
disabled=cfg; disabled.rf.txLinearReference.Enabled=false;
absent=sixgr.truth.publishRFEndpointExecutionLedger(disabled,airFolder,struct());
assert(~absent.Available&&isempty(absent.Evidence)&&absent.TXLinearReferenceModelCSV=="");
p=sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct('RFEndpointExecutionEvidence',e));
q=sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct());
assert(p.TXLinearReferenceModelCSV~=""&&p.TXLinearReferenceLibraryMAT~=""&& ...
    q.Evidence.TXLinearReferenceCompleteFromOrigin&& ...
    isequaln(p.Evidence.TXLinearReferenceIntervals,q.Evidence.TXLinearReferenceIntervals)&& ...
    isequaln(p.Evidence.TXLinearReferenceLibrary,q.Evidence.TXLinearReferenceLibrary));
core=sixgr.truth.RFEndpointExecutionLedger.emptyTable();
assert(isequaln(e.Intervals,q.Evidence.Intervals(:,core.Properties.VariableNames)), ...
    'Model publication must not rewrite actual RF samples/power metadata.');
bad=q.Evidence.TXLinearReferenceIntervals; bad.ResidualEnergy(1)=42;
sixgr.util.csvWriteTable(p.TXLinearReferenceModelCSV,bad);
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct()),'sixgr:truth:TXLinearReferenceFileHash');
sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct('RFEndpointExecutionEvidence',e));
missing=e; missing.TXLinearReferenceIntervals=sixgr.truth.txLinearReferenceInterval();
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct('RFEndpointExecutionEvidence',missing)), ...
    'sixgr:truth:TXLinearReferenceClosure');
wrong=cfg; wrong.rf.txLinearReference.Enabled=false;
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(wrong,airFolder,struct('RFEndpointExecutionEvidence',e)), ...
    'sixgr:truth:TXLinearReferenceCompleteness');
assert(isequal(prior,rng),'RF model ledger/publication must not consume global RNG.');
fprintf('TX_LINEAR_REFERENCE_LEDGER_PUBLICATION_PASS actual_RF=1 original_owner=1 signed_cross=1 primary_RF_unchanged=1 standardized_power=0\n');
ok=true;
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingGuard','Expected %s.',id);
end
