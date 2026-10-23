function T=ssbCandidateCoordinateEvidence(cfg,indices,origins,sampleRates)
% Reporting coordinates for received SSB indices on explicit native/common
% clocks. These are case/grid coordinates, not receiver timing estimates.
indices=double(indices(:)); origins=double(origins(:)); sampleRates=double(sampleRates(:));
assert(numel(origins)==numel(indices) && numel(sampleRates)==numel(indices), ...
    'sixgr:truth:SSBCandidateClockShape','Every candidate needs its own capture origin/sample clock.');
timing=sixgr.util.structGet(cfg,'phy.ssb.timing',struct());
assert(isfield(timing,'CandidateStartSymbols') && isfield(timing,'SSBSubcarrierSpacingKHz'), ...
    'sixgr:truth:MissingSSBTimingSymbolsPerSlot','Require resolved native SSB timing.');
native=sixgr.phy.frame.AbsoluteTime.resolveNumerology(timing.SSBSubcarrierSpacingKHz);
common=sixgr.phy.frame.AbsoluteTime.resolveNumerology(cfg.phy.carrier);
names={'SSBCandidateCarrierSlot0Based','SSBCandidateSymbolWithinSlot0Based', ...
    'SSBCandidateNativeSlot0Based','SSBCandidateNativeSymbolWithinSlot0Based', ...
    'SSBCandidateNativeSCS_kHz','SSBCandidateCPStartSample','SSBCandidateEndSampleExclusive', ...
    'SSBCandidateCommonBoundaryAligned'};
T=array2table(NaN(numel(indices),numel(names)),'VariableNames',names);
T.SSBCandidateCoordinateSource=repmat("resolved_native_SSB_case_on_actual_capture_clock_not_timing_estimate",numel(indices),1);
for k=1:numel(indices)
    index=indices(k);
    if ~isfinite(index), continue; end % No invented index after failed detection.
    assert(index>=0 && index==fix(index) && index<numel(timing.CandidateStartSymbols), ...
        'sixgr:truth:SSBCandidateIndex','SSB index must select a resolved native candidate.');
    fs=sampleRates(k); origin=origins(k);
    assert(isfinite(fs) && fs>0 && isfinite(origin) && origin>=0 && origin==fix(origin), ...
        'sixgr:truth:SSBCandidateClock','Candidate coordinates need the actual captured sample clock.');
    ticks=origin*double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
    assert(abs(ticks-round(ticks))<1e-6,'sixgr:truth:SSBCandidateClock','Capture origin must lie on the NR time lattice.');
    start=sixgr.phy.frame.AbsoluteTime.fromTicks(round(ticks));
    start=start.plusSymbols(timing.CandidateStartSymbols(index+1),native);
    stop=start.plusSymbols(4,native);
    [nf,ns,nl]=start.toNumerology(native);
    [cf,cs,cl,aligned]=start.toNumerology(common);
    first=start.seconds()*fs; last=stop.seconds()*fs;
    assert(all(abs([first last]-round([first last]))<1e-6), ...
        'sixgr:truth:SSBCandidateClock','SSB boundaries are not integral on the observation sample clock.');
    T{k,1:8}=[double(cf)*common.SlotsPerFrame+double(cs),double(cl), ...
        double(nf)*native.SlotsPerFrame+double(ns),double(nl), ...
        timing.SSBSubcarrierSpacingKHz,round(first),round(last),double(aligned)];
end
end
