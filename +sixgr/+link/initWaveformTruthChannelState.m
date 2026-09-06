function state = initWaveformTruthChannelState(cfg, tx, txInfo, varargin)
%INITWAVEFORMTRUTHCHANNELSTATE Prepare the authoritative waveform impairment state.

ip = inputParser;
ip.addParameter("InitialRuntimeChannelState", struct(), ...
    @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
initialRuntimeState = ip.Results.InitialRuntimeChannelState;

fs = localResolveSampleRate(tx, txInfo);
% ChannelFactory receives the numeric waveform below, not tx.Carrier. Bind
% the already resolved producer clock explicitly so it cannot fall back to
% a different rate when an SRS/PUCCH producer names this field OFDMInfo.
txInfo = sixgr.util.structSet(txInfo,"OFDM.SampleRate",fs);
numTx = max(1, size(sixgr.util.structGet(tx, "Waveform", zeros(1, 1)), 2));
direction = localResolveDirection(cfg);
runtimeNumTx = localResolveRuntimeTxPortCapacity(cfg, direction, numTx);
numRx = localResolveRuntimeRxAntennaCount(cfg, direction, runtimeNumTx);
truthMode = sixgr.link.resolveTruthMode(cfg);

state = struct( ...
    "Initialized", true, ...
    "Direction", direction, ...
    "TruthMode", string(truthMode), ...
    "SampleRate_Hz", double(fs), ...
    "UseFading", false, ...
    "Obj", [], ...
    "RuntimeChannelState", sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), ...
    "RuntimeChannelStateUsed", false, ...
    "RuntimeChannelObjectSource", "", ...
    "ChannelPadSamples", 0, ...
    "ChannelTrimSamples", 0, ...
    "LargeScaleGain_dB", 0, ...
    "Pathloss_dB", NaN, ...
    "ShadowFading_dB", NaN, ...
    "O2ILoss_dB", NaN, ...
    "LOS", NaN, ...
    "InterferenceSIR_dB", NaN, ...
    "InterferenceVariance", NaN);

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if ~(awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF")
    ueIdx = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1))));
    servingCell = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeServingCellIndex", ...
        sixgr.util.structGet(cfg, "lls6g.userContext.ServingCell", 1)))));
    linkKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg, direction, ...
        "UEIndex", ueIdx, "ServingCell", servingCell);
    channelSeed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg, linkKey);
    if isempty(initialRuntimeState) || ...
            (isstruct(initialRuntimeState) && isempty(fieldnames(initialRuntimeState)))
        runtimeState = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, direction, ...
            "LinkKey", linkKey, "UEIndex", ueIdx, "ServingCell", servingCell, ...
            "Seed", channelSeed);
    else
        if ~(isscalar(initialRuntimeState) && ...
                isfield(initialRuntimeState, "ContractVersion") && ...
                logical(sixgr.util.structGet(initialRuntimeState, "Initialized", false)))
            error("sixgr:link:InvalidInitialRuntimeChannelState", ...
                "InitialRuntimeChannelState must be an initialized ChannelFactory state.");
        end
        runtimeState = initialRuntimeState;
    end
    if logical(sixgr.util.structGet(runtimeState,"Materialized",false))
        if ~isequal(double(runtimeState.SampleRate_Hz),fs)
            error("sixgr:link:WaveformSampleRateConflict", ...
                "A retained physical channel cannot consume a waveform on a different sample clock.");
        end
        if string(runtimeState.Direction)~=direction
            error("sixgr:link:WaveformLinkDirectionMismatch", ...
                "The scheduler must bind the correct reciprocal direction before channel materialization.");
        end
    end
    % Build the antenna view from the signal's actual logical-port count,
    % while retaining runtimeNumTx as the physical channel capacity.  This
    % lets one-port PUCCH/PRACH/PDCCH waveforms use the configured
    % port-to-element projection instead of padding silent physical ports.
    [txRuntimeAntenna, txRuntimeMeta] = localRuntimeAntennaPair(cfg, direction, "tx", numTx);
    [rxRuntimeAntenna, rxRuntimeMeta] = localRuntimeAntennaPair(cfg, direction, "rx", numRx);
    runtimeState = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        runtimeState, cfg, sixgr.util.structGet(tx, "Waveform", []), txInfo, ...
        "NumTxAnt", runtimeNumTx, "NumRxAnt", numRx, ...
        "TransmitAntennaRuntime", txRuntimeAntenna, ...
        "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
        "TransmitAntennaMeta", txRuntimeMeta, ...
        "ReceiveAntennaMeta", rxRuntimeMeta);
    slotStart = sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeSlotStartTime_s", []);
    if ~isempty(slotStart)
        if ~(isnumeric(slotStart) && isreal(slotStart) && isscalar(slotStart) && ...
                isfinite(slotStart) && slotStart >= 0)
            error("sixgr:link:InvalidRuntimeWaveformStartTime", ...
                "RuntimeSlotStartTime_s must be a finite nonnegative absolute time.");
        end
        % Control and reference waveforms share the same absolute origin
        % contract as data. Never append a declared slot to whichever time
        % another control waveform happened to leave behind.
        runtimeState = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime( ...
            runtimeState, double(slotStart), runtimeNumTx, tx.Waveform);
    end
    state.RuntimeChannelState = runtimeState;
    state.RuntimeChannelStateUsed = true;
    state.RuntimeChannelObjectSource = "sixgr.channel.ChannelFactory.materializeRuntimeChannelState";
    state.UseFading = logical(sixgr.util.structGet(runtimeState, "UseFading", false));
    state.Obj = sixgr.util.structGet(runtimeState, "Obj", []);
    state.ChannelPadSamples = double(sixgr.util.structGet(runtimeState, "ChannelPadSamples", 0));
    state.ChannelTrimSamples = double(sixgr.util.structGet(runtimeState, "ChannelTrimSamples", 0));
