function xOverhead = resolvePDSCHXOverhead(cfg, symAlloc) %#ok<INUSD>
%RESOLVEPDSCHXOVERHEAD Higher-layer N_oh, NOT an RS collision estimator.
% TS 38.214 V18.7.0 section 5.1.3.2: xOverhead is 6, 12 or 18 when
% configured, otherwise N_oh=0. Explicit zero represents the absent setting.
% Physical SSB/CSI-RS/TRS exclusions belong to the resource mapper; neither
% symbol-number coincidences nor their exact RE counts define this parameter.
% Keep the second argument for existing TX/RX/scheduler callers.

xOverhead = 0;
found = false;
for field = ["phy.pdsch.xOverhead", "phy.pdsch.XOverhead"]
    raw = sixgr.util.structGet(cfg, field, []);
    if isempty(raw), continue; end
    if ~(isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
            isfinite(raw) && any(raw == [0 6 12 18]))
        error('sixgr:phy:dl:InvalidPDSCHXOverhead', ...
            '%s must be absent or a numeric scalar in {0,6,12,18}.',field);
    end
    if found && xOverhead ~= double(raw)
        error('sixgr:phy:dl:ConflictingPDSCHXOverhead', ...
            'phy.pdsch.xOverhead and phy.pdsch.XOverhead disagree.');
    end
    xOverhead = double(raw);
    found = true;
end
end
