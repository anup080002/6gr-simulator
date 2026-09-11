function horizons=ssbObservationHorizons(cfg,fs)
% Complete per-occasion prefix extents on the actual capture sample clock.
% The configured search guard covers receive timing uncertainty. No true
% propagation delay, TX samples or receiver estimate chooses the deadline.
validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
indices=double(sixgr.util.structGet(cfg,'phy.ssb.activeCandidateIndices0Based',[]));
validateattributes(indices,{'numeric'},{'vector','nonempty','integer','nonnegative','finite'});
assert(numel(unique(indices))==numel(indices),'sixgr:phy:frame:DuplicateSSBObservation','SSB occasions must be unique.');
[guard,source]=sixgr.phy.sync.resolveTimingSearchGuard(cfg,fs);
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
assert(tc==fix(tc),'sixgr:phy:frame:SSBObservationOffSampleClock','The sample clock must be integral in Tc.');
first=zeros(numel(indices),1); last=first;
for k=1:numel(indices)
    hit=find(timing.CandidateIndices==indices(k));
    assert(isscalar(hit),'sixgr:phy:frame:UnknownSSBObservation','Each requested SSB needs one canonical timing entry.');
    symbol=double(timing.CandidateStartSymbolsWithinHalfFrame(hit));
    starts=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor(symbol/14),mod(symbol,14),timing.Mu);
    ends=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor((symbol+4)/14),mod(symbol+4,14),timing.Mu);
    assert(rem(starts.Ticks,int64(tc))==0 && rem(ends.Ticks,int64(tc))==0, ...
        'sixgr:phy:frame:SSBObservationOffSampleClock','SSB symbols must lie on the observation sample clock.');
    first(k)=double(starts.Ticks)/tc;
    last(k)=double(ends.Ticks)/tc;
end
horizons=table(indices(:),first,last,last+guard,repmat(double(fs),numel(indices),1), ...
    repmat(double(guard),numel(indices),1),repmat(string(source),numel(indices),1), ...
    'VariableNames',{'SSBIndex','SSBStartSample','SSBEndSampleExclusive', ...
    'ObservationEndSampleExclusive','SampleRateHz','TimingGuardSamples','TimingGuardSource'});
end