end

[gain_dB, pathloss_dB, shadow_dB, o2i_dB, losVal] = localResolveLargeScaleGain(cfg);
if isfinite(gain_dB)
    state.LargeScaleGain_dB = double(gain_dB);
end
state.Pathloss_dB = double(pathloss_dB);
state.ShadowFading_dB = double(shadow_dB);
state.O2ILoss_dB = double(o2i_dB);
state.LOS = double(losVal);

sir_dB = double(sixgr.util.structGet(cfg, "channel.interferenceSIR_dB", ...
    sixgr.util.structGet(cfg, "channel.interferenceMargin_dB", NaN)));
if isfinite(sir_dB)
    state.InterferenceSIR_dB = sir_dB;
end
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
    infoRate = sixgr.util.structGet(txInfo,"OFDMInfo.SampleRate",[]);
    if ~isempty(fs) && ~isempty(infoRate) && ~isequal(double(fs),double(infoRate))
        error("sixgr:link:WaveformSampleRateConflict", ...
            "OFDM and OFDMInfo must not declare different clocks for the same samples.");
    end
    if isempty(fs), fs=infoRate; end
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if ~isnumeric(fs) || ~isreal(fs) || ~isscalar(fs) || ~isfinite(fs) || fs<=0
    error("sixgr:link:WaveformSampleRateUnavailable", ...
        "The actual waveform producer must provide its sample rate or carrier; no default sample clock is permitted.");
end
fs = double(fs);
end

function direction = localResolveDirection(cfg)
direction = upper(strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeCurrentDirection", ...
    sixgr.util.structGet(cfg, "lls6g.userContext.Direction", "DL")))));
if ~isscalar(direction) || ismissing(direction) || ~any(direction == ["DL","UL"])
    error("sixgr:link:InvalidWaveformLinkDirection", ...
        "Waveform channel initialization requires DL or UL, not an inferred replacement direction.");
end
end

