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
previousCSI=[]; rankGuardCount=0;
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
    assert(r.ContractVersion=="sixgr.csirs.physical_demodulation/v2" && ...
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
    expectedMapping=sixgr.util.structGet(csi,'CQIEffectiveSINR_dB',NaN);
    assert(isequaln(row.CQIEffectiveSINR_dB,expectedMapping));
    poisoned=csi; poisoned.WidebandSINR_dB=999;
    poisoned=rmfield(poisoned,intersect(fieldnames(poisoned), ...
        {'CQIEffectiveSINR_dB','CQIEffectiveSINRSource'}));
    absent=sixgr.truth.buildIndependentCSIRSTrialRow(this,p,rx,poisoned,struct('UEIndex',1));
    assert(isnan(absent.CQIEffectiveSINR_dB) && strlength(absent.CQIEffectiveSINRSource)==0);
    assert(isfield(csi,'RankSelectionEvidence') && row.RankSelectionEvidenceAvailable && ...
        row.RankSelectionEvidenceSHA256==sixgr.util.sha256Hex(char(row.RankSelectionEvidenceJSON)));
    rankGuardCount=rankGuardCount+localRankEvidenceGuards(p,rx,csi);
    legacy=rmfield(csi,'RankSelectionEvidence');
    legacyRow=sixgr.truth.buildIndependentCSIRSTrialRow(this,p,rx,legacy,struct('UEIndex',1));
    assert(~legacyRow.RankSelectionEvidenceAvailable && legacyRow.RankSelectionEvidenceJSON=="" && ...
        legacyRow.RankSelectionEvidenceSHA256=="" && legacyRow.RankSelectionEvidenceStatus=="not_recorded");
    wrong=csi; wrong.RankSelectionEvidence=[];
    localRejectRank(@()sixgr.truth.buildIndependentCSIRSTrialRow(this,p,rx,wrong,struct('UEIndex',1)));
    rankGuardCount=rankGuardCount+1;
    if ~isempty(previousCSI)
        % The first real reception's COMPLETE result must not qualify this
        % second original reception, even though its own IDs agree internally.
        assert(previousCSI.CSIMeasurementDigest~=csi.CSIMeasurementDigest);
        localRejectRank(@()sixgr.truth.buildIndependentCSIRSTrialRow( ...
            this,p,rx,previousCSI,struct('UEIndex',1)));
        rankGuardCount=rankGuardCount+1;
    end
    previousCSI=csi;
    assert(row.PhysicalMeasurementDemodulationReceiptJSON==token && ...
        row.PhysicalMeasurementDemodulationReceiptSHA256==rx.PhysicalMeasurementDemodulationReceiptSHA256);
    folder=tempname; mkdir(folder);
    path=fullfile(folder,'declared_component_csirs_trial.csv');
    sixgr.util.csvWriteTable(path,struct2table(row),'RoundTripNumericText',true);
    loaded=sixgr.util.csvReadTable(path,'TextType','string');
    assert(loaded.PhysicalMeasurementDemodulationReceiptJSON==token && ...
        loaded.PhysicalMeasurementDemodulationReceiptSHA256==rx.PhysicalMeasurementDemodulationReceiptSHA256);
    assert(loaded.RankSelectionEvidenceJSON==row.RankSelectionEvidenceJSON && ...
        loaded.RankSelectionEvidenceSHA256==row.RankSelectionEvidenceSHA256);
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
fprintf('CSI_MAXSE_ORIGINAL_ROW_GUARDS_PASS negatives=%d no_additional_receiver_or_selection=1\n',rankGuardCount);
disp('CSIRS_PHYSICAL_DEMODULATION_RECEIPT_PASS: native component/operator retention; no shared isolation or RSRP accuracy claim.');
end

function count=localRankEvidenceGuards(p,rx,csi)
% Copies of the already returned native operands only; no new waveform,
% receiver, rank search or invented positive candidate population.
original=csi.RankSelectionEvidence; count=0; prior=rng;
sixgr.truth.validateCSIRSRankSelectionEvidence(original,p,rx,csi);
for field=string(fieldnames(original)).'
    bad=rmfield(original,field);
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
for field=["DecodedBLERAvailable","IndependentSelectionQualityVerified","StandardizedAccuracyQualified"]
    for value={true,0,NaN,[false false]}
        bad=original; bad.(field)=value{1};
        localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
    end
end
for field=["MeasurementID","MeasurementDigest","ReportConfigID"]
    bad=original; bad.(field)="other_original";
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
bad=original; bad.MeasurementSlot=bad.MeasurementSlot+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.ReportConfigurationEpoch=bad.ReportConfigurationEpoch+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
% Coherent aliases cannot replace the ORIGINAL immutable state/config.
other=csi; other.CSIMeasurementID="coherent_other"; other.RankSelectionEvidence.MeasurementID=other.CSIMeasurementID;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(other.RankSelectionEvidence,p,rx,other)); count=count+1;
other=csi; other.CSIReportConfigID="coherent_other_config"; other.RankSelectionEvidence.ReportConfigID=other.CSIReportConfigID;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(other.RankSelectionEvidence,p,rx,other)); count=count+1;
other=rx; other.CSIRSChannelEstimate(1)=other.CSIRSChannelEstimate(1)+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(original,p,other,csi)); count=count+1;
other=rx; other.CSIRSNoiseVar=other.CSIRSNoiseVar+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(original,p,other,csi)); count=count+1;
state=rx.CSIMeasurementState;
for includesNoise=[false true]
    other=rx;
    other.CSIMeasurementState=sixgr.phy.mimo.CSIMeasurementState( ...
        MeasurementID=state.MeasurementID,UEID=state.UEID,ResourceType=state.ResourceType, ...
        ResourceID=state.ResourceID,ResourceOrdinal=state.ResourceOrdinal,Slot=state.Slot, ...
        MaxAgeSlots=state.MaxAgeSlots,ChannelEstimate=state.ChannelEstimate, ...
        NoiseVariance=state.NoiseVariance,InterferenceCovariance=eye(size(state.ChannelEstimate,1))*123, ...
        InterferenceCovarianceIncludesNoise=includesNoise,Provenance=state.Provenance);
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(original,p,other,csi)); count=count+1;
end
other=rmfield(rx,'CSIMeasurementState');
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(original,p,other,csi)); count=count+1;
other=p; other.ReceiverConfig.phy.csi.reportConfiguration.Epoch=other.ReceiverConfig.phy.csi.reportConfiguration.Epoch+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(original,other,rx,csi)); count=count+1;
for field=["ChannelSHA256","DisturbanceSHA256"]
    bad=original; bad.(field)=repmat("f",1,64); bad.(field)=join(bad.(field),"");
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
for field=["NSizeBWP","NStartBWP","CodebookMode"]
    bad=original; bad.Configuration.(field)=bad.Configuration.(field)+1;
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
bad=original; bad.Configuration.CQITable="table4";
if any(strcmpi(original.Configuration.CQITable,{'table4','table4-r17'})), bad.Configuration.CQITable="table1"; end
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates={};
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.RankDomain=[bad.RankDomain bad.RankDomain(end)];
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.RankSearchCallCount=bad.RankSearchCallCount+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.AdditionalRankSearches=1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.ObjectiveByRank(bad.SelectedRank)=bad.SelectedObjective+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.SelectedObjective=bad.SelectedObjective+1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
for field=string(fieldnames(original.Candidates{1})).'
    bad=original; bad.Candidates{1}=rmfield(bad.Candidates{1},field);
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
for field=["Rank","CodewordLayerCounts","Objective"]
    bad=original; bad.Candidates{1}.(field)=bad.Candidates{1}.(field)+1;
    bad.Candidates{1}.(field)(isnan(bad.Candidates{1}.(field)))=0;
    localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
