function ok=testPRACHSampleClock()
setup6GRSimToolkit('Verbose',false);
c=nrCarrierConfig('SubcarrierSpacing',15,'NSizeGrid',25);
p=nrPRACHConfig('DuplexMode','TDD','ConfigurationIndex',157, ...
    'SubcarrierSpacing',30,'NPRACHSlot',29,'ActivePRACHSlot',1);
t=sixgr.rach.prachSampleTiming(c,p);
assert(t.WaveformStartTime_s==0.0145 && t.CarrierSlot0==14);
assert(t.CarrierStartSymbol==7 && t.CarrierDurationSymbols==6, ...
    'B4 PRACH at 30 kHz must occupy the second half of the 15-kHz carrier slot.');
grid=nrPRACHGrid(c,p); grid(nrPRACHIndices(c,p))=nrPRACH(c,p);
[w,info]=nrPRACHOFDMModulate(c,p,grid,'Windowing',0);
nonzero=find(any(abs(w)>0,2));
assert(abs(t.ActiveStartTime_s-(t.WaveformStartTime_s+(nonzero(1)-1)/info.SampleRate))<1e-12);
assert(abs(t.ActiveEndTimeExclusive_s-(t.WaveformStartTime_s+nonzero(end)/info.SampleRate))<1e-12);
assert(abs(t.WaveformEndTimeExclusive_s-t.WaveformStartTime_s-size(w,1)/info.SampleRate)<1e-12);
r=sixgr.phy.frame.PRACHOccasionResolver.resolve('FrequencyRange','FR1', ...
    'DuplexMode','TDD','ConfigurationIndex',157,'CarrierSubcarrierSpacingKHz',15, ...
    'NSizeGrid',25,'PRACHSubcarrierSpacingKHz',30);
assert(all(r.Occasions.StartSymbol==7 & r.Occasions.DurationSymbols==6));
assert(all(r.Occasions.RARNTISymbolIndex==0 & r.Occasions.RARNTISlotIndex==9), ...
    'RA-RNTI must use PRACH slot 9 (30 kHz), not carrier slot 4 (15 kHz).');
% A nonzero cyclic shift can share a root metric with other candidates.
% Its decoded identity must be retained without changing any measured peak.
p.PreambleIndex=7;
grid(:)=0; grid(nrPRACHIndices(c,p))=nrPRACH(c,p);
w=nrPRACHOFDMModulate(c,p,grid,'Windowing',0);
oc=struct('Carrier',c,'PRACH',p);
cfg=struct('ToolboxCarrier',c,'ToolboxPRACH',p);
[idx,offset,raw]=nrPRACHDetect(c,p,w,'PreambleIndex',0:15,'DetectionThreshold',0.5);
d=sixgr.rach.PRACHDetector(w,cfg,'Occasion',oc,'CandidatePreambles',0:15, ...
    'DetectorBackend','toolbox_peak','DetectionThreshold',0.5);
assert(idx(1)==7 && d.DetectedPreambleIndex==idx(1) && d.TimingOffsetSamples==offset(1));
assert(isequal(d.CorrelationPeaks,double(raw.CorrelationPeaks(:))), ...
    'Published correlation metrics must be the unmodified measured Toolbox values.');
disp('PRACH_SAMPLE_CLOCK_PASS: mixed-numerology origin, actual support, unmodified detector metrics.');
ok=true;
end
