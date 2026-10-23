function ok=testRFEndpointExecutionLedger()
% Actual bounded RF operator execution; not hardware energy qualification.
setup6GRSimToolkit('Verbose',false);
fs=122.88e6; epoch=7; first=117;
inventory=table(["gnb_1";"ue_1";"ue_1_rx";"gnb_1_rx"], ...
    ["TX";"TX";"RX";"RX"],["DL";"UL";"DL";"UL"],[64;4;4;64], ...
    'VariableNames',{'EndpointID','Role','Direction','PhysicalPortCount'});
cfg=struct(); cfg.rf.rx.cfo_Hz=301;
owners=cell(height(inventory),1);
for k=1:height(inventory)
    owners{k}=sixgr.rf.runtime.RFImpairmentStream(cfg,lower(inventory.Role(k)), ...
        inventory.Direction(k),fs,inventory.PhysicalPortCount(k),first,epoch,false);
end
ledger=sixgr.truth.RFEndpointExecutionLedger(fs,first,epoch,inventory);
initial=ledger.read(); assert(isempty(initial.Intervals)&&~initial.CompleteFromOrigin);
prior=rng; current=first; expectedInput=zeros(4,1); expectedOutput=zeros(4,1);
folder=tempname; mkdir(folder);
for step=1:3
    n=[17 23 11]; n=n(step);
    execution=struct('StartSample',current,'EndSampleExclusive',current+n, ...
        'TX',struct('ID',{},'Replay',{}),'RX',struct('ID',{},'Replay',{}));
    for k=1:height(inventory)
        x=complex(zeros(n,inventory.PhysicalPortCount(k)));
        if step~=2
            x=reshape(exp(1i*(1:numel(x))/19),size(x))*.1;
            if step==3, x=x*1e-180; end
        end
        r=owners{k}.apply(sixgr.phy.waveform.WaveformChunk(x,current),epoch);
        role=inventory.Role(k);
        execution.(role)(end+1)=struct('ID',inventory.EndpointID(k),'Replay',r.Replay);
        expectedInput(k)=expectedInput(k)+sum(abs(x(:)).^2);
        expectedOutput(k)=expectedOutput(k)+sum(abs(r.Waveform(:)).^2);
    end
    ledger.append(execution); current=current+n;
    if step==1
        % MAT round trip preserves recorded prefix and the next commit clock.
        save(fullfile(folder,'ledger.mat'),'ledger','-v7');
        restored=load(fullfile(folder,'ledger.mat'),'ledger');
        ledger=restored.ledger;
    end
end
assert(isequal(prior,rng),'Recording must not consume random draws.');
e=ledger.read(); assert(e.CompleteFromOrigin && ~e.CompleteFromSampleZero && ...
    ~e.HardwareOperatingStateAvailable && height(e.Intervals)==12);
assert(e.ChainPowerCompleteFromOrigin && height(e.ChainPowerIntervals)==12);
assert(all(isnan(e.ChainPowerIntervals.PostPATotalPower_mW)), ...
    'Undeclared RF samples must not become absolute watts.');
assert(all(e.Coverage.ExecutedSamples==51) && all(e.Coverage.IntervalCount==3));
for k=1:height(inventory)
    rows=e.Intervals(e.Intervals.EndpointID==inventory.EndpointID(k),:);
    assert(abs(sum(rows.InputSquaredMagnitudeSum)-expectedInput(k))<1e-10 && ...
        abs(sum(rows.OutputSquaredMagnitudeSum)-expectedOutput(k))<1e-10);
    assert(nnz(rows.InputIsAllZero)==1 && all(contains(rows.OperatingState,'not_inferred')));
    assert(rows.InputMeanSquare(3)==0 && ~rows.InputIsAllZero(3), ...
        'Underflow of squared magnitude must not classify nonzero RF input samples as zero.');
end
before=ledger.read();
reject(@()ledger.append(execution),'sixgr:truth:RFExecutionClock');
assert(isequaln(before,ledger.read()),'Rejected duplicate commit must not change the ledger.');
next=execution; next.StartSample=current; next.EndSampleExclusive=current+11;
for role=["TX","RX"]
    for k=1:numel(next.(role))
        next.(role)(k).Replay.RFStreamStartSample=current;
        next.(role)(k).Replay.RFStreamEndSampleExclusive=current+11;
    end
end
next.TX(1).Replay.RFChainPowerEvidence.PostPA.TotalMeanSquare=42;
reject(@()ledger.append(next),'sixgr:truth:RFChainPowerClosure');
assert(isequaln(before,ledger.read()),'Rejected chain measurements must not partly commit an interval.');
bad=e; bad.Intervals=bad.Intervals(2:end,:);
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionCoverage');
bad=e; bad.Intervals(bad.Intervals.EndpointID=="gnb_1",:)=[];
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionEndpointCoverage');
bad=e; bad.Intervals.OutputSquaredMagnitudeSum(1)=999;
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionPower');
bad=e; bad.Intervals.OperatingState(:)="sleep";
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionScope');
bad=e; bad.Intervals.InputWaveformSHA256(1)="";
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionHash');
bad=e; bad.Intervals.SampleRateHz(1)=fs/2;
reject(@()sixgr.truth.RFEndpointExecutionLedger.validate(bad),'sixgr:truth:RFExecutionCoverage');
% Normal exporter accepts a portable copy of actual producer evidence and
% report-only calls recover it with both lifecycle and content checks.
cfg.meta.configHash=repmat('a',1,64); cfg.run.executionID='rf_ledger_fixture';
cfg.run.scenarioID='rf_ledger_fixture'; cfg.run.runTag='rf_ledger_fixture_run';
airFolder=fullfile(folder,'air_interface'); mkdir(airFolder);
published=sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct('RFEndpointExecutionEvidence',e));
read=sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct());
assert(published.Available && read.Available && ~read.HardwareOperatingStateAvailable && ...
    ~read.Evidence.CompleteFromSampleZero && read.Evidence.OriginSample==first && ...
    isequaln(published.Evidence.Intervals,read.Evidence.Intervals));
assert(published.ChainPowerCSV~="" && read.Evidence.ChainPowerCompleteFromOrigin && ...
    isequaln(published.Evidence.ChainPowerIntervals,read.Evidence.ChainPowerIntervals));
chain=read.Evidence.ChainPowerIntervals; chain.OutputTotalMeanSquare(1)=42;
sixgr.util.csvWriteTable(published.ChainPowerCSV,chain);
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct()),'sixgr:truth:RFChainPowerFileHash');
sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct('RFEndpointExecutionEvidence',e));
wrong=cfg; wrong.run.executionID='other';
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(wrong,airFolder,struct()),'sixgr:truth:RFExecutionFileScope');
changed=read.Evidence.Intervals; changed.InputMeanSquare(1)=42;
sixgr.util.csvWriteTable(published.CSV,changed);
reject(@()sixgr.truth.publishRFEndpointExecutionLedger(cfg,airFolder,struct()),'sixgr:truth:RFExecutionFileHash');
ok=true; disp('RF_ENDPOINT_EXECUTION_LEDGER_PASS actual_RF=1 zero_input_retained=1 checkpoint_roundtrip=1 no_hardware_state_inference=1');
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingGuard','Expected %s.',id);
end
