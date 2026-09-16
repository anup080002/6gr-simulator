function root=verifyReceivedConstellationCapture(out,cfg,ue)
% Independently reconcile actual receiver pairs; no constellation fitting.
T=out.ConstellationSamples;
assert(istable(T)&&~isempty(T),'test:MissingReceivedPairs','Completed data receiver must retain paired symbols.');
trial=out.TrialTable;
assert(height(trial)==1 && trial.SFN==mod(trial.CarrierNFrame,1024), ...
    'Radio SFN must come from the actual executed carrier, not one-based reporting Frame.');
assert(all(T.SFN==trial.SFN) && all(T.CarrierNFrame==trial.CarrierNFrame) && ...
    all(T.CarrierNSlot==trial.CarrierNSlot));
assert(isequaln(T.UEIndex,repmat(trial.UEIndex,height(T),1)) && ...
    isequaln(T.ue_id,T.UEIndex) && ...
    isequaln(T.RNTI,repmat(trial.RNTI,height(T),1)) && ...
    isequaln(T.BaseStationID,repmat(trial.BaseStationID,height(T),1)), ...
    'Receiver sample exports must preserve available grant identity without replacing missing values.');
assert(all(T.CaptureScope=="full_allocation_paired_symbols"));
assert(all(T.CapturedSymbolCount==height(T)) && all(T.ObservationSymbolCount==height(T)));
assert(height(T)==out.TrialTable.SymbolsCompared);
ref=complex(T.ReferenceSymbolReal,T.ReferenceSymbolImag);
received=complex(T.RawEqualizedReal,T.RawEqualizedImag);
assert(all(isfinite(ref))&&all(isfinite(received)));
assert(isequal(received,complex(T.EqualizedReal,T.EqualizedImag)), ...
    'Reporter must not apply payload-derived gain/phase fitting.');
evm=sqrt(sum(abs(received-ref).^2)/sum(abs(ref).^2));
assert(abs(evm-out.TrialTable.EVM_rms)<=1e-12*max(1,evm), ...
    'Receiver EVM must equal independently summed paired-symbol energy.');
coords=[T.OFDMSymbolIndex,T.SubcarrierIndex,T.LayerIndex];
assert(size(unique(coords,'rows'),1)==height(T));
assert(all(T.UEIndex==ue), ...
    'The producer must retain the component grant UE identity; the test must not fill it in.');
root=tempname; sixgr.util.ensureFolder(root);
[dl,ul]=sixgr.truth.constellationArtifactPaths(cfg,fullfile(root,'air_interface','csv'));
direction=string(T.Direction(1)); path=dl; if direction=="UL", path=ul; end
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
persisted=sixgr.util.csvReadTable(path,'TextType','string');
assert(height(persisted)==height(T));
assert(max(abs(persisted.RawEqualizedReal-T.RawEqualizedReal))<1e-12);
assert(max(abs(persisted.ReferenceSymbolImag-T.ReferenceSymbolImag))<1e-12);
power=jsondecode(trial.AllocationCarrierPowerMeasurementJSON);
assert(power.Direction==direction && power.RNTI==trial.RNTI && ...
    power.NumReceiveAntennas==trial.PhysicalRxAntennas, ...
    'Carrier power must come from this actual received grant and all physical branches.');
