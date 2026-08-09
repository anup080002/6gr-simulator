function cfg = buildPHYConfig(llsCfg, snrDb)
%BUILDPHYCONFIG Bind the clean LLS YAML to existing production PUSCH PHY.

arguments
    llsCfg (1,1) struct
    snrDb (1,1) double {mustBeFinite}
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.strictNoiseVarianceRequired = true;
cfg.run.useMex = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

cfg.channel.model = char(string(llsCfg.channel.model));
cfg.channel.awgnOnly = strcmpi(string(llsCfg.channel.model), "AWGN");
if startsWith(upper(string(llsCfg.channel.model)), "TDL-")
    cfg.channel.tdlProfile = char(upper(string(llsCfg.channel.model)));
elseif startsWith(upper(string(llsCfg.channel.model)), "CDL-")
    cfg.channel.cdlProfile = char(upper(string(llsCfg.channel.model)));
end
cfg.channel.fading.delaySpread_s = double(llsCfg.channel.delaySpreadSeconds);
cfg.channel.fading.velocity_kmh = double(llsCfg.channel.velocityKmph);
cfg.channel.snr_dB = double(snrDb);
cfg.channel.nTxAnt = double(llsCfg.channel.txAntennas);
cfg.channel.nRxAnt = double(llsCfg.channel.rxAntennas);
cfg.phy.nTxAnt = double(llsCfg.channel.txAntennas);
cfg.phy.nRxAnt = double(llsCfg.channel.rxAntennas);
link = upper(string(llsCfg.simulation.link));
if link == "PUSCH"
    cfg.scenario.ue.nTxAnt = double(llsCfg.channel.txAntennas);
    cfg.scenario.bs.nRxAnt = double(llsCfg.channel.rxAntennas);
    cfg.antenna.ue.numElements = double(llsCfg.channel.txAntennas);
    cfg.antenna.bs.numElements = double(llsCfg.channel.rxAntennas);
else
    cfg.scenario.bs.nTxAnt = double(llsCfg.channel.txAntennas);
    cfg.scenario.ue.nRxAnt = double(llsCfg.channel.rxAntennas);
    cfg.antenna.bs.numElements = double(llsCfg.channel.txAntennas);
    cfg.antenna.ue.numElements = double(llsCfg.channel.rxAntennas);
end

cfg.phy.carrier.NCellID = double(llsCfg.carrier.nCellId);
cfg.phy.carrier.SubcarrierSpacing = double(llsCfg.carrier.subcarrierSpacingKHz);
cfg.phy.carrier.NSizeGrid = double(llsCfg.carrier.nSizeGrid);
cfg.phy.carrier.NStartGrid = 0;
cfg.phy.carrier.NSlot = 0;
cfg.phy.carrier.NFrame = 0;
cfg.phy.carrier.CyclicPrefix = char(string(llsCfg.carrier.cyclicPrefix));

