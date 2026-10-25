function ok=testSRSReceivedPilotEVM()
% Declared arithmetic fixture: CDM overlap, all RX branches and exact export.
% Physical OFDM and scoring independence are tested by testSRSReceivedScoringClock.
setup6GRSimToolkit('Verbose',false);
[empty,pairs]=sixgr.phy.srs.measureReceivedPilotEVM();
assert(isnan(empty.EVM_rms) && empty.EVMSymbolCount==0 && isempty(pairs));
K=24; L=14; R=3; P=4;
resources=[1;7;80];
indices=resources+(0:P-1)*K*L;
desired=complex(zeros(K,L,R));
for r=1:R
    desired(resources+(r-1)*K*L)=r+0.25i;
end
received=desired;
for r=1:R
    received(resources+(r-1)*K*L)=received(resources+(r-1)*K*L)+.1*r;
end
e=struct('Source',"same_executed_desired_link_received_pilot_grid", ...
    'ReceiverEstimatorInput',false,'GainOrPhaseFitted',false, ...
    'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0, ...
    'ReferencePlane',"declared_component_same_RX_clock");
[out,pairs]=sixgr.phy.srs.measureReceivedPilotEVM(received,desired,indices,P,49,e);
assert(out.EVMSymbolCount==R*numel(resources), ...
    'CDM port overlap must not multiply the received-sample population.');
assert(abs(out.EVMErrorEnergy-.42)<1e-12 && ...
    abs(out.EVMReferenceEnergy-42.5625)<1e-12 && ...
    abs(out.EVM_rms-sqrt(.42/42.5625))<1e-12);
assert(numel(pairs)==R && isequal(pairs(1).SampleIndex,resources-1));
root=fullfile(pwd,'logs','lls_repairs', ...
    "srs_pilot_evm_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
row=struct2table(out); row.Slot=50; row.UEIndex=1; row.Direction="UL";
row=sixgr.report.retainControlEVMPairs(root,row,pairs);
assert(row.ControlEVMSamplesJSON=="" && row.ControlEVMSamplesCount==9);
path=sixgr.report.exportControlEVMSamples(fullfile(root,'air_interface','csv','srs_trials.csv'),row);
T=sixgr.util.csvReadTable(path,'TextType','string');
ref=complex(T.ReferenceReal,T.ReferenceImag); rx=complex(T.MeasuredReal,T.MeasuredImag);
assert(height(T)==9 && all(T.SignalName=="SRS") && ...
    all(T.MeasurementDomain=="received_resource_elements") && ...
    ~any(T.StandardizedModulationEVMQualified));
assert(abs(sum(abs(rx-ref).^2)-out.EVMErrorEnergy)<1e-12);
assert(abs(sum(abs(ref).^2)-out.EVMReferenceEnergy)<1e-12);
% The physical shared-SRS producer now requires an isolated emitted
% component, which has a distinct source from the legacy desired-link
% diagnostic. Preserve that stronger authority through pair storage/export.
isolated=e;
isolated.Source="same_executed_isolated_emitted_SRS_received_pilot_grid";
isolated.IsolatedComponentProved=true;
[isolatedOut,isolatedPairs]=sixgr.phy.srs.measureReceivedPilotEVM( ...
    received,desired,indices,P,49,isolated);
assert(all([isolatedPairs.IsolatedComponentProved]) && ...
    isolatedOut.EVM_rms==out.EVM_rms && ...
    isolatedOut.EVMReferenceSource==isolated.Source);
isolatedRow=struct2table(isolatedOut);
isolatedRow.Slot=50; isolatedRow.UEIndex=1; isolatedRow.Direction="UL";
isolatedRow=sixgr.report.retainControlEVMPairs(root,isolatedRow,isolatedPairs);
trialPath=fullfile(root,'air_interface','csv','srs_trials.csv');
isolatedPath=sixgr.report.exportControlEVMSamples(trialPath,isolatedRow);
isolatedTable=sixgr.util.csvReadTable(isolatedPath,'TextType','string');
assert(height(isolatedTable)==9 && all(isolatedTable.ReferenceSource==isolated.Source));
assert(isequal(isolatedTable.ReferenceReal,T.ReferenceReal) && ...
    isequal(isolatedTable.MeasuredReal,T.MeasuredReal));
for fault=["missing_proof","false_proof","numeric_proof","vector_proof","unknown_source","wrong_signal"]
    rejectedPairs=isolatedPairs;
    switch fault
        case "missing_proof", rejectedPairs=rmfield(rejectedPairs,'IsolatedComponentProved');
        case "false_proof", [rejectedPairs.IsolatedComponentProved]=deal(false);
        case "numeric_proof", [rejectedPairs.IsolatedComponentProved]=deal(1);
        case "vector_proof", [rejectedPairs.IsolatedComponentProved]=deal([true true]);
        case "unknown_source", [rejectedPairs.ReferenceSource]=deal("unproved_reference");
        case "wrong_signal", [rejectedPairs.SignalName]=deal("TRS");
    end
    rejectedRow=sixgr.report.retainControlEVMPairs(root,isolatedRow,rejectedPairs);
    reject(@()sixgr.report.exportControlEVMSamples(trialPath,rejectedRow), ...
        'sixgr:report:ControlEVMPairAuthority');
end
for malformed={false,1,[true true]}
    bad=isolated; bad.IsolatedComponentProved=malformed{1};
    reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired,indices,P,49,bad), ...
        'sixgr:phy:srs:InvalidEVMAuthority');
end
bad=rmfield(isolated,'IsolatedComponentProved');
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired,indices,P,49,bad), ...
    'sixgr:phy:srs:InvalidEVMAuthority');
exact=sixgr.phy.srs.measureReceivedPilotEVM(desired,desired,indices,P,49,e);
assert(exact.EVM_rms==0,'Do not epsilon-floor exact zero error.');
wrong=sixgr.phy.srs.measureReceivedPilotEVM(received,2*desired,indices,P,49,e);
assert(wrong.EVM_rms>out.EVM_rms,'No fitted normalization may hide wrong reference amplitude.');
bad=e; bad.GainOrPhaseFitted=true;
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired,indices,P,49,bad), ...
    'sixgr:phy:srs:InvalidEVMAuthority');
bad=e; bad.ReceiverEstimatorInput=true;
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired,indices,P,49,bad), ...
    'sixgr:phy:srs:InvalidEVMAuthority');
bad=received; bad(resources(1))=NaN;
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(bad,desired,indices,P,49,e), ...
    'sixgr:phy:srs:MissingEVMPilotSamples');
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired(:,:,1),indices,P,49,e), ...
    'sixgr:phy:srs:EVMPilotGridMismatch');
badIndices=indices; badIndices(2)=badIndices(1);
reject(@()sixgr.phy.srs.measureReceivedPilotEVM(received,desired,badIndices,P,49,e), ...
    'sixgr:phy:srs:InvalidEVMPilotResources');
ok=true;
fprintf('SRS_RECEIVED_PILOT_EVM_PASS unique_REs=3 physical_RX=3 CDM_ports=4 root=%s\n',root);
end
function reject(action,identifier)
try
    action(); error('test:ExpectedFailure','Expected evidence rejection.');
catch cause
    assert(strcmp(cause.identifier,identifier),'%s',cause.identifier);
end
end
