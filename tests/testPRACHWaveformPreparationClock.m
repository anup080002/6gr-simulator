function ok=testPRACHWaveformPreparationClock(mode)
% Native geometry / scheduling-clock regression. No PRACH samples are
% generated or decoded. Event-owner checks use explicitly declared marker
% samples only and are not evidence of RF/PRACH transmission.
if nargin==0, mode="all"; end
assert(isstring(mode) && isscalar(mode) && any(mode==["all","clock_only"]));
f=@sixgr.truth.isPRACHWaveformPreparationSlot;
frame=int64(19660800); ms=int64(1966080);

% Declared reproduction of actual index16 geometry: container1ms versus
% CP/useful start1.5ms on30-kHz carrier. Prepare at0.5ms, not1ms.
n=declared(30,ms,ms+ms/2); cfg=config(n,"normal"); original=cfg;
assert(f(cfg,2) && ~f(cfg,3) && ~f(cfg,1));
assert(f(cfg,22) && f(cfg,42) && ~f(cfg,23) && isequaln(cfg,original));
clockGuard(cfg,ms,2,3);

% A short-PRACH origin may be INSIDE a slower carrier slot. Keep the full
% preceding-slot horizon; do not round or require carrier-slot alignment.
q=declared(15,ms+ms/2,ms+ms/2); c=config(q,"normal");
assert(f(c,1) && ~f(c,2) && f(c,11));
% Exact containing-slot boundary and +/-1Tc. These are declared clock
% operands, not claimed legal native PRACH configurations.
for delta=int64([-1 0 1])
    q=declared(30,ms+delta,ms+delta); c=config(q,"normal");
    expected=2; if delta<0, expected=1; end
    assert(f(c,expected) && ~f(c,expected+1));
end

% Origin0 is prepared in the previous repetition's last slot, for the NEXT
% occurrence; no negative scheduling index or backdated first transmission.
zero=declared(30,int64(0),int64(0)); c=config(zero,"normal");
assert(f(c,20) && f(c,40) && ~f(c,1));
clockGuard(c,frame,20,21);

% Higher-numerology normal CP does not have uniform physical slot lengths.
% The containing slot comes from the canonical CP clock, not ticks/meanSlot.
for scs=[60 120]
    spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',scs,'CyclicPrefix',"normal"));
    boundary=spec.SlotStartTicks(3);
    for delta=int64([-1 0 1])
        q=declared(scs,boundary+delta,boundary+delta); c=config(q,"normal");
        expected=2; if delta<0, expected=1; end
        assert(f(c,expected) && ~f(c,expected+1));
    end
end
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',60,'CyclicPrefix',"extended"));
q=declared(60,spec.SlotStartTicks(3),spec.SlotStartTicks(3),"extended");
assert(f(config(q,"extended"),2));

% Preserve all original native IDs; duplicates (FDM or several time
% occasions in one buffer) do not add a second preparation clock.
q=n; q.Occasions=[q.Occasions;q.Occasions]; c=config(q,"normal");
assert(f(c,2) && ~f(c,3));
bad=cfg; bad.phy.prach.timing.Occasions.PRACHWaveformStartTicks=double(ms);
reject(@()f(bad,2),'InvalidPRACHWaveformTimingAuthority');
bad=cfg; bad.phy.prach.timing.Occasions.PRACHWaveformStartTicks=frame;
bad.phy.prach.timing.Occasions.PRACHActiveStartTicks=frame;
reject(@()f(bad,2),'InvalidPRACHWaveformTimingAuthority');
bad=cfg; bad.phy.prach.timing.Occasions.AbsoluteSlot=2;
reject(@()f(bad,2),'InvalidPRACHWaveformTimingAuthority');
bad=cfg; bad.phy.prach.timing.Occasions.PRACHWaveformStartTicks=ms*2;
reject(@()f(bad,2),'InvalidPRACHWaveformTimingAuthority');
bad=cfg; bad.phy.prach.timing.Occasions=removevars(bad.phy.prach.timing.Occasions,'PRACHWaveformStartTicks');
reject(@()f(bad,2),'MissingPRACHWaveformTimingAuthority');

