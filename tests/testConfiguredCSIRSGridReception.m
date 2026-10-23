function [ok,fixture]=testConfiguredCSIRSGridReception(scs,nPRB)
% CSI-only OFDM component: no PDSCH assignment, decoder or HARQ state.
% This tests the extracted receiver, not shared scheduling or acquisition.
if nargin<1, scs=15; end
if nargin<2, nPRB=25; end
carrier=nrCarrierConfig('NSizeGrid',nPRB,'SubcarrierSpacing',scs,'NCellID',17,'NSlot',1);
cfg=struct();
cfg.run.strictMode=true;
cfg.channel.model='AWGN';
cfg.phy.csirs=struct('enable',true,'period_slots',5,'offset_slots',1, ...
    'numResources',1,'nPorts',4,'rowNumber',4,'density','one', ...
    'symbolLocations',6,'subcarrierLocations',0,'rbOffset',0,'numRB',nPRB, ...
    'runtimeChannelEstimator','nr_channel_estimate');
cfg.phy.mimo=struct('strict',true,'measurementMaxAgeSlots',8);
cfg.phy.csi.reportConfiguration=struct('Ports',4);
cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.lls6g.userContext=struct('RuntimeUEIndex',1,'RuntimeCurrentSlot',2);
cfg.lls6g.runtimePowerContext.WaveformAmplitudeUnit='sqrt_mW';
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP','configured_snr_is_link_authority',true);
[indices,symbols]=sixgr.phy.refsig.csirs(carrier,cfg);
assert(~isempty(indices));
tx=nrResourceGrid(carrier,4); tx(indices)=symbols;
H=[.8 0 .6 0;0 .6 0 .8];
[waveform,ofdm]=nrOFDMModulate(carrier,tx);
capture=sixgr.phy.waveform.addOccupiedREAWGN(waveform*H.',carrier,20, ...
    'Seed',924521,'SignalEnergyPerOccupiedRE',1);
grid=nrOFDMDemodulate(carrier,capture);
received=struct('OFDMGrid',grid,'OFDMInfo',ofdm);
options=struct('PhysicalMeasurementGrid',grid,'PhysicalMeasurementOFDMInfo',ofdm, ...
    'PhysicalMeasurementGridStatus',"available_direct_component_antenna_grid", ...
    'PhysicalMeasurementReferencePlane',"receiver_antenna_connector_no_composite_front_end", ...
    'PhysicalMeasurementSource',"actual_CSI_only_OFDM_component_capture");
actual=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,cfg,received,options);
assert(actual.CSIRSObservation.Observed && actual.CSIRSObservation.ChannelEstimateAvailable);
% Resource identifiers are not zero-based positions in an installed set.
% Both scalar and explicit vector configuration forms must preserve ID 17
% while reporting the only configured resource as CRI ordinal zero.
scalarIDCfg=cfg; scalarIDCfg.phy.csirs.resourceID=17;
singleSetCfg=cfg;
singleSetCfg.phy.csirs.resourceIDs=17;
singleSetCfg.phy.csirs.rowNumbers=4;
singleSetCfg.phy.csirs.symbolLocationsByResource=6;
singleSetCfg.phy.csirs.subcarrierLocationsByResource=0;
singleSetCfg.phy.csirs.rbOffsetsByResource=0;
singleSetCfg.phy.csirs.numRBsByResource=nPRB;
scalarID=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,scalarIDCfg,received,options);
singleSet=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,singleSetCfg,received,options);
assert(scalarID.CSIMeasurementState.ResourceID=="CSI-RS-17" && ...
    singleSet.CSIMeasurementState.ResourceID=="CSI-RS-17" && ...
    scalarID.CSIMeasurementState.ResourceOrdinal==0 && ...
    singleSet.CSIMeasurementState.ResourceOrdinal==0 && ...
    singleSet.CSIRSChannelEstimation.SelectedResourceOrdinal==1 && ...
    isequaln(scalarID.CSIRSChannelEstimate,singleSet.CSIRSChannelEstimate), ...
    'test:CSISingletonIdentity','Scalar/set resource IDs must not become CRI ordinals.');
[setIndices,setSymbols,setInfo,setConfig]=sixgr.phy.refsig.csirs(carrier,singleSetCfg);
assert(isequal(indices,setIndices) && isequal(symbols,setSymbols), ...
    'This identity-only regression requires identical actual reference REs.');
for identityField=["ResourceID","ResourceIDs"]
    poisoned=options;
    poisoned.CSIRSIndices=setIndices; poisoned.CSIRSSymbols=setSymbols;
    poisoned.CSIRSInfo=setInfo; poisoned.CSIRSConfig=setConfig;
    poisoned.CSIRSInfo.(identityField)=18;
    try
        sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,singleSetCfg,received,poisoned);
        error('test:MissingCSIIdentityGuard','Conflicting singleton resource identities must be rejected.');
    catch cause
        assert(strcmp(cause.identifier,'sixgr:refsig:CSIResourceIdentityMismatch'));
    end
end
assert(actual.CSIRSObservation.CSIMeasurementStateAvailable && ...
    actual.CSIRSObservation.HestRxPorts==2 && actual.CSIRSObservation.HestTxPorts==4);
assert(isfinite(actual.CSIRSObservation.ReferenceMeasuredSINR_dB));
assert(~isfield(actual,'CRCPass') && ~isfield(actual,'HARQResults') && ...
    ~isfield(actual,'TransportBlock'));
