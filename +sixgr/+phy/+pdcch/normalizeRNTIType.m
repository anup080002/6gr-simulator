function token = normalizeRNTIType(value)
%NORMALIZERNTITYPE Normalize supported strict PDCCH RNTI labels.

raw = upper(strtrim(string(value)));
raw = replace(raw, "_", "-");
switch raw
    case {"C", "C-RNTI", "CRNTI"}
        token = "C-RNTI";
    case {"SI", "SI-RNTI", "SIRNTI"}
        token = "SI-RNTI";
    case {"RA", "RA-RNTI", "RARNTI"}
        token = "RA-RNTI";
    case {"TC", "TC-RNTI", "TCRNTI"}
        token = "TC-RNTI";
    otherwise
        token = string(value);
end
end
