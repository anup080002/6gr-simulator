function ok=testCausalSIB1ReceptionAudit(originalRunFolder)
% Declared CSV/clock/consumer audit; optional retained original PHY receipts.
% Neither fixture nor successful audit reruns or independently authenticates IQ.
arguments
    originalRunFolder (1,1) string = ""
end
setup6GRSimToolkit('Verbose',false);
folder=string(fullfile(pwd,'results','validation','causal_sib1_audit',char(java.util.UUID.randomUUID())));
layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
scope=sixgr.util.CSVWriteReuse.scope(folder); %#ok<NASGU>
path=string(fullfile(layout.AirInterfaceCSVDir,'sib1_received_trials.csv'));
runId="declared_causal_SI_fixture"; configHash="declared_config_identity";
sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',runId, ...
    'ExecutionID',"declared_audit_execution",'ConfigHash',configHash));
cleanup=onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
sixgr.runtime.RuntimeCallLedger.record("declared_SI_audit_fixture","AUDIT","",struct());
ledger=sixgr.runtime.RuntimeCallLedger.flush();
stage=struct('stage_id',"sib1_type0_pdcch_pdsch",'order',10,'subsystem',"initial_access", ...
    'required',true,'always_required',true,'consumer_functions',"declared_SI_audit_fixture", ...
    'measurement_artifact',"air_interface/csv/sib1_received_trials.csv", ...
    'measured_fields',{{'DCICrcPass','DLSCHCrcPass','SIB1ASN1DecodeOk','SIB1SemanticValid','Installed'}}, ...
    'measurement_min_rows',1,'success_field',"Installed",'success_mode',"any_true", ...
    'dependency_stages',strings(0,1));
dependent=stage; dependent.stage_id="declared_downstream"; dependent.order=20;
dependent.dependency_stages="sib1_type0_pdcch_pdsch";
audit=struct('enabled',true,'required',true,'stages',[stage dependent],'parameter_bindings',struct([]));
scfg=struct('validation',struct('causal_phy_chain_audit',audit));
cfg=struct('meta',struct('configHash',configHash), ...
    'phy',struct('carrier',struct('SubcarrierSpacing',30,'CyclicPrefix',"normal")));
T=localRows(257); original=T;
write(T); result=check();
assert(result.Ok&&all(result.DetailTable.StrictPass)&&result.DetailTable.MeasuredFiniteRows(1)==257);
assert(isequaln(T,original));
for mutation=["missing_hash_column","missing_hash","bad_hash","decoder_hash", ...
        "duplicate_id","duplicate_capture","wrong_prior_generation","wrong_generation_clock", ...
        "wrong_cell_generation","wrong_fs_generation","early_delivery","partial_capture", ...
        "numeric_identity","invalid_flag","false_install_status","installed_failed_CRC", ...
        "success_without_attempt","new_BCH","missing_payload","proxy"]
    bad=T;
    switch mutation
        case "missing_hash_column", bad.RecoverySHA256=[];
        case "missing_hash", bad.RawPostRFInputSHA256(end)="";
        case "bad_hash", bad.PriorBCHContextSHA256(end)="not_a_hash";
        case "decoder_hash", bad.SIB1InputSampleSHA256(end)=string(repmat('f',1,64));
        case "duplicate_id", bad.ObservationID(end)=bad.ObservationID(1);
        case "duplicate_capture"
            names=["ResourceAbsoluteSlot0Based","ObservationStartSample","ObservationEndSampleExclusive"];
            for name=names, bad.(name)(end)=bad.(name)(1); end
        case "wrong_prior_generation", bad.PriorBCHContextSHA256(end)=string(repmat('f',1,64));
        case "wrong_generation_clock"
            bad.ObservationStartSample(end)=bad.ObservationStartSample(end)+1;
            bad.ObservationEndSampleExclusive(end)=bad.ObservationEndSampleExclusive(end)+1;
        case "wrong_cell_generation", bad.ServingCell(end)=2;
        case "wrong_fs_generation", bad.ObservationSampleRateHz(end)=15360000;
        case "early_delivery", bad.DeliverySlot1Based(end)=1;
        case "partial_capture", bad.ObservationEndSampleExclusive(end)=bad.ObservationEndSampleExclusive(end)-1;
        case "numeric_identity", bad.ObservationID=(1:height(bad))';
        case "invalid_flag", bad.DCICrcPass(end)=2;
        case "false_install_status", bad.DeliveryStatus(end)="received_SI_not_accepted";
        case "installed_failed_CRC", bad.DLSCHCrcPass(end)=0;
        case "success_without_attempt", bad.SIB1ReceptionAttempted(end)=0;
        case "new_BCH", bad.NewBCHReceptionAttempted(end)=1;
        case "missing_payload", bad.SIB1PayloadHashRx(end)="";
        case "proxy", bad.ProxyUsed=false(height(bad),1); bad.ProxyUsed(end)=true;
    end
    write(bad); result=check();
    assert(~result.Ok&&~result.DetailTable.StrictPass(1)&& ...
        result.DetailTable.StageOutcome(2)=="BLOCKED_BY_DEPENDENCY", ...
        'Malformed late SI receipt qualified causal installation: %s',mutation);
