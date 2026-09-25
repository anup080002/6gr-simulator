function ok=testTypeIIMeasuredPrecoderPDSCH()
% Physical component chain: noisy CSI-RS -> CSI on PUSCH -> PDSCH.
% This does not stand in for shared-runtime scheduling/report publication.
[passed,~,request,received,H,receivedReport]=testNRCSIReportEngineTypeII();
assert(passed);
W=received.Precoder_W;
rank=received.RI;
cfg=sixgr.config.defaultConfig();
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.phy.ssb.enable=false;
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.SubcarrierSpacing=15;
cfg.phy.carrier.NCellID=17;
cfg.phy.nTxAnt=4; cfg.channel.nTxAnt=4;
cfg.scenario.bs.nTxAnt=4; cfg.antenna.bs.numElements=4;
cfg.phy.nRxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.ue.nRxAnt=2; cfg.antenna.ue.numElements=2;
cfg.phy.pdsch.prbSet=0:11; cfg.phy.pdsch.symbolAllocation=[2 12];
cfg.phy.pdsch.numLayers=rank; cfg.phy.pdsch.nLayers=rank;
cfg.phy.pdsch.numPorts=4; cfg.phy.pdsch.nPorts=4;
cfg.phy.pdsch.dmrs.portSet=0:rank-1;
cfg.phy.pdsch.dmrs.DMRSPortSet=0:rank-1;
cfg.phy.pdsch.enablePTRS=false;
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=308/1024;
cfg.phy.pdsch.mcsIndex=4; cfg.phy.pdsch.mcsTable='qam64_table1';
cfg.phy.pdsch.executionProfile='phy_calibration';
cfg.phy.pdsch.mcsContext=struct('UECapability1024QAM',false, ...
    'RRCEnabled1024QAM',false,'DCIEnabled1024QAM',false, ...
    'DeploymentAllows1024QAM',false,'FrequencyRangeAllows1024QAM',false, ...
    'BandAllows1024QAM',false,'FrequencyRange','FR1','OperatingBand','n78', ...
    'DeploymentClass','controlled_test');
cfg.phy.pdsch.PMI=NaN;
cfg.phy.pdsch.precoding.normalizationConvention='unit_frobenius';
cfg.phy.pdsch.normalizePrecodingMatrix=false;
cfg.phy.channelEstimation.method='LS';
cfg.phy.csi.reportConfiguration=request;
cfg.phy.csi.reportConfigurationEpoch=request.Epoch;
matrix=sixgr.phy.mimo.MatrixContract.validate(W,4,rank);
grant=struct('Direction',"DL",'Frame',1,'Slot',3,'RNTI',1,'UEIndex',1,'ServingCell',1, ...
    'PRBSet',0:11,'SymbolAllocation',[2 12],'Modulation',"QPSK", ...
    'NumLayers',rank,'Layers',rank,'TargetCodeRate',308/1024,'MCSIndex',4,'MCS',4, ...
    'PMI',NaN,'CRI',received.CRI,'ReceivedCSIReport',receivedReport, ...
    'GrantContextId',"typeII_received_component_slot3", ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
frozen=sixgr.phy.grant.freezePHYGrant(cfg,"DL",grant);
assert(string(frozen.PrecodingState.Source)=="frozen_dl_typeII_from_received_csi_bits" && ...
    isnan(frozen.PrecodingState.PMI) && ...
    norm(frozen.PrecodingState.MatrixPhysicalPorts-W,'fro')<1e-14);
bad=grant; bad.ReceivedCSIReport.CSIConfigurationEpoch=request.Epoch+1;
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,"DL",bad), ...
    'sixgr:phy:grant:ReceivedCSIConfigurationMismatch');
bad=grant; bad.ReceivedCSIReport.RNTI=2;
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,"DL",bad), ...
    'sixgr:phy:grant:ReceivedCSIIdentityMismatch');
bad=grant; bad.ReceivedCSIReport.RI=3-rank;
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,"DL",bad), ...
    'sixgr:phy:grant:ReceivedCSIRankOrFieldMismatch');
bad=grant; bad.ReceivedCSIReport.DeliveredSlot=grant.Slot+1;
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,"DL",bad), ...
    'sixgr:phy:grant:NoncausalReceivedCSI');
bad=grant; bad.PrecodingMatrix=W;
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,"DL",bad), ...
    'sixgr:phy:grant:CompetingReceivedCSIPrecoder');
[tx,info]=sixgr.phy.dl.PDSCH_Tx(cfg,'PHYGrant',frozen,'CompactOutput',false);
assert(norm(info.Precoding.MatrixPorts-W,'fro')<1e-14 && ...
    abs(sum(abs(info.Precoding.MatrixPorts(:)).^2)-1)<1e-12, ...
    'Received Type-II coefficients must drive the exact fixed-total-power matrix.');
% Compare the actually executed matrix, not just scheduled report metadata.
assert(sixgr.phy.mimo.MatrixContract.digest(info.Precoding.MatrixPorts)==matrix.MatrixSHA256);
% Same channel used for the preceding CSI-RS measurement, not an estimated
% channel injected into the decoder. Independent noise for the data capture.
[capture,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
    tx.Waveform*H.',tx.Carrier,20,'Seed',38214226,'SignalEnergyPerOccupiedRE',1);
receiver=tx.ReceiverConfig;
receiver.ChannelModel='STATIC-MIMO';
if isfield(receiver,'ReferenceChannelGain'), receiver=rmfield(receiver,'ReferenceChannelGain'); end
% Declared component allocation, not received-DCI evidence. The canonical
% receiver estimates H*W from DM-RS without a TX matrix or scalar PMI.
rx=sixgr.pdsch.PDSCHReceiver(capture,tx.Assignment,tx.ResourcePlan, ...
    tx.Carrier,tx.ReferenceConfig,receiver,'CodingPlans',tx.CodingPlans);
assert(rx.CRCPass && isequal(int8(rx.TransportBlock(:)),int8(tx.TransportBlock(:))), ...
    'PDSCH must physically decode using the received Type-II report matrix.');
assert(~rx.EstimatorUsesTrueChannel && isempty(rx.ChannelGainPerPhysicalPort) && ...
    isequal(size(rx.EffectiveLayerChannelEstimate),[288 14 2 rank]) && ...
    all(isfinite(rx.EffectiveLayerChannelEstimate(:))));
fprintf('TYPEII_MEASURED_PUSCH_CSI_TO_PDSCH_PASS rank=%d bits=%d configured_snr=%g power=%.16g\n', ...
    rank,tx.TransportBlockSize,noise.RequestedEsN0_dB,matrix.FrobeniusPower);
ok=true;
end

function localReject(action,id)
try, action(); catch ex
    assert(string(ex.identifier)==id,'Expected %s, got %s: %s',id,ex.identifier,ex.message);
    return;
end
error('test:ExpectedFailure','Invalid received CSI was accepted by grant freezing.');
end
