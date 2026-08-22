function tx = generateSRSWaveform(srsCfg)
%GENERATESRSWAVEFORM Generate real UL SRS grids and time-domain waveform.

grids = sixgr.phy.srs.mapSRSToULResourceGrid(srsCfg);
wave = [];
ofdmInfo = struct();
ofdmInfoBySlot = cell(numel(grids), 1);
windowingInfo = struct();
for ii = 1:numel(grids)
    carrier = srsCfg.ToolboxCarrier;
    carrier.NSlot = double(grids(ii).Slot);
    [windowingSamples, currentWindowingInfo] = ...
        localResolveWindowing(srsCfg, carrier);
    [w, info] = sixgr.phy.waveform.ofdmModulate( ...
        carrier, grids(ii).Grid, ...
        "Windowing", double(windowingSamples));
    wave = [wave; w]; %#ok<AGROW>
    ofdmInfoBySlot{ii} = info;
    if ii == 1
        ofdmInfo = info;
        windowingInfo = currentWindowingInfo;
    end
end
mapping = sixgr.phy.srs.generateSRSSymbolsAndIndices(srsCfg);
tx = struct();
tx.Waveform = wave;
tx.GridSlots = grids;
tx.Carrier = srsCfg.ToolboxCarrier;
tx.SRS = srsCfg.ToolboxSRS;
tx.OFDMInfo = ofdmInfo;
tx.OFDMInfoBySlot = ofdmInfoBySlot;
tx.OFDMSamplingResolution = sixgr.util.structGet( ...
    ofdmInfo, "OFDMSamplingResolution", struct());
tx.OFDMWindowing = windowingInfo;
tx.OFDMWindowingSamples = double(sixgr.util.structGet( ...
    ofdmInfo, "OFDMWindowingSamples", 0));
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

function [samples, info] = localResolveWindowing(srsCfg, carrier)
baseConfig = sixgr.util.structGet(srsCfg, "BaseConfig", struct());
[samples, info] = sixgr.phy.waveform.resolveOFDMWindowing( ...
    baseConfig, carrier);
end

function h = localHashNumeric(x)
h = string(sixgr.rrc.asn1.asn1SHA256Hex(typecast(double(x(:)).', "uint8")));
end

function h = localHashComplex(x)
data = single([real(x(:)).'; imag(x(:)).']);
h = string(sixgr.rrc.asn1.asn1SHA256Hex(typecast(data(:).', "uint8")));
end
