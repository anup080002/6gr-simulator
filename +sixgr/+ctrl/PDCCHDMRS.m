function dmrs = PDCCHDMRS(ctrlCfg, candidateRETable, context)
%PDCCHDMRS Build explicit DMRS RE locations and sequence symbols.
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

cinit = uint32(mod(double(ctrlCfg.CellID) + 17 * double(ctrlCfg.RNTI) + ...
    29 * double(sixgr.util.structGet(context, "SlotNumber", ctrlCfg.SlotNumber)) + ...
    37 * double(sixgr.util.structGet(context, "CandidateIndex", 0)), 2^31 - 1));
seq = localPRBS(cinit, 2 * height(locT));
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

function seq = localPRBS(cinit, N)
state = false(31,1);
for i = 1:31
    state(i) = bitget(uint32(cinit), i) ~= 0;
end
if ~any(state)
    state(1) = true;
end
seq = false(N,1);
for n = 1:N
    newBit = xor(state(31), state(28));
    seq(n) = state(end);
    state(2:end) = state(1:end-1);
    state(1) = newBit;
end
end
