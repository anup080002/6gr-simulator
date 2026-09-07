function [cfgOut, evidenceT] = installDecodedSIB1RACHConfig(cfgIn, sib1Evidence)
%INSTALLDECODEDSIB1RACHCONFIG Apply decoded SIB1 RACH common config.
%
% SIB1 owns rach-ConfigCommon. This helper maps the decoded RRC tree into
% the simulator random_access subtree while preserving explicitly configured
% simulator-only scheduling fields such as Msg2/Msg3/Msg4 mini-anchor slots
% and PRB allocations.

if nargin < 1 || isempty(cfgIn)
    cfgIn = struct();
end
if nargin < 2 || isempty(sib1Evidence)
    error("sixgr:mac:ra:MissingSIB1Evidence", ...
        "Decoded SIB1 evidence is required to install RACH common config.");
end

[tree, payloadHash, treeHash] = localResolveSIB1Tree(sib1Evidence);
try
    sib1 = tree.message.c1.systemInformationBlockType1;
    serving = sib1.servingCellConfigCommon;
    ul = serving.uplinkConfigCommon.initialUplinkBWP;
    ulGeneric = ul.genericParameters;
    rach = ul.rach_ConfigCommon;
    puschCommon = sixgr.util.structGet(ul, "pusch_ConfigCommon", struct());
    pucchCommon = sixgr.util.structGet(ul, "pucch_ConfigCommon", struct());
catch ME
    error("sixgr:mac:ra:MissingDecodedRACHConfigCommon", ...
        "Decoded SIB1 tree does not contain uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon: %s", ME.message);
end

cfgOut = cfgIn;
ra = sixgr.util.structGet(cfgOut, "random_access", struct());
if ~(isstruct(ra) && ~isempty(fieldnames(ra)))
    ra = struct();
end

% TS 38.331 BWP.locationAndBandwidth uses the TS 38.214 type-1 RIV
% definition with N_BWP=275, not the carrier width and not a literal RB count.
riv = double(ulGeneric.locationAndBandwidth);
[initialUlBwpStart, initialUlBwpSize] = sixgr.bwop.RIVFDRA.decode(275, riv);
if sixgr.bwop.RIVFDRA.encode(275, initialUlBwpStart, initialUlBwpSize) ~= riv
    error("sixgr:mac:ra:InvalidDecodedBWPRIV", "Decoded initial UL BWP RIV is noncanonical.");
end
initialUlBwpSCSkHz = localSCSNameToKHz(sixgr.util.structGet(ulGeneric, "subcarrierSpacing", ""));
initialUlBwpCP = string(sixgr.util.structGet(ulGeneric, "cyclicPrefix", "normal"));
prachSCSkHz = double(sixgr.util.structGet(rach, "msg1SubcarrierSpacing_kHz", initialUlBwpSCSkHz));
restrictedSet = string(sixgr.util.structGet(rach, "restrictedSet", "UnrestrictedSet"));

rows = repmat(localRow(), 0, 1);
ssPower = double(sixgr.util.structGet(serving,'ss_PBCH_BlockPower',NaN));
validateattributes(ssPower,{'numeric'},{'scalar','real','finite','integer','>=',-60,'<=',50});
[ra, rows] = localApply(rows, ra, "ss_pbch_block_power_dbm", ssPower, ...
    "SIB1.servingCellConfigCommon.ss-PBCH-BlockPower", ...
    "Received SSS EPRE declaration; not a transmitter-measurement oracle.", ...
    "dBm/RE", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "enabled", true, "decoded_sib1_control", ...
    "SIB1 presence enables RA common config", "boolean", "n/a", "decoded");
[ra, rows] = localApply(rows, ra, "binding_source", "decoded_sib1_rach_config_common", "decoded_sib1", ...
    "Binding source selected by recovered SIB1 tree", "enum", "n/a", "decoded");
[ra, rows] = localApply(rows, ra, "initial_ul_bwp_start", initialUlBwpStart, ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.genericParameters.locationAndBandwidth", ...
    "TS 38.331 locationAndBandwidth decoded with reference N_BWP=275", "RB", "n/a", "decoded");
[ra, rows] = localApply(rows, ra, "initial_ul_bwp_size", initialUlBwpSize, ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.genericParameters.locationAndBandwidth", ...
    "", "RB", "n/a", "decoded");
[ra, rows] = localApply(rows, ra, "subcarrier_spacing_khz", prachSCSkHz, ...
    "SIB1.rach-ConfigCommon.msg1-SubcarrierSpacing", ...
    "Decoded PRACH Msg1 SCS is used for PRACH waveform numerology.", "kHz", "n/a", "decoded");
