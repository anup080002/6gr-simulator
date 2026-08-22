function dmrs = PDCCHStudyDMRS(ctrlCfg, candidateRETable, context)
%PDCCHStudyDMRS Build explicit DMRS RE locations and sequence symbols.
%
% Baseline study pattern: single-port QPSK DMRS with 3 RE per RB-equivalent
% chunk. The pattern is configurable and explicitly labeled as a study
% baseline rather than a frozen 6GR rule.

if nargin < 3
    context = struct();
end

if ~(istable(candidateRETable) && ~isempty(candidateRETable))
    dmrs = struct("Locations", table(), "Symbols", complex([]), "PayloadREMask", false(0,1), "Context", context);
    return;
end

subcarriers = double(candidateRETable.Subcarrier);
symbols = double(candidateRETable.Symbol);
rb = floor(subcarriers / 12);
scInRB = mod(subcarriers, 12);
pattern = [1 5 9] - 1;
dmrsMask = ismember(scInRB, pattern);

locRows = repmat(struct("Symbol", NaN, "Subcarrier", NaN, "RB", NaN, "Port", NaN, "DMRSIndex", NaN, "SlotIndex", NaN, "CopyIndex", NaN), 0, 1);
sel = find(dmrsMask);
for i = 1:numel(sel)
    idx = sel(i);
    locRows(end+1,1) = struct( ... %#ok<AGROW>
        "Symbol", symbols(idx), ...
        "Subcarrier", subcarriers(idx), ...
        "RB", rb(idx), ...
        "Port", double(ctrlCfg.CORESET.DMRSPortSet(1)), ...
        "DMRSIndex", i, ...
        "SlotIndex", double(candidateRETable.SlotIndex(idx)), ...
        "CopyIndex", double(candidateRETable.CopyIndex(idx)));
end
locT = struct2table(locRows);

nID = round(double(sixgr.util.structGet(ctrlCfg, "DMRSScramblingID", ctrlCfg.CellID)));
nID = mod(nID, 65536);
slotsPerFrame = localRequireSlotsPerFrame(ctrlCfg);
nSlotFrame = mod(round(double(sixgr.util.structGet(context, "SlotNumber", ctrlCfg.SlotNumber))), slotsPerFrame);
dmrsSymbol = round(double(sixgr.util.structGet(ctrlCfg, "CORESET.StartSymbol", 0)));
cinit = uint32(mod(2^17 * (14 * nSlotFrame + dmrsSymbol + 1) * (2 * nID + 1) + 2 * nID, 2^31));
seq = sixgr.ctrl.GoldSequence(2 * height(locT), cinit);
bits = reshape(int8(seq(:)), 2, []).';
sym = ((1 - 2*double(bits(:,1))) + 1j * (1 - 2*double(bits(:,2)))) ./ sqrt(2);

dmrs = struct();
dmrs.Locations = locT;
dmrs.Symbols = complex(sym(:));
dmrs.PayloadREMask = ~dmrsMask;
dmrs.Context = context;
dmrs.SequenceInit = double(cinit);
dmrs.PatternDescription = "single_port_density_3_per_rb study baseline";
end

function slotsPerFrame = localRequireSlotsPerFrame(ctrlCfg)
slotsPerFrame = double(sixgr.util.structGet(ctrlCfg, "SlotsPerFrame", NaN));
if ~(isscalar(slotsPerFrame) && isfinite(slotsPerFrame) && ...
        slotsPerFrame >= 1 && slotsPerFrame == fix(slotsPerFrame))
    error("sixgr:ctrl:PDCCHStudyDMRS:MissingCanonicalNumerology", ...
        "ctrlCfg.SlotsPerFrame must come from ControlChannelConfig's canonical numerology resolution.");
end
end
