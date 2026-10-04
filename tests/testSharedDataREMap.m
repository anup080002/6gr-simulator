function ok=testSharedDataREMap()
% Shared SLS/calibration population must be exact, not an allocated rectangle.
carrier=nrCarrierConfig;
carrier.NSizeGrid=24;
carrier.NStartGrid=10;
carrier.SubcarrierSpacing=30;
carrier.NSlot=7;
plane=12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
for name=["PDSCH","PUSCH"]
    for layers=[1 2 4]
        if name=="PDSCH"
            ch=nrPDSCHConfig;
        else
            ch=nrPUSCHConfig;
            ch.TransformPrecoding=false;
            ch.TransmissionScheme='nonCodebook';
        end
        ch.NStartBWP=12; ch.NSizeBWP=18;
        ch.PRBSet=[1 2 5 6]; ch.SymbolAllocation=[0 14];
        ch.NumLayers=layers; ch.Modulation='16QAM';
        ch.DMRS.DMRSPortSet=0:layers-1;
        ch.DMRS.NumCDMGroupsWithoutData=2;
        ch.EnablePTRS=true;
        ch.PTRS.TimeDensity=1; ch.PTRS.FrequencyDensity=2;
        if name=="PDSCH"
            % Explicit reserved data RE within the BWP, outside DM-RS.
            ch.ReservedRE=12;
            [native,info]=nrPDSCHIndices(carrier,ch);
            dmrs=nrPDSCHDMRSIndices(carrier,ch);
            ptrs=nrPDSCHPTRSIndices(carrier,ch);
        else
            [native,info]=nrPUSCHIndices(carrier,ch);
            dmrs=nrPUSCHDMRSIndices(carrier,ch);
            ptrs=nrPUSCHPTRSIndices(carrier,ch);
        end
        m=sixgr.phy.resource.sharedDataREMap(carrier,ch);
        assert(isequal(m.NativeIndices1Based,double(native)));
        assert(m.NumLayers==layers && m.NativeIndexPlaneCount==layers);
        assert(m.PhysicalRECount==info.Gd && ...
            m.LayerRECount==info.Gd*layers && ...
            isequal(m.CodedBitsPerCodeword,double(info.G(:).')));
        assert(isequal(m.LayerIndices1Based,double(native)));
        assert(m.PhysicalRECount<12*numel(ch.PRBSet)*14);
        assert(~isempty(ptrs) && ~isempty(dmrs));
        assert(isempty(intersect(m.PhysicalIndices1Based,mod(double(dmrs(:))-1,plane)+1)));
        assert(isempty(intersect(m.PhysicalIndices1Based,mod(double(ptrs(:))-1,plane)+1)));
        assert(all(ismember(floor(m.Coordinates0Based(:,1)/12),ch.PRBSet+2)));
        assert(~m.WaveformBacked && contains(m.Source,'not_waveform_evidence'));
        if name=="PDSCH"
            assert(~ismember(12+24+1,m.PhysicalIndices1Based));
        end
    end
end
% Four UL transmission ports must NOT create four independent data layers.
ch=nrPUSCHConfig;
ch.PRBSet=0:5; ch.NumLayers=2;
ch.TransmissionScheme='codebook'; ch.NumAntennaPorts=4; ch.TPMI=0;
ch.DMRS.DMRSPortSet=0:1;
m=sixgr.phy.resource.sharedDataREMap(carrier,ch);
assert(m.NumLayers==2 && m.NativeIndexPlaneCount==4 && ...
    size(m.NativeIndices1Based,2)==4 && size(m.LayerIndices1Based,2)==2);
assert(m.LayerRECount==2*m.PhysicalRECount);
% Frequency-hopped CP-OFDM remains native-mapped, not rectangular.
ch=nrPUSCHConfig; ch.PRBSet=0:3;
ch.FrequencyHopping='intraSlot'; ch.SecondHopStartPRB=10;
m=sixgr.phy.resource.sharedDataREMap(carrier,ch);
assert(any(m.Coordinates0Based(:,1)>=120) && any(m.Coordinates0Based(:,1)<48));
ch.TransformPrecoding=true;
reject(@()sixgr.phy.resource.sharedDataREMap(carrier,ch), ...
    'sixgr:phy:resource:SharedDataTransformPrecoding');
reject(@()sixgr.phy.resource.sharedDataREMap(carrier,struct()), ...
    'sixgr:phy:resource:SharedDataChannel');
ok=true;
fprintf('SHARED_DATA_RE_MAP_PASS native_order=1 ports_not_layers=1 no_rectangle_fallback=1\n');
end

function reject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return
end
error('test:MissingRejection','Expected %s.',id);
end
