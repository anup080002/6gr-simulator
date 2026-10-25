function ok=testSharedSIB1ReceptionExport()
% Declared producer-shaped serialization/consistency fixture, not new PHY.
setup6GRSimToolkit('Verbose',false);
old=getenv('SIXGR_PERSISTENCE_ENABLED');
cleanup=onCleanup(@()setenv('SIXGR_PERSISTENCE_ENABLED',old)); %#ok<NASGU>
setenv('SIXGR_PERSISTENCE_ENABLED','1');
folder=fullfile(pwd,'results','validation','shared_sib1_export',char(java.util.UUID.randomUUID()));
scope=sixgr.util.CSVWriteReuse.scope(folder); %#ok<NASGU>
layout=sixgr.report.resultLayout(folder);
assert(sixgr.truth.exportSharedSIB1Reception(struct(),folder)=="" && ~isfolder(folder));
assert(sixgr.truth.exportSharedSIB1Reception(struct('SharedSIB1ReceptionTable',table()),folder)=="");
T=repmat(localRow(),257,1);
T.ObservationID="declared_si_observation_"+string((1:height(T))');
T.OriginalFixtureNote=repmat("declared metadata only, ""quoted"""+newline+"not a physical receipt",height(T),1);
% Keep actual stage vocabulary distinct from missing/no-attempt values.
T.SIB1ReceptionAttempted(2)=0; T.SIB1ObservationComplete(2)=0;
for name=["DCICrcPass","DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid","StrictOk"]
    T.(name)(2)=NaN;
end
T.Status(2)="declared_no_attempt";
T.SIB1InputSampleSHA256(2)="";
T.Installed(3)=true; T.DeliveryStatus(3)="installed_original_received_SIB1";
for name=["DCICrcPass","DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid","StrictOk"]
    T.(name)(3)=1;
end
T.Status(3)="declared_success";
T.SIB1PayloadHashRx(3)=string(repmat('b',1,64));
T.SIB1RxTreeHash(3)=string(repmat('c',1,64));
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
% Explicit metadata clock fixture, not a fabricated shared runtime owner.
clock=struct('SampleRateHz',30720000,'Events',struct('NextSampleIndex',15360));
state=struct('SharedSIB1ReceptionTable',T,'CompletedSIB1ObservationIDs',T.ObservationID, ...
    'CfgMobility',cfg,'SharedWaveformStream',clock);
original=state;
primary=fullfile(layout.AirInterfaceCSVDir,'pbch_trials.csv');
sixgr.util.csvWriteTable(primary,table("original_declared_PBCH_row",true, ...
    'VariableNames',{'ObservationID','BCHCrcPass'}),'PreserveSchema',true);
primarySHA=sixgr.util.sha256File(primary);
path=sixgr.truth.exportSharedSIB1Reception(state,folder);
assert(path==string(fullfile(layout.AirInterfaceCSVDir,'sib1_received_trials.csv')) && isequaln(original,state));
types=struct();
for name=string(T.Properties.VariableNames)
    if isstring(T.(name)), types.(name)='string'; end
end
R=sixgr.util.csvReadTable(path,'ColumnTypes',types);
assert(isequal(R.Properties.VariableNames,T.Properties.VariableNames) && height(R)==257);
for name=string(T.Properties.VariableNames)
    if isstring(T.(name))
        v=string(R.(name)); v(ismissing(v))=""; assert(isequal(v,T.(name)));
    elseif islogical(T.(name))
        assert(isequal(logical(R.(name)),T.(name)));
    else
        assert(isequaln(R.(name),T.(name)),'Original numeric operand changed: %s',name);
    end
end
assert(all(isnan([R.DCICrcPass(2),R.DLSCHCrcPass(2)])) && R.SIB1ReceptionAttempted(2)==0);
assert(~any(ismember({'BCHCrcPass','MIBDecoded','SS_RSRP_dBm'},R.Properties.VariableNames)));
sha=sixgr.util.sha256File(path); f=java.io.File(char(path)); stamp=f.lastModified();
before=sixgr.util.CSVWriteReuse.statistics();
sixgr.truth.exportSharedSIB1Reception(state,folder);
after=sixgr.util.CSVWriteReuse.statistics();
assert(after.ReusedWrites==before.ReusedWrites+1 && after.PublishedWrites==before.PublishedWrites && ...
    f.lastModified()==stamp && sixgr.util.sha256File(path)==sha);
for mutation=["missing_column","numeric_identity","missing_hash","bad_hash","duplicate", ...
        "uncompleted","early_delivery","reversed_capture","numeric_installation", ...
        "invalid_flag","new_BCH","fake_PBCH","success_without_attempt", ...
        "installed_failure","false_status","false_DLSCH","missing_success_payload", ...
        "wrong_sample_rate","future_boundary"]
    bad=state; B=bad.SharedSIB1ReceptionTable;
    switch mutation
        case "missing_column", B.RecoverySHA256=[];
        case "numeric_identity", B.ObservationID=ones(height(B),1);
        case "missing_hash", B.RawPostRFInputSHA256(end)="";
        case "bad_hash", B.DecoderInputSHA256(end)="not_original_sha";
        case "duplicate", B.ObservationID(end)=B.ObservationID(1);
        case "uncompleted", bad.CompletedSIB1ObservationIDs(end)=[];
        case "early_delivery", B.DeliverySlot1Based(end)=1;
        case "reversed_capture", B.ObservationEndSampleExclusive(end)=B.ObservationStartSample(end);
        case "numeric_installation", B.Installed=double(B.Installed);
        case "invalid_flag", B.DCICrcPass(end)=2;
        case "new_BCH", B.NewBCHReceptionAttempted(end)=1;
        case "fake_PBCH", B.BCHCrcPass=true(height(B),1);
        case "success_without_attempt", B.DCICrcPass(2)=1;
        case "installed_failure", B.Installed(end)=true;
        case "false_status", B.DeliveryStatus(end)="installed_original_received_SIB1";
        case "false_DLSCH", B.DLSCHCrcPass(end)=1;
        case "missing_success_payload", B.SIB1PayloadHashRx(3)="";
        case "wrong_sample_rate", B.ObservationSampleRateHz(end)=15360000;
        case "future_boundary", B.DeliverySlot1Based(end)=3;
    end
    bad.SharedSIB1ReceptionTable=B;
    localReject(@()sixgr.truth.exportSharedSIB1Reception(bad,folder));
    assert(sixgr.util.sha256File(path)==sha,'Reject before changing original output bytes.');
end
assert(sixgr.util.sha256File(primary)==primarySHA && isequaln(original,state));
fprintf('SHARED_SIB1_EXPORT_PASS declared_257_rows_20_negatives %s\n',folder);
ok=true;
end

function T=localRow()
h=string(repmat('a',1,64));
T=table("declared_observation",1,1,0,2,0,15360,30720000, ...
    "declared_received_mib_generation",h,h,h,false,"received_SI_not_accepted", ...
    'VariableNames',{'ObservationID','UEId','ServingCell','ResourceAbsoluteSlot0Based', ...
    'DeliverySlot1Based','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ReceivedMIBGenerationID','RawPostRFInputSHA256', ...
    'DecoderInputSHA256','RecoverySHA256','Installed','DeliveryStatus'});
for name=["Status","FailureReason","FailureIdentifier","SIB1InputSampleSHA256", ...
        "SIB1PayloadHashRx","SIB1RxTreeHash","PriorBCHContextSHA256"]
    T.(name)="";
end
T.Status="declared_monitoring_miss";
T.SIB1InputSampleSHA256=h; T.PriorBCHContextSHA256=h;
for name=["Crash","SIB1ReceptionAttempted","SIB1ObservationComplete","DCICrcPass", ...
        "DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid","StrictOk","NewBCHReceptionAttempted"]
    T.(name)=0;
end
T.SIB1ReceptionAttempted=1; T.SIB1ObservationComplete=1;
end

function localReject(f)
try, f(); catch ex
    assert(startsWith(string(ex.identifier),"sixgr:truth:SIB1Export"), ...
        'Unexpected rejection: %s / %s',ex.identifier,ex.message);
    return;
end
error('test:ExpectedSIB1ExportRejection','Malformed original SI evidence was accepted.');
end
