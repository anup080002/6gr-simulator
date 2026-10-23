function ok=testCSIRSPhysicalDemodulationReceipt()
% Actual native CSI-only waveform/receiver component plus raw-row projection.
% Declared linear mixing/noise/delay/CFO fixture, not a shared RF/channel
% execution, isolated port-power oracle, or RSRP accuracy qualification.
setup6GRSimToolkit('Verbose',false);
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg=sixgr.truth.bindStandaloneSNRPoint(cfg,30);
cfg.phy.csirs.period_slots=1; cfg.phy.csirs.offset_slots=0;
cfg.phy.csirs.runtimeChannelEstimator='nr_channel_estimate';
cfg.phy.rx.cfoCorrectionEnabled=false;
p=sixgr.link.prepareCSIRSTransmission(cfg,30,'RuntimeSlot',1,'Frame',1);
carrier=p.Carrier; cfg=p.ReceiverConfig;
assert(size(p.TransmitSamples,2)==4);
mixed=p.TransmitSamples*[.8 0;.0 .6;.6 0;0 .8];
guard=73; delays=[11 23];
physical=[zeros(delays(1),2);mixed;zeros(guard-delays(1),2)];
post=[zeros(delays(2),2);1.7*mixed;zeros(guard-delays(2),2)];
stream=RandStream('mt19937ar','Seed',927140);
amplitude=max(abs(mixed),[],'all')*1e-4;
physical=physical+amplitude*complex(randn(stream,size(physical)),randn(stream,size(physical)));
post=post+amplitude*complex(randn(stream,size(post)),randn(stream,size(post)));
inputHashes=[sixgr.phy.waveform.WaveformHash.runtimeArray(physical) ...
    sixgr.phy.waveform.WaveformHash.runtimeArray(post)];