nativeRows=0;
if mode=="all"
    for row={[16 1.25],[157 30],[167 30]}
        args=row{1}; actual=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
            'FrequencyRange',"FR1",'DuplexMode',"TDD",'ConfigurationIndex',args(1), ...
            'CarrierSubcarrierSpacingKHz',30,'CarrierCyclicPrefix',"normal", ...
            'NSizeGrid',51,'NStartGrid',0,'NCellID',17, ...
            'PRACHSubcarrierSpacingKHz',args(2),'SequenceIndex',0,'PreambleIndex',0, ...
            'RestrictedSet',"UnrestrictedSet",'ZeroCorrelationZone',0,'Msg1FDM',2,'Msg1FrequencyStart',0);
        untouched=actual; c=config(actual,"normal"); T=actual.Occasions;
        period=actual.PeriodCarrierSlots;
        %30-kHz normal-CP carrier slots are exactly0.5ms. This independent
        % formula intentionally does not use the repaired floorToSlot path.
        containing=double(idivide(T.PRACHWaveformStartTicks,int64(983040),'floor'));
        expected=unique(mod(containing-1,period));
        for repetition=0:2
            observed=find(arrayfun(@(slot)f(c,slot+repetition*period),1:period))-1;
            assert(isequal(observed(:),sort(expected(:))));
        end
        assert(isequaln(actual,untouched));
        if args(1)==16
            hit=find(T.PRACHWaveformStartTicks==ms & T.PRACHActiveStartTicks==ms+ms/2,1);
            assert(~isempty(hit) && T.AbsoluteSlot(hit)==3 && f(c,2));
            assert(~ismember(2,expected), ...
                'This originalindex16 witness must distinguish container preparation from occupied-slot-minus-one.');
            clockGuard(c,T.PRACHWaveformStartTicks(hit),2,3);
        end
        nativeRows=nativeRows+height(T);
    end
end
fprintf('PRACH_WAVEFORM_PREPARATION_CLOCK_PASS mode=%s native_metadata_rows=%d PHY_execution=0\n',mode,nativeRows);
ok=true;
end

function clockGuard(cfg,nominalTicks,preparationSlot1,oldPreparationSlot1)
% Pure production UL clock plus actual event-owner enqueue/rejection. The
% DL timing reference here is an explicitly DECLARED clock fixture, not RX.
fs=30.72e6; tc=int64(64);
cfg.phy.synchronization=struct('maxTimingUncertaintySamples',16);
offset=sixgr.phy.frame.resolveULTimingAdvanceOffsetValue(true,"n39936","FR1");
offset.Source="declared_common_offset_for_clock_regression";
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',-4,'AvailableAtSample',0, ...
    'TestScope',"declared_clock_operand_not_received_evidence");
cfg.SharedULTimingContext=struct('DLReference',reference,'Offset',offset);
timing=sixgr.phy.ra.sharedULStageTiming(cfg,double(nominalTicks)/1966080000,fs,8,0);
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',30,'CyclicPrefix',"normal"));
p=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(preparationSlot1-1,0,spec);
old=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(oldPreparationSlot1-1,0,spec);
now=double(p.Ticks/tc); tooLate=double(old.Ticks/tc);
assert(timing.TransmitStartSample>=now && timing.TransmitStartSample<tooLate && ...
    timing.TransmitStartSample==double(nominalTicks/tc)-4-double(offset.NTAOffset_Tc/tc));
marker=sixgr.phy.waveform.WaveformChunk(complex(ones(8,1)),timing.TransmitStartSample);
owner=sixgr.phy.waveform.WaveformEventRuntime(fs,now,@unusedProcessor,struct());
owner.addTransmitter("ue",1,"double"); receipt=owner.enqueue("ue","declared_marker",marker);
assert(~receipt.PhysicalExecutionPerformed && receipt.StartSample>=receipt.CommittedThroughSample);
late=sixgr.phy.waveform.WaveformEventRuntime(fs,tooLate,@unusedProcessor,struct());
late.addTransmitter("ue",1,"double");
reject(@()late.enqueue("ue","declared_marker",marker),'CommittedTransmission');
% An advance larger than the planning horizon stays rejected, not cropped
% or silently moved to make the new predicate appear universally sufficient.
before=sixgr.phy.waveform.WaveformChunk(complex(ones(8,1)),max(0,now-1));
if now>0, reject(@()owner.enqueue("ue","too_early",before),'CommittedTransmission'); end
end
function varargout=unusedProcessor(varargin) %#ok<INUSD,STOUT>
error('test:UnexpectedPhysicalExecution','This clock test must not execute a physical interval.');
end
function cfg=config(n,cp)
cfg=struct('phy',struct('carrier',struct('CyclicPrefix',cp), ...
    'prach',struct('timing',n)));
end
function n=declared(scs,origin,active,cp)
if nargin<4, cp="normal"; end
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',scs,'CyclicPrefix',cp));
t=sixgr.phy.frame.AbsoluteTime(active); [~,frame,slot]=t.floorToSlot(spec);
n=struct('PeriodCarrierSlots',spec.SlotsPerFrame,'CarrierSubcarrierSpacingKHz',scs, ...
    'Occasions',table(0,double(frame)*spec.SlotsPerFrame+double(slot),origin,active, ...
    'VariableNames',{'PRACHSlot','AbsoluteSlot','PRACHWaveformStartTicks','PRACHActiveStartTicks'}));
end
function reject(fn,suffix)
try
    fn();
catch cause
    assert(endsWith(string(cause.identifier),suffix), ...
        'Unexpected %s; expected %s: %s',cause.identifier,suffix,cause.message);
    return;
end
error('test:MissingExpectedFailure','Expected %s.',suffix);
end
