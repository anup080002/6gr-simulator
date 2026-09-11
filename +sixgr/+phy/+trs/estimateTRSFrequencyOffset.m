function freq = estimateTRSFrequencyOffset(det, cfg, tx, evaluation)
%ESTIMATETRSFREQUENCYOFFSET Received common phase frequency, not oscillator CFO.
% Correlate matching subcarriers on the two receiver-known TRS symbols in
% each slot, on every RX branch. No injected Doppler/CFO enters estimation.
% The fourth argument is used ONLY for explicitly labeled error scoring.
if nargin<4, evaluation=struct(); end
rows=repmat(localRow(),numel(det.SlotDetections),1);
correlations=complex(zeros(numel(rows),1));
for k=1:numel(rows)
    d=det.SlotDetections(k);
    row=localRow();
    row.RunId=string(cfg.RunId); row.ConfigHash=string(cfg.ConfigHash);
    row.FromSlot=double(d.Slot); row.ToSlot=double(d.Slot);
    row.FrequencyTrackingAttempted=true;
    row.FrequencyTolerance_Hz=double(cfg.FrequencyToleranceHz);
    if ~d.Detected
        row.Status="frequency_unavailable_no_detected_trs";
        rows(k)=row; continue;
    end
    try
        grid=d.RxGrid;
        K=size(grid,1); R=size(grid,3);
        ind=double(d.ReferenceIndices(:));
        ref=d.ReferenceSymbols(:);
        assert(numel(ind)==numel(ref) && numel(unique(ind))==numel(ind), ...
            'sixgr:phy:trs:FrequencyReferenceIdentity','Reference RE identities must be unique and complete.');
        symbols=floor((ind-1)/K);
        pair=unique(symbols);
        assert(numel(pair)==2,'sixgr:phy:trs:FrequencyReferencePair', ...
            'Tracking requires two received reference-symbol times per slot.');
        first=find(symbols==pair(1)); last=find(symbols==pair(2));
        [scA,orderA]=sort(mod(ind(first)-1,K)+1);
        [scB,orderB]=sort(mod(ind(last)-1,K)+1);
        assert(isequal(scA,scB) && ~isempty(scA), ...
            'sixgr:phy:trs:FrequencySubcarrierIdentity','Reference symbols must pair the same subcarriers.');
        a=reshape(grid(:,pair(1)+1,:),K,R);
        b=reshape(grid(:,pair(2)+1,:),K,R);
        ha=a(scA,:)./ref(first(orderA)); hb=b(scB,:)./ref(last(orderB));
        assert(all(isfinite(ha(:))) && all(isfinite(hb(:))), ...
            'sixgr:phy:trs:InvalidFrequencySamples','Every paired reference sample must be finite.');
        c=sum(hb.*conj(ha),'all');
        energy=sqrt(sum(abs(ha).^2,'all')*sum(abs(hb).^2,'all'));
        assert(isfinite(c) && abs(c)>0 && isfinite(energy) && energy>0, ...
            'sixgr:phy:trs:NoFrequencyCorrelation','No nonzero received reference correlation.');
        dt=localSymbolDelta(tx,d,pair);
        row.FromSymbol0Based=pair(1); row.ToSymbol0Based=pair(2);
        row.DeltaT_s=dt; row.DeltaPhi_rad=angle(c);
        row.PhaseSampleCount=numel(ha); row.NumReceiveAntennas=R;
        row.CorrelationCoherence=abs(c)/energy;
        row.UnambiguousHalfRange_Hz=1/(2*dt);
        row.EstimatedCommonFrequency_Hz=angle(c)/(2*pi*dt);
        row.EstimatedCFO_Hz=row.EstimatedCommonFrequency_Hz;
        row.TRSCFOEstimateAvailable=true;
        row.Status="received_common_frequency_available";
        correlations(k)=c;
    catch ME
        row.Status="frequency_unavailable:"+string(ME.identifier);
    end
    rows(k)=row;
