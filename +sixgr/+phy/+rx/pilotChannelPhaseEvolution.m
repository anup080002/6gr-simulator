function out=pilotChannelPhaseEvolution(carrier,h,indices,symbols,ofdm)
% Common phase RATE of matched received channel estimates, not Doppler spread.
% Pair the same subcarrier/RX/port across pilot symbols before summing. A
% complex mean across unrelated spatial/frequency channels can cancel even
% a strong static channel. No known channel, mobility or CFO is consumed.
K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
R=size(h,3); P=size(h,4);
assert(isfloat(h) && size(h,1)==K && size(h,2)==L && ndims(h)<=4, ...
    'sixgr:phy:rx:InvalidPilotPhaseChannel', ...
    'Require K-by-L-by-RX-by-reference-port channel estimates.');
indices=double(indices(:)); symbols=symbols(:);
assert(~isempty(indices) && numel(indices)==numel(symbols) && ...
    all(isfinite(indices) & indices==fix(indices) & indices>=1 & indices<=K*L*P) && ...
    all(isfinite(symbols)),'sixgr:phy:rx:InvalidPilotPhaseReference', ...
    'Pilot references must address the same channel port domain.');
active=false(K,L,P); active(indices(abs(symbols)>0))=true;
used=repmat(reshape(active,K,L,1,P),1,1,R,1);
assert(all(isfinite(h(used))), 'sixgr:phy:rx:InvalidPilotPhaseChannel', ...
    'Every active pilot channel value must be finite; unused resources are not observations.');
pilotSymbols=find(any(active,[1 3]));
% nrOFDMInfo reports a whole subframe starting at slot zero. Select this
% received slot, and use the actual FFT window rather than whole-symbol
% centers (which include a different amount of CP). Lengths are in native
% FFT-clock samples even when the external waveform has been resampled.
assert(isstruct(ofdm) && all(isfield(ofdm,{'Nfft','SymbolLengths', ...
    'CyclicPrefixFraction','SlotsPerSubframe'})), ...
    'sixgr:phy:rx:MissingPilotPhaseOFDMClock','Retain the actual receiver OFDM metadata.');
nfft=double(ofdm.Nfft); fraction=double(ofdm.CyclicPrefixFraction);
validateattributes(nfft,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(fraction,{'numeric'},{'scalar','finite','>=',0,'<=',1});
first=mod(double(carrier.NSlot),double(ofdm.SlotsPerSubframe))*L;
assert(numel(ofdm.SymbolLengths)>=first+L, ...
    'sixgr:phy:rx:MissingPilotPhaseOFDMClock','No CP/sample schedule for the received slot.');
lengths=double(ofdm.SymbolLengths(first+(1:L))); cp=lengths-nfft;
assert(all(isfinite(cp) & cp>=0 & cp==fix(cp)), ...
    'sixgr:phy:rx:MissingPilotPhaseOFDMClock','Invalid native OFDM symbol clock.');
times=(cumsum(lengths)-lengths+floor(cp*fraction)+(nfft-1)/2)/ ...
    (nfft*double(carrier.SubcarrierSpacing)*1000);
out=struct('CommonPhaseRate_Hz',NaN,'PhaseFitResidualRMS_deg',NaN, ...
    'PairCount',0,'MatchedChannelValueCount',0,'UnaliasedHalfWidth_Hz',NaN, ...
    'Source',"matched_pilot_channel_cross_products_common_phase_not_doppler_spread", ...
    'SymbolTimeSource',"actual_receiver_FFT_window_centers_at_native_FFT_clock", ...
    'Status',"insufficient_repeated_pilot_coordinates");
dt=[]; phase=[]; weight=[];
for i=2:numel(pilotSymbols)
    a=pilotSymbols(i-1); b=pilotSymbols(i);
    mask=reshape(active(:,a,:)&active(:,b,:),K,1,P);
    mask=repmat(mask,1,R,1);
    first=reshape(h(:,a,:,:),K,R,P); second=reshape(h(:,b,:,:),K,R,P);
    count=nnz(mask); if count==0, continue; end
    cross=sum(conj(first(mask)).*second(mask));
    if abs(cross)==0, continue; end
    dt(end+1)=times(b)-times(a); %#ok<AGROW>
    phase(end+1)=angle(cross); weight(end+1)=abs(cross); %#ok<AGROW>
    out.MatchedChannelValueCount=out.MatchedChannelValueCount+count;
end
if isempty(dt), return; end
% Phase aliases outside this interval are not resolved by this estimator.
omega=sum(weight.*dt.*phase)/sum(weight.*dt.^2);
out.CommonPhaseRate_Hz=omega/(2*pi);
out.PairCount=numel(dt); out.UnaliasedHalfWidth_Hz=min(1./(2*dt));
if numel(dt)>1
    residual=angle(exp(1i*(phase-omega*dt)));
    out.PhaseFitResidualRMS_deg=sqrt(sum(weight.*residual.^2)/sum(weight))*180/pi;
end
out.Status="measured_common_phase_rate_with_explicit_alias_interval";
end
