function ok=testRARReceivedTemporaryIdentity()
% Actual coded RAR must install its identity, not the UE's configured value.
% Explicit unit-channel receive experiment; no multi-UE attach claim.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
ra=sixgr.mac.ra.RAConfig(cfg);
cfg=sixgr.phy.ra.localizeCarrierConfig(cfg,ra);
receiver=sixgr.phy.ra.RARReceiveWindow(cfg,ra);
slot=receiver.Window.MonitoringSlots(1);
scheduled=ra; scheduled.Msg2Slot=slot;
assigned=6201; assert(ra.TempCRNTI~=assigned && ra.FinalCRNTI~=assigned);
grant=sixgr.mac.ra.buildRARULGrant(scheduled);
rar=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex, ...
    'TemporaryCRNTI',assigned,'ULGrant',grant);
tx=sixgr.phy.ra.generateMsg2RARWaveform(cfg,scheduled,rar);
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=nrOFDMInfo(carrier).SampleRate;
start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,receiver.Window.Numerology);
first=double(start.Ticks)*fs/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(tx.Waveform,1),fs,size(tx.Waveform,2));
observation.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,first),fs);
[receiver,out]=receiver.receive(slot,observation,cfg);
assert(out.Accepted && out.Observation.DCICrcPass && out.Observation.PDSCHCrcPass);
assert(out.RAR.TemporaryCRNTI==assigned && out.RAR.ULGrant.TemporaryCRNTI==assigned);
bound=sixgr.phy.ra.bindReceivedRARTiming(cfg,out.RAConfig,out.RAR.ULGrant,out.Receiver.RecoveredSchedule);
assert(bound.TempCRNTI==assigned && bound.FinalCRNTI==assigned, ...
    'test:ReceivedTemporaryCRNTINotBound', ...
    'CRC-valid received RAR identity must drive Msg3/Msg4, not configured identity.');
assert(receiver.RAConfig.TempCRNTI==ra.TempCRNTI, ...
    'The frozen pre-RAR monitor configuration must not be rewritten retrospectively.');
assert(bound.Msg3Slot==slot+out.RAR.ULGrant.K2+out.RAR.ULGrant.Msg3AdditionalDelaySlots);
ok=true;
disp('RECEIVED_TEMPORARY_CRNTI_PASS: actual independent RAR decoding and post-RAR identity binding.');
end