normalized=strcmpi(string(sixgr.util.structGet(cfg,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
    logical(sixgr.util.structGet(cfg,'integration.configured_snr_is_link_authority',false));
if normalized
    assert(power.PowerReferencePlane=="normalized_fixed_esn0_unit_occupied_re_es" && ...
        ~isfield(power,'SymbolPowerPerAntenna_W') && ~isfield(power,'RSSIPerAntenna_dBm'));
    values=10*log10(mean(power.SymbolPowerPerAntenna_UnitOccupiedRE_Es,1));
    assert(max(abs(values(:)-power.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es(:)))<1e-9);
else
    assert(power.PowerReferencePlane=="receiver_antenna_connector_pre_composite_front_end");
    values=10*log10(mean(power.SymbolPowerPerAntenna_W,1))+30;
    assert(max(abs(values(:)-power.RSSIPerAntenna_dBm(:)))<1e-9);
end
trialPath=fullfile(root,'air_interface','csv','dl_pdsch_trials.csv');
if direction=="UL", trialPath=fullfile(root,'air_interface','csv','ul_pusch_trials.csv'); end
sixgr.util.csvWriteTable(trialPath,trial,'PreserveSchema',true);
if direction=="UL"
    spatial=jsondecode(trial.ULSpatialMeasurementEvidenceJSON);
    assert(strcmp(spatial.ChannelEstimateDomain,'pusch_dmrs_effective_layer_domain'));
    assert(~spatial.SRSRITPMIValid && ...
        strcmp(spatial.CSIReportMode,'ul_pusch_dmrs_effective_channel_no_tpmi_recommendation'));
    if isfinite(trial.AppliedPrecoderPMI)
        assert(spatial.PMI==trial.AppliedPrecoderPMI && spatial.RuntimeAppliedPMI==trial.AppliedPrecoderPMI, ...
            'Actual received PUSCH must persist transmitter TPMI without claiming an SRS recommendation.');
        native=nrPUSCHCodebook(trial.PrecodingNumLayers,trial.PrecodingNumLogicalPorts, ...
            trial.AppliedPrecoderPMI,logical(trial.TransformPrecodingApplied));
        expectedPorts=find(sum(abs(native).^2,1)>0);
        actualPorts=str2double(split(string(trial.AppliedCodebookPortIndexSet),'|')).';
        assert(isequal(actualPorts,expectedPorts) && ...
            string(trial.AppliedCodebookPortIndexDefinition)=="one_based_logical_antenna_port_support_not_spatial_beam_ID", ...
            'Persisted codebook port support must match actual transmitter TPMI/layers/ports.');
        assert(strlength(string(trial.AppliedBeamIndexSet))==0 && ...
            string(trial.AppliedBeamTruthClassification)=="not_materialized_in_active_ul_path", ...
            'Native antenna-port support must not become a physical spatial-beam ID.');
    else
        assert(isempty(spatial.PMI) && isempty(spatial.RuntimeAppliedPMI), ...
            'Missing/not-applicable TPMI must retain JSON null rather than an invented index.');
    end
    readback=sixgr.util.csvReadTable(trialPath,'TextType','string');
    assert(string(readback.ULSpatialMeasurementEvidenceJSON)==string(trial.ULSpatialMeasurementEvidenceJSON));
end
receipt=sixgr.artifact.publishLiveCSVPlots(cfg,root);
assert(receipt.Enabled && receipt.CreatedCount>=1);
manifest=jsondecode(fileread(receipt.Manifest));
name="PDSCH EVM per symbol"; if direction=="UL", name="PUSCH EVM per symbol"; end
charts=manifest.charts;
if iscell(charts)
    names=cellfun(@(c)string(c.name),charts);
    selected=find(names==name);
    assert(isscalar(selected));
    chart=charts{selected};
else
    selected=find(string({charts.name})==name);
    assert(isscalar(selected));
    chart=charts(selected);
end
assert(string(chart.status)=="measured_checkpoint");
powerName="PDSCH-window carrier RSSI timeline";
if direction=="UL", powerName="PUSCH-window carrier RSSI timeline"; end
if iscell(charts)
    powerChart=charts{find(cellfun(@(c)string(c.name),charts)==powerName)};
else
    powerChart=charts(find(string({charts.name})==powerName));
end
assert(isscalar(powerChart) && string(powerChart.status)=="measured_checkpoint", ...
    'Actual received carrier RSSI must publish source-bound CSV and PNG with its own reference units.');
powerCSV=sixgr.util.csvReadTable(fullfile(fileparts(receipt.Manifest),powerChart.csv),'TextType','string');
if normalized
    assert(ismember('rssi_db_re_unit_occupied_re_es',powerCSV.Properties.VariableNames) && ...
        ~ismember('rssi_dbm',powerCSV.Properties.VariableNames));
    assert(max(abs(powerCSV.rssi_db_re_unit_occupied_re_es(:)-values(:)))<1e-9);
else
    assert(max(abs(powerCSV.rssi_dbm(:)-values(:)))<1e-9);
end
stem="pdsch"; if direction=="UL", stem="pusch"; end
files=dir(fullfile(root,'reports','live_measurements','*','csv',stem+"_evm_per_symbol.csv"));
assert(numel(files)==1,'Exactly one current measured-symbol CSV is expected.');
plotted=readtable(fullfile(files.folder,files.name),'TextType','string');
assert(~isempty(plotted) && all(plotted.sfn==trial.SFN), ...
    'EVM plotting must preserve the executed radio SFN.');
knownCells=unique(T.ServingCell(isfinite(T.ServingCell)));
if isscalar(knownCells)
    assert(all(plotted.cell_id==knownCells), ...
        'Available serving-cell identity must survive the plotting CSV.');
else
    assert(isempty(knownCells) && all(ismissing(plotted.cell_id)), ...
        'A missing serving-cell identity must not be guessed.');
end
fprintf('RECEIVED_CONSTELLATION_CAPTURE_PASS: %s samples=%d EVM_pct=%.12g root=%s\n', ...
    direction,height(T),100*evm,root);
diagnosticNames=intersect(["Direction","Slot","EstimatedCFO_PreCorrection_Hz", ...
    "EstimatedCFO_Hz","ResidualCFO_EstimatedPostCorrection_Hz", ...
    "TimingOffset_samples","EVM_rms","PostEqSINR_dB"], ...
    string(out.TrialTable.Properties.VariableNames),'stable');
disp(out.TrialTable(:,diagnosticNames));
end
