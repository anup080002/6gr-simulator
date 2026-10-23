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
    % A joint sweep CSV must not be able to relabel the same retained
    % observation as another operating point. These are storage identity
    % tests, not new decoded performance trials at the changed SNR.
    for identityField=["SweepPointIndex","ConfiguredSNR_dB"]
        altered=compact;
        altered.(identityField)=altered.(identityField)+1;
        localReject(@()sixgr.report.readControlEVMPairs(altered,trialPath), ...
            'sixgr:report:ControlEVMDetailTrialIdentity');
    end
    if prepared.Carrier.NSizeGrid==25
        % Build an explicitly legacy storage fixture with the original v1
        % identity fields. Reading it must preserve that scope and exact
        % samples; backward compatibility cannot relabel it as v2 evidence.
        legacyBinding=localLegacyBinding(root,trial,pairs);
        assert(legacyBinding.ControlEVMSamplesStorageContract=="control_evm_pairs/v1");
        assert(compact.ControlEVMSamplesStorageContract=="control_evm_pairs/v2");
        assert(isequaln(sixgr.report.readControlEVMPairs(legacyBinding,trialPath),pairs));
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
        % Production continuation can append the first paired observation
        % after historical rows without EVM captures. Exercise the same
        % blank decoration boundary as control-reference publication. Do
        % not manufacture samples for the earlier row or weaken bindings.
        unbound=compact;
        unbound.Slot=slot-1;
        for field=["ControlEVMSamplesJSON","ControlEVMSamplesMATFile", ...
                "ControlEVMSamplesMATFileSHA256","ControlEVMSamplesContentSHA256", ...
                "ControlEVMSamplesStorageContract"]
            unbound.(field)="";
        end
        unbound.ControlEVMSamplesCount=NaN;
        mixedBindings=sixgr.truth.fillBlankCategoricalColumns([unbound;compact],"csirs");
        assert(mixedBindings.ControlEVMSamplesMATFile(1)=="" && ...
            mixedBindings.ControlEVMSamplesStorageContract(1)=="", ...
            'Historical missing captures must not become invalid file authorities.');
        mixedPath=sixgr.report.exportControlEVMSamples(trialPath,mixedBindings);
        mixedPairs=sixgr.util.csvReadTable(mixedPath,'TextType','string');
        assert(height(mixedPairs)==compact.ControlEVMSamplesCount && ...
            all(mixedPairs.SourceTrialRow==2) && all(mixedPairs.Slot==compact.Slot), ...
            'Only the actually retained observation may contribute paired samples.');
        assert(isequaln(sixgr.report.readControlEVMPairs(mixedBindings(2,:),trialPath),pairs));
        % Empty historical evidence is valid; a declared positive sample
        % population or checksum without its authority is corruption, not
        % permission to silently drop that observation during publication.
        orphan=unbound;
        orphan.ControlEVMSamplesCount=compact.ControlEVMSamplesCount;
        localReject(@()sixgr.report.readControlEVMPairs(orphan,trialPath,true), ...
            'sixgr:report:ControlEVMDetailBinding');
        orphan=unbound;
        orphan.ControlEVMSamplesMATFileSHA256=compact.ControlEVMSamplesMATFileSHA256;
        localReject(@()sixgr.report.readControlEVMPairs(orphan,trialPath,true), ...
            'sixgr:report:ControlEVMDetailBinding');
        assert(isempty(sixgr.report.readControlEVMPairs(unbound,trialPath)));
        emptyCount=unbound; emptyCount.ControlEVMSamplesCount=0;
        assert(isempty(sixgr.report.readControlEVMPairs(emptyCount,trialPath)));
        malformed=mixedBindings;
        malformed.ControlEVMSamplesMATFile(1)="not_applicable_for_active_csirs_runtime";
        localReject(@()sixgr.report.exportControlEVMSamples(trialPath,malformed), ...
            'sixgr:report:ControlEVMDetailBinding');
        malformed=mixedBindings;
        malformed.ControlEVMSamplesStorageContract(2)="control_evm_pairs/unknown";
        localReject(@()sixgr.report.exportControlEVMSamples(trialPath,malformed), ...
            'sixgr:report:ControlEVMDetailBinding');
        % Deliberately identical numeric fixtures exercise JOINT STORAGE
        % only. Each point gets its own complete identity binding; copying
        % one real artifact and changing its CSV SNR is forbidden above.
        mixed=repmat(compact,8,1);
        snrLabels=[40;30;20;10;0;-10;-20;-30];
        for point=1:8
            pointTrial=trial;
            pointTrial.SweepPointIndex=point;
            pointTrial.ConfiguredSNR_dB=snrLabels(point);
            mixed(point,:)=sixgr.report.retainControlEVMPairs(root,pointTrial,pairs);
        end
        assert(numel(unique(mixed.ControlEVMSamplesContentSHA256))==8, ...
            'Distinct sweep identities require distinct immutable bindings.');
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

function row=localLegacyBinding(root,row,pairs)
% Test-only reproduction of the old immutable format, not a PHY execution.
contract="control_evm_pairs/v1";
names=intersect(["Direction","UEIndex","CellID","RNTI","Slot","SNR_dB"], ...
    string(row.Properties.VariableNames),'stable');
identity=table2struct(row(:,names));
descriptor=pairs;
for k=1:numel(pairs)
    for field=["SampleIndex","ReferenceReal","ReferenceImag","MeasuredReal","MeasuredImag"]
        descriptor(k).(field)=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(pairs(k).(field)));
    end
end
digest=sixgr.util.sha256Hex(struct('Contract',contract,'TrialIdentity',identity,'Pairs',descriptor));
relative="air_interface/mat/control_evm/"+digest+".mat";
target=fullfile(root,relative);
sixgr.util.matSave(target,struct('Contract',contract,'ContentSHA256',digest, ...
    'TrialIdentity',identity,'Pairs',pairs),'UseArtifactStore',false);
row.ControlEVMSamplesJSON="";
row.ControlEVMSamplesMATFile=relative;
row.ControlEVMSamplesMATFileSHA256=sixgr.util.sha256File(target);
row.ControlEVMSamplesContentSHA256=digest;
row.ControlEVMSamplesStorageContract=contract;
row.ControlEVMSamplesCount=sum(arrayfun(@(p)numel(p.SampleIndex),pairs));
end