firstPRB = double(llsCfg.allocation.startPRB);
numPRB = double(llsCfg.allocation.numberPRB);
linkCfg = llsCfg.(lower(char(link)));
if link == "PUSCH"
    cfg.phy.pusch.prbSet = firstPRB:(firstPRB + numPRB - 1);
    cfg.phy.pusch.symbolAllocation = double(llsCfg.allocation.symbols(:).');
    cfg.phy.pusch.mappingType = char(string(llsCfg.allocation.mappingType));
    cfg.phy.pusch.modulation = char(string(linkCfg.modulation));
    cfg.phy.pusch.codeRate = double(linkCfg.targetCodeRate);
    cfg.phy.pusch.mcsIndex = double(linkCfg.mcsIndex);
    cfg.phy.pusch.numLayers = double(linkCfg.numberLayers);
    cfg.phy.pusch.nLayers = double(linkCfg.numberLayers);
    cfg.phy.pusch.numAntennaPorts = double(linkCfg.numberAntennaPorts);
    cfg.phy.pusch.NumAntennaPorts = double(linkCfg.numberAntennaPorts);
    cfg.phy.pusch.numPorts = double(linkCfg.numberAntennaPorts);
    cfg.phy.pusch.transmissionScheme = char(string(linkCfg.transmissionScheme));
    cfg.phy.pusch.transformPrecoding = logical(linkCfg.transformPrecoding);
    cfg.phy.pusch.RNTI = double(linkCfg.rnti);
    cfg.phy.pusch.NID = double(linkCfg.nid);
    cfg.phy.pusch.rv = double(linkCfg.rv);
    cfg.phy.pusch.xOverhead = double(linkCfg.xOverhead);
    cfg.phy.pusch.enablePTRS = logical(linkCfg.ptrs.enabled);
    cfg.phy.pusch.dmrs.typeAPosition = double(linkCfg.dmrs.typeAPosition);
    cfg.phy.pusch.dmrs.configurationType = double(linkCfg.dmrs.configurationType);
    cfg.phy.pusch.dmrs.additionalPositions = double(linkCfg.dmrs.additionalPositions);
    cfg.phy.pusch.dmrs.length = double(linkCfg.dmrs.length);
    cfg.phy.pusch.dmrs.numCDMGroupsWithoutData = double(linkCfg.dmrs.numCDMGroupsWithoutData);
    cfg.phy.pusch.dmrs.portSet = double(linkCfg.dmrs.portSet(:).');
    cfg.phy.pusch.dmrs.groupHopping = logical(linkCfg.dmrs.groupHopping);
    cfg.phy.pusch.dmrs.sequenceHopping = logical(linkCfg.dmrs.sequenceHopping);
else
    cfg.phy.pdsch.prbSet = firstPRB:(firstPRB + numPRB - 1);
    cfg.phy.pdsch.symbolAllocation = double(llsCfg.allocation.symbols(:).');
    cfg.phy.pdsch.mappingType = char(string(llsCfg.allocation.mappingType));
    cfg.phy.pdsch.modulation = char(string(linkCfg.modulation));
    cfg.phy.pdsch.codeRate = double(linkCfg.targetCodeRate);
    cfg.phy.pdsch.mcsIndex = double(linkCfg.mcsIndex);
    cfg.phy.pdsch.mcsTable = char(string(linkCfg.mcsTable));
    cfg.phy.pdsch.mcsContext = struct( ...
        "UECapability1024QAM", logical(linkCfg.mcsContext.ueCapability1024QAM), ...
        "RRCEnabled1024QAM", logical(linkCfg.mcsContext.rrcEnabled1024QAM), ...
        "DCIEnabled1024QAM", logical(linkCfg.mcsContext.dciEnabled1024QAM), ...
        "DeploymentAllows1024QAM", logical(linkCfg.mcsContext.deploymentAllows1024QAM), ...
        "FrequencyRangeAllows1024QAM", logical(linkCfg.mcsContext.frequencyRangeAllows1024QAM), ...
        "BandAllows1024QAM", logical(linkCfg.mcsContext.bandAllows1024QAM), ...
        "FrequencyRange", char(string(linkCfg.mcsContext.frequencyRange)), ...
        "OperatingBand", char(string(linkCfg.mcsContext.operatingBand)), ...
        "DeploymentClass", char(string(linkCfg.mcsContext.deploymentClass)));
    cfg.phy.pdsch.numLayers = double(linkCfg.numberLayers);
    cfg.phy.pdsch.nLayers = double(linkCfg.numberLayers);
    cfg.phy.pdsch.numPorts = double(linkCfg.numberAntennaPorts);
    cfg.phy.pdsch.nPorts = double(linkCfg.numberAntennaPorts);
    cfg.phy.pdsch.RNTI = double(linkCfg.rnti);
    cfg.phy.pdsch.NID = double(linkCfg.nid);
    cfg.phy.pdsch.rv = double(linkCfg.rv);
    cfg.phy.pdsch.xOverhead = double(linkCfg.xOverhead);
    cfg.phy.pdsch.enablePTRS = logical(linkCfg.ptrs.enabled);
    cfg.phy.pdsch.executionProfile = "phy_calibration";
    cfg.run.pdschExecutionProfile = "phy_calibration";
    cfg.phy.pdsch.dmrs.typeAPosition = double(linkCfg.dmrs.typeAPosition);
    cfg.phy.pdsch.dmrs.configurationType = double(linkCfg.dmrs.configurationType);
    cfg.phy.pdsch.dmrs.additionalPositions = double(linkCfg.dmrs.additionalPositions);
    cfg.phy.pdsch.dmrs.length = double(linkCfg.dmrs.length);
    cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = double(linkCfg.dmrs.numCDMGroupsWithoutData);
    cfg.phy.pdsch.dmrs.portSet = double(linkCfg.dmrs.portSet(:).');
    cfg.phy.csirs.enable = false;
    cfg.phy.csirs.enabled = false;
end

cfg.phy.rx.channelEstimation = char(string(llsCfg.receiver.channelEstimation));
cfg.phy.channelEstimation.method = localEstimatorToken(llsCfg.receiver.channelEstimation);
cfg.phy.rx.equalizer = char(string(llsCfg.receiver.equalizer));
cfg.phy.pusch.equalizer = char(string(llsCfg.receiver.equalizer));
cfg.phy.pdsch.equalizer = char(string(llsCfg.receiver.equalizer));
cfg.phy.ldpc.maxIterations = double(llsCfg.receiver.ldpcMaxIterations);
cfg.phy.ldpc.algorithm = char(string(llsCfg.receiver.ldpcAlgorithm));
cfg.phy.harq.enable = false;
cfg.mac.harq.enable = false;
end

function token = localEstimatorToken(value)
if strcmpi(string(value), "perfect")
    token = "ideal";
else
    token = "LS";
end
end
