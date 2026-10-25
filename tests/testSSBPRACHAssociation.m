function ok=testSSBPRACHAssociation()
% Pure original-operand mapping tests, NOT PHY/decoded-SIB1/RA acceptance.
% Native timing integration and actual received SIB1 ownership are separate.
setup6GRSimToolkit('Verbose',false);
f=@sixgr.mac.ra.resolveSSBPRACHAssociation;

% n40 clock: 30kHz data, a 10ms native period, RO in zero-slot9.
% Four SSBs with one/n64 need40ms: beam0 belongs to radio10 then90,
% not to every RO (radio30 is beam1). Reception time cannot reset mapping.
r=timing(1,20,9,0,0,0);
r.Occasions.PRACHActiveEndTicksExclusive=int64(9007199254740991);
r.Occasions.DeclaredCaptureSample=int64(9007199254740990);
a=f(r,0:3,1,64,64,true);
assert(a.AssociationPeriodConfigurationCount==4 && ...
    a.AssociationPeriodFrames==4 && a.AssociationPeriodCarrierSlots==80);
assert(isequal(a.Mapping.AbsoluteSlot,[9;29;49;69]) && ...
    isequal(a.Mapping.SSBIndex0,(0:3).') && ...
    all(a.Mapping.CBPreambleStart0==0) && all(a.Mapping.CBPreambleCount==64));
assert(a.Mapping.AbsoluteSlot(1)+a.AssociationPeriodCarrierSlots+1==90);
assert(isequaln(a.OriginalOccasions,r.Occasions));
assert(~any(ismember(["PRACHActiveEndTicksExclusive","DeclaredCaptureSample"], ...
    string(a.Mapping.Properties.VariableNames))), ...
    'Original-period sample/tick operands must not acquire translated-clock labels.');

% Every ASN.1 N ratio: complete coverage, original sparse SSB identities,
% exact allowed preamble ranges, no fabricated trailing assignments.
r=timing(1,20,[1 3 5 7 9 11 13 15],zeros(1,8),zeros(1,8),zeros(1,8));
for n=[1/8 1/4 1/2 1 2 4 8 16]
    total=64; cb=min(4,total/max(1,n));
    a=f(r,[0 2 4 7],n,cb,total,true(8,1));
    t=a.Mapping;
    assert(isequal(unique(t.SSBIndex0),[0;2;4;7]) && ...
        all(t.CBPreambleStart0+t.CBPreambleCount<=total) && ...
        all(t.CBPreambleCount==cb) && all(t.AbsoluteSlot<a.AssociationPeriodCarrierSlots));
    if n<1
        for s=[0 2 4 7]
            chosen=t(t.SSBMappingCycleIndex0==0 & t.SSBIndex0==s,:);
            assert(height(chosen)==1/n && all(diff(chosen.ROIndexWithinAssociation0)==1));
        end
    else
        assert(all(t.CBPreambleStart0==t.PreamblePartitionIndex0*(total/n)));
    end
end

% N=2, R8 versus partition width32: two complete three-SSB cycles,
% including a cycle boundary INSIDE an RO. Never use n*R as the start.
r=timing(2,20,[9 9 19],[0 0 0],[0 0 0],[0 1 0]);
a=f(r,[7 1 4],2,8,64,true(3,1));
assert(isequal(a.Mapping.SSBIndex0,[1;4;7;1;4;7]) && ...
    isequal(a.Mapping.CBPreambleStart0,[0;32;0;32;0;32]) && ...
    isequal(a.Mapping.ROIndexWithinAssociation0,[0;0;1;1;2;2]) && ...
    a.CompleteMappingCycles==2 && a.UnassociatedPartitionCount==0);

% N=4: one complete sparse-SSB cycle leaves the last partition unassigned.
r=timing(1,20,9,0,0,0);
a=f(r,[1 4 7],4,4,64,true);
assert(isequal(a.Mapping.CBPreambleStart0,[0;16;32]) && ...
    a.UnassociatedPartitionCount==1 && height(a.Mapping)==3);

% Fractional mapping repeats each SSB across two consecutive VALID ROs.
% Nine ROs permit two full two-SSB cycles, not a partial third cycle.
r=timing(1,20,0:8,zeros(1,9),zeros(1,9),zeros(1,9));
a=f(r,[2 6],1/2,8,64,true(9,1));
assert(isequal(a.Mapping.SSBIndex0,[2;2;6;6;2;2;6;6]) && ...
    a.CompleteMappingCycles==2 && a.UnassociatedPartitionCount==1);

% Frequency is innermost, then time, then active/native PRACH slot. Input
% ordering must not become authority. Invalid original rows remain retained
% but do not consume association positions.
r=timing(1,20,[9 9 9 9 9 19], ...
    [0 0 0 0 1 0],[0 0 1 1 0 0],[0 1 0 1 0 0]);
r.Occasions=r.Occasions([6 4 2 5 1 3],:);
valid=logical([1 1 0 1 1 1]);
a=f(r,[0 1],1,32,64,valid);
assert(isequal(a.Mapping.SourceOccasionOrdinal,[1;3;4;5]) && ...
    isequal(a.Mapping.SSBIndex0,[0;1;0;1]) && ...
    a.UnassociatedPartitionCount==1 && ...
    isequaln(a.OriginalOccasions,r.Occasions) && ...
    isequal(a.OriginalValidityMask,valid(:)));

% Association period selection uses Table8.1-1, not the receiver's current
% frame or a handpicked wait. Even the largest permissible period can fail.
for base=[1 2 4 8 16]
    r=timing(base,20,9,0,0,0);
    a=f(r,0,1,64,64,true);
    assert(a.AssociationPeriodConfigurationCount==1 && a.AssociationPeriodFrames==base);
end
r=timing(1,20,9,0,0,0);
mustFail(@()f(r,0:63,1/8,4,64,true),'SSBAssociationCoverageImpossible');
mustFail(@()f(r,[0 0],1,64,64,true),'InvalidAssociationSSBs');
mustFail(@()f(r,[],1,64,64,true),'InvalidAssociationSSBs');
mustFail(@()f(r,0,3,4,64,true),'InvalidSSBsPerRO');
mustFail(@()f(r,0,2,8,63,true),'InvalidAssociationPreambles');
mustFail(@()f(r,0,2,33,64,true),'InvalidAssociationPreambleChoice');
mustFail(@()f(r,0,1,1,64,true),'InvalidAssociationPreambleChoice');
mustFail(@()f(r,0,2,3,64,true),'InvalidAssociationPreambleChoice');
mustFail(@()f(r,0,1,64,32,true),'InvalidAssociationPreambles');
mustFail(@()f(r,0,1,4.5,64,true),'InvalidAssociationOperand');
mustFail(@()f(r,0,1,64,64,NaN),'MissingAssociationValidity');
mustFail(@()f(r,0,1,64,64,[]),'MissingAssociationValidity');
mustFail(@()f(r,0,1,64,64,false),'NoValidAssociationOccasion');
bad=r; bad.Occasions=[r.Occasions;r.Occasions];
mustFail(@()f(bad,0,1,64,64,[true;true]),'DuplicateAssociationOccasion');
bad=r; bad.PeriodFrames=2; bad.PeriodCarrierSlots=40; bad.PeriodPRACHSlots=20;
mustFail(@()f(bad,0,1,64,64,true),'AssociationPatternNotImplemented');
bad=r; bad.Occasions.Frame=1;
mustFail(@()f(bad,0,1,64,64,true),'InvalidAssociationOccasions');
bad=timing(1,20,[9 19],[0 0],[0 0],[0 0]);
bad.Occasions.Ordinal=[1;3];
mustFail(@()f(bad,0:3,1,64,64,[true;true]),'InvalidAssociationOrdinal');
bad=r; bad.Occasions.Ordinal=0;
mustFail(@()f(bad,0,1,64,64,true),'InvalidAssociationOrdinal');
ok=true;
fprintf('PASS testSSBPRACHAssociation: original declared calendars; no PHY or integrated-SIB1 claim.\n');
end

function r=timing(frames,slotsPerFrame,slots,active,time,frequency)
% Declared zero-based resource fixture, deliberately not native PHY evidence.
slots=double(slots(:)); active=double(active(:)); time=double(time(:)); frequency=double(frequency(:));
count=numel(slots);
assert(all([numel(active),numel(time),numel(frequency)]==count));
% This fixture uses 30kHz PRACH slots to keep integer carrier alignment.
original=table((1:count).',floor(slots/slotsPerFrame),slots, ...
    mod(slots,slotsPerFrame),slots,active,time,frequency, ...
    'VariableNames',{'Ordinal','Frame','AbsoluteSlot','SlotWithinFrame', ...
    'PRACHSlot','ActivePRACHSlot','TimeIndex','FrequencyIndex'});
r=struct('BasePeriodFrames',frames,'PeriodFrames',frames, ...
    'BasePeriodCarrierSlots',frames*slotsPerFrame,'PeriodCarrierSlots',frames*slotsPerFrame, ...
    'BasePeriodPRACHSlots',frames*slotsPerFrame,'PeriodPRACHSlots',frames*slotsPerFrame, ...
    'Occasions',original);
end

function mustFail(fn,suffix)
caught=false;
try, fn(); catch cause
    caught=string(cause.identifier)=="sixgr:mac:ra:"+suffix;
    if ~caught, rethrow(cause); end
end
assert(caught,'Expected the specific association rejection %s.',suffix);
end
