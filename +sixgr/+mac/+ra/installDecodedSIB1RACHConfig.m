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
% Mandatory received operands cannot be rescued from the transmitter's
% authored random_access subtree and then labelled decoded. The constrained
% semantic decoder retains these fields even when their value is zero.
requiredRACH = ["configurationIndex","rootSequenceIndex", ...
    "zeroCorrelationZoneConfig","restrictedSet","msg1FDM", ...
    "msg1FrequencyStart","preambleReceivedTargetPower_dBm", ...
    "powerRampingStep","preambleTransMax","raResponseWindow"];
assert(isstruct(rach) && isscalar(rach) && all(isfield(rach,requiredRACH)), ...
    'sixgr:mac:ra:MissingDecodedRACHOperand', ...
    'Mandatory RACH common fields must come from the original decoded SIB1; host defaults are not received evidence.');
assert(isfield(rach,'preambleFormat') && ...
    ((ischar(rach.preambleFormat) && isrow(rach.preambleFormat)) || ...
    (isstring(rach.preambleFormat) && isscalar(rach.preambleFormat))) && ...
    any(string(rach.preambleFormat)==["0","1","2","3","A1","A2","A3", ...
    "B1","B2","B3","B4","C0","C2","A1/B1","A2/B2","A3/B3"]), ...
    'sixgr:mac:ra:MissingDecodedPRACHFormatAnchor', ...
    'The bounded decoder must retain its derived PRACH format anchor; a host format is not decoded metadata.');