for enabled=[false true]
    this=cfg; this.phy.rx.cfoCorrectionEnabled=enabled;
    this.phy.impairments.cfoEstimationMethod='cyclic_prefix';
    preInput=physical; postInput=post;
    if enabled
        t=(0:size(physical,1)-1).'/p.SampleRateHz;
        preInput=preInput.*exp(1i*2*pi*390*t);
        postInput=postInput.*exp(-1i*2*pi*520*t);
    end
    before=rng;
    rx=sixgr.phy.refsig.receiveCSIRSWaveform(carrier,this,postInput,preInput,[0 guard],struct());
    assert(isequal(before,rng),'Receipt retention must not consume global RNG.');
    assert(rx.PhysicalMeasurementDemodulationReceiptAvailable);
    token=rx.PhysicalMeasurementDemodulationReceiptJSON;
    assert(rx.PhysicalMeasurementDemodulationReceiptSHA256==sixgr.util.sha256Hex(char(token)));
    r=jsondecode(token);
    assert(r.ContractVersion=="sixgr.csirs.physical_demodulation/v1" && ...
        r.InputSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(preInput) && ...
        r.InputSHA256~=sixgr.phy.waveform.WaveformHash.runtimeArray(postInput));
    assert(isequal(r.InputSize(:).',size(preInput)) && r.NumReceiveChannels==2 && ...
        isequal(r.ReceiveChannelIndices0(:).',[0 1]) && ...
        r.WaveformAmplitudeUnit==string(p.PowerContext.WaveformAmplitudeUnit));
    assert(~r.AbsoluteObservationIdentityBound && ~r.ReceiveBranchLayoutQualified && ...
        ~r.IndependentPowerReferenceAvailable && ~r.RSRPAccuracyQualified && ...
        r.AdditionalTimingAcquisitions==0 && r.AdditionalOFDMDemodulations==0);
    assert(r.Timing.AppliedTimingCorrectionSamples==delays(1) && ...
        rx.ReceiveTiming.AppliedTimingCorrectionSamples==delays(2));
    assert(r.Frequency.CFOCorrectionApplied==enabled && ...
        r.Frequency.PhaseOrigin=="original_preRF_capture_start_zero_based");
    if enabled
        assert(r.Frequency.CFOCorrectionApplied_Hz==rx.PhysicalMeasurementTrackingCorrection.CFOCorrectionApplied_Hz && ...
            abs(r.Frequency.CFOCorrectionApplied_Hz-390)<1 && ...
            abs(rx.ReceiverTrackingCorrection.CFOCorrectionApplied_Hz+520)<1);
    else
        assert(isempty(r.Frequency.CFOCorrectionApplied_Hz), ...
            'Original unavailable CFO is JSON null, not an invented applied zero.');
    end
    % Independent readback of the recorded operator, no new timing search.
    preAligned=localApplyRecorded(preInput,rx.PhysicalMeasurementReceiveTiming, ...
        rx.PhysicalMeasurementTrackingCorrection,p.SampleRateHz);
    postAligned=localApplyRecorded(postInput,rx.ReceiveTiming,rx.ReceiverTrackingCorrection,p.SampleRateHz);
    [preGrid,preOFDM]=sixgr.phy.waveform.ofdmDemodulate(carrier,preAligned);
    [postGrid,postOFDM]=sixgr.phy.waveform.ofdmDemodulate(carrier,postAligned);
    assert(r.AlignedSHA256==preOFDM.WaveformSHA256 && r.GridSHA256==preOFDM.GridSHA256);
    assert(isequal(rx.RxGrid,postGrid));
    opt=struct('PhysicalMeasurementGrid',preGrid,'PhysicalMeasurementOFDMInfo',preOFDM, ...
        'PhysicalMeasurementGridStatus',"available_exact_pre_front_end_grid", ...
        'PhysicalMeasurementReferencePlane',"receiver_antenna_connector_pre_composite_front_end", ...
        'PhysicalMeasurementSource',"actual_independent_csirs_pre_front_end_capture", ...
        'ReceivedExecutionEvidence',struct());
    baseline=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,this, ...
        struct('OFDMGrid',postGrid,'OFDMInfo',postOFDM),opt);
    assert(isequaln(baseline.CSIRSChannelEstimate,rx.CSIRSChannelEstimate) && ...
        isequaln(baseline.CSIRSNoiseVar,rx.CSIRSNoiseVar) && ...
        baseline.CSIMeasurementState.Digest==rx.CSIMeasurementState.Digest && ...
        isequaln(baseline.CSIRSObservation.MeasurementPhysicalResourcesJSON, ...
            rx.CSIRSObservation.MeasurementPhysicalResourcesJSON), ...
        'Receipt retention must leave practical estimation and measured power unchanged.');
    localCheckSupport(r,carrier,rx,preOFDM,size(preInput,1));
    [csi,~]=sixgr.phy.refsig.computeCSIRSFeedback(carrier,this,rx);
    row=sixgr.truth.buildIndependentCSIRSTrialRow(this,p,rx,csi,struct('UEIndex',1));
    assert(row.PhysicalMeasurementDemodulationReceiptJSON==token && ...
        row.PhysicalMeasurementDemodulationReceiptSHA256==rx.PhysicalMeasurementDemodulationReceiptSHA256);
    folder=tempname; mkdir(folder);
    path=fullfile(folder,'declared_component_csirs_trial.csv');
    sixgr.util.csvWriteTable(path,struct2table(row),'RoundTripNumericText',true);
    loaded=sixgr.util.csvReadTable(path,'TextType','string');
    assert(loaded.PhysicalMeasurementDemodulationReceiptJSON==token && ...
        loaded.PhysicalMeasurementDemodulationReceiptSHA256==rx.PhysicalMeasurementDemodulationReceiptSHA256);
    bad=rx; bad.PhysicalMeasurementDemodulationReceiptSHA256="changed";
    localReject(@()sixgr.truth.buildIndependentCSIRSTrialRow(this,p,bad,csi,struct()));
    bad=rx; changed=r; changed.Carrier.NCellID=changed.Carrier.NCellID+1;
    bad.PhysicalMeasurementDemodulationReceiptJSON=string(jsonencode(changed));
    bad.PhysicalMeasurementDemodulationReceiptSHA256=sixgr.util.sha256Hex(char(bad.PhysicalMeasurementDemodulationReceiptJSON));
    localReject(@()sixgr.truth.buildIndependentCSIRSTrialRow(this,p,bad,csi,struct()));
    bad=rx; changed=r; changed.IndependentPowerReferenceAvailable=true;
    bad.PhysicalMeasurementDemodulationReceiptJSON=string(jsonencode(changed));
    bad.PhysicalMeasurementDemodulationReceiptSHA256=sixgr.util.sha256Hex(char(bad.PhysicalMeasurementDemodulationReceiptJSON));
    localReject(@()sixgr.truth.buildIndependentCSIRSTrialRow(this,p,bad,csi,struct()));
end
assert(isequal(inputHashes,[sixgr.phy.waveform.WaveformHash.runtimeArray(physical) ...
    sixgr.phy.waveform.WaveformHash.runtimeArray(post)]));
ok=true;
disp('CSIRS_PHYSICAL_DEMODULATION_RECEIPT_PASS: native component/operator retention; no shared isolation or RSRP accuracy claim.');
end

function aligned=localApplyRecorded(input,timing,tracking,fs)
if tracking.CFOCorrectionApplied
    rotation=exp(-1i*2*pi*tracking.CFOCorrectionApplied_Hz*(0:size(input,1)-1).'/fs);
    input=input.*cast(rotation,'like',input);
end
aligned=input(timing.AppliedTimingCorrectionSamples+(1:timing.DemodulatedSampleCount),:);
end

function localCheckSupport(r,carrier,rx,ofdm,inputCount)
f=r.FFTSupport;
assert(f.Available && string(version('-release'))=="2026a", ...
    'This native FFT-window regression is scoped to the qualified R2026a operator.');
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot;
ind=double(rx.CSIRSIndices(:)); physical=unique(mod(ind-1,K*L));
support=unique([mod(physical,K) floor(physical/K)],'rows','sorted');
assert(f.ResourceSupportSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(support) && ...
    f.PhysicalRECount==size(support,1));
symbol=unique(support(:,2));
positions=mod(carrier.NSlot,carrier.SlotsPerSubframe)*L+(1:L);
lengths=double(ofdm.SymbolLengths(positions)); cp=double(ofdm.CyclicPrefixLengths(positions));
starts=[0 cumsum(lengths(1:end-1))];
first=r.Timing.AppliedTimingCorrectionSamples+starts(symbol+1)+fix(cp(symbol+1)*ofdm.CyclicPrefixFraction);
expected=[first(:) first(:)+ofdm.Nfft];
actualIntervals=double(f.FFTIntervals);
if isvector(actualIntervals)&&numel(actualIntervals)==2, actualIntervals=reshape(actualIntervals,1,2); end
assert(isequal(actualIntervals,expected) && all(expected(:,1)>=0) && all(expected(:,2)<=inputCount));
resources=r.Resources;
if iscell(resources), resources=vertcat(resources{:}); end
assert(numel(resources)==rx.CSIRSInfo.NumResources && ...
    sum([resources.LogicalPilotCount])==numel(rx.CSIRSIndices));
assert(~isfield(r,'Waveform') && ~isfield(r,'Grid') && ~isfield(resources,'Indices'), ...
    'The compact receipt must not duplicate captured IQ, grids, or full pilot arrays.');
end

function localReject(fn)
try, fn(); catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:CSIPhysicalDemodulationReceiptMismatch'), ...
        'Unexpected rejection: %s',cause.identifier);
    return;
end
error('test:MissingCSIReceiptRejection','Expected original receipt binding rejection.');
end
