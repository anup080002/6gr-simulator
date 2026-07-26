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
    case {"CS", "CS-RNTI", "CSRNTI"}
        token = "CS-RNTI";
    case {"MCS-C", "MCS-C-RNTI", "MCSCRNTI"}
        token = "MCS-C-RNTI";
    case {"P", "P-RNTI", "PRNTI"}
        token = "P-RNTI";
    case {"TPC-PUSCH", "TPC-PUSCH-RNTI", "TPCPUSCHRNTI"}
        token = "TPC-PUSCH-RNTI";
    case {"TPC-PUCCH", "TPC-PUCCH-RNTI", "TPCPUCCHRNTI"}
        token = "TPC-PUCCH-RNTI";
    case {"TPC-SRS", "TPC-SRS-RNTI", "TPCSRSRNTI"}
        token = "TPC-SRS-RNTI";
    otherwise
        token = string(value);
end
end