end
valid=[rows.TRSCFOEstimateAvailable];
common=NaN; available=false; halfRange=NaN;
if any(valid)
    times=[rows(valid).DeltaT_s];
    halfRange=min([rows(valid).UnambiguousHalfRange_Hz]);
    % Equal TRS symbol spacing permits circular pooling without averaging
    % opposite sides of the phase wrap into a false near-zero frequency.
    assert(max(times)-min(times)<1e-12,'sixgr:phy:trs:IncompatibleFrequencyPairTimes', ...
        'One frequency aggregate requires equal observed reference-symbol spacing.');
    pooled=sum(correlations(valid));
    if isfinite(pooled) && abs(pooled)>0
        common=angle(pooled)/(2*pi*times(1)); available=true;
    end
end
% Scoring has no influence on availability, correlation or correction values.
reference=double(sixgr.util.structGet(evaluation,'FrequencyReferenceForScoring_Hz',NaN));
source=string(sixgr.util.structGet(evaluation,'FrequencyReferenceForScoringSource',"unavailable"));
validateattributes(reference,{'numeric'},{'real','scalar'});
for k=1:numel(rows)
    rows(k).FrequencyReferenceForScoring_Hz=reference;
    rows(k).FrequencyReferenceForScoringSource=source;
    rows(k).FrequencyError_Hz=rows(k).EstimatedCommonFrequency_Hz-reference;
end
freq=struct('Table',struct2table(rows,'AsArray',true), ...
    'Attempted',~isempty(rows),'EstimateAvailable',available, ...
    'EstimatedCFO_Hz',common,'EstimatedCommonFrequency_Hz',common, ...
    'EstimatedOscillatorCFO_Hz',NaN,'PhysicalDoppler_Hz',NaN, ...
    'UnambiguousHalfRange_Hz',halfRange, ...
    'FrequencyEstimateDomain',"received_TRS_common_phase_frequency", ...
    'FrequencyReferenceForScoring_Hz',reference, ...
    'FrequencyReferenceForScoringSource',source,'FrequencyError_Hz',common-reference);
end

function dt=localSymbolDelta(tx,d,pair)
L=double(tx.GridSlots(1).Carrier.SymbolsPerSlot);
first=(double(d.Slot)-double(tx.FirstSlot0Based))*L;
lengths=double(tx.OFDM.SymbolLengths(:));
cp=double(tx.OFDM.CyclicPrefixLengths(:));
carrier=tx.GridSlots(1).Carrier;
scale=double(tx.SampleRateHz)/(double(tx.OFDM.Nfft)*double(carrier.SubcarrierSpacing)*1000);
% FFT-window center differences: the useful FFT duration cancels. Retain
% actual CP-pattern differences and the demodulator's configured CP fraction.
fraction=double(d.CyclicPrefixFraction);
a=first+pair(1)+1; b=first+pair(2)+1;
samples=(sum(lengths(a:b-1))+fraction*(cp(b)-cp(a)))*scale;
dt=samples/double(tx.SampleRateHz);
assert(isfinite(dt) && dt>0,'sixgr:phy:trs:InvalidFrequencySampleClock', ...
    'Frequency estimation requires positive actual FFT-window time separation.');
end

function row=localRow()
row=struct('RunId',"",'ConfigHash',"",'FromSlot',NaN,'ToSlot',NaN, ...
    'FromSymbol0Based',NaN,'ToSymbol0Based',NaN, ...
    'FrequencyTrackingAttempted',false,'TRSCFOEstimateAvailable',false, ...
    'EstimatedCommonFrequency_Hz',NaN,'EstimatedCFO_Hz',NaN, ...
    'EstimatedOscillatorCFO_Hz',NaN,'PhysicalDoppler_Hz',NaN, ...
    'FrequencyReferenceForScoring_Hz',NaN,'FrequencyReferenceForScoringSource',"unavailable", ...
    'FrequencyError_Hz',NaN,'FrequencyTolerance_Hz',NaN, ...
    'PhaseSampleCount',0,'NumReceiveAntennas',NaN,'CorrelationCoherence',NaN, ...
    'UnambiguousHalfRange_Hz',NaN,'DeltaPhi_rad',NaN,'DeltaT_s',NaN, ...
    'CrossCorrelationOrder',"late_times_conj_early_same_subcarrier_and_receive_branch", ...
    'FrequencyEstimateDomain',"received_TRS_common_phase_frequency", ...
    'Status',"",'TruthStatus',"real_lls_evidence");
end
