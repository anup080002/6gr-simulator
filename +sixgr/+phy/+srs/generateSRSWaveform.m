function tx = generateSRSWaveform(srsCfg)
%GENERATESRSWAVEFORM Generate real UL SRS grids and time-domain waveform.

grids = sixgr.phy.srs.mapSRSToULResourceGrid(srsCfg);
wave = [];
ofdmInfo = struct();
for ii = 1:numel(grids)
    carrier = srsCfg.ToolboxCarrier;
    carrier.NSlot = double(grids(ii).Slot);
    [w, info] = nrOFDMModulate(carrier, grids(ii).Grid);
    wave = [wave; w]; %#ok<AGROW>
    if ii == 1
        ofdmInfo = info;
    end
end
mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
tx = struct();
tx.Waveform = wave;
tx.GridSlots = grids;
tx.Carrier = srsCfg.ToolboxCarrier;
tx.SRS = srsCfg.ToolboxSRS;
tx.OFDMInfo = ofdmInfo;
tx.Mapping = mapping;
tx.ConfigHash = string(srsCfg.ConfigHash);
tx.TxResourceIndicesHash = localHashNumeric(vertcat(grids.Indices));
tx.TxSRSSymbolHash = localHashComplex(vertcat(grids.Symbols));
tx.TxULGridHash = localHashComplex(cat(1, grids.Grid));
tx.TxWaveformHash = localHashComplex(wave);
tx.ExpectedRECount = height(mapping.ResourceMappingTable);
tx.ExpectedRBCount = double(mapping.Coverage.OccupiedPRBCount);
tx.ExpectedCoverageStatus = string(mapping.Coverage.BandwidthCoverageStatus);
end

function h = localHashNumeric(x)
h = string(sixgr.rrc.asn1.sha256Hex(typecast(double(x(:)).', "uint8")));
end

function h = localHashComplex(x)
data = single([real(x(:)).'; imag(x(:)).']);
h = string(sixgr.rrc.asn1.sha256Hex(typecast(data(:).', "uint8")));
end
