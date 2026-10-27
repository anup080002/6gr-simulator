function items=orderSharedReceiverCompletions(items)
% Dependency order within one ALREADY COMPLETED shared-clock callback.
% This function neither advances the clock nor adds an observation. Actual
% TX commits precede receivers; completed UL pilots precede pilot-free PUCCH.
% A disjoint same-slot PUSCH may provide the current received timing clock
% after the earlier SRS expires. Do not depend on registration order.
if isempty(items), return; end
kinds=string({items.Kind});
tx=ismember(kinds,["DataTX","PUCCHTX","CellSIB1TX","CellSSBTX","Msg1TX","Msg3TX","CellRARTX","CellMsg4TX"]);
srs=kinds=="SRS";
pusch=kinds=="PUSCH";
power=kinds=="BindSRSPower";
expiry=kinds=="RRCSetupExpiry";
% Receiver/control reductions at this exact clock precede emission-time
% power binding. Future commands remain excluded by the effective-time query.
% At the exact original deadline, complete received access and MAC timer
% decisions before initial RRC expiry. A received Setup can stop T300;
% another completed MAC step cannot silently extend its deadline.
order=[find(tx),find(srs),find(pusch),find(~tx & ~srs & ~pusch & ~power & ~expiry),find(expiry),find(power)];
items=items(order);
end
