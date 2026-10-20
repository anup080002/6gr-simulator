function [out,state]=pilotChannelPhaseEvolution(carrier,h,indices,symbols,ofdm,varargin)
% Common phase RATE of matched received channel estimates, not Doppler spread.
% Pair the same subcarrier/RX/port across pilot symbols before summing. A
% complex mean across unrelated spatial/frequency channels can cancel even
% a strong static channel. No known channel, mobility or CFO is consumed.
ip=inputParser;
ip.addParameter('ObservationStartTime_s',0,@(v)isnumeric(v)&&isscalar(v)&&isfinite(v)&&v>=0);
ip.addParameter('AvailableAtTime_s',NaN,@(v)isnumeric(v)&&isscalar(v));
ip.addParameter('ContextID',"",@(v)(ischar(v)||isstring(v))&&isscalar(string(v)));
ip.addParameter('PreviousObservation',struct(),@(v)isstruct(v)&&isscalar(v));
ip.parse(varargin{:}); opt=ip.Results;
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
    'Status',"insufficient_repeated_pilot_coordinates", ...
    'ObservationScope',"within_received_slot",'HistoryStatus',"no_previous_observation", ...
    'PreviousObservationTime_s',NaN,'CurrentObservationTime_s',NaN, ...
    'ObservationSeparation_s',NaN);

% Retain only measured pilot coordinates from the last observed symbol,
% never an interpolated full grid or the propagation-channel truth object.
state=struct();
if ~isempty(pilotSymbols)
    [keys,values]=localSnapshot(h,active,pilotSymbols(end),K,R,P);
    available=double(opt.AvailableAtTime_s);
    if isnan(available)
        available=opt.ObservationStartTime_s+sum(lengths)/(nfft*double(carrier.SubcarrierSpacing)*1000);
    end
    lastTime=opt.ObservationStartTime_s+times(pilotSymbols(end));
    assert(isfinite(available)&&available>=lastTime, ...
        'sixgr:phy:rx:InvalidPilotPhaseClock','Receiver availability must follow its observed pilot.');
    state=struct('Version',"received_pilot_phase_snapshot/v1", ...
        'ContextID',string(opt.ContextID),'Dimensions',[K R P], ...
        'LastTime_s',lastTime,'AvailableAtTime_s',available, ...
        'CoordinateKeys',keys,'ChannelValues',values);
    % The first single-symbol observation has an actual pilot clock,
    % but not yet a phase pair, rate, or unaliasing interval.
    out.CurrentObservationTime_s=lastTime;
end
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
previous=opt.PreviousObservation;
if isempty(dt) && ~isempty(fieldnames(previous)) && ~isempty(fieldnames(state))
    required={'Version','ContextID','Dimensions','LastTime_s','AvailableAtTime_s','CoordinateKeys','ChannelValues'};
    assert(all(isfield(previous,required))&&isscalar(string(previous.Version)) && ...
        string(previous.Version)==state.Version && isscalar(string(previous.ContextID)), ...
        'sixgr:phy:rx:InvalidPilotPhaseHistory','Require a typed receiver-owned pilot snapshot.');
    if strlength(state.ContextID)==0 || string(previous.ContextID)~=state.ContextID || ...
            ~isequal(previous.Dimensions,state.Dimensions)
        out.HistoryStatus="context_changed_no_cross_observation_pair";
    else
        firstTime=opt.ObservationStartTime_s+times(pilotSymbols(1));
        assert(isscalar(previous.LastTime_s)&&isfinite(previous.LastTime_s)&&previous.LastTime_s<firstTime && ...
            isscalar(previous.AvailableAtTime_s)&&isfinite(previous.AvailableAtTime_s)&&previous.AvailableAtTime_s>=previous.LastTime_s && ...
            previous.AvailableAtTime_s<=state.AvailableAtTime_s, ...
            'sixgr:phy:rx:NoncausalPilotPhaseHistory','Do not reuse duplicate or future pilot observations.');
        [keys,values]=localSnapshot(h,active,pilotSymbols(1),K,R,P);
        assert(iscolumn(previous.CoordinateKeys)&&iscolumn(previous.ChannelValues)&& ...
            all(isfinite(previous.CoordinateKeys)&previous.CoordinateKeys>=1 & ...
                previous.CoordinateKeys<=K*R*P & previous.CoordinateKeys==fix(previous.CoordinateKeys))&& ...
            numel(previous.CoordinateKeys)==numel(previous.ChannelValues)&& ...
            numel(unique(previous.CoordinateKeys))==numel(previous.CoordinateKeys)&& ...
            all(isfinite(previous.ChannelValues)), ...
            'sixgr:phy:rx:InvalidPilotPhaseHistory','History must retain unique actual pilot coordinates.');
        [~,a,b]=intersect(previous.CoordinateKeys,keys);
        cross=sum(conj(previous.ChannelValues(a)).*values(b));
        out.HistoryStatus="no_matching_pilot_coordinates_across_occasions";
        if ~isempty(a)&&abs(cross)>0
            dt=firstTime-previous.LastTime_s; phase=angle(cross); weight=abs(cross);
            out.MatchedChannelValueCount=numel(a);
            out.ObservationScope="between_received_occasions";
            out.HistoryStatus="matched_previous_received_pilot_snapshot";
            out.PreviousObservationTime_s=previous.LastTime_s;
            out.CurrentObservationTime_s=firstTime;
            out.ObservationSeparation_s=dt;
        end
    end
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

function [keys,values]=localSnapshot(h,active,symbol,K,R,P)
[k,p]=find(reshape(active(:,symbol,:),K,P));
n=numel(k); k=repmat(k(:),R,1); p=repmat(p(:),R,1);
% MATLAB repeats a scalar into a row, even when its input is transposed.
% Keep all subscript vectors column-shaped for the single-RX case too.
r=reshape(repelem((1:R).',n),[],1);
keys=sub2ind([K R P],k,r,p);
at=sub2ind(size(h,1:4),k,repmat(symbol,numel(k),1),r,p);
values=reshape(h(at),[],1);
end
