classdef NetworkSpatialGrantProvider < sixgr.system.abstraction.SpatialGrantProvider
    % Frequency-selective NR fading and scheduled-resource covariance.
    % TDD reciprocal propagation, ideal RF. No BLER table or CQI is invented.
    % Power plane: watts per subcarrier per receive connector. Large-scale
    % attenuation is applied once; legacy scalar SINR/beam gains are not used.
    properties (SetAccess=private)
        LastContext struct = struct()
        LastObservation struct = struct()
    end
    properties (Access=private)
        Cfg struct
        Policy struct
        Carrier
        OFDM struct
        Template
        ChannelMeta struct
        ProfileID string
        LastKey string = ""
        LastResponse = []
        CSIBases = []
    end
    methods
        function obj=NetworkSpatialGrantProvider(cfg)
            obj.Cfg=cfg;
            p=cfg.system.linkAbstraction.networkSpatial;
            assert(all(isfield(p,{'bsPorts','uePorts','noiseDensity_dBmHz','powerPolicy', ...
                'rfProfileID','resultClassification','sinrResourcePopulation','interferencePopulation'})), ...
                'sixgr:abstraction:NetworkPolicy','Install the complete networkSpatial YAML policy.');
            validateattributes([p.bsPorts p.uePorts],{'numeric'},{'integer','positive','finite','numel',2});
            validateattributes(p.noiseDensity_dBmHz,{'numeric'},{'scalar','real','finite'});
            assert(string(p.powerPolicy)=="equal_psd_per_active_transmitter_split_overlapping_dl_grants" && ...
                string(p.resultClassification)=="modeled_frequency_selective_network_not_waveform" && ...
                string(p.sinrResourcePopulation)=="allocated_prb_symbol_footprint_including_pilots" && ...
                string(p.interferencePopulation)=="scheduled_shared_data_grants_only" && ...
                string(p.rfProfileID)=="ideal_rf_no_impairments", ...
                'sixgr:abstraction:NetworkPolicy','This provider implements the labelled ideal-RF, equal-PSD baseline.');
            assert(strcmpi(sixgr.phy.frame.resolveDuplexMode(cfg),'TDD'), ...
                'sixgr:abstraction:NetworkDuplex','Reciprocal network provider requires TDD.');
            obj.Policy=p;
            basis=string(sixgr.util.structGet(p,'dlAntennaBasis','direct_ports'));
            assert(any(basis==["direct_ports","configured_csirs_elements"]), ...
                'sixgr:abstraction:DLCSIPortBasis','Unknown networkSpatial.dlAntennaBasis.');
            if basis=="configured_csirs_elements"
                B=sixgr.util.structGet(cfg,'phy.csirs.precoderMatrices',[]);
                np=cfg.system.linkAbstraction.dlFeedback.panel.Ports;
                nc=cfg.phy.csi.reportConfiguration.NumCSIResources;
                assert(isnumeric(B) && size(B,1)==p.bsPorts && size(B,2)==np && ...
                    size(B,3)==nc && all(isfinite(B),'all'), ...
                    'sixgr:abstraction:DLCSIPortBasis','Require a finite physical-TXRU by CSI-port matrix for every configured CRI.');
                for k=1:nc
                    assert(norm(B(:,:,k)'*B(:,:,k)-eye(np),'fro')<1e-10, ...
                        'sixgr:abstraction:DLCSIPortBasis','CSI beam bases must preserve total port power.');
                end
                obj.CSIBases=B;
            end
            requiredRF=string(sixgr.util.structGet(cfg,'system.linkAbstraction.requiredRFProfileID',''));
            assert((strlength(requiredRF)==0 || requiredRF==string(p.rfProfileID)) && ...
                ~anyEnabled(sixgr.util.structGet(cfg,'rf',struct())) && ...
                ~anyEnabled(sixgr.util.structGet(cfg,'phy.impairments',struct())), ...
                'sixgr:abstraction:NetworkRFUnsupported','Enabled RF impairments require a calibrated RF-aware spatial provider; they cannot silently become ideal.');
            obj.Carrier=nrCarrierConfig;
            obj.Carrier.NSizeGrid=cfg.phy.carrier.NSizeGrid;
            obj.Carrier.SubcarrierSpacing=sixgr.util.structGet(cfg,'phy.carrier.SubcarrierSpacing', ...
                sixgr.util.structGet(cfg,'phy.numerology.scs_kHz',NaN));
            assert(double(sixgr.util.structGet(cfg,'phy.carrier.NStartGrid',0))==0 && ...
                strcmpi(sixgr.util.structGet(cfg,'phy.numerology.cyclicPrefix','normal'),'normal'), ...
                'sixgr:abstraction:NetworkGrid','This baseline uses a zero-start carrier grid and normal CP.');
            obj.Carrier.NStartGrid=0;
            obj.OFDM=nrOFDMInfo(obj.Carrier);
            channel=sixgr.channel.ChannelFactory.create(cfg,'LinkDirection','DL', ...
                'SampleRate',obj.OFDM.SampleRate,'NumTxAnt',p.bsPorts,'NumRxAnt',p.uePorts);
            assert(isa(channel.Object,'nrTDLChannel') || isa(channel.Object,'nrCDLChannel'), ...
                'sixgr:abstraction:NetworkChannel','Configure a concrete TDL/CDL profile; no flat-channel substitute.');
            obj.Template=channel.Object; obj.ChannelMeta=channel.Meta;
            assert(isprop(obj.Template,'ChannelResponseOutput'), ...
                'sixgr:abstraction:NetworkToolbox','Frequency-domain response requires a supporting 5G Toolbox release.');
            assert(~obj.Template.NormalizeChannelOutputs, ...
                'sixgr:abstraction:NetworkPower','Disable receive-count normalization for per-connector power.');
            obj.Template.ChannelFiltering=false;
            obj.Template.ChannelResponseOutput='ofdm-response';
            sampling=string(sixgr.util.structGet(p,'channelResponseSampling','signal_rate'));
            assert(any(sampling==["signal_rate","static_exact"]), ...
                'sixgr:abstraction:NetworkSampling','Select signal_rate or static_exact explicitly.');
            assert(sampling~="static_exact" || obj.Template.MaximumDopplerShift==0, ...
                'sixgr:abstraction:NetworkSamplingMobility', ...
                'static_exact is validated only at zero Doppler. Moving channels require signal_rate.');
            if isa(obj.Template,'nrTDLChannel')
                obj.Template.PathGainSampleRate='signal';
                if sampling=="static_exact", obj.Template.PathGainSampleRate='auto'; end
            else
                obj.Template.SampleDensity=Inf;
                if sampling=="static_exact", obj.Template.SampleDensity=64; end
            end
            obj.ChannelMeta.SLSChannelResponseSampling=sampling;
            obj.Template.NumTimeSamples=sum(obj.OFDM.SymbolLengths(1:obj.Carrier.SymbolsPerSlot));
            identity=struct('DelayProfile',obj.Template.DelayProfile,'DelaySpread',obj.Template.DelaySpread, ...
                'MaximumDopplerShift',obj.Template.MaximumDopplerShift,'SampleRate',obj.OFDM.SampleRate, ...
                'NormalizePathGains',obj.Template.NormalizePathGains,'NormalizeChannelOutputs',false, ...
                'BSPorts',p.bsPorts,'UEPorts',p.uePorts,'ResourcePopulation',p.sinrResourcePopulation, ...
                'PowerPolicy',p.powerPolicy,'InterferencePopulation',p.interferencePopulation);
            identity.DLAntennaBasis=basis;
            identity.ChannelResponseSampling=sampling;
            identity.CSIBasesSHA256=sixgr.phy.mimo.MatrixContract.digest(obj.CSIBases);
            if isa(obj.Template,'nrCDLChannel')
                identity.TransmitAntennaArray=obj.Template.TransmitAntennaArray;
                identity.ReceiveAntennaArray=obj.Template.ReceiveAntennaArray;
            else
                identity.MIMOCorrelation=obj.Template.MIMOCorrelation;
                identity.Polarization=obj.Template.Polarization;
                for field=["TransmitCorrelationMatrix","ReceiveCorrelationMatrix","SpatialCorrelationMatrix"]
                    if isprop(obj.Template,field), identity.(field)=obj.Template.(field); end
                end
            end
            obj.ProfileID=string(obj.Template.DelayProfile)+"_"+sixgr.util.sha256Hex(uint8(jsonencode(sixgr.util.jsonSafeValue(identity))));
        end
        function o=evaluate(obj,ctx,state)
            assert(ctx.TTI==state.TTI && ctx.TTI>=1, ...
                'sixgr:abstraction:NetworkClock','Grant and active network population must share a slot.');
            direction=string(ctx.Direction); assert(any(direction==["DL","UL"]));
            % Cross-link BS-to-BS/UE-to-UE interference is not approximated
            % by a UE-to-BS path. Reject asynchronous/mixed-direction reuse.
            other="UL"; if direction=="UL", other="DL"; end
            assert(~hasOverlap(state.("Grants"+other),ctx.Grant), ...
                'sixgr:abstraction:CrossLinkUnsupported','Overlapping opposite-direction transmissions require explicit cross-link channels.');
            grants=state.("Grants"+direction); cells=state.("GrantCells"+direction);
            assert(numel(grants)==numel(cells),'sixgr:abstraction:NetworkPopulation','Every active grant needs its cell owner.');
            match=find(arrayfun(@(g) g.RNTI==ctx.Grant.RNTI && isequal(g.PRBSet,ctx.Grant.PRBSet) && ...
                isequal(g.SymbolAllocation,ctx.Grant.SymbolAllocation),grants) & reshape(cells,1,[])==ctx.ServingCellID);
            assert(isscalar(match),'sixgr:abstraction:NetworkPopulation','Desired grant must occur exactly once in the active population.');
            u=double(ctx.Grant.RNTI); c=double(ctx.ServingCellID); slot=ctx.TTI-1;
            coords=coordinates(ctx.Grant,obj.Carrier.NSizeGrid); n=size(coords,1);
            H=obj.channel(direction,u,c,slot,state.LargeScaleState,coords);
            F=precoder(ctx.Grant,size(H,2));
            power=obj.power(direction,u,c,ctx.Grant,coords,grants,cells,state.LargeScaleState);
            entity='ue'; if direction=="UL", entity='bs'; end
            nf=obj.Cfg.scenario.(entity).noiseFigure_dB;
            noise=10^((obj.Policy.noiseDensity_dBmHz+10*log10(1000*obj.Carrier.SubcarrierSpacing)+nf-30)/10);
            covariance=repmat(noise*eye(size(H,1)),1,1,n);
            interferers=zeros(n,1);
            for j=1:numel(grants)
                if j==match, continue; end
                g=grants(j); mask=overlap(coords,g);
                if ~any(mask), continue; end
                if direction=="DL"
                    cross=obj.channel(direction,u,cells(j),slot,state.LargeScaleState,coords(mask,:));
                else
                    assert(g.RNTI~=u,'sixgr:abstraction:DuplicateULTransmitter','One UE cannot independently power two overlapping UL grants.');
                    cross=obj.channel(direction,g.RNTI,c,slot,state.LargeScaleState,coords(mask,:));
                end
                W=precoder(g,size(cross,2));
                q=obj.power(direction,g.RNTI,cells(j),g,coords(mask,:),grants,cells,state.LargeScaleState);
                ix=find(mask);
                for k=1:numel(ix)
                    G=cross(:,:,k)*W;
                    covariance(:,:,ix(k))=covariance(:,:,ix(k))+q(k)*(G*G');
                end
                interferers(mask)=interferers(mask)+1;
            end
            o=struct('Channel',H,'Precoder',F,'TotalTransmitPower',power, ...
                'ExternalCovariance',covariance,'RFProfileID',string(obj.Policy.rfProfileID), ...
                'ReceiverProfileID',"network_"+string(obj.Cfg.system.linkAbstraction.receiverType), ...
                'ChannelProfileID',obj.ProfileID, ...
                'ModelObservationID',string(obj.Cfg.run.executionID)+"_"+direction+"_"+u+"_"+c+"_"+slot, ...
                'SourceClassification',"modeled_spatial_channel_not_waveform_measurement", ...
                'Coordinates0Based',coords,'ActiveInterferersPerRE',interferers, ...
                'NoisePowerPerRE_W',noise,'PowerPlane',"watts_per_subcarrier_per_receive_connector", ...
                'ChannelMetadata',obj.ChannelMeta,'ArrayQualified',false,'RFQualified',false, ...
                'ResourcePopulation',string(obj.Policy.sinrResourcePopulation), ...
                'InterferencePopulation',string(obj.Policy.interferencePopulation), ...
                'CommonControlInterferenceQualified',false);
            obj.LastContext=ctx; obj.LastObservation=o;
        end
        function observations=observeCSI(obj,state)
            observations=struct([]);
            p=obj.Cfg.system.linkAbstraction.dlFeedback;
            assert(string(p.disturbanceAssumption)=="thermal_noise_only" && ...
                (~isempty(obj.CSIBases) || p.panel.Ports==obj.Policy.bsPorts), ...
                'sixgr:abstraction:DLCSIPortBasis', ...
                'This port-domain baseline requires matching CSI/PDSCH/channel ports and explicit thermal-only CSI.');
            assert(~isempty(obj.CSIBases) || obj.Cfg.phy.csi.reportConfiguration.NumCSIResources==1, ...
                'sixgr:abstraction:DLCSIBeamBasis', ...
                'Multiple beam resources require their distinct configured port-to-array mappings; do not duplicate one channel basis.');
            rows=state.CommonChannelAllocations;
            if isempty(rows), return; end
            rows=rows(string(rows.channel)=="CSI_RS",:);
            slot=state.AbsoluteSlot0;
            due=false(height(rows),1);
            for k=1:height(rows)
                due(k)=ismember(slot,str2double(split(string(rows.occurrence_slots(k)),"|")));
            end
            rows=rows(due,:);
            assert(ismember('csi_resource_index',rows.Properties.VariableNames), ...
                'sixgr:abstraction:DLCSIResourceIdentity','CSI calendar must retain explicit resource indices, not hash ordering.');
            ids=unique(double(rows.csi_resource_index),'stable');
            carrier=obj.Carrier;
            noise=10^((obj.Policy.noiseDensity_dBmHz+10*log10(1000*carrier.SubcarrierSpacing)+ ...
                obj.Cfg.scenario.ue.noiseFigure_dB-30)/10);
            for resource=1:numel(ids)
                cri=ids(resource);
                assert(isfinite(cri) && cri==fix(cri) && cri>=0 && ...
                    cri<obj.Cfg.phy.csi.reportConfiguration.NumCSIResources, ...
                    'sixgr:abstraction:DLCSIResourceIdentity','Invalid zero-based CSI resource index.');
                rs=rows(rows.csi_resource_index==cri,:);
                if isempty(rs), continue; end
                coords=zeros(0,2);
                for k=1:height(rs)
                    sc=double(rs.subcarrier_start(k))+(0:double(rs.subcarrier_count(k))-1);
                    coords=[coords;sc(:) repmat(double(rs.symbol_index(k)),numel(sc),1)]; %#ok<AGROW>
                end
                coords=unique(coords,'rows');
                part=sixgr.util.resolveTDDSlotPartition(obj.Cfg,slot); a=part.DLSymbolAllocation;
                assert(all(coords(:,2)>=a(1) & coords(:,2)<sum(a)), ...
                    'sixgr:abstraction:DLCSITiming','CSI reference must occupy DL symbols.');
                for u=1:numel(state.ServingCells)
                    c=state.ServingCells(u); H=obj.channel("DL",u,c,slot,state.LargeScaleState,coords);
                    B=eye(obj.Policy.bsPorts);
                    if ~isempty(obj.CSIBases), B=obj.CSIBases(:,:,cri+1); end
                    logicalH=zeros(size(H,1),size(B,2),size(H,3),'like',H);
                    for k=1:size(H,3), logicalH(:,:,k)=H(:,:,k)*B; end
                    id=obj.Cfg.phy.frame.DefaultIdentity;
                    ue=struct('UEID',u,'RNTI',u,'ServingCell',c,'PUCCHCell',c, ...
                        'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
                    cal=sixgr.truth.buildPeriodicCSIReportObligations(obj.Cfg,ue,slot+1,slot+p.maximumAgeSlots+1);
                    eligible=cal.ULResourceAvailable & cal.CSIReferenceSlot>=slot+1 & ...
                        cal.ReportSlot-1>=slot+p.deliveryDelaySlots;
                    if ~any(eligible), continue; end
                    reportSlot0=min(cal.ReportSlot(eligible))-1;
                    power=state.LargeScaleState.TxPower_dBm(u,c);
                    o=struct('ObservationID',string(obj.Cfg.run.executionID)+"_csi_"+u+"_"+c+"_"+slot+"_"+cri, ...
                        'ExecutionID',string(obj.Cfg.run.executionID),'UEIndex',u,'ServingCell',c, ...
                        'SourceAbsoluteSlot0',slot,'AvailableAbsoluteSlot0',reportSlot0+1, ...
                        'ReportAbsoluteSlot0',reportSlot0,'ReferenceAvailableAtSlot0',slot+p.deliveryDelaySlots, ...
                        'ChannelEstimate',logicalH,'ExternalCovariance',noise*eye(size(H,1)), ...
                        'PortToElementMatrix',B,'PortBasisSHA256',string(sixgr.phy.mimo.MatrixContract.digest(B)), ...
                        'TotalTransmitPower',10^((power-30)/10)/(12*carrier.NSizeGrid), ...
                        'CRI',cri,'Coordinates0Based',coords, ...
                        'RFProfileID',string(obj.Policy.rfProfileID),'SourceClassification',string(p.sourceClassification));
                    observations=[observations o]; %#ok<AGROW>
                end
            end
        end
        function observations=observeSRS(obj,state)
            observations=struct([]);
            assert(logical(sixgr.util.structGet(obj.Cfg,'phy.srs.enable',false)), ...
                'sixgr:abstraction:NetworkSRSDisabled','Enable configured SRS occasions before enabling modeled SRS feedback.');
            assert(string(obj.Policy.soundingRankReference)=="full_carrier_pusch_thermal_noise_only", ...
                'sixgr:abstraction:NetworkSoundingPolicy','Declare the rank-reference power/interference assumption.');
            delay=obj.Policy.srsDeliveryDelaySlots;
            validateattributes(delay,{'numeric'},{'scalar','integer','positive','finite'});
            strict=sixgr.phy.srs.buildSRSConfigFromScenario(obj.Cfg);
            srs=strict.ToolboxSRS; slot=state.AbsoluteSlot0;
            assert(isnumeric(srs.SRSPeriod) && numel(srs.SRSPeriod)==2 && srs.NumSRSPorts==obj.Policy.uePorts, ...
                'sixgr:abstraction:NetworkSRSConfig','Use configured periodic SRS covering all UE transmit ports.');
            if mod(slot-srs.SRSPeriod(2),srs.SRSPeriod(1))~=0, return; end
            slots=sixgr.util.structGet(obj.Cfg,'phy.srs.slotNumbers',[]);
            if ~isempty(slots) && ~ismember(slot,slots), return; end
            carrier=obj.Carrier; carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
            mapped=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal( ...
                carrier,'SRS',srs,'AbsoluteSlot',slot);
            coords=unique(double(mapped.ActualCoordinates0Based(:,1:2)),'rows');
            assert(~isempty(coords),'sixgr:abstraction:NetworkSRSConfig','Due SRS must have actual configured resources.');
            partition=sixgr.util.resolveTDDSlotPartition(obj.Cfg,slot);
            a=double(partition.ULSymbolAllocation);
            assert(all(coords(:,2)>=a(1) & coords(:,2)<sum(a)), ...
                'sixgr:abstraction:NetworkSRSTiming','SRS resources must lie in resolved UL symbols.');
            noise=10^((obj.Policy.noiseDensity_dBmHz+10*log10(1000*carrier.SubcarrierSpacing)+ ...
                obj.Cfg.scenario.bs.noiseFigure_dB-30)/10);
            for u=1:numel(state.ServingCells)
                c=state.ServingCells(u);
                H=obj.channel("UL",u,c,slot,state.LargeScaleState,coords);
                tx=obj.Cfg.scenario.ue.txPower_dBm; if ~isscalar(tx), tx=tx(u); end
                o=struct('ObservationID',string(obj.Cfg.run.executionID)+"_srs_"+u+"_"+c+"_"+slot, ...
                    'ExecutionID',string(obj.Cfg.run.executionID),'ChannelOwnerID',"reciprocal_link_"+u+"_"+c, ...
                    'UEIndex',u,'ServingCell',c,'SourceAbsoluteSlot0',slot,'AvailableAbsoluteSlot0',slot+delay, ...
                    'SRI',double(strict.ResourceId),'ChannelEstimate',H,'ExternalCovariance',noise*eye(size(H,1)), ...
                    'TotalPUSCHPower',10^((tx-30)/10)/(12*carrier.NSizeGrid), ...
                    'SourceClassification',"modeled_srs_not_waveform_measurement", ...
                    'ReceiverType',string(obj.Cfg.system.linkAbstraction.receiverType), ...
                    'EstimationAssumption',"ideal_delayed_channel_estimate", ...
                    'RFProfileID',string(obj.Policy.rfProfileID), ...
                    'RankReferenceAssumption',string(obj.Policy.soundingRankReference), ...
                    'Coordinates0Based',coords);
                observations=[observations o]; %#ok<AGROW>
            end
        end
        function H=channel(obj,direction,u,c,slot,largeScale,coords)
            validateattributes([u c],{'numeric'},{'integer','positive','finite','numel',2});
            validateattributes(slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            loss=largeScale.Pathloss_dB(u,c);
            assert(isfinite(loss),'sixgr:abstraction:NetworkPathloss','Require an explicit finite per-link pathloss including configured large-scale losses.');
            key=string(u)+"_"+c+"_"+slot;
            if obj.LastKey~=key
                % Same link seed and absolute InitialTime make call order
                % independent, including a later UL request of the same link.
                seedText=string(obj.Cfg.run.seed)+"_network_link_"+u+"_"+c;
                hash=char(sixgr.util.sha256Hex(uint8(char(seedText))));
                ch=clone(obj.Template); release(ch);
                ch.RandomStream='mt19937ar with seed';
                ch.Seed=mod(hex2dec(hash(1:8)),2^32-1);
                ch.InitialTime=slot*1e-3/(obj.Carrier.SubcarrierSpacing/15);
                carrier=obj.Carrier; carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
                [response,~]=ch(carrier);
                assert(size(response,1)==12*carrier.NSizeGrid && size(response,3)==obj.Policy.uePorts && ...
                    size(response,4)==obj.Policy.bsPorts, ...
                    'sixgr:abstraction:NetworkDimensions','Channel factory must retain configured BS/UE connector dimensions.');
                obj.LastResponse=response; obj.LastKey=key;
            end
            response=obj.LastResponse;
            H=zeros(obj.Policy.uePorts,obj.Policy.bsPorts,size(coords,1),'like',response);
            for k=1:size(coords,1)
                H(:,:,k)=reshape(response(coords(k,1)+1,coords(k,2)+1,:,:),obj.Policy.uePorts,obj.Policy.bsPorts);
            end
            if string(direction)=="UL", H=permute(H,[2 1 3]); end % reciprocal transpose, NOT conjugate
            H=H*10^(-loss/20);
        end
    end
    methods (Access=private)
        function p=power(obj,direction,u,c,g,coords,grants,cells,largeScale)
            n=size(coords,1);
            if direction=="DL"
                watts=10^((largeScale.TxPower_dBm(u,c)-30)/10);
                count=zeros(n,1);
                for j=1:numel(grants)
                    if cells(j)==c, count=count+overlap(coords,grants(j)); end
                end
                assert(all(count>0),'sixgr:abstraction:NetworkPower','Desired DL resource has no active transmitter.');
                p=watts/(12*obj.Carrier.NSizeGrid)./count;
            else
                tx=obj.Cfg.scenario.ue.txPower_dBm;
                if ~isscalar(tx), tx=tx(u); end
                p=repmat(10^((tx-30)/10)/(12*numel(g.PRBSet)),n,1);
            end
            assert(all(isfinite(p) & p>0),'sixgr:abstraction:NetworkPower','Invalid configured transmit power.');
        end
    end
end
function yes=anyEnabled(s)
yes=false;
if ~isstruct(s), return; end
for item=1:numel(s)
    names=fieldnames(s(item));
    for k=1:numel(names)
        name=names{k}; v=s(item).(name);
        if isstruct(v), yes=yes || anyEnabled(v);
        elseif (strcmpi(name,'enable') || endsWith(lower(name),'enabled')) && ...
                (islogical(v) || isnumeric(v)), yes=yes || any(logical(v(:)));
        end
    end
end
end

function W=precoder(g,nt)
W=sixgr.util.structGet(g,'PHYGrant.PrecodingState.MatrixPorts',[]);
assert(~isempty(W) && size(W,1)==nt && size(W,2)==g.NumLayers && all(isfinite(W),'all'), ...
    'sixgr:abstraction:NetworkPrecoder','Use the actual frozen port-domain precoder; no identity/SVD fallback.');
W=W/norm(W,'fro');
end
function x=coordinates(g,nrb)
prb=double(g.PRBSet(:)); sym=double(g.SymbolAllocation);
assert(~isempty(prb) && all(prb>=0 & prb<nrb & prb==fix(prb)) && numel(unique(prb))==numel(prb) && ...
    numel(sym)==2 && sym(1)>=0 && sym(2)>0 && sum(sym)<=14 && all(sym==fix(sym)), ...
    'sixgr:abstraction:NetworkAllocation','Require valid zero-based carrier PRBs and symbols.');
[k,l]=ndgrid(reshape(12*prb.'+(0:11).',[],1),sym(1)+(0:sym(2)-1));
x=[k(:) l(:)];
end
function mask=overlap(x,g)
mask=ismember(floor(x(:,1)/12),g.PRBSet) & x(:,2)>=g.SymbolAllocation(1) & ...
    x(:,2)<sum(g.SymbolAllocation);
end
function yes=hasOverlap(grants,g)
yes=false;
for k=1:numel(grants)
    other=grants(k);
    yes=yes || (~isempty(intersect(other.PRBSet,g.PRBSet)) && ...
        max(other.SymbolAllocation(1),g.SymbolAllocation(1))<min(sum(other.SymbolAllocation),sum(g.SymbolAllocation)));
end
end
