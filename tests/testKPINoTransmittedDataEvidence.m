function ok=testKPINoTransmittedDataEvidence()
% Completed zero-transmission observation is not a successful decode.
cfg=struct('scenario',struct('layout',struct('nSites',2,'nSectorsPerSite',3)));
capacity=sixgr.kpi.loadDirectionRawTables(struct('Config',cfg));
assert(capacity.NumResourceCells==6,'Installed sites/sectors must include idle resource cells.');
cfg.scenario.layout=rmfield(cfg.scenario.layout,'nSectorsPerSite');
capacity=sixgr.kpi.loadDirectionRawTables(struct('Config',cfg));
assert(isnan(capacity.NumResourceCells),'Missing topology must not become a one-cell default.');
for direction=["DL","UL"]
    raw=fixture(direction);
    proof=sixgr.kpi.proveNoTransmittedData(raw,direction);
    assert(proof.Proven && abs(proof.DurationSec-.002)<1e-12);
    assert(strlength(proof.SourceHash)==64);
    out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, ...
        'SourcePaths',raw.Paths,'MeasurementWindowSec',.002,'EffectiveBandwidthHz',5e6);
    rows=out.ReconstructionSummary;
    for name=["Scenario_Total_"+direction+"_DeliveredBits", ...
            "Scenario_Total_"+direction+"_ScheduledBits", ...
            direction+"_TB_Delivery_Goodput_Mbps",direction+"_SpectralEfficiency_bpsHz"]
        r=rows(rows.KPIName==name,:);
        assert(height(r)==1 && r.Value==0 && r.StrictOk && ~r.MissingRawData);
        assert(r.MeasurementWindowSec==.002 && r.ScheduledResourceExposureSec==0);
        assert(r.NoTransmittedDataProven && r.SourceRowsHash=="empty" && ...
            strlength(r.NoTransmissionEvidenceHash)==64);
    end
    for name=direction+["_BLER","_BER","_TB_Delivery_Latency_ms","_Goodput_Max_Mbps", ...
            "_PHY_ScheduledThroughput_Mbps","_HARQ_NACK_Rate","_Retransmission_Rate"]
        r=rows(rows.KPIName==name,:);
        assert(isnan(r.Value) && ~r.StrictOk && ~r.FormulaExecuted && ...
            r.Status=="unavailable_no_transmissions" && ~r.MissingRawData);
    end
    assert(~out.StrictOk); % No fake overall qualification.
    resource=rows(rows.KPIName==direction+"_PRB_Utilization",:);
    assert(resource.StrictOk && resource.Value==0 && resource.NumeratorValue==0 && resource.DenominatorValue==350);
    manifest=out.SourceManifest(out.SourceManifest.Direction==direction,:);
    assert(manifest.Exists && manifest.RowCount==0 && manifest.FileHash=="empty");
    unit=out.UnitConversionAudit(out.UnitConversionAudit.KPIName==direction+"_PHY_ScheduledThroughput_Mbps",:);
    assert(~unit.Pass && unit.Status=="unavailable_no_transmissions" && isnan(unit.ExpectedMbps));
    noCapacity=raw; noCapacity.NumResourceCells=NaN;
    unavailable=sixgr.kpi.reconstructLLSKPISummaryFromRaw(noCapacity);
    resource=unavailable.ReconstructionSummary(unavailable.ReconstructionSummary.KPIName==direction+"_PRB_Utilization",:);
    assert(~resource.StrictOk && isnan(resource.Value));
    badWindow=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'MeasurementWindowSec',.003);
    r=badWindow.ReconstructionSummary;
    r=r(r.KPIName==direction+"_TB_Delivery_Goodput_Mbps",:);
    assert(isnan(r.Value) && contains(r.FailureReason,"duration_mismatch"));
    for name=["ScenarioSummary","RunState","SlotTrace",direction,direction+"Grants"]
        assertRejected(rmfield(raw,name),direction);
    end
    for field=direction+["GrantCount","ExecutedGrantCount","TrialRows","TBSBits","SuccessCount"]
        changed=raw; changed.SlotTrace.(field)(2)=1; assertRejected(changed,direction);
    end
    for field=["CanonicalSlotsPerSweepPoint","CurrentCanonicalSlot","SlotTraceRows"]
        changed=raw; changed.RunState.(field)=1; assertRejected(changed,direction);
    end
    changed=raw; changed.RunState.(direction+"GrantRows")=1; assertRejected(changed,direction);
    changed=raw; changed.ScenarioSummary.("Effective"+direction+"TrialCount")=1; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.ConfigHash(2)="other"; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.ConfiguredSNR_dB(2)=20; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.SweepPointIndex(2)=2; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.CanonicalSlot(2)=1; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.(direction+"Scheduled")(2)=NaN; assertRejected(changed,direction);
    changed=raw; changed.SlotTrace.(direction+"Status")(2)="started"; assertRejected(changed,direction);
    changed=raw; changed.ScenarioSummary.RunCompletion="running"; assertRejected(changed,direction);
    changed=raw; changed.ScenarioSummary.SlotDuration_ms=NaN; assertRejected(changed,direction);
    changed=raw; changed.(direction)=table(2,0,'VariableNames',{'Slot','CRCPass'}); assertRejected(changed,direction);
    changed=raw; changed.(direction+"Grants")=table("actual",8,direction, ...
        'VariableNames',{'GrantContextId','TBSBits','Direction'}); assertRejected(changed,direction);
    changed=raw; changed.PacketSDU=table(direction,1,'VariableNames',{'Direction','DeliverySuccess'});
    assertRejected(changed,direction);