[ra, rows] = localApply(rows, ra, "initial_ul_bwp_cyclic_prefix", initialUlBwpCP, ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.genericParameters.cyclicPrefix", ...
    "", "enum", "normal", "decoded");
[ra, rows] = localApply(rows, ra, "configuration_index", double(rach.configurationIndex), ...
    "SIB1.rach-ConfigCommon.rach-ConfigGeneric.prach-ConfigurationIndex", "", "index", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "msg1_fdm", localMsg1FDMValue( ...
    sixgr.util.structGet(rach, "msg1FDM", "")), ...
    "SIB1.rach-ConfigCommon.rach-ConfigGeneric.msg1-FDM", "", "enum", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "root_sequence_index", double(rach.rootSequenceIndex), ...
    "SIB1.rach-ConfigCommon.rootSequenceIndex", "", "index", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "restricted_set", restrictedSet, ...
    "SIB1.rach-ConfigCommon.restrictedSetConfig", ...
    "", "enum", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "zero_correlation_zone", double(rach.zeroCorrelationZoneConfig), ...
    "SIB1.rach-ConfigCommon.zeroCorrelationZoneConfig", "", "index", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "frequency_start", double(sixgr.util.structGet(rach, "msg1FrequencyStart", ...
    sixgr.util.structGet(ra, "frequency_start", 0))), ...
    "SIB1.rach-ConfigCommon.msg1-FrequencyStart", "", "RB", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_received_target_power_dbm", ...
    double(sixgr.util.structGet(rach, "preambleReceivedTargetPower_dBm", ...
    sixgr.util.structGet(ra, "preamble_received_target_power_dbm", NaN))), ...
    "SIB1.rach-ConfigCommon.preambleReceivedTargetPower", "", "dBm", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "power_ramping_step_db", localPowerRampingStepDb(rach), ...
    "SIB1.rach-ConfigCommon.powerRampingStep", "", "dB", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_trans_max", localPreambleTransMax(rach), ...
    "SIB1.rach-ConfigCommon.preambleTransMax", "", "count", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "ra_response_window_slots", localRAResponseWindowSlots(rach), ...
    "SIB1.rach-ConfigCommon.ra-ResponseWindow", "", "slots", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_count", double(sixgr.util.structGet(rach, "nPreambles", ...
    sixgr.util.structGet(ra, "preamble_count", NaN))), ...
    "SIB1.rach-ConfigCommon.totalNumberOfRA-Preambles", "", "count", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "prach_format", string(sixgr.util.structGet(rach, "preambleFormat", ...
    sixgr.util.structGet(ra, "prach_format", ""))), ...
    "SIB1.rach-ConfigCommon.prach-RootSequenceIndex/format anchor", "", "enum", "anchor_profile", "decoded");
[ra, rows] = localApply(rows, ra, "pusch_common_msg3_delta_preamble", ...
    double(sixgr.util.structGet(puschCommon, "msg3_DeltaPreamble", NaN)), ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pusch-ConfigCommon.msg3-DeltaPreamble", ...
    "", "dB", "n/a", "decoded_if_present");
[ra, rows] = localApply(rows, ra, "pucch_common_resource", ...
    double(sixgr.util.structGet(pucchCommon, "pucch_ResourceCommon", NaN)), ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pucch-ConfigCommon.pucch-ResourceCommon", ...
    "", "index", "n/a", "decoded_if_present");

% Not all 38.331 RACH fields are represented in the constrained SIB1 anchor
% profile yet. Simulator-only scheduling fields must remain explicit in the
% input config; RAConfig will fail closed if they are missing.
ra.initial_ul_bwp = struct("start_rb", initialUlBwpStart, "size_rb", initialUlBwpSize, ...
    "scs_khz", initialUlBwpSCSkHz, "cyclic_prefix", initialUlBwpCP);
ra.decoded_sib1_payload_hash = string(payloadHash);
ra.decoded_sib1_tree_hash = string(treeHash);
cfgOut.random_access = ra;
cfgOut.UECommonCellConfiguration = localBuildUECommonCellConfiguration(serving, ra, payloadHash, treeHash);
cfgOut.ue_common_cell_configuration = cfgOut.UECommonCellConfiguration;
commonCell = cfgOut.UECommonCellConfiguration;
[ra, rows] = localApply(rows, ra, "initial_ul_bwp_scs_khz", initialUlBwpSCSkHz, ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.genericParameters.subcarrierSpacing", ...
    "UL BWP SCS is independent of msg1-SubcarrierSpacing", "kHz", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "initial_dl_bwp", commonCell.InitialDLBWP, ...
    "SIB1.servingCellConfigCommon.downlinkConfigCommon.initialDownlinkBWP.genericParameters", ...
    "locationAndBandwidth decoded with N_BWP=275", "RB/kHz", "mandatory", "decoded");