function numRx = localResolveRuntimeRxAntennaCount(cfg, direction, fallback)
if nargin < 3 || ~(isnumeric(fallback) && isscalar(fallback) && isfinite(fallback) && fallback >= 1)
    fallback = 1;
end
direction = upper(strtrim(string(direction)));
if direction == "UL"
    numRx = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", fallback));
    return;
end
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
numRx = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumPorts", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumPorts", []), ...
    sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", []), ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", []), ...
    sixgr.util.structGet(cfg, "channel.nRxAnt", []), ...
    fallback);
numRx = max(1, round(double(numRx)));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    vals = double(raw(:));
    vals = vals(isfinite(vals) & vals >= 1);
    if ~isempty(vals)
        value = double(vals(1));
        return;
    end
end
end

function numTx = localResolveRuntimeTxPortCapacity(cfg, direction, activePortCount)
activePortCount = max(1, round(double(activePortCount)));
direction = upper(strtrim(string(direction)));
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
if direction == "UL"
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumLogicalPorts", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxULLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", []), ...
        activePortCount);
else
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumLogicalPorts", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxDLLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", []), ...
        activePortCount);
    if isfinite(numTx) && numTx > 32
        numTx = activePortCount;
    end
end
numTx = max(activePortCount, round(double(numTx)));
end

function [ant, meta] = localRuntimeAntennaPair(cfg, direction, endpoint, signalPortCount)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
role = localRuntimeRole(direction, endpoint);
if role == "BS"
    ant = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
else
    ant = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
end
[needsPortView, portViewSource] = localNeedsSignalPortView(cfg, direction, endpoint, signalPortCount);
if needsPortView
    [ant, meta] = sixgr.rf.AntennaArrayFactory.logicalPortView( ...
        ant, meta, signalPortCount, portViewSource);
    [ant, meta] = localApplyConfiguredSignalProjection( ...
        cfg, ant, meta, direction, endpoint, signalPortCount);
end
end

function [ant, meta] = localApplyConfiguredSignalProjection( ...
        cfg, ant, meta, direction, endpoint, signalPortCount)
signalFamily = upper(strtrim(string(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.RuntimeSignalFamily", ...
    sixgr.util.structGet(cfg, "phy.runtimeSignalFamily", "")))));
if ~(upper(strtrim(string(direction))) == "DL" && ...
        lower(strtrim(string(endpoint))) == "tx" && ...
        ismember(signalFamily, ["PBCH","SSB"]))
    return;
end
waveformDomain = localResolveSSBWaveformDomain(cfg);
if waveformDomain ~= "logical_rf_chain_post_analog_precoder"
    error("sixgr:link:UnexpectedSSBSignalProjection", ...
        ["An SSB/PBCH port-to-element projection may only be applied to " ...
         "logical_rf_chain_post_analog_precoder waveforms; the configured " ...
         "domain is '%s'."], char(waveformDomain));
end
if signalPortCount ~= 1
    error("sixgr:link:SSBBeamRequiresSingleLogicalPort", ...
        ["SSB/PBCH runtime propagation in the logical RF-chain domain " ...
         "requires one logical common-channel waveform column; observed %d."], ...
        round(double(signalPortCount)));
end
matrices = sixgr.util.structGet(cfg, "phy.ssb.precoderMatrices", []);
selectedIndex = double(sixgr.util.structGet(cfg, ...
    "phy.ssb.runtimeSSBIndex", NaN));
numElements = round(localFirstFiniteScalar( ...
    sixgr.util.structGet(meta, "NumElements", []), ...
    sixgr.util.structGet(ant, "NumElements", []), ...
    sixgr.util.structGet(ant, "Nant", []), NaN));
if ~(isnumeric(matrices) && ismatrix(matrices) && ...
        isfinite(numElements) && size(matrices, 2) == numElements && ...
        isfinite(selectedIndex) && selectedIndex == fix(selectedIndex) && ...
        selectedIndex >= 0 && selectedIndex < size(matrices, 1))
    error("sixgr:link:ConfiguredSSBBeamUnavailable", ...
        ["Physical SSB/PBCH propagation requires the YAML-resolved SSB " ...
         "precoder matrix and a valid zero-based selected SSB index."]);
