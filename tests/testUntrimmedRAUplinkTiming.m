function ok=testUntrimmedRAUplinkTiming()
% Actual coded receivers on explicitly delayed FIR observations. These
% component fixtures do not claim a complete main-scheduler access pass.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
ra=sixgr.mac.ra.RAConfig(cfg);
grant=sixgr.mac.ra.buildRARULGrant(ra);
for field=["TransformPrecoding","EnablePTRS"]
    for invalid={NaN,2,"false",[true false]}
        bad=grant; bad.(field)=invalid{1};
        rejected=false;
        try
            sixgr.phy.ra.localPUSCHConfigFromGrant(ra,bad);
        catch ME
            assert(string(ME.identifier)=="sixgr:phy:ra:InvalidPUSCHWaveformFlag",ME.message);
            rejected=true;
        end
        assert(rejected,"Invalid Msg3 waveform flags must never silently select defaults.");
    end
end
msg3=sixgr.mac.ra.buildMsg3Payload('UEId',1,'UEIdentity','UE-1');
msg5=sixgr.mac.ra.buildRRCSetupComplete('UEIdentity','UE-1');
cfg.lls6g.receiverSync=struct('RuntimeWaveformSampleAligned',false, ...
    'ReceivedWaveformTimingPlane','untrimmed_shared_physical_receive_stream', ...
    'ReceivedTimingPrecompensation_samples',0,'ChannelFilterDelay_samples',11, ...
    'ChannelPathDelay_samples',8);
for stage=["Msg3","RRCSetupComplete"]
    if stage=="Msg3"
        tx=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,grant,msg3);
    else
        tx=sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg,ra,grant,msg5);
    end
    delay=19;
    x=[tx.Waveform;zeros(delay,size(tx.Waveform,2),'like',tx.Waveform)];
    y=filter([zeros(1,delay) 1],1,x);
    if stage=="Msg3"
        [rx,msg]=sixgr.phy.ra.recoverMsg3PUSCH(y,cfg,ra,grant,tx);
    else
        [rx,msg]=sixgr.phy.ra.recoverRRCSetupComplete(y,cfg,ra,tx);
    end
    assert(rx.Ok && isequal(rx.TransportBlock(:),tx.TransportBlockBits(:)));
    assert(rx.AppliedTimingCorrection_samples==delay, ...
        'The actual untrimmed arrival must be corrected once, without subtracting a modeled delay.');
    assert(~isempty(fieldnames(msg)));
end
% PRACH TA excludes the implementation delay only. The receiver must not
% subtract the configured propagation delay or consult transmitted timing.
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
y=filter([zeros(1,19) 1],1,[tx.Waveform;zeros(19,size(tx.Waveform,2))]);
d=sixgr.phy.ra.detectMsg1PRACH(y,cfg,ra,occasion);
% The practical correlation estimator has sub-sample interpolation error
% (this fixture measures 19.0286), not an exact-delay oracle. Check one
% input-sample resolution and exact calibration arithmetic separately.
assert(d.Detected && abs(d.RawTimingOffsetSamples-19)<1 && ...
    d.PropagationTimingOffsetSamples==d.RawTimingOffsetSamples-11 && ...
    d.ImplementationFilterDelay_samples==11);
disp('UNTRIMMED_RA_UL_TIMING_PASS: Msg3 and SRB1 bits/CRC; measured PRACH delay and filter calibration.');
ok=true;
end
