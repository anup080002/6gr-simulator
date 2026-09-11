function ok=testStrictPDCCHReceiveSlotAuthority()
% Independent scheduled waveform tests both blind RX APIs, including cache reuse.
% Unit-channel/aligned-slot component fixture, not measured acquisition evidence.
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
dci=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
prepared=sixgr.phy.pdcch.PDCCHReceiver.prepare(strict);
spf=double(strict.ToolboxCarrier.SlotsPerFrame);
for slot=[1 spf-1 spf spf+1 1024*spf+1]
    carrier=strict.ToolboxCarrier;
    carrier.NSlot=mod(slot,spf);
    carrier.NFrame=mod(floor(slot/spf),1024);
    toolbox=sixgr.phy.pdcch.PDCCHToolboxFactory.create(carrier, ...
        strict.CORESETDefinition,strict.SearchSpaceDefinition,4, ...
        context.Data.RNTIValue,strict.NCellID,context.Data.ActiveDLBWPStart, ...
        max(context.Data.ActiveDLBWPSize,context.Data.ActiveULBWPSize));
    pdcch=toolbox.PDCCH;
    % The independent waveform must not inherit a factory's default CSS/USS.
    if string(strict.SearchSpaceDefinition.Data.SearchSpaceType)=="USS"
        pdcch.SearchSpace.SearchSpaceType='ue';
    else
        pdcch.SearchSpace.SearchSpaceType='common';
    end
    pdcch.AllocatedCandidate=1;
    runtime=sixgr.phy.pdcch.applyPDCCHConfigToRuntime(cfg,strict, ...
        'RNTI',context.Data.RNTIValue,'DCIFormat',context.Data.DCIFormat, ...
        'AggregationLevel',4);
    [tx,~]=sixgr.phy.dl.PDCCH_Tx(runtime,'Carrier',carrier,'PDCCH',pdcch, ...
        'DCIBits',dci.Bits,'K',numel(dci.Bits), ...
        'RNTI',context.Data.RNTIValue,'NCellID',strict.NCellID);
    expected=sixgr.phy.pdcch.resolveCandidateContext(carrier,pdcch,4,0);
    for cached=[false true]
        % Distinct test identifiers: TCI, beam, CORESET and RS are separate
        % namespaces. Installed test state is not an RF measurement claim.
        beam=sixgr.phy.pdcch.ControlBeamState(struct( ...
            'TCIStateID',context.Data.ActiveTCIStateID,'TCIActive',true, ...
            'QCLSourceType','CSI_RS','QCLSourceID',17,'BeamID',93, ...
            'BeamActive',true,'BeamBlocked',false,'MeasurementSlot',slot, ...
            'MeasurementMaxAgeSlots',2, ...
            'MeasurementProvenance','component_fixture_installed_RS_state'));
        if cached
            rx=sixgr.phy.pdcch.PDCCHReceiver.receivePrepared(tx.Waveform, ...
                prepared,'AbsoluteSlot',slot,'ControlBeamState',beam);
        else
            rx=sixgr.phy.pdcch.PDCCHReceiver.receive(tx.Waveform, ...
                strict,'AbsoluteSlot',slot,'ControlBeamState',beam);
        end
        assert(rx.Detected && rx.ValidHypothesisCount==1, ...
            'test:StrictPDCCHReceiverClockMismatch', ...
            'The blind receiver must demodulate the scheduled slot, including reused preparation.');
        assert(rx.SelectedFirstCCE==expected.FirstCCE && ...
            rx.DecodedDCIEvent.Data.AbsoluteSlot==slot);
        assert(~rx.UsedKnownLocation && ~rx.UsedOracleTiming);
        event=rx.DecodedDCIEvent.Data;
        assert(event.QCLSourceType=="CSI_RS" && event.QCLSourceID==17 && ...
            event.BeamID==93 && event.ControlBeamStateDigest==beam.Digest);
    end
end
unbound=sixgr.phy.pdcch.PDCCHReceiver.receivePrepared(tx.Waveform, ...
    prepared,'AbsoluteSlot',slot);
assert(unbound.Detected && isnan(unbound.DecodedDCIEvent.Data.BeamID) && ...
    isnan(unbound.DecodedDCIEvent.Data.QCLSourceID) && ...
    unbound.DecodedDCIEvent.Data.QCLSourceType=="unavailable", ...
    'Missing measured state must not be replaced by TCI/CORESET identifiers.');
ok=true;
fprintf('STRICT_PDCCH_RECEIVE_SLOT_AUTHORITY_PASS: live and prepared blind RX across frames.\n');
end