end
projection = matrices(selectedIndex + 1, :).';
residual = norm(projection' * projection - 1, "fro");
if residual > 1e-9
    error("sixgr:link:ConfiguredSSBBeamNotPowerPreserving", ...
        "The selected SSB beam is not unit norm (residual %.3g).", residual);
end
ids = string(sixgr.util.structGet(cfg, ...
    "phy.ssb.precoderIDs", strings(0, 1)));
beamId = "ssb_index_" + string(selectedIndex);
if numel(ids) >= selectedIndex + 1
    beamId = ids(selectedIndex + 1);
end
ant.PortToElementMatrix = projection;
ant.ElementToPortMatrix = projection';
ant.HybridElementToPortMatrix = projection;
ant.HybridBeamformingEnabled = true;
ant.PortToElementMappingSource = "yaml_selected_ssb_precoder";
ant.SelectedBeamId = char(beamId);
meta.PortToElementMatrix = projection;
meta.HybridBeamformingEnabled = true;
meta.PortToElementMappingSource = "yaml_selected_ssb_precoder";
meta.SelectedBeamId = char(beamId);
end

function role = localRuntimeRole(direction, endpoint)
direction = upper(strtrim(string(direction)));
endpoint = lower(strtrim(string(endpoint)));
if direction == "UL"
    if endpoint == "tx"
        role = "UE";
    else
        role = "BS";
    end
else
    if endpoint == "tx"
        role = "BS";
    else
        role = "UE";
    end
end
end

function [tf, sourceToken] = localNeedsSignalPortView(cfg, direction, endpoint, signalPortCount)
tf = false;
sourceToken = "";
if ~(isnumeric(signalPortCount) && isscalar(signalPortCount) && isfinite(signalPortCount) && signalPortCount >= 1)
    return;
end
direction = upper(strtrim(string(direction)));
endpoint = lower(strtrim(string(endpoint)));
signalFamily = upper(strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.RuntimeSignalFamily", ...
    sixgr.util.structGet(cfg, "phy.runtimeSignalFamily", "")))));
if direction == "DL" && endpoint == "tx"
    switch signalFamily
        case "PDCCH"
            tf = true;
            sourceToken = "pdcch_runtime_waveform_port_count";
        case "PDSCH"
            tf = true;
            sourceToken = "pdsch_runtime_waveform_port_count";
        case {"PBCH","SSB"}
            waveformDomain = localResolveSSBWaveformDomain(cfg);
            if waveformDomain == "physical_element_domain"
                expectedElements = localResolveSSBPhysicalElementCount(cfg);
                if ~(isfinite(expectedElements) && ...
                        round(double(signalPortCount)) == expectedElements)
                    error("sixgr:link:SSBPhysicalElementCountMismatch", ...
                        ["SSB/PBCH physical_element_domain propagation " ...
                         "requires one waveform column per configured physical " ...
                         "element; observed %d columns and expected %d elements."], ...
                        round(double(signalPortCount)), expectedElements);
                end
                % SSB_Tx has already applied the per-candidate beam weights to
                % the physical-element waveform.  Retain the physical runtime
                % array and never apply the same precoder a second time.
                tf = false;
                sourceToken = "ssb_pbch_physical_element_waveform_already_precoded";
            else
                if round(double(signalPortCount)) ~= 1
                    error("sixgr:link:SSBBeamRequiresSingleLogicalPort", ...
                        ["SSB/PBCH logical_rf_chain_post_analog_precoder " ...
                         "propagation requires one waveform column; observed %d."], ...
                        round(double(signalPortCount)));
                end
                tf = true;
                sourceToken = "ssb_pbch_logical_rf_chain_waveform_port_count";
            end
        case {"TRS","CSI-RS","CSIRS"}
            tf = true;
            sourceToken = "dl_reference_signal_runtime_waveform_port_count";
    end
    if tf
        return;
    end
