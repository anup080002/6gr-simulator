function [carrier,native]=splitREAllocationDomains(T)
% Keep native PRACH coordinates out of every carrier-RE CSV/renderer.
carrier=T; native=table();
if ~istable(T) || isempty(T), return; end
assert(ismember('grid_domain',T.Properties.VariableNames), ...
    'sixgr:truth:MissingREGridDomain','Allocation publication requires explicit grid domains.');
domain=string(T.grid_domain);
assert(all(ismember(domain,["carrier_cp_ofdm","prach_native_ofdm"])), ...
    'sixgr:truth:UnknownREGridDomain','An unrecognized grid cannot become carrier RE evidence.');
isNative=domain=="prach_native_ofdm";
assert(all(string(T.channel(isNative))=="PRACH") && ...
    ~any(string(T.channel(~isNative))=="PRACH"), ...
    'sixgr:truth:PRACHGridDomainMismatch','PRACH must retain its native OFDM grid domain.');
carrier=T(~isNative,:); native=T(isNative,:);
if ~isempty(native)
    old=["absolute_slot","symbol_index","subcarrier_start","subcarrier_count","re_count"];
    new=["carrier_origin_slot0","native_symbol_index","native_subcarrier_start","native_subcarrier_count","native_mapped_re_count"];
    native=renamevars(native,old,new);
end
end
