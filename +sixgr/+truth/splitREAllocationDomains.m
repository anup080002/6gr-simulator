function [carrier,native,ssb]=splitREAllocationDomains(T)
% Keep native PRACH and mixed-numerology SSB out of carrier-RE CSVs/renderers.
carrier=T; native=table(); ssb=table();
if ~istable(T) || isempty(T), return; end
assert(ismember('grid_domain',T.Properties.VariableNames), ...
    'sixgr:truth:MissingREGridDomain','Allocation publication requires explicit grid domains.');
domain=string(T.grid_domain);
assert(all(ismember(domain,["carrier_cp_ofdm","prach_native_ofdm","ssb_native_cp_ofdm"])), ...
    'sixgr:truth:UnknownREGridDomain','An unrecognized grid cannot become carrier RE evidence.');
isNative=domain=="prach_native_ofdm";
isSSB=domain=="ssb_native_cp_ofdm";
assert(all(ismember(string(T.channel(isSSB)),["SSB","SSB_PBCH"])), ...
    'sixgr:truth:SSBGridDomainMismatch','Only SSB uses the native SS/PBCH grid domain.');
assert(all(string(T.channel(isNative))=="PRACH") && ...
    ~any(string(T.channel(~isNative))=="PRACH"), ...
    'sixgr:truth:PRACHGridDomainMismatch','PRACH must retain its native OFDM grid domain.');
carrier=T(~isNative & ~isSSB,:); native=T(isNative,:); ssb=T(isSSB,:);
if ~isempty(native)
    old=["absolute_slot","symbol_index","subcarrier_start","subcarrier_count","re_count"];
    new=["carrier_origin_slot0","native_symbol_index","native_subcarrier_start","native_subcarrier_count","native_mapped_re_count"];
    native=renamevars(native,old,new);
end
if ~isempty(ssb)
    ssb=renamevars(ssb, ...
        ["absolute_slot","symbol_index","subcarrier_start","subcarrier_count","re_count"], ...
        ["native_absolute_slot0","native_symbol_index","native_subcarrier_start", ...
         "native_subcarrier_count","native_mapped_re_count"]);
end
end