if commonCell.PDCCHConfigCommonPresent
    [ra, rows] = localApply(rows, ra, "pdcch_config_common", commonCell.PDCCHConfigCommon, ...
        "SIB1.servingCellConfigCommon.downlinkConfigCommon.initialDownlinkBWP.pdcch-ConfigCommon", ...
        "Exact recovered IE; installation alone does not qualify scheduler monitoring", ...
        "ASN.1 IE", "optional", "decoded");
elseif isfield(ra,"pdcch_config_common")
    % An absent decoded IE cannot retain a pre-decode scenario oracle.
    ra = rmfield(ra,"pdcch_config_common");
end
cfgOut.random_access = ra;

for i = 1:numel(rows)
    rows(i).PayloadHash = string(payloadHash);
    rows(i).TreeHash = string(treeHash);
    rows(i).SourceMessageId = string(payloadHash);
end
evidenceT = struct2table(rows, "AsArray", true);
end

function [ra, rows] = localApply(rows, ra, name, value, source, note, units, standardsDefault, validationStatus)
if nargin < 7
    units = "";
end
if nargin < 8
    standardsDefault = "";
end
if nargin < 9
    validationStatus = "decoded";
end
before = "";
if isfield(ra, name)
    before = string(localScalarToText(ra.(name)));
end
ra.(char(name)) = value;
row = localRow();
row.Parameter = string(name);
row.ValueBefore = before;
row.ValueAfter = string(localScalarToText(value));
row.Source = string(source);
row.Note = string(note);
row.PayloadHash = "";
row.TreeHash = "";
row.DecodedASN1Path = string(source);
row.DecodedValue = row.ValueAfter;
row.Units = string(units);
row.StandardsDefault = string(standardsDefault);
row.SourceCallId = "recoverSIB1FromWaveform";
row.SourceMessageId = "";
row.SourceBitRange = "anchor_codec_field_level";
row.ValidationStatus = string(validationStatus);
rows(end+1, 1) = row; %#ok<AGROW>
end

function row = localRow()
row = struct("Parameter", "", "ValueBefore", "", "ValueAfter", "", ...
    "Source", "", "Note", "", "PayloadHash", "", "TreeHash", "", ...
    "DecodedASN1Path", "", "DecodedValue", "", "Units", "", ...
    "StandardsDefault", "", "SourceCallId", "", "SourceMessageId", "", ...
    "SourceBitRange", "", "ValidationStatus", "");
end

function [tree, payloadHash, treeHash] = localResolveSIB1Tree(sib1Evidence)
payloadHash = "";
treeHash = "";
if isstruct(sib1Evidence) && isfield(sib1Evidence, "SIB1RxTree")
    tree = sib1Evidence.SIB1RxTree;
    payloadHash = string(sixgr.util.structGet(sib1Evidence, "SIB1PayloadHashRx", ""));
    treeHash = string(sixgr.util.structGet(sib1Evidence, "SIB1RxTreeHash", ""));
elseif isstruct(sib1Evidence) && isfield(sib1Evidence, "message")
    tree = sib1Evidence;
else
    error("sixgr:mac:ra:BadSIB1Evidence", ...
        "SIB1 evidence must be a recoverSIB1FromWaveform result or decoded SIB1 tree.");
end
if isempty(fieldnames(tree))
    error("sixgr:mac:ra:EmptySIB1Tree", "Decoded SIB1 tree is empty.");
end
if strlength(treeHash) == 0
    [~, cmp] = sixgr.rrc.asn1.compareSIB1Trees(tree, tree);
    treeHash = string(cmp.RxTreeHash);
end
end

function khz = localSCSNameToKHz(name)
switch string(name)
    case "kHz15"
        khz = 15;
    case "kHz30"
        khz = 30;
    case "kHz60"
        khz = 60;
    case "kHz120"
        khz = 120;
    otherwise
        khz = NaN;
end
end

function cfg = localBuildUECommonCellConfiguration(serving, ra, payloadHash, treeHash)
ul = serving.uplinkConfigCommon.initialUplinkBWP;
ulGeneric = ul.genericParameters;
cfg = struct();
cfg.Source = "decoded_sib1";
cfg.PayloadHash = string(payloadHash);
cfg.TreeHash = string(treeHash);
cfg.SSPBCHBlockPower_dBm = double(serving.ss_PBCH_BlockPower);
cfg.InitialULBWP = struct( ...
    "StartRB", double(sixgr.util.structGet(ra, "initial_ul_bwp_start", NaN)), ...
    "SizeRB", double(sixgr.util.structGet(ra, "initial_ul_bwp_size", NaN)), ...
    "SubcarrierSpacing_kHz", double(ra.initial_ul_bwp.scs_khz), ...
    "CyclicPrefix", string(sixgr.util.structGet(ulGeneric, "cyclicPrefix", "normal")));