end
if ~(direction == "UL" && endpoint == "tx")
    return;
end
switch signalFamily
    case "PUSCH"
        tf = true;
        sourceToken = "pusch_runtime_waveform_port_count";
    case "PUCCH"
        tf = true;
        sourceToken = "pucch_runtime_waveform_port_count";
    case "PRACH"
        tf = true;
        sourceToken = "prach_runtime_waveform_port_count";
    case "SRS"
        tf = true;
        sourceToken = "srs_runtime_waveform_port_count";
end
end

function domain = localResolveSSBWaveformDomain(cfg)
domain = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "phy.ssb.waveformDomain", "physical_element_domain"))));
allowed = ["physical_element_domain", ...
    "logical_rf_chain_post_analog_precoder"];
if ~isscalar(domain) || ~any(domain == allowed)
    error("sixgr:phy:ia:InvalidSSBWaveformDomain", ...
        "phy.ssb.waveformDomain must be one of: %s.", ...
        char(strjoin(allowed, ", ")));
end
end

function count = localResolveSSBPhysicalElementCount(cfg)
matrices = sixgr.util.structGet(cfg, "phy.ssb.precoderMatrices", []);
matrixCount = NaN;
if isnumeric(matrices) && ismatrix(matrices) && ~isempty(matrices)
    matrixCount = size(matrices, 2);
elseif iscell(matrices) && ~isempty(matrices) && ...
        isnumeric(matrices{1}) && ismatrix(matrices{1})
    matrixCount = size(matrices{1}, 2);
end
count = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.ssb.precoderPhysicalElementCount", []), ...
    sixgr.util.structGet(cfg, ...
        "initial_access.ssb.precoder_codebook.physical_element_count", []), ...
    matrixCount);
if ~(isfinite(count) && count == fix(count) && count >= 1)
    error("sixgr:link:MissingSSBPhysicalElementCount", ...
        ["physical_element_domain requires a positive integer physical " ...
         "element count from YAML or the resolved SSB precoder matrices."]);
end
count = round(double(count));
end
function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, fs)
padSamples = 0;
trimSamples = 0;
if isempty(chObj) || ~isfinite(double(fs)) || double(fs) <= 0
    return;
end
filterDelay = 0;
pathDelays = [];
try
    chInfo = info(chObj);
    filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
end
if isempty(pathDelays)
    try
        pathDelays = double(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end
maxPathDelay = 0;
if ~isempty(pathDelays)
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function [gain_dB, pathloss_dB, shadow_dB, o2i_dB, losVal] = localResolveLargeScaleGain(cfg)
gain_dB = 0;
pathloss_dB = NaN;
shadow_dB = NaN;
o2i_dB = NaN;
losVal = NaN;

explicitGain = double(sixgr.util.structGet(cfg, "channel.largeScaleGain_dB", NaN));
if isfinite(explicitGain)
    gain_dB = explicitGain;
    pathloss_dB = -explicitGain;
    return;
end

explicitPathloss = double(sixgr.util.structGet(cfg, "channel.pathloss_dB", NaN));
if isfinite(explicitPathloss)
    gain_dB = -explicitPathloss;
    pathloss_dB = explicitPathloss;
    return;
end

pathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
shadowEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false));
losEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", false));
modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
needsLargeScale = pathlossEnabled || shadowEnabled || any(modelRaw == ["TR38901", "TR38.901", "TR38_901", "ABG", "RAYTRACING", "RT"]);
if ~needsLargeScale
    return;
end

scenarioName = string(sixgr.util.structGet(cfg, "channel.propagationScenario", ...
    sixgr.util.structGet(cfg, "run.scenario", ...
    sixgr.util.structGet(cfg, "scenario.profileName", "UMa"))));
fc_Hz = double(sixgr.util.structGet(cfg, "phy.fc_Hz", sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9)));
seed = double(sixgr.util.structGet(cfg, "run.seed", 1));

