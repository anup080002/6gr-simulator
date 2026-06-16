function ncs = deriveNCSFromZeroCorrelationZone(zcz, restrictedSet, lra)
%DERIVENCSFROMZEROCORRELATIONZONE Resolve N_CS from nrPRACHConfig tables.

zcz = round(double(zcz));
if ~(isfinite(zcz) && zcz >= 0 && zcz <= 15)
    error("sixgr:phy:prach:InvalidZCZ", ...
        "zeroCorrelationZoneConfig must be an integer in [0..15]. Got %g.", zcz);
end
restrictedSet = sixgr.phy.prach.normalizeRestrictedSet(restrictedSet);
lra = round(double(lra));
p = nrPRACHConfig;
tables = p.Tables;
if lra == 839
    T = tables.NCSFormat012;
    col = char(restrictedSet);
elseif any(lra == [139 571 1151])
    if restrictedSet ~= "UnrestrictedSet"
        error("sixgr:phy:prach:RestrictedSetInvalidForShortFormat", ...
            "Restricted-set PRACH is only supported for long-sequence formats in this strict profile; L_RA=%g is short-sequence.", lra);
    end
    T = tables.NCSFormatABC;
    col = char("LRA_" + string(lra));
else
    error("sixgr:phy:prach:UnsupportedLRA", ...
        "No nrPRACHConfig N_CS table is available for L_RA=%g.", lra);
end
if ~ismember(col, string(T.Properties.VariableNames))
    error("sixgr:phy:prach:NCSColumnMissing", ...
        "N_CS table column '%s' is unavailable for L_RA=%g.", col, lra);
end
ncs = double(T.(col)(zcz + 1));
if ~(isfinite(ncs) && ncs >= 0)
    error("sixgr:phy:prach:InvalidRestrictedSetZCZ", ...
        "RestrictedSet=%s with zeroCorrelationZoneConfig=%g has no finite N_CS for L_RA=%g.", ...
        string(restrictedSet), zcz, lra);
end
end
