function value = normalizeRestrictedSet(rawValue)
%NORMALIZERESTRICTEDSET Canonicalize PRACH restricted-set tokens.

token = lower(strtrim(string(rawValue)));
token = erase(token, "-");
token = erase(token, "_");
token = erase(token, " ");
switch token
    case {"", "unrestricted", "unrestrictedset", "none"}
        value = "UnrestrictedSet";
    case {"restrictedsettypea", "restrictedseta", "restrictedtypea", "restricteda", "typea", "a"}
        value = "RestrictedSetTypeA";
    case {"restrictedsettypeb", "restrictedsetb", "restrictedtypeb", "restrictedb", "typeb", "b"}
        value = "RestrictedSetTypeB";
    otherwise
        error("sixgr:phy:prach:BadRestrictedSet", ...
            "RestrictedSet must resolve to UnrestrictedSet, RestrictedSetTypeA, or RestrictedSetTypeB. Got '%s'.", string(rawValue));
end
end
