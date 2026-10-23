function [qm, canonicalName] = reportModulationOrder(modulation)
%REPORTMODULATIONORDER Catalog Qm, not a waveform/applicability assertion.
% Unknown and combined-codeword tokens remain unknown; never default QPSK.
tokens=upper(strtrim(string(modulation)));
tokens=replace(tokens," ","");
tokens(ismember(tokens,["PI/2-BPSK","PI2-BPSK","PI/2BPSK","PI2BPSK"]))="BPSK";
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
entries=catalog.value_maps.modulation_order_to_name;
names=upper(string({entries.name})); orders=double([entries.order]);
assert(numel(unique(names))==numel(names) && all(isfinite(orders) & orders>0 & orders==fix(orders)), ...
    'sixgr:report:InvalidModulationDictionary','The canonical modulation dictionary must be unambiguous.');
qm=nan(size(tokens)); canonicalName=strings(size(tokens));
for k=1:numel(names)
    mask=~ismissing(tokens) & tokens==names(k);
    qm(mask)=orders(k); canonicalName(mask)=names(k);
end
end