[txPos_m, rxPos_m, indoorRx, indoorDistance_m] = localResolveSingleLinkGeometry(cfg);
if any(modelRaw == ["RAYTRACING", "RT"])
    plModel = sixgr.channel.RayTracingAdapter(cfg, "Scenario", scenarioName, "Fc_Hz", fc_Hz);
    [pl_dB, det] = plModel.pathloss(txPos_m, rxPos_m);
    pl_dB = double(pl_dB);
    los = NaN;
    ex = struct("shadow_dB", NaN, "o2i_dB", NaN);
    if isstruct(det) && isfield(det, "pl_dB")
        pl_dB = double(det.pl_dB);
    end
else
    plModel = sixgr.channel.TR38901Plus(cfg, "Scenario", scenarioName, "Fc_Hz", fc_Hz, "Seed", seed);
    [pl_dB, los, ex] = plModel.pathloss(txPos_m, rxPos_m, ...
        "Scenario", scenarioName, ...
        "IndoorRx", indoorRx, ...
        "IndoorDistance_m", indoorDistance_m, ...
        "PathlossEnabled", pathlossEnabled, ...
        "ShadowFadingEnabled", shadowEnabled, ...
        "LOSEnabled", losEnabled);
end

pl_dB = double(pl_dB);
if isempty(pl_dB)
    return;
end
pathloss_dB = double(pl_dB(1));
gain_dB = -double(pathloss_dB);
if isstruct(ex)
    shadow_dB = double(sixgr.util.structGet(ex, "shadow_dB", NaN));
    if numel(shadow_dB) >= 1
        shadow_dB = double(shadow_dB(1));
    end
    o2i_dB = double(sixgr.util.structGet(ex, "o2i_dB", NaN));
    if numel(o2i_dB) >= 1
        o2i_dB = double(o2i_dB(1));
    end
end
if exist("los", "var") && ~isempty(los)
    losVal = double(los(1));
end
end

function [txPos_m, rxPos_m, indoorRx, indoorDistance_m] = localResolveSingleLinkGeometry(cfg)
bsDefault = [0; 0; 25];
ueIdx = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1))));
ueDefault = [100 + 10 * (ueIdx - 1); 0; 1.5];

txPos_m = localResolvePosition(cfg, ...
    ["scenario.bs.position_m","scenario.bs.pos_m","scenario.base_station.position_m"], ...
    bsDefault);
rxPos_m = localResolvePosition(cfg, ...
    ["lls6g.userContext.Position_m","scenario.ue.position_m","scenario.ue.pos_m"], ...
    ueDefault);
indoorRx = logical(sixgr.util.structGet(cfg, "lls6g.userContext.Indoor", ...
    sixgr.util.structGet(cfg, "scenario.ue.indoor", false)));
indoorDistance_m = double(sixgr.util.structGet(cfg, "channel.o2i.indoorDistance_m", 10));
if ~(isfinite(indoorDistance_m) && indoorDistance_m >= 0)
    indoorDistance_m = 10;
end
end

function pos = localResolvePosition(cfg, candidates, fallback)
pos = [];
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, char(candidates(i)), []);
    pos = localAsPositionColumn(raw);
    if ~isempty(pos)
        return;
    end
end
pos = localAsPositionColumn(fallback);
end

function pos = localAsPositionColumn(raw)
pos = [];
if isempty(raw)
    return;
end
if iscell(raw)
    try
        raw = cell2mat(raw);
    catch
        return;
    end
end
raw = double(raw);
if isequal(size(raw), [1 3])
    pos = raw(:);
elseif isequal(size(raw), [3 1])
    pos = raw;
elseif ndims(raw) == 2 && size(raw, 2) == 3 && size(raw, 1) >= 1
    pos = raw(1, :).';
elseif ndims(raw) == 2 && size(raw, 1) == 3 && size(raw, 2) >= 1
    pos = raw(:, 1);
end
if isempty(pos) || numel(pos) ~= 3 || any(~isfinite(pos))
    pos = [];
end
end
