function txt = sib1TreeToJson(tree)
%SIB1TREETOJSON Stable JSON rendering for SIB1 evidence artifacts.
try
    txt = jsonencode(orderfields(tree), "PrettyPrint", true);
catch
    txt = jsonencode(orderfields(tree));
end
txt = char(txt);
end
