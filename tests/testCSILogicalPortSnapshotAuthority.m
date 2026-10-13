function ok = testCSILogicalPortSnapshotAuthority()
% Mathematical CSI boundary fixture, not measured-waveform qualification.
% A logical CSI-RS port can be beamformed over several physical TX chains.
% Frequency snapshots are neither additional ports nor receive antennas.
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.mimo.strict = false;
cfg.phy.mimo.strict = false;
cfg.phy.csi.reportCSI = true;
cfg.phy.csi.reportCQI = true;
cfg.phy.csi.reportPMI = true;
cfg.phy.csi.reportRI = true;
cfg.phy.csi.maxRank = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.csirs.nPorts = 1;
cfg.phy.csirs.numPorts = 1;
cfg.phy.csi.reportSubbandCQI = false;
cfg.phy.csi.reportingMode = 'wideband';
noiseVariance = 0.1;
caseCount = 0;
for physicalTx = [2 4]
    cfg.phy.nTxAnt = physicalTx;
    for receiveAntennas = [1 2 4]
        cfg.phy.nRxAnt = receiveAntennas;
        spatial = (1:receiveAntennas).' .* exp(1i*(0:receiveAntennas-1).');
        spatial = spatial/norm(spatial);
        for snapshots = [1 24 273]
            phase = exp(1i*2*pi*(0:snapshots-1)/max(snapshots,1));
            H = reshape(spatial,receiveAntennas,1,1) .* reshape(phase,1,1,[]);
            checkObservation(cfg,H,noiseVariance,10*log10(1/noiseVariance));
            caseCount = caseCount+1;
        end
    end
end
% Independent frequency-selective reference: equalize each snapshot, then
% average information. Do not average complex channel coefficients first.
cfg.phy.nTxAnt = 4;
cfg.phy.nRxAnt = 2;
spatial = [1;1i]/sqrt(2);
amplitude = [0.1 0.25 0.5 1 2 0.75];
phase = exp(1i*2*pi*(0:numel(amplitude)-1)/numel(amplitude));
H = reshape(spatial,2,1,1) .* reshape(amplitude.*phase,1,1,[]);
expected = 10*log10(expm1(mean(log1p(amplitude.^2/noiseVariance))));
checkObservation(cfg,H,noiseVariance,expected);
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="CSI-noise-identity-negative",UEID="1", ...
    ResourceType="CSI-RS",ResourceID="0",Slot=0,MaxAgeSlots=8, ...
    ChannelEstimate=H,NoiseVariance=0,Provenance="measured_contract_declared_tensor_unit_fixture");
for invalidNoise=[NaN -1 Inf]
    rejected=false;
    try
        sixgr.phy.dl.CSI_Feedback(H,invalidNoise,cfg,'MeasurementState',measurement);
    catch cause
        rejected=strcmp(cause.identifier,'sixgr:mimo:MeasurementIdentityMismatch');
    end
    assert(rejected,'Invalid supplied noise must not be silently converted to the zero-noise measured state.');
end
fprintf('CSI_LOGICAL_PORT_SNAPSHOT_AUTHORITY_PASS %d constant and one selective tensor cases; not PHY qualification.\n',caseCount);
ok = true;
end

function checkObservation(cfg,H,noiseVariance,expectedSINR)
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="CSI-logical-port-math-fixture",UEID="1", ...
    ResourceType="CSI-RS",ResourceID="0",ResourceOrdinal=0, ...
    Slot=0,MaxAgeSlots=8,ChannelEstimate=H,NoiseVariance=noiseVariance, ...
    Provenance="measured_contract_declared_tensor_unit_fixture");
[csi,info] = sixgr.phy.dl.CSI_Feedback(H,noiseVariance,cfg, ...
    'MeasurementState',measurement,'MaxRank',1);
assert(csi.NumRxAnt==size(H,1) && csi.NumTxPorts==size(H,2), ...
    'test:CSISnapshotAxisAsAntenna', ...
    'CSI must preserve logical Nrx/Nport independently of physical TX count and snapshot count.');
assert(isequaln(info.WidebandChannel,H), ...
    'test:CSIMeasuredTensorChanged', ...
    'The immutable canonical CSI observation must reach the receiver objective unchanged.');
assert(abs(csi.SINR_dB-expectedSINR)<1e-10 && csi.RI==1, ...
    'test:CSISnapshotProcessingGain', ...
    'Rank-one CSI SINR must match independent MRC/mean-information math, not gain from snapshot duplication.');
assert(string(csi.SINRSource)=="measured_csi_state_receiver_objective");
end
