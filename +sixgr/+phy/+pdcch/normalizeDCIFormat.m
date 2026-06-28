function fmt = normalizeDCIFormat(dciFormat)
%NORMALIZEDCIFORMAT Canonicalize supported DCI format tokens.

fmt = upper(strrep(string(dciFormat), "-", "_"));
fmt = strtrim(fmt);
if startsWith(fmt, "DCI_")
    fmt = extractAfter(fmt, strlength("DCI_"));
end
if ~any(fmt == ["0_0","0_1","1_0","1_1"])
    error("sixgr:phy:pdcch:UnsupportedDCIFormat", ...
        "Supported bit-exact PDCCH DCI formats are 0_0, 0_1, 1_0 and 1_1; got %s.", string(dciFormat));
end
end

