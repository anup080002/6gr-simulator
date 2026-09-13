function ok=testReceivedULTotalDAICodebook(outputRoot)
% Actual CRC-accepted UL DCI and retained received-DL event evidence.
% This qualifies the UE procedure, not shared PUSCH/gNB reception.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
mkdir(outputRoot); rows=table();
for k=1:4
    saved=load(fullfile('docs','lls','evidence_20260913','received_harq_event_04', ...
        sprintf('received_event_%d.mat',k)));
    event=saved.event; e=event.Data;
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,e.TargetSlot-1);
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    fields=struct();
    for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
    fields.mcs=10; fields.ndi=1;
    fields.antenna_ports=sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna(context.Data,1,0,2,1);
    fields.precoding_information_and_number_of_layers= ...
        sixgr.phy.pdcch.ULPrecodingField.encode(context.Data,1,0);
    for raw=0:3
        fields.first_dai=raw;
        packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        prepared=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits,'RNTI',e.RNTI);
        [control,info]=sixgr.phy.dl.PDCCH_Rx(prepared.TransmitSamples,cfg, ...
            'SampleRate_Hz',prepared.SampleRateHz);
        a=sixgr.phy.pdcch.materializeConnectedDCI(control,info,cfg);
        assert(a.Direction=="UL" && a.Fields.first_dai==raw && a.DataAbsoluteSlot+1==e.TargetSlot);
        book=sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,a,e);
        n=raw+1+4*double(raw+1<e.DAI);
        expected=zeros(n,1,'int8'); expected(e.DAI)=int8(e.State=="ACK");
        positions=zeros(n,1); positions(e.DAI)=1;
        assert(isequal(book.Bits,expected) && isequal(book.SourceEventIndex,positions) && ...
            ~any(book.DTXMask) && numel(book.Events)==1 && ...
            book.Events(1).Digest==event.Digest && ...
            book.ProcedureContext.ReceivedULAssignmentDigest==a.AssignmentDigest);
        payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',book);
        assert(isequal(payload.HARQACK,expected) && payload.HARQACKReport.Digest==book.Digest && ...
            payload.toStruct().HARQACKReport.Digest==book.Digest);
        none=sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,a,struct([]));
        emptyCount=raw+1; if raw==3, emptyCount=0; end
        assert(numel(none.Bits)==emptyCount && ~any(none.Bits) && ...
            all(none.MissingAssignmentMask) && ~any(none.DTXMask) && isempty(none.Events));
        bad=a; bad.Fields.first_dai=mod(raw+1,4);
        localReject(@()sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,bad,e), ...
            'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
        bad=e; bad.TargetSlot=bad.TargetSlot+1;
        localReject(@()sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,a,bad), ...
            'sixgr:phy:pucch:MixedHARQContext');
        bad=e; bad.RNTI=bad.RNTI+1;
        localReject(@()sixgr.phy.pucch.HARQACKCodebookBuilder.buildForPUSCH(cfg,a,bad), ...
            'sixgr:phy:pucch:MixedHARQContext');
        pucch=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',e,e.ConfigurationEpoch);
        localReject(@()sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',pucch), ...
            'sixgr:pusch:HARQACKProcedureRequired');
        save(fullfile(outputRoot,sprintf('received_ul_dai_%d_%d.mat',k,raw)), ...
            'control','info','a','event','book','payload','none');
        row=table(k,raw,numel(book.Bits),emptyCount,string(a.AssignmentDigest), ...
            string(book.Digest),'VariableNames',{'DLCase','ULTotalDAIRaw','CodebookLength', ...
            'NoDLEventLength','ReceivedULAssignmentDigest','CodebookDigest'});
        rows=[rows;row]; %#ok<AGROW>
    end
end
writetable(rows,fullfile(outputRoot,'received_ul_dai_codebooks.csv'));
fprintf('RECEIVED_UL_TOTAL_DAI_CODEBOOK_PASS received_dcIs=16 codebooks=32 guards=64 folder=%s\n',outputRoot);
ok=true;
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