validateattributes(rach.msg1FrequencyStart,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',0,'<=',274});
validateattributes(rach.preambleReceivedTargetPower_dBm,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',-202,'<=',-60});
assert(mod(rach.preambleReceivedTargetPower_dBm,2)==0, ...
    'sixgr:mac:ra:InvalidDecodedRACHTargetPower', ...
    'TS 38.331 preambleReceivedTargetPower uses even dBm values in [-202,-60].');
% totalNumberOfRA-Preambles absent on the wire denotes 64. The semantic
% decoder may already have materialized 64; this is not proof of IE presence.
totalPreambles=64;
totalStatus="standard_default_absent_decoded_operand";
if isfield(rach,'nPreambles')
    validateattributes(rach.nPreambles,{'numeric'}, ...
        {'scalar','real','finite','integer','>=',1,'<=',64});
    totalPreambles=double(rach.nPreambles);
    totalStatus="decoded_semantic_operand_wire_presence_not_retained";
end
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
[prachSCSkHz,prachSCSSource] = sixgr.mac.ra.resolveDecodedPRACHSubcarrierSpacing(rach);
restrictedSet = string(rach.restrictedSet);

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
    prachSCSSource, ...
    "Short PRACH uses received Msg1 SCS; long PRACH uses the retained index-derived format, not UL BWP SCS.", ...
    "kHz", "n/a", prachSCSSource);
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
[ra, rows] = localApply(rows, ra, "frequency_start", double(rach.msg1FrequencyStart), ...
    "SIB1.rach-ConfigCommon.msg1-FrequencyStart", "", "RB", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_received_target_power_dbm", ...
    double(rach.preambleReceivedTargetPower_dBm), ...
    "SIB1.rach-ConfigCommon.preambleReceivedTargetPower", "", "dBm", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "power_ramping_step_db", localPowerRampingStepDb(rach), ...
    "SIB1.rach-ConfigCommon.powerRampingStep", "", "dB", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_trans_max", localPreambleTransMax(rach), ...
    "SIB1.rach-ConfigCommon.preambleTransMax", "", "count", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "ra_response_window_slots", localRAResponseWindowSlots(rach), ...
    "SIB1.rach-ConfigCommon.ra-ResponseWindow", "", "slots", "mandatory", "decoded");
[ra, rows] = localApply(rows, ra, "preamble_count", totalPreambles, ...
    "SIB1.rach-ConfigCommon.totalNumberOfRA-Preambles", ...
    "Absent optional IE means 64; host preamble_count is never a received operand.", ...
    "count", "64", totalStatus);
[ra, rows] = localApply(rows, ra, "prach_format", string(rach.preambleFormat), ...
    "SIB1.rach-ConfigCommon.prach-RootSequenceIndex/format anchor", ...
    "Derived decoder-profile metadata; not a separately transmitted preamble-format IE.", ...
    "enum", "anchor_profile", "decoded_derived_format_anchor");
[ra, rows] = localApply(rows, ra, "pusch_common_msg3_delta_preamble", ...
    2*double(sixgr.util.structGet(puschCommon, "msg3_DeltaPreamble", NaN)), ...
    "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pusch-ConfigCommon.msg3-DeltaPreamble", ...
    "", "dB", "n/a", "decoded_if_present");
if ~isempty(fieldnames(pucchCommon))
    [ra, rows] = localApply(rows, ra, "pucch_common_resource", ...
        double(sixgr.util.structGet(pucchCommon, "pucch_ResourceCommon", NaN)), ...
        "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pucch-ConfigCommon.pucch-ResourceCommon", ...
        "Common PUCCH resource-set row selector; actual resource also depends on CCE and PRI.", ...
        "index", "optional", "decoded");
    [ra, rows] = localApply(rows, ra, "pucch_group_hopping", ...
        string(pucchCommon.pucch_GroupHopping), ...
        "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pucch-ConfigCommon.pucch-GroupHopping", ...
        "", "enum", "mandatory_when_present", "decoded");
    for mapping = {"hoppingId","pucch_hopping_id","identity"; ...
            "p0_nominal","pucch_p0_nominal_dbm","dBm"}.'
        decodedName = string(mapping{1});
        if isfield(pucchCommon, decodedName)
            [ra, rows] = localApply(rows, ra, string(mapping{2}), ...
                double(pucchCommon.(decodedName)), ...
                "SIB1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pucch-ConfigCommon." + decodedName, ...
                "", string(mapping{3}), "optional", "decoded");
        elseif isfield(ra,string(mapping{2}))
            ra=rmfield(ra,string(mapping{2}));
        end
    end
else
    for name = ["pucch_common_resource","pucch_group_hopping", ...
            "pucch_hopping_id","pucch_p0_nominal_dbm"]
        if isfield(ra, name)
            ra = rmfield(ra, name);
        end
    end
end

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
receivedMIB=sixgr.mac.ra.resolveReceivedCommonMIBConfiguration(cfgIn,sib1Evidence);
if ~isempty(fieldnames(receivedMIB))
    cfgOut.UECommonMIBConfiguration=receivedMIB;
elseif isfield(cfgOut,'UECommonMIBConfiguration')
    % A new received SI tree cannot inherit unrelated caller MIB authority.
    cfgOut=rmfield(cfgOut,'UECommonMIBConfiguration');
end
commonCell = cfgOut.UECommonCellConfiguration;
[ra, rows] = localApply(rows,ra,"tdd_config_common_present",commonCell.TDDConfigCommonPresent, ...
    "SIB1.servingCellConfigCommon.tdd-UL-DL-ConfigurationCommon", ...
    "Original optional IE presence; not scenario or dedicated-TDD authority.", ...
    "boolean","optional","decoded_presence");
if commonCell.TDDConfigCommonPresent
    [ra, rows] = localApply(rows,ra,"tdd_ul_dl_config_common",commonCell.TDDConfigCommon, ...
        "SIB1.servingCellConfigCommon.tdd-UL-DL-ConfigurationCommon", ...
        "Original IE retained. Separate runtime maps use received BWP SCS/CP and radio-even-frame epoch; not PRACH validity qualification.", ...
        "ASN.1 IE","optional","decoded");
elseif isfield(ra,'tdd_ul_dl_config_common')
    ra=rmfield(ra,'tdd_ul_dl_config_common');
end
offsetStatus="absent_IE_requires_standard_frequency_range_default";
if commonCell.TimingAdvanceOffsetPresent, offsetStatus="decoded"; end
[ra, rows] = localApply(rows,ra,"n_timing_advance_offset",commonCell.TimingAdvanceOffset, ...
    "SIB1.servingCellConfigCommon.n-TimingAdvanceOffset", ...
    "IE presence retained; installation does not assert waveform timing application", ...
    "enum","TS 38.133 V18.8.0 Table 7.1.2-2",offsetStatus);
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
% Preserve absence through the receiver boundary. An absent IE does not
% mean zero and cannot inherit a transmitter-side scenario value.
cfg.TimingAdvanceOffsetPresent = isfield(serving,'n_TimingAdvanceOffset');
cfg.TimingAdvanceOffset = "";
if cfg.TimingAdvanceOffsetPresent
    cfg.TimingAdvanceOffset = string(serving.n_TimingAdvanceOffset);
end
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
cfg.PUCCHConfigCommonPresent = isfield(ul, "pucch_ConfigCommon");
% Mandatory received MAC timer authority. Do not substitute a scenario
% timer at the UE or lose it when the RA continuation is released.
cfg.TimeAlignmentTimerCommon = string(serving.uplinkConfigCommon.timeAlignmentTimerCommon);
dl = serving.downlinkConfigCommon.initialDownlinkBWP;
[dlStart, dlSize] = sixgr.bwop.RIVFDRA.decode(275, double(dl.genericParameters.locationAndBandwidth));
cfg.InitialDLBWP = struct("StartRB", dlStart, "SizeRB", dlSize, ...
    "SubcarrierSpacing_kHz", localSCSNameToKHz(dl.genericParameters.subcarrierSpacing), ...
    "CyclicPrefix", string(sixgr.util.structGet(dl.genericParameters, "cyclicPrefix", "normal")));
cfg.PDCCHConfigCommon = sixgr.util.structGet(dl, "pdcch_ConfigCommon", struct());
cfg.PDCCHConfigCommonPresent = isfield(dl, "pdcch_ConfigCommon");
cfg.PDSCHConfigCommon = sixgr.util.structGet(dl,"pdsch_ConfigCommon",struct());
cfg.TDDConfigCommonPresent=isfield(serving,'tdd_UL_DL_ConfigurationCommon');
cfg.TDDConfigCommon=struct();
cfg.TDDCommonRuntime=struct();
if cfg.TDDConfigCommonPresent
    cfg.TDDConfigCommon=serving.tdd_UL_DL_ConfigurationCommon;
    % The codec profile is bounded FR1. No host TDD pattern, active traffic,
    % dedicated symbol override or delivery-relative epoch enters this map.
    ulTDD=sixgr.rrc.asn1.resolveTDDCommonRuntime(cfg.TDDConfigCommon, ...
        cfg.InitialULBWP.SubcarrierSpacing_kHz,cfg.InitialULBWP.CyclicPrefix,"FR1");
    dlTDD=sixgr.rrc.asn1.resolveTDDCommonRuntime(cfg.TDDConfigCommon, ...
        cfg.InitialDLBWP.SubcarrierSpacing_kHz,cfg.InitialDLBWP.CyclicPrefix,"FR1");
    assert(ulTDD.Present && dlTDD.Present,'sixgr:rrc:asn1:InvalidTDDCommonIE', ...
        'A decoded present TDD common IE cannot be an absent marker.');
    cfg.TDDCommonRuntime=struct('Source',"decoded_sib1_tdd_common", ...
        'Reference',ulTDD.Reference,'EffectiveConfig',ulTDD.EffectiveConfig, ...
        'InitialDLBWP',localTDDMap(dlTDD.SlotFormatState), ...
        'InitialULBWP',localTDDMap(ulTDD.SlotFormatState));
end
cfg.ValidationStatus = "decoded_sib1_common_cell_config_installed";
end

function out=localTDDMap(state)
% Plain immutable snapshot for common-config serialization; the original
% IE is retained separately and remains the authority for future consumers.
out=struct();
for name=string(properties(state)).'
    out.(name)=state.(name);
end
end

function value = localPowerRampingStepDb(rach)
value=localDecodedEnumNumber(rach.powerRampingStep,["dB0","dB2","dB4","dB6"],[0 2 4 6]);
end

function value = localMsg1FDMValue(raw)
value=localDecodedEnumNumber(raw,["one","two","four","eight"],[1 2 4 8]);
end

function value = localPreambleTransMax(rach)
counts=[3 4 5 6 7 8 10 20 50 100 200];
value=localDecodedEnumNumber(rach.preambleTransMax,"n"+string(counts),counts);
end

function value = localRAResponseWindowSlots(rach)
counts=[1 2 4 8 10 20 40 80];
value=localDecodedEnumNumber(rach.raResponseWindow,"sl"+string(counts),counts);
end

function value=localDecodedEnumNumber(raw,tokens,values)
assert(((ischar(raw) && isrow(raw)) || ...
    (isstring(raw) && isscalar(raw) && ~ismissing(raw))) && ...
    any(string(raw)==tokens),'sixgr:mac:ra:InvalidDecodedRACHEnum', ...
    'Retain an exact received ASN.1 enum token; do not coerce numeric values, prefixes, suffixes or whitespace.');
value=values(tokens==string(raw));
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
