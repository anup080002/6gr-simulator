function [waveform, grid, ofdmInfo] = modulatePRACHSymbols(symbols, seq, cfg)
%MODULATEPRACHSYMBOLS Deterministic PRACH OFDM modulation from nrPRACH symbols.
% The sequence source remains nrPRACH/nrPRACHIndices; this avoids PRACH
% grid/time-domain toolbox kernels that can access-violate in some runtimes.

symbols = complex(symbols(:));
if isempty(symbols)
    waveform = complex(zeros(0, 1));
    grid = complex(zeros(0, 0));
    ofdmInfo = struct("SampleRate", NaN, "Nfft", 0, ...
        "CyclicPrefixLengths", zeros(0, 1), "SymbolLengths", zeros(0, 1), ...
        "Backend", "inrepo_nrPRACH_symbol_ofdm");
    return;
end

lra = round(double(sixgr.util.structGet(seq, "LRA", numel(symbols))));
if ~(isfinite(lra) && lra >= 1)
    lra = numel(symbols);
end
numSymbols = max(1, ceil(numel(symbols) / lra));
scsHz = double(sixgr.util.structGet(seq, "PRACH.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "PRACHSubcarrierSpacing", 1.25))) * 1e3;
if ~(isfinite(scsHz) && scsHz > 0)
    scsHz = 1.25e3;
end
nGridRE = max(12, round(double(sixgr.util.structGet(cfg, "NSizeGrid", 52))) * 12);
nfft = 2^nextpow2(max([lra, nGridRE, 128]));
cpLen = max(1, round(0.08 * nfft));

grid = complex(zeros(nfft, numSymbols));
waveParts = cell(numSymbols, 1);
for iSym = 1:numSymbols
    idx = (iSym - 1) * lra + (1:lra);
    idx = idx(idx <= numel(symbols));
    block = complex(zeros(lra, 1));
    block(1:numel(idx)) = symbols(idx);
    startIdx = floor((nfft - lra) / 2) + 1;
    freq = complex(zeros(nfft, 1));
    freq(startIdx:startIdx + lra - 1) = block;
    grid(:, iSym) = freq;
    timeNoCP = ifft(ifftshift(freq), nfft) * sqrt(nfft);
    waveParts{iSym} = [timeNoCP(end-cpLen+1:end); timeNoCP];
end

waveform = vertcat(waveParts{:});
ofdmInfo = struct();
ofdmInfo.SampleRate = double(nfft * scsHz);
ofdmInfo.Nfft = double(nfft);
ofdmInfo.CyclicPrefixLengths = repmat(double(cpLen), numSymbols, 1);
ofdmInfo.SymbolLengths = repmat(double(nfft + cpLen), numSymbols, 1);
ofdmInfo.Backend = "inrepo_nrPRACH_symbol_ofdm";
end
