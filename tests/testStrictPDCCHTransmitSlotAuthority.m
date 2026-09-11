function ok=testStrictPDCCHTransmitSlotAuthority()
% Absolute control time must reach actual OFDM/DM-RS and CCE resources.
% This is a transmitter component test, not a connected scheduler claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','master_geometry_based.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
strict=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(cfg);
formats=cellfun(@(c)string(c.Data.DCIFormat),strict.DCIContexts);
context=strict.DCIContexts{find(formats=="1_0",1)};
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for definition=reshape(schema.Definitions,1,[])
    fields.(char(definition.Name))=definition.ValueMin;
end
spf=double(strict.ToolboxCarrier.SlotsPerFrame);
for slot=[1 spf-1 spf 3*spf+1 1024*spf+1]
    tx=sixgr.phy.pdcch.PDCCHTransmitter.transmit(strict,fields,context, ...
        'AbsoluteSlot',slot,'AggregationLevel',4,'CandidateIndex',0);
    assert(double(tx.Carrier.NSlot)==mod(slot,spf) && ...
        double(tx.Carrier.NFrame)==mod(floor(slot/spf),1024), ...
        'test:StrictPDCCHWaveformClockMismatch', ...
        'AbsoluteSlot must advance the actual waveform carrier, not only the event label.');
    expectedCarrier=strict.ToolboxCarrier;
    expectedCarrier.NSlot=mod(slot,spf);
    expectedCarrier.NFrame=mod(floor(slot/spf),1024);
    [indices,symbols,dmrsIndices]=nrPDCCHResources(expectedCarrier,tx.PDCCH);
    assert(isequal(tx.PDCCHIndices,indices) && isequal(tx.DMRSIndices,dmrsIndices));
    assert(isequal(tx.DMRSSymbols,symbols), ...
        'The transmitted DM-RS must use the scheduled slot sequence.');
    receivedContext=sixgr.phy.pdcch.resolveCandidateContext(expectedCarrier,tx.PDCCH,4,0);
    assert(tx.FirstCCE==receivedContext.FirstCCE, ...
        'Strict CCE metadata must match actual frame-relative waveform resources.');
end
ok=true;
fprintf('STRICT_PDCCH_TRANSMIT_SLOT_AUTHORITY_PASS: actual DM-RS and resources across frame boundaries.\n');
end
