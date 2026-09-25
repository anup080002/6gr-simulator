function ok = testMsg4ReceiverOwnsDCI(modes)
% Actual ideal-channel component, not full MAC/RRC/access qualification.
if nargin<1, modes=["TDD","FDD"]; end
assert(~isempty(modes) && all(ismember(string(modes),["TDD","FDD"])));
for mode = reshape(string(modes),1,[])
    suffix=""; if mode=="TDD", suffix="_tdd"; end
    sc=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
        "lls_causal_access_to_data_wiring"+suffix+".yaml"));
    cfg=sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(sc,tempname));
    cfg.random_access.associated_ssb_index=cfg.phy.ssb.runtimeSSBIndex;
    cfg.random_access.associated_ssb_selection_source="configured_Msg4_component_reference_not_measured_selection";
    ra = sixgr.mac.ra.RAConfig(cfg);
    assert(ra.DCIPayloadBits==ra.Msg4DCIPayloadBits && ra.Msg4DCIPayloadBits~=32);
    msg3 = sixgr.mac.ra.buildMsg3Payload('UEId',1);
    msg4 = sixgr.mac.ra.buildMsg4ContentionResolution(msg3.ContentionIdentity,'FinalCRNTI',ra.FinalCRNTI);
    [tx,sched] = sixgr.phy.ra.generateMsg4Waveform(cfg,ra,msg4);
    % Neither the TX schedule/grid/length nor authored PDSCH can tell this
    % receiver which data allocation or TBS was actually transmitted.
    rxRA = ra; rxRA.Msg4PDSCH=struct();
    [control,rx,decoded] = sixgr.phy.ra.recoverMsg4Waveform(tx.Waveform,cfg,rxRA,struct(),struct());
    assert(control.CausalGrantDecodeOk && rx.Ok && decoded.ContentionIdentity==msg3.ContentionIdentity);
    assert(isequal(control.DCIBits,sched.DCIBits) && ...
        isequal(rx.RecoveredSchedule.PDSCH.PRBSet,sched.PDSCH.PRBSet));
    assert(rx.RecoveredSchedule.HARQProcessId==ra.Msg4DCI.harq_process && ...
        rx.RecoveredSchedule.PUCCHResourceIndicator==ra.Msg4DCI.pucch_resource_indicator && ...
        ~rx.RecoveredSchedule.FeedbackTransmissionQualified);
    assert(decoded.EncodingProfile=="legacy_bounded_not_NR_MAC_RRC");
    assert(tx.PDCCHInfo.CommonControlEvidence.Source=="scenario_common_control_pending_sib1");
    fields=sixgr.phy.ra.commonDCIFieldEvidence(struct('RunId',"Msg4_component",'UEId',1), ...
        ra.Msg4Slot,ra.TempCRNTI,tx,rx,"Msg4");
    assert(height(fields)==24 && sum(fields.Endpoint=="UE_RX")==12 && ...
        all(fields.RNTI==ra.TempCRNTI) && all(strlength(fields.ContextDigest)==64));
    file=string(tempname)+".csv";
    cleanup=onCleanup(@()delete(file));
    sixgr.util.csvWriteTable(file,fields);
    restored=readtable(file,'TextType','string');
    assert(isequal(restored.Value,fields.Value) && isequal(restored.ContextDigest,fields.ContextDigest));
    clear cleanup;
    fprintf('MSG4_RECEIVER_OWNS_DCI_PASS: %s bits=%d CRC=%d TBS=%d\n', ...
        mode,numel(control.DCIBits),rx.Ok,tx.TransportBlockSize);
    % The default-A allocation TABLE also contains mapping-type-B rows.
    % Do not confuse its table name with a mapping-type-A restriction.
    ra.Msg4PDSCH.SymbolStart=5; ra.Msg4PDSCH.NumSymbols=2;
    [txB,schedB]=sixgr.phy.ra.generateMsg4Waveform(cfg,ra,msg4);
    [~,rxB,decodedB]=sixgr.phy.ra.recoverMsg4Waveform(txB.Waveform,cfg,rxRA,struct(),struct());
    assert(rxB.Ok && schedB.PDSCH.MappingType=="B" && ...
        isequal(rxB.RecoveredSchedule.PDSCH.SymbolAllocation,[5 2]) && ...
        decodedB.ContentionIdentity==msg3.ContentionIdentity);
    fprintf('MSG4_TYPE_B_RECEIVER_PASS: %s TBS=%d\n',mode,txB.TransportBlockSize);
end
ok=true;
end