end
% Exercise the actual persisted loader used by exportLinkKPIs, not just an
% in-memory proof. Outputs are fixture evidence under a new temporary root.
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
raw=fixture("UL");
for name=string(fieldnames(raw.Paths))'
    file=fullfile(root,raw.Paths.(name));
    sixgr.util.ensureFolder(fileparts(file));
    sixgr.util.csvWriteTable(file,raw.(name));
end
loaded=sixgr.kpi.loadDirectionRawTables(struct(),'RunFolder',root,'PreferPersistedPrimary',true);
proof=sixgr.kpi.proveNoTransmittedData(loaded,"UL");
assert(proof.Proven && proof.DurationSec==.002);
missingRoot=fullfile(root,'empty_run'); mkdir(missingRoot);
missingEvidence=sixgr.kpi.loadDirectionRawTables(struct(),'RunFolder',missingRoot);
assert(isempty(missingEvidence.RunState) && isempty(missingEvidence.ScenarioSummary) && ...
    isempty(missingEvidence.HARQFeedback));
fprintf('PASS testKPINoTransmittedDataEvidence: zero totals, unavailable decoder metrics, contradictory evidence rejected.\n');
ok=true;
end

function assertRejected(raw,direction)
evidence=sixgr.kpi.proveNoTransmittedData(raw,direction);
assert(~evidence.Proven);
out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'MeasurementWindowSec',.002);
r=out.ReconstructionSummary;
r=r(r.KPIName==direction+"_TB_Delivery_Goodput_Mbps",:);
assert(~r.StrictOk && isnan(r.Value));
end

function raw=fixture(direction)
raw=struct();
raw.(direction)=table(zeros(0,1),zeros(0,1),'VariableNames',{'Slot','CRCPass'});
raw.(direction+"Grants")=table(strings(0,1),zeros(0,1),strings(0,1), ...
    'VariableNames',{'GrantContextId','TBSBits','Direction'});
raw.ScenarioSummary=table("fixture","hash","completed_with_failures",1,0, ...
    'VariableNames',{'ScenarioID','ConfigHash','RunCompletion','SlotDuration_ms', ...
    char("Effective"+direction+"TrialCount")});
raw.RunState=table("fixture","hash",-10,2,2,2,0, ...
    'VariableNames',{'ScenarioID','ConfigHash','ConfiguredSNR_dB', ...
    'CanonicalSlotsPerSweepPoint','CurrentCanonicalSlot','SlotTraceRows',char(direction+"GrantRows")});
raw.SlotTrace=table(["fixture";"fixture"],["hash";"hash"],[-10;-10],[1;2],[1;1], ...
    'VariableNames',{'ScenarioID','ConfigHash','ConfiguredSNR_dB','CanonicalSlot','SweepPointIndex'});
for suffix=["GrantCount","ExecutedGrantCount","TrialRows","TBSBits","SuccessCount"]
    raw.SlotTrace.(direction+suffix)=[0;0];
end
raw.SlotTrace.(direction+"Scheduled")=[0;1];
raw.SlotTrace.(direction+"Status")=["";"idle_no_grant"];
raw.SlotTrace.(direction+"SymbolStart")=[0;0];
raw.SlotTrace.(direction+"NumSymbols")=[0;14];
raw.GridNumRBs=25; raw.NumResourceCells=1; raw.SymbolsPerSlot=14;
raw.Paths=struct('ScenarioSummary',"reports/csv/scenario_summary.csv", ...
    'RunState',"reports/csv/run_state.csv",'SlotTrace',"reports/csv/slot_trace.csv");
channel="pdsch"; if direction=="UL", channel="pusch"; end
raw.Paths.(direction)="air_interface/csv/"+lower(direction)+"_"+channel+"_trials.csv";
raw.Paths.(direction+"Grants")="packet_flow/csv/live_"+lower(direction)+"_scheduler_grants.csv";
end
