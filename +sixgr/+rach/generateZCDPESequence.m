function seq = generateZCDPESequence(cfg, varargin)
%GENERATEZCDPESEQUENCE Generate analytical ZC-DPE PRACH sequences.

p = inputParser;
p.FunctionName = "sixgr.rach.generateZCDPESequence";
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
parse(p, cfg, varargin{:});
opts = p.Results;

occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end

baseSeq = sixgr.rach.generatePRACHSequence(cfg, "Occasion", occasion, "PreambleIndex", opts.PreambleIndex);
zcfg = sixgr.rach.ZCDPEConfig(cfg, "NumSymbols", localResolveNumSymbols(cfg, baseSeq));

LRA = double(baseSeq.LRA);
if ~(LRA == 139 || LRA == 839)
    error("sixgr:rach:ZCDPE:UnsupportedLRA", ...
        "ZC-DPE currently supports L_RA=139 or 839 per TS 38.211 Table 6.3.3.1-1. Got: %g", LRA);
end

D = double(zcfg.DPI_D);
d = double(zcfg.DPI_d(1));
requestedM = double(zcfg.NumSymbols);
preambleIndex = double(baseSeq.PreambleIndex);
Ncs = localResolveNCS(LRA, double(baseSeq.ZeroCorrelationZone), baseSeq.RestrictedSet);
if Ncs <= 0
    cyclicShiftIndex = 0;
else
    cyclicShiftIndex = floor(preambleIndex * Ncs / LRA);
end
rootIndex = double(baseSeq.SequenceIndex);

actualM = floor(numel(baseSeq.Symbols) / LRA);
if actualM < 1
    error("sixgr:rach:ZCDPE:NoPRACHSymbols", ...
        "The resolved PRACH occasion did not provide a complete L_RA=%g symbol group.", LRA);
end
M = min(requestedM, actualM);
if M < requestedM
    error("sixgr:rach:ZCDPE:NumSymbolsUnavailable", ...
        "Requested ZC-DPE NumSymbols=%g but the toolbox PRACH occasion contains only %g group(s).", ...
        requestedM, actualM);
end

baseMatrix = reshape(baseSeq.Symbols(1:(LRA * M)), LRA, M);
phaseStep = 2*pi*d/D;
zc = complex(baseMatrix);
for m = 0:M-1
    zc(:, m+1) = zc(:, m+1) .* exp(1i * m * phaseStep);
end

modulusError = max(abs(abs(zc(:)) - abs(baseMatrix(:))));
if modulusError > 1e-10
    warning("sixgr:rach:ZCDPE:ConstantModulusDrift", ...
        "ZC-DPE phase progression changed baseline PRACH symbol amplitudes by %.3g.", modulusError);
end

seq = struct();
seq.Sequence = zc;
seq.SequenceFlat = zc(:);
seq.PAPR_dB = 0;
seq.LRA = LRA;
seq.NumSymbols = M;
seq.DPI_D = D;
seq.DPI_d = d;
seq.PhaseStep_rad = phaseStep;
seq.IsOrthogonal = mod(M, D) == 0;
seq.IsBackwardCompat = d == 0;
seq.ReferenceEnergyPerSymbol = sum(abs(baseMatrix).^2, 1);
seq.CyclicShiftIndex = cyclicShiftIndex;
seq.N_CS = Ncs;
seq.RootIndex = rootIndex;
seq.PreambleIndex = preambleIndex;
seq.SequenceIndex = double(baseSeq.SequenceIndex);
seq.ZeroCorrelationZone = double(baseSeq.ZeroCorrelationZone);
seq.RestrictedSet = string(baseSeq.RestrictedSet);
seq.Occasion = occasion;
seq.PRACHSequence = baseSeq;
localValidate(seq);
end

function M = localResolveNumSymbols(cfg, baseSeq)
configured = sixgr.util.structGet(cfg, "ZCDPE.NumSymbols", []);
if isempty(configured)
    configured = sixgr.util.structGet(cfg, "random_access.zcdpe_num_symbols", []);
end
if ~isempty(configured)
    M = max(1, round(double(configured)));
    return;
end
M = max(1, round(numel(baseSeq.Symbols) / max(double(baseSeq.LRA), 1)));
end

function Ncs = localResolveNCS(LRA, zcz, restrictedSet)
zcz = max(0, min(15, round(double(zcz))));
restrictedSet = lower(string(restrictedSet));
if restrictedSet ~= "unrestrictedset"
    warning("sixgr:rach:ZCDPE:RestrictedSetNCSApprox", ...
        "ZC-DPE analytical N_CS export uses the unrestricted TS 38.211 table for restricted-set metadata; toolbox waveform placement remains authoritative.");
end
if LRA == 839
    tableVals = [0 13 15 18 22 26 32 38 46 59 76 93 119 167 279 419];
else
    tableVals = [0 2 4 6 8 10 12 13 15 17 19 23 27 34 46 69];
end
Ncs = tableVals(zcz + 1);
end

function localValidate(seq)
energy = sum(abs(seq.Sequence).^2, 1);
referenceEnergy = double(sixgr.util.structGet(seq, "ReferenceEnergyPerSymbol", seq.LRA * ones(size(energy))));
if any(abs(energy - referenceEnergy) > max(1e-9, 1e-10 * max(referenceEnergy, 1)))
    warning("sixgr:rach:ZCDPE:EnergyDrift", ...
        "ZC-DPE sequence energy differs from the baseline PRACH symbol energy beyond numerical tolerance.");
end
if seq.DPI_D > 1 && seq.NumSymbols > 1
    m = (0:seq.NumSymbols-1).';
    phi = 2*pi*(0:seq.DPI_D-1).'/seq.DPI_D;
    A = exp(1i * m * phi.')./sqrt(seq.NumSymbols);
    C = abs(A' * A).^2;
    C(1:size(C,1)+1:end) = 0;
    maxCross = max(C(:));
    if seq.IsOrthogonal && maxCross > 1e-10
        warning("sixgr:rach:ZCDPE:OrthogonalityDrift", ...
            "DPI cross-correlation is %.4g although D divides M.", maxCross);
    elseif ~seq.IsOrthogonal && maxCross > 0.1
        warning("sixgr:rach:ZCDPE:HighDPIConfusion", ...
            "Non-orthogonal DPI cross-correlation is %.4g.", maxCross);
    end
end
end
