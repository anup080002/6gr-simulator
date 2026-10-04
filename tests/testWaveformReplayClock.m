function ok=testWaveformReplayClock()
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.carrier.NSlot=3; cfg.phy.carrier.NFrame=2;
g=struct('ScheduledAbsoluteSlot',47,'ControlAbsoluteSlot',43);
resolve=@(grant,field,time)sixgr.system.waveform.resolveReplayChannelTime(cfg,grant,field,time);
% At 30 kHz the physical slots are uniform. Use the exact rational clock,
% not a differently rounded floating multiplication by 0.0005.
assert(resolve(g,'ScheduledAbsoluteSlot',[])==47/2000);
assert(resolve(g,'ControlAbsoluteSlot',[])==43/2000);
assert(resolve(g,'ScheduledAbsoluteSlot',47/2000)==47/2000);
assert(resolve(struct(),'ScheduledAbsoluteSlot',[])==43/2000);
bad=g; bad.ScheduledAbsoluteSlot=47.1;
reject(@()resolve(bad,'ScheduledAbsoluteSlot',[]),'InvalidAbsoluteSlot');
bad=g; bad.ControlAbsoluteSlot=-1;
reject(@()resolve(bad,'ControlAbsoluteSlot',[]),'InvalidAbsoluteSlot');
reject(@()resolve(g,'ScheduledAbsoluteSlot',0),'ChannelClockMismatch');
reject(@()resolve(g,'ControlAbsoluteSlot',47*.0005),'ChannelClockMismatch');
fprintf('WAVEFORM_REPLAY_CLOCK_PASS data_and_control_absolute_clock=1 no_zero_reset=1\n');
ok=true;
end
function reject(fn,suffix)
try, fn(); catch ME
    assert(strcmp(ME.identifier,['sixgr:system:WaveformReplay:' suffix])); return;
end
error('test:MissingRejection','Expected %s',suffix);
end
