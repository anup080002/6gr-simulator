function ok=testReceivedULEmptyUCIIdentity()
% Received UL DCI authorizes an empty Type-2 report (not absent authority).
% Encoding zero UCI bits must retain its procedure identity on new TX/retx.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
entity=sixgr.link.ReceivedULHARQState(installed);
bits=[];
for k=1:2
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,31+10*(k-1));
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
    defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
    fields=struct(); for d=defs(:).', fields.(d.Name)=d.ValueMin; end
    fields.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*5+3;
    fields.mcs=10; fields.rv=2*(k-1); fields.ndi=1; fields.harq_process=2;
    fields.antenna_ports=3; fields.precoding_information_and_number_of_layers=3;
    fields.dmrs_sequence_initialization=1;
    fields.first_dai=3; % No received DL event + total DAI=4: zero ACK bits.
    packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    controlTx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits, ...
        'RNTI',cfg.phy.pdsch.RNTI);
    [control,controlInfo]=sixgr.phy.dl.PDCCH_Rx(controlTx.TransmitSamples,cfg, ...
        'SampleRate_Hz',controlTx.SampleRateHz);
    assignment=sixgr.phy.pdcch.materializeConnectedDCI(control,controlInfo,cfg);
    book=sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,assignment,struct([]));
    uci=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',book);
    assert(isempty(book.Bits) && ~uci.hasPayload() && ~isempty(uci.HARQACKReport));
    if k==1
        allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,assignment);
        bits=int8(mod((1:allocation.NominalTBSBits)',2));
        inputBits=bits;
    else
        inputBits=[];
    end
    before=entity;
    [tx,~,entity]=entity.transmit(cfg,assignment,inputBits,uci);
    [withoutReport,~,~]=before.transmit(cfg,assignment,inputBits,[]);
    assert(isequal(tx.Waveform,withoutReport.Waveform) && ...
        isequal(tx.TransportBlock,bits), ...
        'Retaining empty UCI authority must not change data bits or samples.');
    fprintf('EMPTY_UCI_IDENTITY attempt=%d expected_fields=%d retained_fields=%d\n', ...
        k,numel(fieldnames(uci.toStruct())),numel(fieldnames(tx.UCIPayload)));
    assert(isequaln(tx.UCIPayload,uci.toStruct()), ...
        'test:EmptyUCIProcedureDropped', ...
        'The transmitter dropped the zero-bit received-DAI procedure binding.');
end
fprintf('RECEIVED_UL_EMPTY_UCI_IDENTITY_PASS new_and_retx=1 samples_unchanged=1\n');
ok=true;
end
