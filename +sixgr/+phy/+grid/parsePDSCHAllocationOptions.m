function opts = parsePDSCHAllocationOptions(varargin)
opts = struct();
opts.IndexBase = "1based";
opts.PRBSet = [];
opts.SymbolAllocation = [];
opts.RNTI = [];
opts.NumLayers = [];
opts.Modulation = [];
opts.MappingType = "";
opts.MappingTypeExplicit = false;
opts.NID = [];
opts.FixedReferenceMode = false;

if mod(numel(varargin),2) ~= 0
    error("sixgr:allocREsPDSCH:InvalidNV", "Name-Value arguments must come in pairs.");
end

for i = 1:2:numel(varargin)
    name = varargin{i};
    val  = varargin{i+1};
    if ~(ischar(name) || isstring(name))
        continue;
    end
    n = char(lower(string(name)));
    switch n
        case "indexbase"
            opts.IndexBase = string(val);
        case "prbset"
            opts.PRBSet = val;
        case "symbolallocation"
            opts.SymbolAllocation = val;
        case "rnti"
            opts.RNTI = val;
        case "numlayers"
            opts.NumLayers = val;
        case "modulation"
            opts.Modulation = val;
        case "mappingtype"
            opts.MappingType = string(val);
            opts.MappingTypeExplicit = true;
        case "nid"
            opts.NID = val;
        case "fixedreferencemode"
            opts.FixedReferenceMode = logical(val);
    end
end

if opts.IndexBase ~= "0based" && opts.IndexBase ~= "1based"
    % IMPORTANT: Do NOT use C-style escaping (\") inside MATLAB string literals.
    % MATLAB interprets 0b... as a binary literal prefix, and something like
    % 0based (without quotes) will throw: "Invalid digit in binary literal".
    % Use a char vector where embedded double-quotes are literal characters.
    error("sixgr:allocREsPDSCH:BadIndexBase", 'IndexBase must be "0based" or "1based".');
end

end
