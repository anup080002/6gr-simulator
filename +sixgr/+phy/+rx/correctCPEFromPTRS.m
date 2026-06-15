function [rxGridOut, cpeVec_rad, info] = correctCPEFromPTRS(rxGrid, ptrsInd, ptrsSym, carrier)
%CORRECTCPEFROMPTRS Estimate and apply per-symbol PT-RS CPE correction.
%
%   [GRIDOUT,CPE,INFO] = sixgr.phy.rx.correctCPEFromPTRS(GRID,IND,SYM,CARRIER)
%   estimates common phase error from PT-RS REs and rotates each affected
%   OFDM symbol by the inverse phase. The correction uses only received
%   PT-RS samples and their transmitted reference symbols; it does not use
%   configured SNR, CQI, or any scheduler proxy.

info = struct('Enabled', false, 'NumSymbolsCorrected', 0, ...
    'MeanCPE_deg', NaN, 'NAReason', "");
rxGridOut = rxGrid;

numSymbols = 0;
try
    numSymbols = double(carrier.SymbolsPerSlot);
catch
    if ndims(rxGrid) >= 2
        numSymbols = size(rxGrid, 2);
    end
end
if ~(isfinite(numSymbols) && numSymbols >= 1)
    numSymbols = 14;
end
cpeVec_rad = NaN(max(1, round(numSymbols)), 1);

if isempty(rxGrid) || isempty(ptrsInd) || isempty(ptrsSym)
    info.NAReason = "ptrs_unavailable";
    return;
end

try
    dims = size(rxGrid);
    if numel(dims) < 2
        info.NAReason = "rx_grid_not_resource_grid";
        return;
    end
    K = dims(1);
    L = dims(2);
    [kVec, lVec] = ind2sub([K L], double(ptrsInd(:)));
    ptrsSym = ptrsSym(:);
    n = min(numel(kVec), numel(ptrsSym));
    kVec = kVec(1:n);
    lVec = lVec(1:n);
    ptrsSym = ptrsSym(1:n);
    valid = kVec >= 1 & kVec <= K & lVec >= 1 & lVec <= L & abs(ptrsSym) > 0;
    kVec = kVec(valid);
    lVec = lVec(valid);
    ptrsSym = ptrsSym(valid);
    if isempty(kVec)
        info.NAReason = "ptrs_indices_outside_grid";
        return;
    end

    for lSym = unique(lVec(:)).'
        mask = (lVec == lSym);
        if ~any(mask)
            continue;
        end
        rxP = squeeze(rxGridOut(kVec(mask), lSym, :));
        if isempty(rxP)
            continue;
        end
        if isvector(rxP)
            rxP = rxP(:);
        else
            rxP = mean(rxP, 2, "omitnan");
        end
        refP = ptrsSym(mask);
        denom = max(sum(abs(refP(:)).^2), eps);
        cpe = angle(sum(conj(refP(:)) .* rxP(:)) ./ denom);
        if ~(isfinite(cpe))
            continue;
        end
        cpeVec_rad(lSym) = cpe;
        rxGridOut(:, lSym, :) = rxGridOut(:, lSym, :) .* cast(exp(-1j * cpe), "like", rxGridOut);
        info.NumSymbolsCorrected = info.NumSymbolsCorrected + 1;
    end

    finiteCPE = cpeVec_rad(isfinite(cpeVec_rad));
    if ~isempty(finiteCPE)
        info.Enabled = true;
        info.MeanCPE_deg = rad2deg(mean(abs(finiteCPE), "omitnan"));
        info.NAReason = "";
    else
        info.NAReason = "no_finite_cpe_estimates";
    end
catch ME
    rxGridOut = rxGrid;
    cpeVec_rad(:) = NaN;
    info.Enabled = false;
    info.NAReason = string(ME.identifier);
end
end