end
% Genuine failed attempts remain measured failures; absent/no-attempt rows
% cannot acquire success from another file or generic combined PBCH status.
miss=T; miss.Installed(:)=false; miss.DeliveryStatus(:)="received_SI_not_accepted";
for name=["DCICrcPass","DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid","StrictOk"]
    miss.(name)(:)=0;
end
write(miss); result=check();
assert(~result.Ok&&result.DetailTable.StageOutcome(1)=="FAILED_MEASUREMENT");
miss.SIB1ReceptionAttempted(:)=0; miss.SIB1ObservationComplete(:)=0;
write(miss); result=check();
assert(~result.Ok&&result.DetailTable.StageOutcome(1)=="CALLED_NO_MEASUREMENT");
write(T);
badLedger=ledger; badLedger.RunId(:)="different_original_run";
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir,'runtime_call_ledger.csv'),badLedger,'PreserveSchema',true);
result=check(); assert(~result.Ok&&~result.DetailTable.ConsumerObserved(1));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir,'runtime_call_ledger.csv'),ledger,'PreserveSchema',true);
binding=struct('parameter_id',"unobserved_original_consumer",'subsystem',"unit", ...
    'scenario_path',"declaredValue",'runtime_path',"declaredValue",'required',true, ...
    'consumer_functions',"never_executed_consumer");
scfg.declaredValue=4; cfg.declaredValue=4;
scfg.validation.causal_phy_chain_audit.parameter_bindings=binding;
result=check();
assert(all(result.DetailTable.StrictPass)&&~result.Ok&&result.ParameterBindingFailureCount==1);
if strlength(originalRunFolder)>0
    localRetained(originalRunFolder,folder,stage,cfg);
end
fprintf('CAUSAL_SIB1_AUDIT_PASS declared_rows257 negatives20 dependency_and_parameter_failclosed retained=%d PHY_reexecution=0\n', ...
    strlength(originalRunFolder)>0);
ok=true;
    function write(value)
        sixgr.util.csvWriteTable(path,value,'PreserveSchema',true,'RoundTripNumericText',true);
    end
    function out=check()
        before=sixgr.util.sha256File(path);
        out=sixgr.truth.exportCausalPHYChainAudit(folder,scfg,cfg,'RunId',runId,'WriteArtifacts',false);
        assert(sixgr.util.sha256File(path)==before,'Audit must not rewrite the original SI table.');
    end
end

function T=localRows(n)
h=string(repmat('a',1,64)); slot=(10:10+n-1)';
T=table("declared_si_"+string((1:n)'),ones(n,1),ones(n,1),slot,slot+3, ...
    slot*15360+9,(slot+1)*15360+9,repmat(30720000,n,1), ...
    'VariableNames',{'ObservationID','UEId','ServingCell','ResourceAbsoluteSlot0Based', ...
    'DeliverySlot1Based','ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz'});
for name=["ReceivedMIBGenerationID","RawPostRFInputSHA256","DecoderInputSHA256", ...
        "RecoverySHA256","PriorBCHContextSHA256","SIB1InputSampleSHA256","SIB1PayloadHashRx","SIB1RxTreeHash"]
    T.(name)=repmat(h,n,1);
end
T.Installed=true(n,1); T.DeliveryStatus=repmat("installed_original_received_SIB1",n,1);
for name=["SIB1ReceptionAttempted","SIB1ObservationComplete","DCICrcPass", ...
        "DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid","StrictOk"]
    T.(name)=ones(n,1);
end
T.Crash=zeros(n,1); T.NewBCHReceptionAttempted=zeros(n,1);
end

function localRetained(original,folder,stage,cfg)
relative=["air_interface/csv/sib1_received_trials.csv","reports/csv/runtime_call_ledger.csv"];
copyFolder=fullfile(folder,'retained_original_readonly_copy');
for path=relative
    source=fullfile(original,path); destination=fullfile(copyFolder,path);
    assert(isfile(source),'Requested retained evidence is required, not substituted.');
    sixgr.util.ensureFolder(fileparts(destination)); copyfile(source,destination);
    assert(sixgr.util.sha256File(source)==sixgr.util.sha256File(destination));
end
L=sixgr.util.csvReadTable(fullfile(copyFolder,relative(2)),'TextType','string');
assert(numel(unique(L.RunId))==1&&numel(unique(L.ConfigHash))==1);
cfg.meta.configHash=string(L.ConfigHash(1));
stage.consumer_functions="sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB";
audit=struct('enabled',true,'required',true,'stages',stage,'parameter_bindings',struct([]));
scfg=struct('validation',struct('causal_phy_chain_audit',audit));
out=sixgr.truth.exportCausalPHYChainAudit(copyFolder,scfg,cfg,'RunId',string(L.RunId(1)),'WriteArtifacts',false);
assert(out.Ok&&out.DetailTable.MeasuredFiniteRows>=1,'Retained independent SI receipt did not qualify its original consumer.');
for path=relative
    assert(sixgr.util.sha256File(fullfile(original,path))==sixgr.util.sha256File(fullfile(copyFolder,path)));
end
end
