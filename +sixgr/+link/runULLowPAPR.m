function out = runULLowPAPR(cfg, varargin)
%RUNULLOWPAPR UL CP-OFDM vs DFT-s-OFDM PAPR comparison.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumFrames", 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.parse(varargin{:});
log = p.Results.Logger;
numFrames = max(1, round(double(p.Results.NumFrames)));

nRB = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 25));
nRB = max(6, min(50, round(nRB)));
nSC = 12 * nRB;
nSym = 14;
cpLen = round(nSC/16);
modStr = char(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", "16QAM")));
if isempty(modStr), modStr = "16QAM"; end

out = struct();
out.Ok = true;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.PAPR_CP_dB = NaN;
out.PAPR_DFTs_dB = NaN;
out.PAPR_Gain_dB = NaN;
out.Notes = "";

paprCP = zeros(numFrames,1);
paprDFTs = zeros(numFrames,1);
useMexFFT = logical(sixgr.util.structGet(cfg, "run.useMex", false)) ...
    && (exist("sixgr_fft_papr_kernel_mex","file") == 3 || exist("sixgr_fft_papr_kernel","file") == 2);

for k = 1:numFrames
    bitsPerSym = localBitsPerSym(modStr);
    nBits = nSC * nSym * bitsPerSym;
    bits = int8(randi([0 1], nBits, 1));

    try
        [sym, ~] = sixgr.phy.mod.modulate(bits, modStr);
    catch ME
        out.Ok = false;
        out.Notes = "Modulator failure: " + string(ME.message);
        if ~isempty(log)
            log.warn("runULLowPAPR failed: " + string(ME.message));
        end
        return;
    end

    sym = reshape(sym, nSC, nSym);
    if useMexFFT
        try
            if exist("sixgr_fft_papr_kernel_mex","file") == 3
                [paprCP(k), paprDFTs(k)] = sixgr_fft_papr_kernel_mex(sym, cpLen);
            else
                [paprCP(k), paprDFTs(k)] = sixgr_fft_papr_kernel(sym, cpLen);
            end
            continue;
        catch
            % Fall back to MATLAB path if MEX path fails.
        end
    end

    blkLen = nSC + cpLen;
    wfCP = complex(zeros(blkLen*nSym,1));
    wfDFTs = complex(zeros(blkLen*nSym,1));
    idx = 1;
    for s = 1:nSym
        d = sym(:,s);

        tCP = ifft(d, nSC);
        tCP = [tCP(end-cpLen+1:end); tCP];

        dSpread = fft(d, nSC) / sqrt(nSC);
        tDFT = ifft(dSpread, nSC);
        tDFT = [tDFT(end-cpLen+1:end); tDFT];

        wfCP(idx:idx+blkLen-1) = tCP;
        wfDFTs(idx:idx+blkLen-1) = tDFT;
        idx = idx + blkLen;
    end

    paprCP(k) = localPAPRdB(wfCP);
    paprDFTs(k) = localPAPRdB(wfDFTs);
end

out.PAPR_CP_dB = mean(paprCP);
out.PAPR_DFTs_dB = mean(paprDFTs);
out.PAPR_Gain_dB = out.PAPR_CP_dB - out.PAPR_DFTs_dB;
out.Notes = "Avg over " + string(numFrames) + " frame(s), mod=" + string(modStr);
end

function b = localBitsPerSym(modStr)
switch upper(strtrim(modStr))
    case {'BPSK','PI/2-BPSK'}
        b = 1;
    case 'QPSK'
        b = 2;
    case '16QAM'
        b = 4;
    case '64QAM'
        b = 6;
    case '256QAM'
        b = 8;
    case '1024QAM'
        b = 10;
    case '4096QAM'
        b = 12;
    otherwise
        b = 4;
end
end

function v = localPAPRdB(x)
p = abs(x(:)).^2;
v = 10*log10(max(p)/max(mean(p), eps));
end
