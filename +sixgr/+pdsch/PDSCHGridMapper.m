function map = PDSCHGridMapper(tx)
%PDSCHGridMapper Package grid-mapping evidence from the active truth path.

map = struct();
map.Grid = sixgr.util.structGet(tx, "Grid", []);
map.PDSCHIndices = sixgr.util.structGet(tx, "PDSCHIndices", []);
map.DMRSIndices = sixgr.util.structGet(tx, "DMRSIndices", []);
map.PTRSIndices = sixgr.util.structGet(tx, "PTRSIndices", []);
map.MappingStatus = "materialized_resource_grid";
end

