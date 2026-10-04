function ok=testSLSNonoverlappingUCI()
% Installed NR calendars with declared grant-ownership fixtures. No RF claim.
request=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=request.Config; cfg.phy.csi.reportCSI=false;
cfg.phy.pucch.uciOnPUSCHEnabled=true;
cfg.system.linkAbstraction.dynamicPUCCH.transportPolicy='causal_native_pusch_multiplexing';
for mode=["shared_configured_resources","per_cell_frequency_pool"]
    cfg.system.linkAbstraction.dynamicPUCCH.resourceBinding.mode=char(mode);
    for withHARQ=[false true]
        ledger=sixgr.system.SLSDynamicPUCCH(cfg);
        ledger.configureUEIdentities(4660);
        if withHARQ
            % Serialize a PRI through an explicit, grid-sized DCI fixture. The ledger
            % must resolve HARQ resources from that payload, not a test-only
            % bypass of its received-control resource-selection contract.
            context=sixgr.phy.pdcch.DCIContext.fromLegacy(struct( ...
                'NSizeGrid',cfg.phy.carrier.NSizeGrid,'RNTIValue',4660),"1_0");
            schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
            fields=struct();
            for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
            fields.pucch_resource_indicator=0;
            dci=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
            dci.ContextData=context.Data;
            dl=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',5, ...
                'ScheduledAbsoluteSlot',5,'HARQFeedbackAbsoluteSlot',9, ...
                'DCI',dci, ...
                'PHYGrant',struct('IsFrozen',true,'CodingLayout',struct('NumCodewords',1)));
            ledger.appendDL(dl,1,5);
        end
        before=ledger.snapshot(8,9,1,struct([]));
        assert(~isempty(before) && all([before.SRBits]>=1));
        assert(sum([before.HARQBits])==double(withHARQ));
        firstSymbol=min(vertcat(before.Coordinates0Based),[],1); firstSymbol=firstSymbol(2);
        assert(firstSymbol>=2,'Fixture needs a real non-overlapping UL symbol interval.');
        % The ledger only selects a transport here. The declared frozen marker
        % is not claimed to be a generated PUSCH or a decoded transport block.
        g=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',8, ...
            'ScheduledAbsoluteSlot',9,'SymbolAllocation',[0 firstSymbol], ...
            'PRBSet',20:21,'PHYGrant',struct('IsFrozen',true));
        selected=ledger.bindPUSCH(g,1,8,1,struct([]));
        assert(isempty(fieldnames(selected.SLSUCIAllocation)) && selected.SLSUCIObligationID=="");
        assert(isequaln(selected.PHYGrant,g.PHYGrant) && isequal(selected.SymbolAllocation,g.SymbolAllocation));
        after=ledger.snapshot(8,9,1,struct([]));
        assert(isequaln(after,before) && all(string({after.Transport})=="PUCCH"), ...
            'test:NonoverlapUCI','Non-overlapping UCI must remain on its original PUCCH.');
        % Exercise the production runner's admission and execution helpers,
        % not only the transport binder. Neither may reject adjacent symbols.
        assert(isempty(ledger.blockedUEsForPUSCH(before,1,g.SymbolAllocation)));
        ledger.assertPUSCHExecution(selected,1,after,9);
        overlapGrant=g; overlapGrant.SymbolAllocation=[firstSymbol 1];
        blocked=ledger.blockedUEsForPUSCH(before,1,overlapGrant.SymbolAllocation);
        assert(isequal(isempty(blocked),withHARQ));
        reject(@()ledger.assertPUSCHExecution(overlapGrant,1,before,9), ...
            'sixgr:system:DedicatedPUCCHPUSCHCollision');
        reject(@()ledger.assertPUSCHExecution(g,1,before,10), ...
            'sixgr:system:ReservationExecutionClock');
        % A second same-slot occasion outside PUSCH must not turn the one
        % overlapping HARQ/CSI obligation into ambiguous multiplexing.
        later=before(1); later.Coordinates0Based(:,2)=firstSymbol+1;
        mixed=[before later];
        assert(isequal(isempty(ledger.blockedUEsForPUSCH( ...
            mixed,1,overlapGrant.SymbolAllocation)),withHARQ));
        dedicatedCfg=cfg; dedicatedCfg.phy.pucch.uciOnPUSCHEnabled=false;
        dedicatedCfg.system.linkAbstraction.dynamicPUCCH.transportPolicy='dedicated_pucch_no_pusch_multiplexing';
        dedicated=sixgr.system.SLSDynamicPUCCH(dedicatedCfg);
        dedicated.configureUEIdentities(4660);
        assert(isempty(dedicated.blockedUEsForPUSCH(before,1,g.SymbolAllocation)));
        assert(isequal(dedicated.blockedUEsForPUSCH(before,1,overlapGrant.SymbolAllocation),1));
        dedicated.assertPUSCHExecution(g,1,before,9);
        % A valid index is not authority to transmit under another RNTI.
        % Reject before even publishing or binding an obligation.
        wrong=g; wrong.RNTI=4661;
        rejectIdentity(@()ledger.bindPUSCH(wrong,1,8,1,struct([])));
        assert(isequaln(ledger.snapshot(8,9,1,struct([])),before) && ...
            isempty(ledger.Trace) && isempty(ledger.CompletionTrace));
        if ~withHARQ
            overlapping=g; overlapping.SymbolAllocation=[firstSymbol 1];
            caught=false;
            try
                ledger.bindPUSCH(overlapping,1,8,1,struct([]));
            catch ME
                assert(strcmp(ME.identifier,'sixgr:system:SLSUCIUnsupportedOverlap'));
                caught=true;
            end
            assert(caught,'Unsupported overlapping SR-only UCI must not be silently dropped or bound.');
            assert(isequaln(ledger.snapshot(8,9,1,struct([])),before));
        end
        if withHARQ
            % Supply an explicitly labeled ledger decision fixture. A PRI
            % and a reservation alone are not an ACK/NACK producer.
            tb="nonoverlap_ledger_fixture";
            ctx=struct('Direction',"DL",'Grant',dl,'ServingCellID',1,'TransportBlockIdentity',tb);
            ctx.Grant.TransportBlockIdentity=tb;
            modeled=struct('Ok',false,'TransportBlockIdentity',tb, ...
                'TransmissionAbsoluteSlot0',5,'ReceiveCompletionAbsoluteSlot0',5, ...
                'SourceClassification',"development_fixture_not_study_result", ...
                'CalibrationQualified',false,'CalibrationSHA256',repmat('a',1,64), ...
                'CalibrationCurveID',"fixture_only",'CalibrationKeySHA256',repmat('b',1,64), ...
                'WaveformReplayExecuted',false,'PHYDecisionStatus',"OK");
            ledger.recordHARQDecision(ctx,modeled);
        end
        ledger.completeSlot(9,1,struct([]),{},struct([]));
        assert(height(ledger.CompletionTrace)==numel(before) && ...
            all(ledger.CompletionTrace.Transport=="PUCCH") && ...
            ~any(ledger.CompletionTrace.WaveformBacked));
    end
end
fprintf('SLS_NONOVERLAPPING_UCI_PASS policies=2 SR_and_HARQ=1 physical_qualification=0\n');
ok=true;
end

function rejectIdentity(fn)
reject(fn,'sixgr:system:UCIIdentityMismatch');
end

function reject(fn,id)
try, fn(); catch ME
    assert(strcmp(ME.identifier,id), ...
        'Unexpected ownership failure %s: %s',ME.identifier,ME.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
