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
    rach = ul.rach_ConfigCommon;
catch ME
    error("sixgr:mac:ra:MissingDecodedRACHConfigCommon", ...
        "Decoded SIB1 tree does not contain uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon: %s", ME.message);
end

cfgOut = cfgIn;
ra = sixgr.util.structGet(cfgOut, "random_access", struct());
if ~(isstruct(ra) && ~isempty(fieldnames(ra)))
    ra = struct();
end

rows = repmat(localRow(), 0, 1);
[ra, rows] = localApply(rows, ra, "enabled", true, "decoded_sib1_control", "SIB1 presence enables RA common config");
[ra, rows] = localApply(rows, ra, "binding_source", "decoded_sib1_rach_config_common", "decoded_sib1", ...
    "Binding source selected by recovered SIB1 tree");
[ra, rows] = localApply(rows, ra, "configuration_index", double(rach.configurationIndex), ...
    "SIB1.rach-ConfigCommon.rach-ConfigGeneric.prach-ConfigurationIndex", "");
[ra, rows] = localApply(rows, ra, "root_sequence_index", double(rach.rootSequenceIndex), ...
    "SIB1.rach-ConfigCommon.rootSequenceIndex", "");
[ra, rows] = localApply(rows, ra, "zero_correlation_zone", double(rach.zeroCorrelationZoneConfig), ...
    "SIB1.rach-ConfigCommon.zeroCorrelationZoneConfig", "");
[ra, rows] = localApply(rows, ra, "frequency_start", double(sixgr.util.structGet(rach, "msg1FrequencyStart", ...
    sixgr.util.structGet(ra, "frequency_start", 0))), ...
    "SIB1.rach-ConfigCommon.msg1-FrequencyStart", "");
[ra, rows] = localApply(rows, ra, "preamble_received_target_power_dbm", ...
    double(sixgr.util.structGet(rach, "preambleReceivedTargetPower_dBm", ...
    sixgr.util.structGet(ra, "preamble_received_target_power_dbm", NaN))), ...
    "SIB1.rach-ConfigCommon.preambleReceivedTargetPower", "");
[ra, rows] = localApply(rows, ra, "power_ramping_step_db", localPowerRampingStepDb(rach), ...
    "SIB1.rach-ConfigCommon.powerRampingStep", "");
[ra, rows] = localApply(rows, ra, "preamble_trans_max", localPreambleTransMax(rach), ...
    "SIB1.rach-ConfigCommon.preambleTransMax", "");
[ra, rows] = localApply(rows, ra, "ra_response_window_slots", localRAResponseWindowSlots(rach), ...
    "SIB1.rach-ConfigCommon.ra-ResponseWindow", "");
[ra, rows] = localApply(rows, ra, "preamble_count", double(sixgr.util.structGet(rach, "nPreambles", ...
    sixgr.util.structGet(ra, "preamble_count", NaN))), ...
    "SIB1.rach-ConfigCommon.totalNumberOfRA-Preambles", "");
[ra, rows] = localApply(rows, ra, "prach_format", string(sixgr.util.structGet(rach, "preambleFormat", ...
    sixgr.util.structGet(ra, "prach_format", ""))), ...
    "SIB1.rach-ConfigCommon.prach-RootSequenceIndex/format anchor", "");

% Not all 38.331 RACH fields are represented in the constrained SIB1 anchor
% profile yet. Simulator-only scheduling fields must remain explicit in the
% input config; RAConfig will fail closed if they are missing.
ra.decoded_sib1_payload_hash = string(payloadHash);
ra.decoded_sib1_tree_hash = string(treeHash);
cfgOut.random_access = ra;

for i = 1:numel(rows)
    rows(i).PayloadHash = string(payloadHash);
    rows(i).TreeHash = string(treeHash);
end
evidenceT = struct2table(rows, "AsArray", true);
end

function [ra, rows] = localApply(rows, ra, name, value, source, note)
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
rows(end+1, 1) = row; %#ok<AGROW>
end

function row = localRow()
row = struct("Parameter", "", "ValueBefore", "", "ValueAfter", "", ...
    "Source", "", "Note", "", "PayloadHash", "", "TreeHash", "");
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

function value = localPowerRampingStepDb(rach)
raw = string(sixgr.util.structGet(rach, "powerRampingStep", ""));
tokens = regexp(char(raw), "dB(\d+)", "tokens", "once");
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1});
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