% Capture time is not the callback/processing time. Reusing a UE context
% from another slot must not refresh an old CSI observation or move it to
% a different frame. CSI-RS sequence and calendar repeat in this fixture;
% check that explicitly before using the same actual received samples.
clockedCarrier=carrier; clockedCarrier.NFrame=3;
[clockedIndices,clockedSymbols]=sixgr.phy.refsig.csirs(clockedCarrier,cfg);
assert(isequal(indices,clockedIndices) && isequal(symbols,clockedSymbols));
captureSlot=clockedCarrier.NFrame*clockedCarrier.SlotsPerFrame+clockedCarrier.NSlot+1;
lateCfg=cfg; lateCfg.lls6g.userContext.RuntimeCurrentSlot=captureSlot+7;
late=sixgr.phy.refsig.receiveCSIRSFromGrid(clockedCarrier,lateCfg,received,options);
assert(late.CSIMeasurementState.Slot==captureSlot, ...
    'test:CSIRSCaptureClock','CSI time must describe the capture, not its later callback.');
noContext=cfg; noContext.lls6g.userContext=rmfield(noContext.lls6g.userContext,'RuntimeCurrentSlot');
sameClock=sixgr.phy.refsig.receiveCSIRSFromGrid(clockedCarrier,noContext,received,options);
assert(sameClock.CSIMeasurementState.Slot==captureSlot && ...
    late.CSIMeasurementState.MeasurementID==sameClock.CSIMeasurementState.MeasurementID && ...
    isequal(late.CSIRSChannelEstimate,sameClock.CSIRSChannelEstimate));
late.CSIMeasurementState.validateAt(captureSlot+late.CSIMeasurementState.MaxAgeSlots);
staleRejected=false;
try
    late.CSIMeasurementState.validateAt(captureSlot+late.CSIMeasurementState.MaxAgeSlots+1);
catch cause
    assert(strcmp(cause.identifier,'sixgr:mimo:StaleMeasurementState'));
    staleRejected=true;
end
assert(staleRejected,'A late callback must not extend the measured CSI freshness window.');
% The actual power application now declares normalized samples explicitly.
% Its receiver must agree numerically with the independently checked legacy
% unit conversion, without a fake absolute power context or another decode.
normalizedCfg=cfg;
[unchanged,normalizedCfg.lls6g.runtimePowerContext]=sixgr.rf.applyPowerContext( ...
    waveform,normalizedCfg,'DL',struct('OFDM',ofdm),'ApplyPA',false);
assert(isequal(waveform,unchanged));
normalized=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,normalizedCfg,received,options);
for field=["MeasurementRSRP_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSSI_dB_re_UnitOccupiedRE_Es","MeasurementRSRQ_dB", ...
        "ReferenceMeasuredSINR_dB"]
    assert(abs(actual.CSIRSObservation.(field)-normalized.CSIRSObservation.(field))<1e-8);
end
assert(isequaln(actual.CSIRSChannelEstimate,normalized.CSIRSChannelEstimate) && ...
    actual.CSIMeasurementState.Digest==normalized.CSIMeasurementState.Digest && ...
    isnan(normalized.CSIRSObservation.MeasurementRSRP_dBm));
missingPlane=rmfield(options,'PhysicalMeasurementGrid');
frontEndCfg=normalizedCfg;
frontEndCfg.lls6g.receiverMeasurement.CompositeReceiverFrontEndApplied=true;
missing=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,frontEndCfg,received,missingPlane);
assert(~startsWith(missing.CSIRSObservation.PhysicalMeasurementStatus,"available") && ...
    missing.CSIRSObservation.MeasurementSource=="" && ...
    isnan(missing.CSIRSObservation.MeasurementRSRP_dB_re_UnitOccupiedRE_Es), ...
    'Post-front-end samples cannot replace a missing antenna-plane measurement.');
bad=normalizedCfg; bad.lls6g.runtimePowerContext.PhysicalDevicePowerClaim=true;
try
    sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,bad,received,options);
    error('test:MissingPowerGuard','Reject an inconsistent normalized amplitude contract.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:rf:WaveformAmplitudeAuthorityMismatch'));
end
% A rejected or corrupted PDSCH command has no authority over the configured
% periodic reference receiver. No TX reference symbols are supplied to it.
poison=received;
poison.PDCCHCausalGrantDecodeOk=false;
poison.PDSCHAssignment=struct('NumLayers',99,'MCS',99);
poison.HARQ=struct('HarqID',99,'NDI',false);
other=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,cfg,poison,options);
assert(isequaln(actual.CSIRSChannelEstimate,other.CSIRSChannelEstimate) && ...
    actual.CSIRSNoiseVar==other.CSIRSNoiseVar && ...
    actual.CSIMeasurementState.Digest==other.CSIMeasurementState.Digest && ...
    actual.CSIRSObservation.ReferenceSINRMeasurementJSON==other.CSIRSObservation.ReferenceSINRMeasurementJSON);
% The configured calendar, not energy in an unrelated slot, owns eligibility.
carrier.NSlot=2; cfg.lls6g.userContext.RuntimeCurrentSlot=3;
absent=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,cfg,received,options);
assert(~absent.CSIRSObservation.Observed && isempty(absent.CSIMeasurementState));
fprintf('CONFIGURED_CSIRS_GRID_RECEPTION_PASS CSI_only=1 DCI_independent=1 HARQ_unchanged=1 calendar_bound=1 measured_SINR=%g\n', ...
    actual.CSIRSObservation.ReferenceMeasuredSINR_dB);
ok=true;
carrier.NSlot=1; cfg.lls6g.userContext.RuntimeCurrentSlot=2;
fixture=struct('Carrier',carrier,'Config',cfg,'Waveform',waveform*H.', ...
    'SampleRateHz',ofdm.SampleRate);
end
