function [cfg,prepared]=buildConfiguredPDCCHCampaignEpisode(cfg,c)
% Materialize authored TX only. Never narrow the installed receive search.
cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,c.ue_index,c.serving_cell);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,c.absolute_slot0+1);
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
cfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
    sixgr.phy.frame.slotStartSample(carrier,c.absolute_slot0,ofdm.SampleRate)/ofdm.SampleRate;
prepared=struct([]);
if ~c.signal_present, return; end
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,c.transmitter.dci_format);
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
for name=string(fieldnames(c.transmitter.fields)).'
    assert(isfield(fields,name),'sixgr:pdcch:InvalidCampaignTransmitter', ...
        'The installed DCI schema has no field %s.',name);
    fields.(name)=c.transmitter.fields.(name);
end
authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
prepared=sixgr.link.prepareSharedPDCCHTransmission(cfg, ...
    'DCIBits',authored.Bits,'RNTI',context.Data.RNTIValue);
end
