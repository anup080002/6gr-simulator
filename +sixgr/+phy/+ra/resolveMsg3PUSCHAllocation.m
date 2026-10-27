function a=resolveMsg3PUSCHAllocation(cfg,ra,grant)
% Original RAR UL grant -> exact Msg3 geometry and TBS; no transmitter input.
slot=sixgr.phy.ra.resolveMsg3SlotFromRAR(ra,grant);
cfg=sixgr.phy.ra.localizeRAPUSCHConfig(cfg,ra,grant,slot);
carrier=sixgr.phy.grid.makeCarrier(cfg);
pusch=sixgr.phy.ra.localPUSCHConfigFromGrant(ra,grant);
[indices,info]=nrPUSCHIndices(carrier,pusch,'IndexStyle','index');
% Msg3 uses the common RA allocation; no dedicated PUSCH-ServingCellConfig
% xOverhead has been received. TS38.214 6.1.4.2 uses zero in its absence.
xoh=0;
accounting=sixgr.phy.resource.computeResourceAccounting('PUSCH',carrier,pusch, ...
    'ChannelIndices',indices,'AllocationInfo',info,'IndexBase','1based', ...
    'TargetCodeRate',grant.TargetCodeRate,'XOverhead',xoh);
tbs=nrTBS(pusch.Modulation,pusch.NumLayers,numel(pusch.PRBSet), ...
    accounting.NREPerPRBForTBS,grant.TargetCodeRate,xoh);
assert(isscalar(tbs)&&isfinite(tbs)&&tbs>0&&mod(tbs,8)==0, ...
    'sixgr:phy:ra:InvalidMsg3TBS','Msg3 requires one exact octet-aligned transport block.');
a=struct('Config',cfg,'Carrier',carrier,'PUSCH',pusch,'TransportBlockSize',double(tbs), ...
    'ResourceAccounting',accounting,'XOverhead',xoh,'AbsoluteSlot',slot, ...
    'Source',"original_RAR_UL_grant_exact_PUSCH_resource_accounting");
end
