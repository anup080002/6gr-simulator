function sample=srsResourceStartSample(tx,slotOrigin,fs)
% Beginning of the configured SRS resource (including CP), TS 38.213 7.3.1.
% Do not derive the control deadline from incidental zero/nonzero IQ values.
validateattributes(slotOrigin,{'double'},{'scalar','integer','nonnegative','finite'});
validateattributes(fs,{'double'},{'scalar','positive','finite'});
assert(isscalar(tx.SRS),'sixgr:srs:MultiplePowerBoundariesRequired', ...
    'Each independent SRS resource requires its own power-binding event.');
c=tx.Carrier;
spec=sixgr.phy.frame.NumerologyCatalog.resolve(double(c.SubcarrierSpacing), ...
    string(c.CyclicPrefix),'generic_waveform_test','');
a=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(double(c.NSlot),0,spec);
b=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(double(c.NSlot),double(tx.SRS.SymbolStart),spec);
offset=double(b.Ticks-a.Ticks)*fs/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
assert(offset==fix(offset),'sixgr:srs:PowerBoundaryOffClock','SRS must begin on the physical sample clock.');
assert(~any(tx.Waveform(1:offset,:)~=0,'all'), ...
    'sixgr:srs:PowerBoundaryPrecursor','A nonzero windowing precursor needs an earlier explicit power commitment.');
sample=slotOrigin+offset;
end
