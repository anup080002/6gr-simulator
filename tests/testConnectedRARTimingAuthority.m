function ok=testConnectedRARTimingAuthority()
% Normative MAC application timing and causal SRS delivery, not field data.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
receivedTree=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
[installed,~]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,receivedTree);
common=installed.UECommonCellConfiguration;
assert(common.TimeAlignmentTimerCommon== ...
    string(tree.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.timeAlignmentTimerCommon));
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier); fs=info.SampleRate;
common.ReceivedDLTimingReference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',1000);
common.ULTimingAdvanceOffset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1');
rar=struct('TimingAdvanceCommand',3);
received=17*(fs/1000)+15;
context=sixgr.mac.ra.connectedTimingFromRAR(cfg,common,rar,16,received,fs);
assert(context.Application.N1Symbols==14 && context.Application.N2Symbols==10 && ...
    context.Application.ApplicationDelaySlotsK==5 && context.Application.EffectiveULSlot0Based==22);
assert(context.TimingAdvanceEffectiveAtSample==22*(fs/1000)+6-100-12);
assert(context.ReceivedRARTiming.Command==3 && context.TimingAdvanceAvailableAtSample==received);
finite=common; finite.TimeAlignmentTimerCommon="ms500";
c=sixgr.mac.ra.connectedTimingFromRAR(cfg,finite,rar,16,received,fs);
assert(c.TimeAlignmentExpirySampleExclusive==received+fs*.5);
invalid=common; invalid.TimeAlignmentTimerCommon="";
reject(@()sixgr.mac.ra.connectedTimingFromRAR(cfg,invalid,rar,16,received,fs), ...
    'sixgr:mac:ra:InvalidReceivedTimeAlignmentTimer');
reject(@()sixgr.mac.ra.connectedTimingFromRAR(cfg,common,rar,16,23*(fs/1000),fs), ...
    'sixgr:mac:ra:LateRARTimingDelivery');
% Availability remains later than production, including an observation
% completed at the last simulated slot without a future consumer.
row=table(5,39900,40015,fs,40015/fs,"complete_contiguous_received_sample_buffer", ...
    7,.006,"canonical_slot_start_after_complete_received_window", ...
    'VariableNames',{'Slot','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource', ...
    'ObservationDeliverySlot','ObservationDeliveryTime_s','ObservationDeliverySource'});
state=struct('CurrentSlot',7,'SlotDuration_s',.001);
assert(sixgr.truth.srsResultDeliverySlot(state,row)==7);
assert(sixgr.truth.srsResultDeliverySlot(struct(),struct('SINR_dB',12),4)==4);
state.CurrentSlot=6;
reject(@()sixgr.truth.srsResultDeliverySlot(state,row),'sixgr:truth:SRSResultBeforeDelivery');
ok=true; disp('Connected RAR authority and SRS receive/delivery clock PASS.');
end
function reject(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),e.message); return; end
error('test:ExpectedError','Expected %s.',id);
end
