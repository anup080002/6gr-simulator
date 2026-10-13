function ok=testH4100ConnectedControlFrequencyReception()
% Full 100-MHz carrier, one logical control-port unit-channel component.
% No fading/array qualification claim; RX receives samples and installed
% policy only, never a transmitter PDCCH object or transmitted payload size.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_adaptive.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
for format=["0_1","1_1"]
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,format);
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    fields=struct();
    for def=schema.Definitions(:).'
        fields.(def.Name)=def.ValueMin;
    end
    fields.mcs=10; fields.ndi=1;
    packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    [tx,info]=sixgr.phy.dl.PDCCH_Tx(cfg, ...
        'DCIBits',packed.Bits,'RNTI',context.Data.RNTIValue);
    assert(tx.Carrier.NSizeGrid==273 && tx.Carrier.SubcarrierSpacing==30);
    coordinates=info.AllocatedRECoordinates;
    assert(all(coordinates(:,1)>=112*12 & coordinates(:,1)<160*12), ...
        'Executed PDCCH must occupy the YAML-owned CORESET frequency interval.');
    [rx,evidence]=sixgr.phy.dl.PDCCH_Rx(tx.Waveform,cfg,'SampleRate_Hz',122.88e6);
    assert(rx.Ok && isequal(rx.DCIBits,packed.Bits) && rx.DecodedDCI.Format==format);
    assert(evidence.ReceiverConfiguredMonitoring, ...
        'Control reception must construct its own installed hypotheses.');
    % A valid but wrong receiver location must fail physically. Do not pass
    % it the transmitter's CORESET or search for a strongest-energy layout.
    wrong=cfg; wrong.phy.pdcch.coreset.rbStart=0;
    rejected=sixgr.phy.dl.PDCCH_Rx(tx.Waveform,wrong,'SampleRate_Hz',122.88e6);
    assert(~rejected.Ok,'An unconfigured frequency search must not rescue the wrong receive CORESET.');
end
fprintf('H4_100_CONNECTED_CONTROL_FREQUENCY_RECEPTION_PASS formats=2 wrong_location_rejections=2\n');
ok=true;
end
