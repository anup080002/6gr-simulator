function items=orderSharedReceiverCompletions(items)
% Dependency order within one ALREADY COMPLETED shared-clock callback.
% This function neither advances the clock nor adds an observation. Actual
% TX commits precede receivers; completed UL pilots precede pilot-free PUCCH.
% A disjoint same-slot PUSCH may provide the current received timing clock
% after the earlier SRS expires. Do not depend on registration order.
if isempty(items), return; end
kinds=string({items.Kind});
tx=ismember(kinds,["DataTX","PUCCHTX"]);
srs=kinds=="SRS";
pusch=kinds=="PUSCH";
order=[find(tx),find(srs),find(pusch),find(~tx & ~srs & ~pusch)];
items=items(order);
end
