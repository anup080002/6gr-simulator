function ok = testSharedQCLTimingTransfer()
% Bounded Type-A timing transfer; explicit fixtures are not production truth.
setup6GRSimToolkit('Verbose',false);
policy=struct('enabled',true,'state_id',17,'codepoint',0,'configuration_epoch',1, ...
    'activation_absolute_slot0',0,'source_resource_id',100,'source_max_age_slots',20, ...
    'timing_search_radius_samples',4,'initialization_source',"lls_preconfigured_higher_layer_context");
source=struct('UEIndex',1,'ServingCellIndex',1,'SourceResourceID',100, ...
    'ConfigurationEpoch',1,'SourceSlot0',20,'AvailableAtSample',900, ...
    'SampleRateHz',1e6,'TimingPhaseSamples',7,'Source',"received_nzp_csi_rs_trs_timing_estimator");
cfg=struct(); cfg=sixgr.util.structSet(cfg,'phy.pdsch.qclTCI',policy);
cfg=sixgr.util.structSet(cfg,'lls6g.runtime.AbsoluteSlotIndex0',30);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.QCLTimingReference',source);
grant=struct('UEIndex',1,'ServingCell',1,'ReceivedTCICodepoint',0, ...
    'ReceivedTCIConfigurationEpoch',1,'DCICrcPass',true,'PDCCHPayloadMatch',true, ...
    'PDCCHCausalGrantDecodeOk',true,'PDCCHGrantBindingOk',true);
observation=sixgr.phy.waveform.WaveformObservationBuffer(1000,2000,1e6,1);
[window,evidence]=sixgr.phy.rx.applyQCLTimingTransfer(cfg,grant,observation,1000,[0 20]);
assert(isequal(window,[3 11]) && evidence.TCIStateID==17 && evidence.TCICodepoint==0 && ...
    evidence.QCLTimingPriorUsed && isnan(evidence.QCLDMRSDelayResidual_samples));
for field=["UEIndex","ServingCellIndex","SourceResourceID","SampleRateHz"]
    bad=source; bad.(field)=bad.(field)+1;
    mutated=sixgr.util.structSet(cfg,'lls6g.userContext.QCLTimingReference',bad);
    reject(mutated,grant,observation,'sixgr:qcl:ReferenceIdentityMismatch');
end
for field=["AvailableAtSample","SourceSlot0"]
    bad=source; bad.(field)=2001;
    mutated=sixgr.util.structSet(cfg,'lls6g.userContext.QCLTimingReference',bad);
    reject(mutated,grant,observation,'sixgr:qcl:InactiveOrStaleReference');
end
bad=grant; bad.ReceivedTCICodepoint=17;
reject(cfg,bad,observation,'sixgr:qcl:TCIMismatch');
bad=grant; bad.ReceivedTCIConfigurationEpoch=2;
reject(cfg,bad,observation,'sixgr:qcl:TCIMismatch');
bad=grant; bad.DCICrcPass=false;
reject(cfg,bad,observation,'sixgr:qcl:MissingReceivedTCI');
reject(sixgr.util.structSet(cfg,'phy.pdsch.qclTCI.activation_absolute_slot0',31), ...
    grant,observation,'sixgr:qcl:InactiveOrStaleReference');
reject(sixgr.util.structSet(cfg,'phy.pdsch.qclTCI.source_max_age_slots',2), ...
    grant,observation,'sixgr:qcl:InactiveOrStaleReference');
reject(sixgr.util.structSet(cfg,'lls6g.userContext.QCLTimingReference',struct()), ...
    grant,observation,'sixgr:qcl:MissingReceivedReference');

% The production DM-RS timing function consumes the transferred window,
% independently measuring a delayed waveform (not selecting a truth offset).
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',15);
pdsch=nrPDSCHConfig('PRBSet',0:5);
indices=nrPDSCHDMRSIndices(carrier,pdsch); symbols=nrPDSCHDMRS(carrier,pdsch);
grid=nrResourceGrid(carrier); grid(indices)=symbols;
wave=nrOFDMModulate(carrier,grid);
received=[zeros(7,1);wave;zeros(20,1)]; % generated unit-channel capture fixture
[~,timing]=sixgr.phy.sync.alignULReferenceObservation(carrier,received,indices,symbols,window);
assert(isequal(timing.SearchWindowSamples,window) && timing.TimingOffsetSamples==7 && ...
    ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed);
ok=true;
fprintf('PASS testSharedQCLTimingTransfer\n');
end

function reject(cfg,grant,observation,id)
try
    sixgr.phy.rx.applyQCLTimingTransfer(cfg,grant,observation,1000,[0 20]);
    error('testSharedQCLTimingTransfer:ExpectedRejection','Invalid QCL accepted.');
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier);
end
end