cfg.RACHConfigCommon = struct( ...
    "ConfigurationIndex", double(sixgr.util.structGet(ra, "configuration_index", NaN)), ...
    "Msg1FDM", string(sixgr.util.structGet(ra, "msg1_fdm", "")), ...
    "Msg1FrequencyStart", double(sixgr.util.structGet(ra, "frequency_start", NaN)), ...
    "PRACHSubcarrierSpacing_kHz", double(sixgr.util.structGet(ra, "subcarrier_spacing_khz", NaN)), ...
    "RootSequenceIndex", double(sixgr.util.structGet(ra, "root_sequence_index", NaN)), ...
    "RestrictedSet", string(sixgr.util.structGet(ra, "restricted_set", "")), ...
    "ZeroCorrelationZoneConfig", double(sixgr.util.structGet(ra, "zero_correlation_zone", NaN)), ...
    "TotalNumberOfRAPreambles", double(sixgr.util.structGet(ra, "preamble_count", NaN)), ...
    "PreambleReceivedTargetPower_dBm", double(sixgr.util.structGet(ra, "preamble_received_target_power_dbm", NaN)), ...
    "PowerRampingStep_dB", double(sixgr.util.structGet(ra, "power_ramping_step_db", NaN)), ...
    "PreambleTransMax", double(sixgr.util.structGet(ra, "preamble_trans_max", NaN)), ...
    "RAResponseWindowSlots", double(sixgr.util.structGet(ra, "ra_response_window_slots", NaN)), ...
    "PRACHFormat", string(sixgr.util.structGet(ra, "prach_format", "")));
cfg.PUSCHConfigCommon = sixgr.util.structGet(ul, "pusch_ConfigCommon", struct());
cfg.PUCCHConfigCommon = sixgr.util.structGet(ul, "pucch_ConfigCommon", struct());
dl = serving.downlinkConfigCommon.initialDownlinkBWP;
[dlStart, dlSize] = sixgr.bwop.RIVFDRA.decode(275, double(dl.genericParameters.locationAndBandwidth));
cfg.InitialDLBWP = struct("StartRB", dlStart, "SizeRB", dlSize, ...
    "SubcarrierSpacing_kHz", localSCSNameToKHz(dl.genericParameters.subcarrierSpacing), ...
    "CyclicPrefix", string(sixgr.util.structGet(dl.genericParameters, "cyclicPrefix", "normal")));
cfg.PDCCHConfigCommon = sixgr.util.structGet(dl, "pdcch_ConfigCommon", struct());
cfg.PDCCHConfigCommonPresent = isfield(dl, "pdcch_ConfigCommon");
cfg.PDSCHConfigCommon = sixgr.util.structGet(dl,"pdsch_ConfigCommon",struct());
cfg.ValidationStatus = "decoded_sib1_common_cell_config_installed";
end

function value = localPowerRampingStepDb(rach)
raw = string(sixgr.util.structGet(rach, "powerRampingStep", ""));
tokens = regexp(char(raw), "dB(\d+)", "tokens", "once");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1});
end
end

function value = localMsg1FDMValue(raw)
if isnumeric(raw) && isscalar(raw) && isfinite(raw) && ...
        any(double(raw) == [1 2 4 8])
    value = double(raw);
    return;
end
token = lower(strtrim(string(raw)));
switch token
    case {"one", "n1", "1"}
        value = 1;
    case {"two", "n2", "2"}
        value = 2;
    case {"four", "n4", "4"}
        value = 4;
    case {"eight", "n8", "8"}
        value = 8;
    otherwise
        error("sixgr:mac:ra:UnsupportedDecodedMsg1FDM", ...
            "Decoded SIB1 msg1-FDM must resolve to one of 1, 2, 4, or 8; got '%s'.", ...
            char(token));
end
end

function value = localPreambleTransMax(rach)
raw = string(sixgr.util.structGet(rach, "preambleTransMax", ""));
tokens = regexp(char(raw), "n(\d+)", "tokens", "once");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1});
end
end

function value = localRAResponseWindowSlots(rach)
raw = string(sixgr.util.structGet(rach, "raResponseWindow", ""));
tokens = regexp(char(raw), "sl(\d+)", "tokens", "once");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1});
end
end

function txt = localScalarToText(value)
if isstring(value) || ischar(value)
    txt = string(value);
elseif isnumeric(value) || islogical(value)
    if isscalar(value)
        txt = string(double(value));
    else
        txt = string(mat2str(double(value)));
    end
elseif isstruct(value)
    try
        txt = string(jsonencode(value));
    catch
        txt = "<struct>";
    end
else
    txt = string(value);
end
end
