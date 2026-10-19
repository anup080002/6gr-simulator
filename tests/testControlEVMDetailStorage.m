function ok=testControlEVMDetailStorage()
% Actual prepared CSI-RS waveforms: exact storage, identity and corruption.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'logs','lls_repairs', ...
    "evm_detail_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
measurements=struct([]);
for yaml=["lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml", ...
        "h4_100_cdlc100_connected_impaired_40db_gate.yaml"]
    scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator/configs/scenarios',yaml));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
    slot=cfg.phy.csirs.offset_slots+1;
    prepared=sixgr.link.prepareCSIRSTransmission(cfg,40,'RuntimeSlot',slot);
    prepared.TransmitStartSample=0;
    observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
        0,prepared.NumSamples,prepared.SampleRateHz,size(prepared.TransmitSamples,2));
    % Known test operator, not claimed as physical PA qualification.
    observation.append(sixgr.phy.waveform.WaveformChunk(1.1*prepared.TransmitSamples,0),prepared.SampleRateHz);
    pairs=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared,observation);
    trial=table("DL",1,1,slot,1,40, ...
        'VariableNames',{'Direction','UEIndex','CellID','Slot','SweepPointIndex','ConfiguredSNR_dB'});
    timer=tic; inline=trial; inline.ControlEVMSamplesJSON=string(jsonencode(pairs));
    inlineSeconds=toc(timer); inlineInfo=whos('inline');
    timer=tic; compact=sixgr.report.retainControlEVMPairs(root,trial,pairs);
    detailSeconds=toc(timer); compactInfo=whos('compact');
    trialPath=fullfile(root,'air_interface','csv','csi_rs_trials.csv');
    restored=sixgr.report.readControlEVMPairs(compact,trialPath);
    assert(isequaln(restored,pairs) && compact.ControlEVMSamplesCount==nnz(prepared.Tx.Grid), ...
        'sixgr:test:EVMDetailLoss','No port, RE, sample, numeric class or metadata may be lost.');
    assert(compactInfo.bytes<inlineInfo.bytes/10 && compact.ControlEVMSamplesJSON=="", ...
        'sixgr:test:EVMDetailRetention','Live rows must not retain the paired sample arrays or JSON.');
    repeated=sixgr.report.retainControlEVMPairs(root,trial,pairs);
    assert(isequaln(compact,repeated),'Exact repeated storage must reuse immutable bytes.');
    for e=restored
        r=complex(e.ReferenceReal,e.ReferenceImag); m=complex(e.MeasuredReal,e.MeasuredImag);
        assert(abs(sqrt(sum(abs(m-r).^2)/sum(abs(r).^2))-.1)<1e-10, ...
            'Raw gain-inclusive paired error must retain the declared 1.1 test operator.');
    end
    % CSV roundtrip must preserve the binding and exact paired samples.
    sixgr.util.csvWriteTable(trialPath,compact,'PreserveSchema',true,'RoundTripNumericText',true);
    persisted=sixgr.util.csvReadTable(trialPath,'TextType','string');
    assert(isequaln(sixgr.report.readControlEVMPairs(persisted,trialPath),pairs));
    altered=compact; altered.Slot=altered.Slot+1;
    localReject(@()sixgr.report.readControlEVMPairs(altered,trialPath), ...
        'sixgr:report:ControlEVMDetailTrialIdentity');
    if prepared.Carrier.NSizeGrid==25
        % A matching file in a parent or another run must never rescue a
        % missing run-local artifact, even when its checksum is identical.
        nestedRun=fullfile(root,'other_run');
        nestedCSV=fullfile(nestedRun,'air_interface','csv','csi_rs_trials.csv');
        localReject(@()sixgr.report.readControlEVMPairs(compact,nestedCSV), ...
            'sixgr:report:ControlEVMDetailMissing');
        mirrorPath=fullfile(root,'control','csv','csi_rs_trials.csv');
        assert(isequaln(sixgr.report.readControlEVMPairs(compact,mirrorPath),pairs));
        % Explicit legacy component-root layout, isolated within THIS run.
        legacyRun=fullfile(root,'legacy_component_root');
        legacyTarget=fullfile(legacyRun,'air_interface',compact.ControlEVMSamplesMATFile);
        mkdir(fileparts(legacyTarget));
        copyfile(fullfile(root,compact.ControlEVMSamplesMATFile),legacyTarget);
        legacyCSV=fullfile(legacyRun,'control','csv','csi_rs_trials.csv');
        assert(isequaln(sixgr.report.readControlEVMPairs(compact,legacyCSV),pairs));
        relocatedRun=fullfile(root,'relocated_run');
        copyfile(legacyRun,relocatedRun);
        assert(isequaln(sixgr.report.readControlEVMPairs(compact, ...
            fullfile(relocatedRun,'air_interface','csv','csi_rs_trials.csv')),pairs));
        canonical=fullfile(legacyRun,compact.ControlEVMSamplesMATFile);
        mkdir(fileparts(canonical)); copyfile(legacyTarget,canonical);
        localReject(@()sixgr.report.readControlEVMPairs(compact,legacyCSV), ...
            'sixgr:report:AmbiguousControlEVMPairs');
        % Same complete sample CSV under old and new storage; no plots need
        % a new measurement definition or a reduced sample population.
        oldPath=sixgr.report.exportControlEVMSamples(trialPath,inline);
        oldHash=sixgr.util.sha256File(oldPath);
        newPath=sixgr.report.exportControlEVMSamples(trialPath,compact);
        assert(oldHash==sixgr.util.sha256File(newPath),'Legacy/detail sample CSV bytes must match exactly.');
        [~,rewritten]=sixgr.report.exportControlEVMSamples(trialPath,compact);
        assert(~rewritten,'Unchanged source and sink must use the verified publication cache.');
        mixed=repmat(compact,8,1); mixed.SweepPointIndex=(1:8).';
        mixed.ConfiguredSNR_dB=[40;30;20;10;0;-10;-20;-30];
        jointPath=sixgr.report.exportControlEVMSamples(trialPath,mixed);
        joint=sixgr.util.csvReadTable(jointPath,'TextType','string');
        assert(height(joint)==8*compact.ControlEVMSamplesCount && numel(unique(joint.SweepPointIndex))==8);
        sixgr.report.exportControlEVMSamples(trialPath,compact);
        % Deletion/corruption must not hide behind an already cached CSV.
        source=fullfile(root,compact.ControlEVMSamplesMATFile); moved=source+".retained";
        movefile(source,moved);
        localReject(@()sixgr.report.exportControlEVMSamples(trialPath,compact), ...
            'sixgr:report:ControlEVMDetailMissing');
        copyfile(moved,source);
        fid=fopen(source,'a'); assert(fid>=0); fwrite(fid,uint8(123)); fclose(fid);
        localReject(@()sixgr.report.exportControlEVMSamples(trialPath,compact), ...
            'sixgr:report:ControlEVMDetailChecksum');
        copyfile(moved,source,'f');
    end
    disk=dir(fullfile(root,compact.ControlEVMSamplesMATFile));
    measurement=struct('NSizeGrid',prepared.Carrier.NSizeGrid,'PhysicalTXPorts',numel(pairs), ...
        'PairedSampleCount',compact.ControlEVMSamplesCount, ...
        'InlineRowMemoryBytes',inlineInfo.bytes,'CompactRowMemoryBytes',compactInfo.bytes, ...
        'DetailFileBytes',disk.bytes,'InlineEncodeSeconds',inlineSeconds, ...
        'DetailWriteAndReadbackSeconds',detailSeconds,'ExactNumericRoundTrip',true, ...
        'BenchmarkScope',"storage_only_not_full_run_peak_memory_or_speedup");
    measurements=[measurements;measurement]; %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(root,'storage_measurements.csv'),struct2table(measurements),'PreserveSchema',true);
fprintf('CONTROL_EVM_DETAIL_STORAGE_PASS root=%s\n',root);
ok=true;
end
function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s; received %s',identifier,cause.identifier);
    return;
end
error('sixgr:test:ExpectedEVMDetailRejection','Expected %s',identifier);
end