end
bad=original; bad.Candidates{1}.WidebandCQI=16;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates{1}.ModelEstimatedTransportBLER=-1;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates{1}.CQITableSpectralEfficiency=42;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates{1}.RankSearchPMI.i1=Inf;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates{1}.RankSearchPrecoderSHA256="";
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.Candidates{1}.Status="PASS";
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
bad=original; bad.CopiedChannel=rx.CSIRSChannelEstimate;
localRejectRank(@()sixgr.truth.validateCSIRSRankSelectionEvidence(bad,p,rx,csi)); count=count+1;
assert(isequal(prior,rng) && isequaln(original,csi.RankSelectionEvidence), ...
    'Pure evidence validation cannot mutate actual operands or RNG.');
end

function localRejectRank(fn)
try, fn(); catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:CSIRankSelectionEvidenceMismatch'), ...
        'Unexpected rank-evidence rejection: %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingCSIRankEvidenceRejection','Expected original decision binding rejection.');
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
assert(f.Available && f.NativeFFTCapability.Available && ...
    string(f.RuntimeMATLABRelease)==string(version('-release')));
sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(f,carrier,ofdm.Nfft,ofdm.SampleRate, ...
    ofdm.CyclicPrefixFraction,double(carrier.SymbolsPerSlot),0,false);
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot;
ind=double(rx.CSIRSIndices(:)); physical=unique(mod(ind-1,K*L));
support=unique([mod(physical,K) floor(physical/K)],'rows','sorted');
prepared=struct('Carrier',carrier,'SampleRateHz',ofdm.SampleRate, ...
    'Tx',struct('OFDMInfo',ofdm),'ReceiveStartSample',0,'ReceiveEndSampleExclusive',inputCount);
sixgr.truth.validateCSIRSOriginalOperator(r,rx,prepared,support);
% Legacy-shaped compatibility fixture only. The original actual v2 receipt
% and its exported token remain untouched; no historical evidence is relabeled.
legacy=r; legacy.ContractVersion="sixgr.csirs.physical_demodulation/v1";
legacy.FFTSupport=rmfield(legacy.FFTSupport,'NativeFFTCapability');
if string(version('-release'))=="2026a"
    sixgr.truth.validateCSIRSOriginalOperator(legacy,rx,prepared,support);
    bad=legacy; bad.FFTSupport.FFTIntervals(1,1)=bad.FFTSupport.FFTIntervals(1,1)+1;
    localRejectOperator(@()sixgr.truth.validateCSIRSOriginalOperator(bad,rx,prepared,support), ...
        'sixgr:truth:CSIRSLinearModelOperator');
else
    localRejectOperator(@()sixgr.truth.validateCSIRSOriginalOperator(legacy,rx,prepared,support), ...
        'sixgr:waveform:RecordedFFTAuthority');
end
bad=r; bad.FFTSupport=rmfield(bad.FFTSupport,'NativeFFTCapability');
localRejectOperator(@()sixgr.truth.validateCSIRSOriginalOperator(bad,rx,prepared,support), ...
    'sixgr:waveform:RecordedFFTAuthority');
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

function localRejectOperator(fn,id)
try, fn(); catch failure
    assert(strcmp(failure.identifier,id),'test:FFTAuthorityGuard','Expected %s, got %s',id,failure.identifier); return;
end
error('test:FFTAuthorityMissingGuard','Expected %s.',id);
end
