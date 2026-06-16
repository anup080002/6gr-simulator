function T = validateRestrictedSetMapping(runId, configHash, prachCfg)
%VALIDATERESTRICTEDSETMAPPING Validate N_CS/cyclic-shift mappings.

sets = ["UnrestrictedSet", "RestrictedSetTypeA", "RestrictedSetTypeB"];
numPreambles = min(64, max(1, round(double(sixgr.util.structGet(prachCfg, "NumPreambles", 64)))));
preambles = 0:(numPreambles - 1);
nRows = numel(sets) * numel(preambles);
rows = repmat(localRow(), nRows, 1);
idx = 0;
lra = double(prachCfg.ToolboxPRACH.LRA);
for iSet = 1:numel(sets)
    restrictedSet = sets(iSet);
    ncs = NaN;
    setValid = true;
    failureReason = "";
    try
        ncs = sixgr.phy.prach.deriveNCSFromZeroCorrelationZone( ...
            prachCfg.ZeroCorrelationZone, restrictedSet, lra);
    catch ME
        setValid = false;
        failureReason = string(ME.identifier);
    end
    for iPreamble = 1:numel(preambles)
        idx = idx + 1;
        cyclicShift = NaN;
        if setValid
            cyclicShift = mod(double(preambles(iPreamble)) * double(ncs), max(lra, 1));
        end
        rows(idx) = struct( ...
            "RunId", string(runId), ...
            "ConfigHash", string(configHash), ...
            "PreambleFormat", string(prachCfg.ResolvedPRACHFormat), ...
            "SequenceLength", string(localSequenceLength(lra)), ...
            "RestrictedSet", restrictedSet, ...
            "ZeroCorrelationZoneConfig", double(prachCfg.ZeroCorrelationZone), ...
            "NCS", double(ncs), ...
            "RootSequenceIndex", double(prachCfg.SequenceIndex), ...
            "PreambleIndex", double(preambles(iPreamble)), ...
            "CyclicShift", double(cyclicShift), ...
            "Valid", logical(setValid), ...
            "FailureReason", string(failureReason));
    end
end
T = struct2table(rows, "AsArray", true);
end

function row = localRow()
row = struct("RunId", "", "ConfigHash", "", "PreambleFormat", "", ...
    "SequenceLength", "", "RestrictedSet", "", "ZeroCorrelationZoneConfig", NaN, ...
    "NCS", NaN, "RootSequenceIndex", NaN, "PreambleIndex", NaN, ...
    "CyclicShift", NaN, "Valid", false, "FailureReason", "");
end

function txt = localSequenceLength(lra)
if round(double(lra)) == 839
    txt = "long";
else
    txt = "short";
end
end
