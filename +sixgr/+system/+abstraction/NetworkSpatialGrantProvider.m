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
        ULProfileID string
        DLReceiverProfileID string
        ULReceiverProfileID string
        LastKey string = ""
        LastResponse = []
        CSIBases = []
        UCIResources = []
        CPChannelSupport struct = struct()
        ScheduledHistory
        PendingReferenceFeedback cell = {}
        LastCSIObservationSlot0 double = -1
        LastSRSObservationSlot0 double = -1
        CommittedSRS cell = {}
    end
    methods
        function obj=NetworkSpatialGrantProvider(cfg)
            obj.Cfg=cfg;
            p=cfg.system.linkAbstraction.networkSpatial;
            p.sinrPredictorModel=sixgr.system.abstraction.resolveNetworkSINRModel(cfg);
            assert(all(isfield(p,{'bsPorts','uePorts','noiseDensity_dBmHz','powerPolicy', ...
                'rfProfileID','resultClassification','sinrResourcePopulation','interferencePopulation'})), ...
                'sixgr:abstraction:NetworkPolicy','Install the complete networkSpatial YAML policy.');
            validateattributes([p.bsPorts p.uePorts],{'numeric'},{'integer','positive','finite','numel',2});
            validateattributes(p.noiseDensity_dBmHz,{'numeric'},{'scalar','real','finite'});
            assert(string(p.powerPolicy)=="equal_psd_per_active_transmitter_split_overlapping_dl_grants" && ...
                string(p.resultClassification)=="modeled_frequency_selective_network_not_waveform" && ...
                any(string(p.sinrResourcePopulation)==["allocated_prb_symbol_footprint_including_pilots", ...
                    "native_shared_channel_data_re"]) && ...
                any(string(p.interferencePopulation)==["scheduled_shared_data_grants_only","scheduled_shared_data_and_srs", ...
                    "scheduled_shared_data_and_srs_and_csirs","scheduled_shared_data_and_srs_and_csirs_and_pdcch"]) && ...
                string(p.rfProfileID)=="ideal_rf_no_impairments", ...
                'sixgr:abstraction:NetworkPolicy','This provider implements the labelled ideal-RF, equal-PSD baseline.');
            if includesSRS(p)
                assert(p.sinrPredictorModel=="finite_committed_shared_data" && ...
                    string(p.sinrResourcePopulation)=="native_shared_channel_data_re" && ...
                    string(sixgr.util.structGet(p,'srsPowerPolicy',''))=="configured_ue_total_power_per_srs_symbol" && ...
                    string(sixgr.util.structGet(p,'srsPhaseAssumption',''))=="native_sequence_phase_at_committed_epoch", ...
                    'sixgr:abstraction:SRSEmissionPolicy', ...
                    'Emitted SRS requires finite native data-RE evaluation and explicit power/phase policy.');
            end
            if includesCSIRS(p)
                assert(string(sixgr.util.structGet(p,'csirsPowerPolicy',''))=="configured_bs_full_carrier_psd_per_occupied_re" && ...
                    string(sixgr.util.structGet(p,'csirsPhaseAssumption',''))=="native_sequence_phase_at_committed_epoch" && ...
                    isfield(p,'csirsScramblingIDs'), ...
                    'sixgr:abstraction:CSIRSEmissionPolicy', ...
                    'Emitted CSI-RS needs configured power, relative phase and per-cell scrambling identities.');
            end
            if includesPDCCH(p)
                assert(all(isfield(p,{'pdcchPowerPolicy','pdcchPhaseAssumption', ...
                    'pdcchBeamPolicy','pdcchScramblingIDs','pdcchPrecoderMatrices'})), ...
                    'sixgr:abstraction:PDCCHEmissionPolicy', ...
                    'Emitted PDCCH needs explicit power, phase, cell identities and physical beam columns.');
            end
            if includesSSB(p)
                assert(includesPDCCH(p) && all(isfield(p,{'ssbPowerPolicy','ssbPhaseAssumption', ...
                    'ssbBeamPolicy','ssbCellIDs'})), 'sixgr:abstraction:SSBEmissionPolicy', ...
                    'SSB requires the finite native control/RS population and explicit power, phase, beam and cell policies.');
            end
            if includesPUCCH(p)
                assert(includesSRS(p) && ...
                    string(sixgr.util.structGet(p,'pucchPowerPolicy',''))=="typed_PUCCH_power_control_active_symbol_mean" && ...
                    string(sixgr.util.structGet(p,'pucchPhaseAssumption',''))=="native_sequence_phase_at_committed_epoch", ...
                    'sixgr:abstraction:PUCCHEmissionPolicy', ...
                    'PUCCH requires finite native RS history and explicit transmitter power/phase policies.');
            end
            assert(strcmpi(sixgr.phy.frame.resolveDuplexMode(cfg),'TDD'), ...
                'sixgr:abstraction:NetworkDuplex','Reciprocal network provider requires TDD.');
            obj.Policy=p;
            basis=string(sixgr.util.structGet(p,'dlAntennaBasis','direct_ports'));
            assert(any(basis==["direct_ports","configured_csirs_elements"]), ...
                'sixgr:abstraction:DLCSIPortBasis','Unknown networkSpatial.dlAntennaBasis.');
            if includesCSIRS(p)
                assert(basis=="configured_csirs_elements", ...
                    'sixgr:abstraction:CSIRSEmissionBasis', ...
                    'Emitted CSI-RS and ideal delayed CSI must share the same configured physical beam basis.');
            end
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
            channel=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,obj.OFDM.SampleRate,"DL");
            assert(isa(channel.Object,'nrTDLChannel') || isa(channel.Object,'nrCDLChannel'), ...
                'sixgr:abstraction:NetworkChannel','Configure a concrete TDL/CDL profile; no flat-channel substitute.');
            obj.Template=channel.Object; obj.ChannelMeta=channel.Meta;
            nativeInfo=info(obj.Template);
            obj.CPChannelSupport=sixgr.phy.waveform.channelCyclicPrefixSupport( ...
                getPathFilters(obj.Template),double(nativeInfo.ChannelFilterDelay), ...
                obj.OFDM.CyclicPrefixLengths,0.5);
            slotSamples=sum(reshape(obj.OFDM.SymbolLengths,obj.Carrier.SymbolsPerSlot,[]),1);
            filterMemory=size(getPathFilters(obj.Template),1)-1;
            obj.ScheduledHistory=sixgr.system.abstraction.ScheduledSlotHistory( ...
                ceil(filterMemory/min(slotSamples)), ...
                ceil(max(obj.CPChannelSupport.RequiredFollowingSymbolSamples)/min(slotSamples)));
            assert(isprop(obj.Template,'ChannelResponseOutput'), ...
                'sixgr:abstraction:NetworkToolbox','Frequency-domain response requires a supporting 5G Toolbox release.');
            assert(~obj.Template.NormalizeChannelOutputs, ...
                'sixgr:abstraction:NetworkPower','Disable receive-count normalization for per-connector power.');
            obj.Template.ChannelFiltering=false;
            obj.Template.ChannelResponseOutput='path-gains';
            sampling=string(sixgr.util.structGet(p,'channelResponseSampling','signal_rate'));
            assert(any(sampling==["signal_rate","static_exact"]), ...
                'sixgr:abstraction:NetworkSampling','Select signal_rate or static_exact explicitly.');
            assert(sampling~="static_exact" || obj.Template.MaximumDopplerShift==0, ...
                'sixgr:abstraction:NetworkSamplingMobility', ...
                'static_exact is validated only at zero Doppler. Moving channels require signal_rate.');
            obj.ChannelMeta.SLSChannelResponseSampling=sampling;
            obj.Template.NumTimeSamples=sum(obj.OFDM.SymbolLengths(1:obj.Carrier.SymbolsPerSlot));
            identity=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,obj.Template);
            obj.ProfileID=identity.ProfileID;
            reciprocal=clone(obj.Template); release(reciprocal);
            swapTransmitAndReceive(reciprocal);
            identity=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,reciprocal);
            obj.ULProfileID=identity.ProfileID;
            identity=sixgr.system.abstraction.networkReceiverCalibrationIdentity(cfg,"DL",cfg.system.linkAbstraction.receiverType);
            obj.DLReceiverProfileID=identity.ProfileID;
            identity=sixgr.system.abstraction.networkReceiverCalibrationIdentity(cfg,"UL",cfg.system.linkAbstraction.receiverType);
            obj.ULReceiverProfileID=identity.ProfileID;
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
            % Scheduler populations may be column vectors. Both predicates
            % must share a shape: Nx1 & 1xN otherwise selects an NxN matrix
            % and can fail to exclude the desired grant as an interferer.
            same=reshape(arrayfun(@(g) g.RNTI==ctx.Grant.RNTI && ...
                sixgr.system.resolveGrantUEIndex(g)==sixgr.system.resolveGrantUEIndex(ctx.Grant) && isequal(g.PRBSet,ctx.Grant.PRBSet) && ...
                isequal(g.SymbolAllocation,ctx.Grant.SymbolAllocation),grants),1,[]);
            match=find(same & reshape(cells,1,[])==ctx.ServingCellID);
            assert(isscalar(match),'sixgr:abstraction:NetworkPopulation','Desired grant must occur exactly once in the active population.');
            u=sixgr.system.resolveGrantUEIndex(ctx.Grant); c=double(ctx.ServingCellID); slot=ctx.TTI-1;
            resourceMaps={};
            if string(obj.Policy.sinrResourcePopulation)=="native_shared_channel_data_re"
                assert(isequaln(ctx.Grant.PHYGrant,grants(match).PHYGrant), ...
                    'sixgr:abstraction:NetworkPopulation','Desired frozen grant differs from its active network entry.');
                resourceMaps=cell(1,numel(grants));
                for j=1:numel(grants)
                    resourceMaps{j}=sixgr.system.abstraction.scheduledDataREMap(obj.Cfg,grants(j),slot);
                end
                coords=resourceMaps{match}.Coordinates0Based;
            else
                coords=coordinates(ctx.Grant,obj.Carrier.NSizeGrid);
            end
            n=size(coords,1);
            H=obj.channel(direction,u,c,slot,state.LargeScaleState,coords);
            F=precoder(ctx.Grant,size(H,2));
            power=obj.power(direction,u,c,ctx.Grant,coords,grants,cells,state.LargeScaleState,resourceMaps);
            entity='ue'; if direction=="UL", entity='bs'; end
            nf=obj.Cfg.scenario.(entity).noiseFigure_dB;
            noise=10^((obj.Policy.noiseDensity_dBmHz+10*log10(1000*obj.Carrier.SubcarrierSpacing)+nf-30)/10);
            covariance=repmat(noise*eye(size(H,1)),1,1,n);
            interferers=zeros(n,1);
            for j=1:numel(grants)
                if j==match, continue; end
                g=grants(j); mask=resourceOverlap(coords,g,resourceMaps,j);
                if ~any(mask), continue; end
                if direction=="DL"
                    cross=obj.channel(direction,u,cells(j),slot,state.LargeScaleState,coords(mask,:));
                else
                    assert(sixgr.system.resolveGrantUEIndex(g)~=u,'sixgr:abstraction:DuplicateULTransmitter','One UE cannot independently power two overlapping UL grants.');
                    cross=obj.channel(direction,sixgr.system.resolveGrantUEIndex(g),c,slot,state.LargeScaleState,coords(mask,:));
                end
                W=precoder(g,size(cross,2));
                q=obj.power(direction,sixgr.system.resolveGrantUEIndex(g),cells(j),g,coords(mask,:),grants,cells,state.LargeScaleState,resourceMaps);
                ix=find(mask);
                for k=1:numel(ix)
                    G=cross(:,:,k)*W;
                    covariance(:,:,ix(k))=covariance(:,:,ix(k))+q(k)*(G*G');
                end
                interferers(mask)=interferers(mask)+1;
            end
            profileID=obj.ProfileID;
            receiverProfileID=obj.DLReceiverProfileID;
            if direction=="UL", profileID=obj.ULProfileID; receiverProfileID=obj.ULReceiverProfileID; end
            o=struct('Channel',H,'Precoder',F,'TotalTransmitPower',power, ...
                'ExternalCovariance',covariance,'RFProfileID',string(obj.Policy.rfProfileID), ...
                'ReceiverProfileID',receiverProfileID, ...
                'ChannelProfileID',profileID, ...
                'ModelObservationID',string(obj.Cfg.run.executionID)+"_"+direction+"_"+u+"_"+c+"_"+slot, ...
                'SourceClassification',"modeled_spatial_channel_not_waveform_measurement", ...
                'Coordinates0Based',coords,'ActiveInterferersPerRE',interferers, ...
                'NoisePowerPerRE_W',noise,'PowerPlane',"watts_per_subcarrier_per_receive_connector", ...
                'ChannelMetadata',obj.ChannelMeta,'ArrayQualified',false,'RFQualified',false, ...
                'ResourcePopulation',string(obj.Policy.sinrResourcePopulation), ...
                'InterferencePopulation',string(obj.Policy.interferencePopulation), ...
                'CommonControlInterferenceQualified',false);
            % A nominal diagonal OFDM response is not the complete linear
            % waveform operator when the finite filter extends outside the
            % FFT's cyclic interval. Report this domain explicitly; never
            % call unmodeled leakage zero or call the predictor measured.
            o.ChannelCyclicPrefixSupport=obj.CPChannelSupport;
            o.StaticUnwindowedCircularConvolutionSupported= ...
                obj.CPChannelSupport.CircularConvolutionSupported && ...
                obj.Template.MaximumDopplerShift==0;
            o.ResidualISIICIIncluded=false;
            o.ReceiveSlotSupport=obj.receiveSupport(slot,coords);
            if ~isempty(resourceMaps)
                o.DataREAllocationIdentity=resourceMaps{match}.AllocationIdentity;
                o.DataREAllocationSHA256=resourceMaps{match}.AllocationIdentitySHA256;
                % Interfering reference/control signals still require their
                % own powers, precoders and resource maps. Do not claim them.
                o.ReferenceSignalInterferenceQualified=false;
            end
            o.SINRPredictorModel=string(obj.Policy.sinrPredictorModel);
            o.InterferenceCountingUnit="source_grant_occurrence";
            if o.SINRPredictorModel=="finite_committed_shared_data"
                finite=obj.evaluateFiniteWindow(ctx);
                o.FiniteWindow=finite;
                o.ExternalCovariance=finite.ExternalCovariance;
                o.ResidualISIICIIncluded=true;
                o.SRSInterferenceIncluded=finite.SRSInterferenceIncluded;
                o.SRSEmissionCount=numel(finite.SRSEmissionPopulation);
                o.CSIRSInterferenceIncluded=finite.CSIRSInterferenceIncluded;
                o.CSIRSEmissionCount=numel(finite.CSIRSEmissionPopulation);
                o.PDCCHInterferenceIncluded=finite.PDCCHInterferenceIncluded;
                o.PDCCHEmissionCount=numel(finite.PDCCHEmissionPopulation);
                o.SSBInterferenceIncluded=finite.SSBInterferenceIncluded;
                o.SSBEmissionCount=numel(finite.SSBEmissionPopulation);
                o.PUCCHInterferenceIncluded=finite.PUCCHInterferenceIncluded;
                o.PUCCHEmissionCount=numel(finite.PUCCHEmissionPopulation);
                o.ActiveInterferersPerRE=zeros(n,1);
                for j=1:numel(finite.Population)
                    if finite.Population(j).IsDesired, continue; end
                    contribution=finite.Population(j).Covariance;
                    o.ActiveInterferersPerRE=o.ActiveInterferersPerRE+ ...
                        reshape(any(any(contribution~=0,1),2),[],1);
                end
            end
            obj.LastContext=ctx; obj.LastObservation=o;
        end
        function bindUCIResources(obj,ledger)
            assert(isa(ledger,'sixgr.system.SLSDynamicPUCCH'), ...
                'sixgr:abstraction:UCIResourceBinding','Require the production UCI ownership ledger.');
            obj.UCIResources=ledger;
        end
        function commitSlotPopulation(obj,state)
            emissions=struct([]);
            csirs=struct([]);
            pdcch=struct([]);
            ssb=struct([]);
            pucch=struct([]);
            if includesSRS(obj.Policy)
                emissions=sixgr.system.abstraction.buildScheduledSRSEmissions(obj.Cfg,state);
            end
            if includesCSIRS(obj.Policy)
                csirs=sixgr.system.abstraction.buildScheduledCSIRSEmissions(obj.Cfg,state);
            end
            if includesSSB(obj.Policy)
                ssb=sixgr.system.abstraction.buildScheduledSSBEmissions(obj.Cfg,state);
                assertSSBResources(obj.Cfg,state,ssb,csirs);
            end
            if includesPDCCH(obj.Policy)
                pdcch=sixgr.system.abstraction.buildScheduledPDCCHEmissions(obj.Cfg,state,csirs,ssb);
            end
            if includesPUCCH(obj.Policy)
                pucch=sixgr.system.abstraction.validateCommittedPUCCHEmissions(obj.Cfg,state,emissions);
            else
                assert(~isfield(state,'PUCCHEmissions') || isempty(state.PUCCHEmissions), ...
                    'sixgr:abstraction:PUCCHEmissionPolicy','Do not silently discard an emitted PUCCH population.');
            end
            obj.ScheduledHistory.append(state);
            if includesSRS(obj.Policy)
                record=struct('TTI',state.TTI,'Emissions',emissions,'CSIRSEmissions',csirs, ...
                    'PDCCHEmissions',pdcch,'SSBEmissions',ssb,'PUCCHEmissions',pucch);
                if ~isempty(obj.CommittedSRS) && obj.CommittedSRS{end}.TTI==state.TTI
                    assert(isequaln(record,obj.CommittedSRS{end}), ...
                        'sixgr:abstraction:SlotHistoryMutation','Committed reference symbols, identity and power cannot change.');
                    return;
                end
                obj.CommittedSRS{end+1}=record;
                limit=obj.ScheduledHistory.LookbackSlots+obj.ScheduledHistory.LookaheadSlots+1;
                if numel(obj.CommittedSRS)>limit, obj.CommittedSRS(1)=[]; end
            end
        end
        function emissions=committedSRSEmissions(obj,tti)
            match=find(cellfun(@(r)r.TTI==tti,obj.CommittedSRS));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'Require the actual committed SRS population, including an explicit empty occasion.');
            emissions=obj.CommittedSRS{match}.Emissions;
        end
        function emissions=committedCSIRSEmissions(obj,tti)
            match=find(cellfun(@(r)r.TTI==tti,obj.CommittedSRS));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'Require committed native CSI-RS emissions, including explicit empty occasions.');
            emissions=obj.CommittedSRS{match}.CSIRSEmissions;
        end
        function emissions=committedPDCCHEmissions(obj,tti)
            match=find(cellfun(@(r)r.TTI==tti,obj.CommittedSRS));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'Require committed coded PDCCH emissions, including explicit empty control occasions.');
            emissions=obj.CommittedSRS{match}.PDCCHEmissions;
        end
        function emissions=committedSSBEmissions(obj,tti)
            match=find(cellfun(@(r)r.TTI==tti,obj.CommittedSRS));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'Require committed native SS/PBCH emissions, including empty burst occasions.');
            emissions=obj.CommittedSRS{match}.SSBEmissions;
        end
        function [states,evidence]=interferenceWindow(obj,tti)
            [states,evidence]=obj.ScheduledHistory.window(tti);
        end
        function emissions=committedPUCCHEmissions(obj,tti)
            match=find(cellfun(@(r)r.TTI==tti,obj.CommittedSRS));
            assert(isscalar(match),'sixgr:abstraction:IncompleteSlotHistory', ...
                'Require committed native PUCCH emissions, including explicit empty occasions.');
            emissions=obj.CommittedSRS{match}.PUCCHEmissions;
        end
        function [states,evidence]=receiveInterferenceWindow(obj,tti,lookahead)
            [states,evidence]=obj.ScheduledHistory.receiveWindow(tti,lookahead);
        end
        function [states,evidence]=receiveGrantWindow(obj,ctx)
            % Bind a receive window to the actual committed grant. This is
            % schedule evidence only; it does not execute a finite detector
            % or change the existing diagonal model's calibration identity.
            validateattributes(ctx.TTI,{'numeric'},{'scalar','integer','positive','finite'});
            direction=string(ctx.Direction);
            assert(any(direction==["DL","UL"]),'sixgr:abstraction:NetworkPopulation','Require an explicit grant direction.');
            if string(obj.Policy.sinrResourcePopulation)=="native_shared_channel_data_re"
                map=sixgr.system.abstraction.scheduledDataREMap(obj.Cfg,ctx.Grant,ctx.TTI-1);
                coords=map.Coordinates0Based;
            else
                coords=coordinates(ctx.Grant,obj.Carrier.NSizeGrid);
            end
            support=obj.receiveSupport(ctx.TTI-1,coords);
            [states,evidence]=obj.ScheduledHistory.receiveWindow(ctx.TTI,support.RequiredFollowingSlots);
            assert(obj.ScheduledHistory.LookbackSlots>=support.RequiredPreviousSlots, ...
                'sixgr:abstraction:ReceiveWindowRetention','Receive FFT requires more previous-slot history than retained.');
            % Storage is conservative; the physical receive window is not.
            % An interior FFT must not acquire a needless previous UL slot
            % merely because the same history also serves boundary grants.
            evidence.RetainedWindowTTIs=evidence.TTIs;
            keep=cellfun(@(s)s.TTI>=max(1,ctx.TTI-support.RequiredPreviousSlots),states);
            states=states(keep);
            evidence.TTIs=evidence.TTIs(keep);
            evidence.AbsoluteSlots0=evidence.TTIs-1;
            evidence.ExplicitIdleTTIs=intersect(evidence.ExplicitIdleTTIs,evidence.TTIs,'stable');
            evidence.InitialSimulationBoundaryIncluded=evidence.TTIs(1)==1;
            evidence.RequiredPreviousSlots=support.RequiredPreviousSlots;
            target=states{find(cellfun(@(s)s.TTI==ctx.TTI,states),1)};
            grants=target.("Grants"+direction); cells=target.("GrantCells"+direction);
            same=reshape(arrayfun(@(g)sixgr.system.abstraction.matchesScheduledGrant(g,ctx),grants),1,[]);
            match=find(same & reshape(cells,1,[])==ctx.ServingCellID);
            assert(isscalar(match),'sixgr:abstraction:NetworkPopulation', ...
                'Receive context must exactly match one committed serving-cell grant.');
            evidence.ReceiveSlotSupport=support;
            evidence.Coordinates0Based=coords;
            evidence.DesiredGrantIndex=match;
            evidence.DesiredServingCellID=ctx.ServingCellID;
            evidence.ResidualISIICIIncluded=false;
        end
        function [available,evidence,state]=receptionAvailability(obj,ctx)
            % Check the immutable issued grant even BEFORE its last sample
            % is available. Waiting is not permission to change its fields.
            state=obj.ScheduledHistory.scheduledState(ctx.TTI);
            direction=string(ctx.Direction);
            assert(any(direction==["DL","UL"]),'sixgr:abstraction:NetworkPopulation','Invalid direction.');
            grants=state.("Grants"+direction); cells=state.("GrantCells"+direction);
            same=reshape(arrayfun(@(g)sixgr.system.abstraction.matchesScheduledGrant(g,ctx),grants),1,[]);
            assert(sum(same & reshape(cells,1,[])==ctx.ServingCellID)==1, ...
                'sixgr:abstraction:NetworkPopulation','Receive context differs from its committed grant.');
            if string(obj.Policy.sinrResourcePopulation)=="native_shared_channel_data_re"
                map=sixgr.system.abstraction.scheduledDataREMap(obj.Cfg,ctx.Grant,ctx.TTI-1);
                coords=map.Coordinates0Based;
            else
                coords=coordinates(ctx.Grant,obj.Carrier.NSizeGrid);
            end
            support=obj.receiveSupport(ctx.TTI-1,coords);
            required=ctx.TTI+support.RequiredFollowingSlots;
            available=obj.ScheduledHistory.CommittedThroughTTI>=required;
            evidence=struct('TransmissionTTI',ctx.TTI,'RequiredCommittedThroughTTI',required, ...
                'ReadAtCommittedTTI',obj.ScheduledHistory.CommittedThroughTTI, ...
                'ReceiveSlotSupport',support,'Available',available);
            if available
                % Validate retained past/following support, not just a clock.
                obj.receiveGrantWindow(ctx);
            end
        end
        function [available,evidence]=referenceReceptionAvailability(obj,ctx,coords)
            % CSI/SRS need receive support even when no data grant exists.
            % Coordinates identify the actual observation resources; they
            % are not a fabricated PDSCH/PUSCH allocation.
            validateattributes(ctx.TTI,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes([ctx.UEIndex ctx.ServingCellID],{'numeric'}, ...
                {'integer','positive','finite','numel',2});
            assert(any(string(ctx.Direction)==["DL","UL"]), ...
                'sixgr:abstraction:NetworkPopulation','Reference reception requires an explicit direction.');
            validateattributes(coords,{'numeric'},{'2d','ncols',2,'nonempty','integer','nonnegative','finite'});
            assert(all(coords(:,1)<12*obj.Carrier.NSizeGrid) && ...
                all(coords(:,2)<obj.Carrier.SymbolsPerSlot) && size(unique(coords,'rows'),1)==size(coords,1), ...
                'sixgr:abstraction:NetworkAllocation','Reference coordinates must be unique, in-carrier, zero-based REs.');
            obj.ScheduledHistory.scheduledState(ctx.TTI);
            support=obj.receiveSupport(ctx.TTI-1,coords);
            required=ctx.TTI+support.RequiredFollowingSlots;
            available=obj.ScheduledHistory.CommittedThroughTTI>=required;
            evidence=struct('TransmissionTTI',ctx.TTI,'RequiredCommittedThroughTTI',required, ...
                'ReadAtCommittedTTI',obj.ScheduledHistory.CommittedThroughTTI, ...
                'ReceiveSlotSupport',support,'Available',available);
            if available
                obj.ScheduledHistory.receiveWindow(ctx.TTI,support.RequiredFollowingSlots);
            end
        end
        function observation=evaluateReferenceInterference(obj,ctx,coords)
            % Shared-data contribution at reference-signal observation REs.
            % The desired pilot and other control/RS signals are NOT modeled
            % here. This intermediate covariance is not complete CSI/SRS
            % qualification or a received waveform measurement.
            observation=obj.evaluateFiniteWindow(ctx,coords);
        end
        function observation=evaluateFiniteWindow(obj,ctx,referenceCoordinates)
            % Exact reference evaluation of COMMITTED shared-data grants.
            % This does not borrow a diagonal-model BLER package, change
            % HARQ timing, or claim missing common/RS interference is zero.
            referenceOnly=nargin==3;
            if referenceOnly
                [available,support]=obj.referenceReceptionAvailability(ctx,referenceCoordinates);
                assert(available,'sixgr:abstraction:ReceiveWindowNotAvailable', ...
                    'Reference interference needs every required following committed slot; do not assume silence.');
                [states,window]=obj.ScheduledHistory.receiveWindow(ctx.TTI, ...
                    support.ReceiveSlotSupport.RequiredFollowingSlots);
                window.RetainedWindowTTIs=window.TTIs;
                keep=cellfun(@(s)s.TTI>=max(1,ctx.TTI-support.ReceiveSlotSupport.RequiredPreviousSlots),states);
                states=states(keep); window.TTIs=window.TTIs(keep);
                window.AbsoluteSlots0=window.TTIs-1;
                window.ExplicitIdleTTIs=intersect(window.ExplicitIdleTTIs,window.TTIs,'stable');
                window.InitialSimulationBoundaryIncluded=window.TTIs(1)==1;
                window.ReceiveSlotSupport=support.ReceiveSlotSupport;
                window.Coordinates0Based=double(referenceCoordinates);
                window.RequiredPreviousSlots=support.ReceiveSlotSupport.RequiredPreviousSlots;
                receiverUE=double(ctx.UEIndex);
            else
                [states,window]=obj.receiveGrantWindow(ctx);
                receiverUE=sixgr.system.resolveGrantUEIndex(ctx.Grant);
            end
            firstTTI=states{1}.TTI;
            carrier=nrCarrierConfig('NSizeGrid',obj.Carrier.NSizeGrid, ...
                'NStartGrid',obj.Carrier.NStartGrid,'SubcarrierSpacing',obj.Carrier.SubcarrierSpacing, ...
                'CyclicPrefix',obj.Carrier.CyclicPrefix,'NCellID',obj.Carrier.NCellID);
            carrier.NSlot=mod(firstTTI-1,carrier.SlotsPerFrame);
            direction=string(ctx.Direction);
            if referenceOnly && includesCSIRS(obj.Policy) && direction=="DL"
                assert(isfield(ctx,'CRI') && isnumeric(ctx.CRI) && isscalar(ctx.CRI) && ...
                    isfinite(ctx.CRI) && ctx.CRI>=0 && ctx.CRI==fix(ctx.CRI), ...
                    'sixgr:abstraction:CSIRSReferenceIdentity','Name the independently scheduled desired CSI resource.');
                due=obj.committedCSIRSEmissions(ctx.TTI);
                assert(~isempty(due) && nnz([due.ServingCellID]==ctx.ServingCellID & [due.CRI]==ctx.CRI)==1, ...
                    'sixgr:abstraction:CSIRSReferenceIdentity','The desired CSI observation requires one committed native source.');
            end
            opposite="UL"; nr=obj.Policy.uePorts;
            if direction=="UL", opposite="DL"; nr=obj.Policy.bsPorts; end
            receiveCoords=window.Coordinates0Based;
            receiveCoords(:,2)=receiveCoords(:,2)+(ctx.TTI-firstTTI)*carrier.SymbolsPerSlot;
            entity='ue'; if direction=="UL", entity='bs'; end
            noise=10^((obj.Policy.noiseDensity_dBmHz+10*log10(1000*carrier.SubcarrierSpacing)+ ...
                obj.Cfg.scenario.(entity).noiseFigure_dB-30)/10);
            external=repmat(noise*eye(nr),1,1,size(receiveCoords,1));
            desired=struct(); population=struct([]);
            for index=1:numel(states)
                state=states{index};
                assert(isempty(state.("Grants"+opposite)), ...
                    'sixgr:abstraction:CrossLinkUnsupported', ...
                    'A finite receive window containing opposite-direction grants needs BS-BS/UE-UE propagation.');
                grants=state.("Grants"+direction); cells=state.("GrantCells"+direction);
                maps={};
                if string(obj.Policy.sinrResourcePopulation)=="native_shared_channel_data_re"
                    maps=cell(1,numel(grants));
                    for j=1:numel(grants)
                        maps{j}=sixgr.system.abstraction.scheduledDataREMap(obj.Cfg,grants(j),state.TTI-1);
                    end
                end
                for j=1:numel(grants)
                    g=grants(j);
                    local=coordinates(g,carrier.NSizeGrid);
                    if ~isempty(maps), local=maps{j}.Coordinates0Based; end
                    if direction=="DL"
                        u=receiverUE; c=double(cells(j)); nt=obj.Policy.bsPorts;
                    else
                        u=sixgr.system.resolveGrantUEIndex(g); c=double(ctx.ServingCellID); nt=obj.Policy.uePorts;
                    end
                    W=precoder(g,nt);
                    power=obj.power(direction,sixgr.system.resolveGrantUEIndex(g),cells(j),g,local,grants,cells,state.LargeScaleState,maps);
                    source=local;
                    source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                    realization=obj.sampledWindowChannel(direction,u,c,states);
                    % Exact finite transfer, independently checked against
                    % native OFDM/FIR probes. This is not the diagonal model
                    % and must not omit previous-slot or disjoint-RE leakage.
                    result=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                        carrier,source,W,power,receiveCoords,realization,'Algorithm','fft_transfer');
                    isDesired=~referenceOnly && state.TTI==ctx.TTI && j==window.DesiredGrantIndex;
                    if isDesired
                        desired=result;
                    else
                        external=external+result.Covariance;
                    end
                    row=struct('SourceTTI',state.TTI,'ServingCellID',cells(j),'RNTI',g.RNTI,'UEIndex',sixgr.system.resolveGrantUEIndex(g), ...
                        'ChannelLinkUE',u,'ChannelLinkCell',c,'IsDesired',isDesired, ...
                        'SourceCoordinates0Based',source,'TransmitPowerPerRE_W',power, ...
                        'Precoder',W,'Covariance',result.Covariance);
                    population=[population row]; %#ok<AGROW>
                end
            end
            referenceResponse=complex(zeros(nr,size(receiveCoords,1)));
            referencePopulation=struct([]);
            csirsPopulation=struct([]);
            csirsResponse=complex(zeros(size(referenceResponse)));
            includeSRS=includesSRS(obj.Policy);
            if includeSRS
                for index=1:numel(states)
                    state=states{index}; emissions=obj.committedSRSEmissions(state.TTI);
                    for j=1:numel(emissions)
                        e=emissions(j); source=e.Coordinates0Based;
                        source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                        if ~finiteSymbolsOverlap(carrier,obj.OFDM,source,receiveCoords, ...
                                numel(states)*carrier.SymbolsPerSlot,obj.CPChannelSupport.TrimSamples,getPathFilters(obj.Template))
                            continue;
                        end
                        assert(direction=="UL",'sixgr:abstraction:CrossLinkUnsupported', ...
                            'SRS reaching a DL receive window requires a UE-to-UE channel; it cannot use reciprocal UE-to-BS propagation.');
                        % The observation is an ideal delayed SRS channel,
                        % not a noisy estimator. Its desired pilot is not an
                        % external interferer; other UEs/occasions still are.
                        if referenceOnly && state.TTI==ctx.TTI && e.UEIndex==ctx.UEIndex, continue; end
                        realization=obj.sampledWindowChannel("UL",e.UEIndex,ctx.ServingCellID,states);
                        r=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                            carrier,source,e.Precoder,e.TransmitPowerPerRE_W,receiveCoords,realization, ...
                            'Algorithm','fft_transfer','SourceSymbols',e.Symbols);
                        referenceResponse=referenceResponse+r.ExplicitSymbolResponse;
                        row=rmfield(e,{'Symbols','NativeSRSConfiguration'});
                        row.ReceiverCellID=ctx.ServingCellID;
                        row.ReceivedResponseSHA256=string(sixgr.phy.mimo.MatrixContract.digest(r.ExplicitSymbolResponse));
                        referencePopulation=[referencePopulation row]; %#ok<AGROW>
                    end
                end
            end
            if includesCSIRS(obj.Policy)
                for index=1:numel(states)
                    state=states{index}; emissions=obj.committedCSIRSEmissions(state.TTI);
                    for j=1:numel(emissions)
                        e=emissions(j); source=e.Coordinates0Based;
                        source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                        if ~finiteSymbolsOverlap(carrier,obj.OFDM,source,receiveCoords, ...
                                numel(states)*carrier.SymbolsPerSlot,obj.CPChannelSupport.TrimSamples,getPathFilters(obj.Template))
                            continue;
                        end
                        assert(direction=="DL",'sixgr:abstraction:CrossLinkUnsupported', ...
                            'CSI-RS reaching UL reception requires a BS-to-BS channel, not reciprocal UE-to-BS propagation.');
                        if referenceOnly && state.TTI==ctx.TTI && e.ServingCellID==ctx.ServingCellID
                            assert(isfield(ctx,'CRI'),'sixgr:abstraction:CSIRSReferenceIdentity', ...
                                'A CSI reference observation must name its desired CRI; do not exclude every serving-cell beam.');
                            if e.CRI==ctx.CRI, continue; end
                        end
                        realization=obj.sampledWindowChannel("DL",receiverUE,e.ServingCellID,states);
                        r=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                            carrier,source,e.Precoder,e.TransmitPowerPerRE_W,receiveCoords,realization, ...
                            'Algorithm','fft_transfer','SourceSymbols',e.Symbols);
                        csirsResponse=csirsResponse+r.ExplicitSymbolResponse;
                        row=rmfield(e,'Symbols'); row.ReceiverUEIndex=receiverUE;
                        row.ReceivedResponseSHA256=string(sixgr.phy.mimo.MatrixContract.digest(r.ExplicitSymbolResponse));
                        csirsPopulation=[csirsPopulation row]; %#ok<AGROW>
                    end
                end
            end
            pdcchPopulation=struct([]);
            pdcchResponse=complex(zeros(size(referenceResponse)));
            if includesPDCCH(obj.Policy)
                for index=1:numel(states)
                    state=states{index}; emissions=obj.committedPDCCHEmissions(state.TTI);
                    for j=1:numel(emissions)
                        e=emissions(j); source=e.Coordinates0Based;
                        source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                        if ~finiteSymbolsOverlap(carrier,obj.OFDM,source,receiveCoords, ...
                                numel(states)*carrier.SymbolsPerSlot,obj.CPChannelSupport.TrimSamples,getPathFilters(obj.Template))
                            continue;
                        end
                        assert(direction=="DL",'sixgr:abstraction:CrossLinkUnsupported', ...
                            'PDCCH reaching UL reception needs BS-to-BS propagation, not a reciprocal UE link.');
                        realization=obj.sampledWindowChannel("DL",receiverUE,e.ServingCellID,states);
                        r=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                            carrier,source,e.Precoder,e.TransmitPowerPerRE_W,receiveCoords,realization, ...
                            'Algorithm','fft_transfer','SourceSymbols',e.Symbols);
                        pdcchResponse=pdcchResponse+r.ExplicitSymbolResponse;
                        row=rmfield(e,{'Symbols','DCIBits','DCICodeword'});
                        row.ReceiverUEIndex=receiverUE;
                        row.ReceivedResponseSHA256=string(sixgr.phy.mimo.MatrixContract.digest(r.ExplicitSymbolResponse));
                        pdcchPopulation=[pdcchPopulation row]; %#ok<AGROW>
                    end
                end
            end
            ssbPopulation=struct([]);
            ssbResponse=complex(zeros(size(referenceResponse)));
            if includesSSB(obj.Policy)
                for index=1:numel(states)
                    state=states{index}; emissions=obj.committedSSBEmissions(state.TTI);
                    for j=1:numel(emissions)
                        e=emissions(j); source=e.Coordinates0Based;
                        source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                        if ~finiteSymbolsOverlap(carrier,obj.OFDM,source,receiveCoords, ...
                                numel(states)*carrier.SymbolsPerSlot,obj.CPChannelSupport.TrimSamples,getPathFilters(obj.Template))
                            continue;
                        end
                        assert(direction=="DL",'sixgr:abstraction:CrossLinkUnsupported', ...
                            'SSB reaching UL reception requires a BS-to-BS channel, not a reciprocal UE link.');
                        realization=obj.sampledWindowChannel("DL",receiverUE,e.ServingCellID,states);
                        r=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                            carrier,source,e.Precoder,e.TransmitPowerPerRE_W,receiveCoords,realization, ...
                            'Algorithm','fft_transfer','SourceSymbols',e.Symbols);
                        ssbResponse=ssbResponse+r.ExplicitSymbolResponse;
                        row=rmfield(e,{'Symbols','MIBTransportBits','BCHCodeword'});
                        row.ReceiverUEIndex=receiverUE;
                        row.ReceivedResponseSHA256=string(sixgr.phy.mimo.MatrixContract.digest(r.ExplicitSymbolResponse));
                        ssbPopulation=[ssbPopulation row]; %#ok<AGROW>
                    end
                end
            end
            pucchPopulation=struct([]);
            pucchResponse=complex(zeros(size(referenceResponse)));
            if includesPUCCH(obj.Policy)
                for index=1:numel(states)
                    state=states{index}; emissions=obj.committedPUCCHEmissions(state.TTI);
                    for j=1:numel(emissions)
                        e=emissions(j); source=e.Coordinates0Based;
                        source(:,2)=source(:,2)+(state.TTI-firstTTI)*carrier.SymbolsPerSlot;
                        if ~finiteSymbolsOverlap(carrier,obj.OFDM,source,receiveCoords, ...
                                numel(states)*carrier.SymbolsPerSlot,obj.CPChannelSupport.TrimSamples,getPathFilters(obj.Template))
                            continue;
                        end
                        assert(direction=="UL",'sixgr:abstraction:CrossLinkUnsupported', ...
                            'PUCCH reaching a DL receive window requires a UE-to-UE channel.');
                        realization=obj.sampledWindowChannel("UL",e.UEIndex,ctx.ServingCellID,states);
                        r=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
                            carrier,source,e.Precoder,e.TransmitPowerPerRE_W,receiveCoords,realization, ...
                            'Algorithm','fft_transfer','SourceSymbols',e.Symbols);
                        pucchResponse=pucchResponse+r.ExplicitSymbolResponse;
                        row=rmfield(e,'Symbols'); row.ReceiverCellID=ctx.ServingCellID;
                        row.ReceivedResponseSHA256=string(sixgr.phy.mimo.MatrixContract.digest(r.ExplicitSymbolResponse));
                        pucchPopulation=[pucchPopulation row]; %#ok<AGROW>
                    end
                end
            end
            referenceResponse=referenceResponse+csirsResponse+pdcchResponse+ssbResponse+pucchResponse;
            for k=1:size(receiveCoords,1)
                v=referenceResponse(:,k); external(:,:,k)=external(:,:,k)+v*v';
            end
            spatial=struct();
            if ~referenceOnly
                assert(~isempty(fieldnames(desired)),'sixgr:abstraction:NetworkPopulation','The committed desired grant was not evaluated.');
                spatial=sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR( ...
                    desired,external,obj.Cfg.system.linkAbstraction.receiverType);
            end
            observation=struct('DesiredObservation',desired,'ExternalCovariance',external, ...
                'SpatialResult',spatial,'Population',population,'ReceiveWindow',window, ...
                'Coordinates0Based',window.Coordinates0Based,'NoisePowerPerRE_W',noise, ...
                'SourceClassification',"modeled_committed_finite_window_shared_data", ...
                'LargeScaleTimePolicy',"received_sample_slot_piecewise_constant", ...
                'ResourcePopulation',string(obj.Policy.sinrResourcePopulation), ...
                'WithinWindowISIICIIncluded',true,'WaveformMeasured',false, ...
                'CommonControlInterferenceQualified',false,'ReferenceSignalInterferenceQualified',false, ...
                'FullNetworkInterferenceQualified',false,'DiagonalCalibrationCompatible',false, ...
                'StatisticalBLERQualified',false,'PrimaryStudyAccepted',false);
            observation.SRSInterferenceIncluded=includeSRS;
            observation.SRSEmissionPopulation=referencePopulation;
            observation.CSIRSInterferenceIncluded=includesCSIRS(obj.Policy);
            observation.CSIRSEmissionPopulation=csirsPopulation;
            observation.ExplicitCSIRSResponse=csirsResponse;
            observation.PDCCHInterferenceIncluded=includesPDCCH(obj.Policy);
            observation.PDCCHEmissionPopulation=pdcchPopulation;
            observation.ExplicitPDCCHResponse=pdcchResponse;
            observation.SSBInterferenceIncluded=includesSSB(obj.Policy);
            observation.SSBEmissionPopulation=ssbPopulation;
            observation.ExplicitSSBResponse=ssbResponse;
            observation.PUCCHInterferenceIncluded=includesPUCCH(obj.Policy);
            observation.PUCCHEmissionPopulation=pucchPopulation;
            observation.ExplicitPUCCHResponse=pucchResponse;
            observation.ExplicitReferenceResponse=referenceResponse;
            observation.ReferenceObservationOnly=referenceOnly;
            if referenceOnly
                observation.SourceClassification="modeled_shared_data_interference_at_reference_resources";
            end
            if includeSRS
                observation.SourceClassification="modeled_committed_finite_window_shared_data_and_srs";
            end
            if includesCSIRS(obj.Policy)
                observation.SourceClassification="modeled_committed_finite_window_shared_data_and_srs_and_csirs";
            end
            if includesPDCCH(obj.Policy)
                observation.SourceClassification="modeled_committed_finite_window_shared_data_and_srs_and_csirs_and_pdcch";
            end
            if includesSSB(obj.Policy)
                observation.SourceClassification=observation.SourceClassification+"_and_ssb";
            end
            if includesPUCCH(obj.Policy)
                observation.SourceClassification=observation.SourceClassification+"_and_pucch";
            end
        end
        function observations=observeCSI(obj,state)
            created=obj.prepareCSIObservations(state);
            observations=obj.completeReferenceFeedback("CSI",created,state);
        end
        function pending=referenceFeedbackPending(obj)
            % Audit-only pending observations, never fabricated completions.
            pending=table();
            for k=1:numel(obj.PendingReferenceFeedback)
                item=obj.PendingReferenceFeedback{k}; o=item.Observation;
                support=obj.receiveSupport(o.SourceAbsoluteSlot0,o.Coordinates0Based);
                row=table(string(o.ObservationID),item.Kind,o.UEIndex,o.ServingCell, ...
                    o.SourceAbsoluteSlot0,obj.ScheduledHistory.CommittedThroughTTI-1, ...
                    o.SourceAbsoluteSlot0+support.RequiredFollowingSlots, ...
                    "awaiting_committed_receive_window",false, ...
                    'VariableNames',{'ObservationID','ReferenceKind','UEIndex','ServingCell', ...
                    'SourceAbsoluteSlot0','LastCommittedAbsoluteSlot0','RequiredThroughAbsoluteSlot0', ...
                    'Status','WaveformBacked'});
                pending=[pending;row]; %#ok<AGROW>
            end
        end
        function observations=prepareCSIObservations(obj,state)
            observations=struct([]);
            p=obj.Cfg.system.linkAbstraction.dlFeedback;
            assert(any(string(p.disturbanceAssumption)==["thermal_noise_only","finite_committed_shared_data"]) && ...
                (~isempty(obj.CSIBases) || p.panel.Ports==obj.Policy.bsPorts), ...
                'sixgr:abstraction:DLCSIPortBasis', ...
                'Require matching CSI/PDSCH/channel ports and an explicit supported CSI disturbance policy.');
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
                    emitted=struct([]);
                    if includesCSIRS(obj.Policy)
                        population=obj.committedCSIRSEmissions(state.TTI);
                        assert(~isempty(population),'sixgr:abstraction:CSIRSReferenceIdentity', ...
                            'A CSI reservation cannot replace a missing native transmission.');
                        selected=find([population.ServingCellID]==c & [population.CRI]==cri);
                        assert(isscalar(selected),'sixgr:abstraction:CSIRSReferenceIdentity', ...
                            'A calendar row cannot create CSI feedback without its committed native emitter.');
                        emitted=population(selected);
                        assert(isequal(sortrows(coords),sortrows(emitted.Coordinates0Based)), ...
                            'sixgr:abstraction:CSIRSReferenceIdentity', ...
                            'CSI observation and emitted resource must use the same RE population.');
                    end
                    B=eye(obj.Policy.bsPorts);
                    if ~isempty(obj.CSIBases), B=obj.CSIBases(:,:,cri+1); end
                    logicalH=zeros(size(H,1),size(B,2),size(H,3),'like',H);
                    for k=1:size(H,3), logicalH(:,:,k)=H(:,:,k)*B; end
                    id=obj.Cfg.phy.frame.DefaultIdentity;
                    assert(isfield(state,'RNTIByUE') && numel(state.RNTIByUE)==numel(state.ServingCells), ...
                        'sixgr:abstraction:MissingUEIdentity','CSI report obligations require the committed protocol identity map.');
                    ue=struct('UEID',u,'RNTI',state.RNTIByUE(u),'ServingCell',c,'PUCCHCell',c, ...
                        'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
                    reportCfg=obj.Cfg;
                    if ~isempty(obj.UCIResources)
                        reportCfg=obj.UCIResources.configForUE(ue);
                    else
                        assert(string(sixgr.util.structGet(obj.Cfg, ...
                            'system.linkAbstraction.dynamicPUCCH.resourceBinding.mode','shared_configured_resources')) ...
                            ~="per_cell_frequency_pool",'sixgr:abstraction:UCIResourceBinding', ...
                            'Per-UE CSI reports require installed UCI resource ownership.');
                    end
                    referenceAvailable=slot+p.deliveryDelaySlots;
                    if string(p.disturbanceAssumption)=="finite_committed_shared_data"
                        ctx=struct('TTI',slot+1,'Direction',"DL",'UEIndex',u,'ServingCellID',c);
                        [~,support]=obj.referenceReceptionAvailability(ctx,coords);
                        referenceAvailable=max(referenceAvailable,support.RequiredCommittedThroughTTI);
                    end
                    cal=sixgr.truth.buildPeriodicCSIReportObligations(reportCfg,ue,slot+1,slot+p.maximumAgeSlots+1);
                    eligible=cal.ULResourceAvailable & cal.CSIReferenceSlot>=slot+1 & ...
                        cal.ReportSlot-1>=referenceAvailable;
                    if ~any(eligible), continue; end
                    reportSlot0=min(cal.ReportSlot(eligible))-1;
                    power=state.LargeScaleState.TxPower_dBm(u,c);
                    o=struct('ObservationID',string(obj.Cfg.run.executionID)+"_csi_"+u+"_"+c+"_"+slot+"_"+cri, ...
                        'ExecutionID',string(obj.Cfg.run.executionID),'UEIndex',u,'RNTI',state.RNTIByUE(u),'ServingCell',c, ...
                        'SourceAbsoluteSlot0',slot,'AvailableAbsoluteSlot0',reportSlot0+1, ...
                        'ReportAbsoluteSlot0',reportSlot0,'ReferenceAvailableAtSlot0',referenceAvailable, ...
                        'ChannelEstimate',logicalH,'ExternalCovariance',noise*eye(size(H,1)), ...
                        'PortToElementMatrix',B,'PortBasisSHA256',string(sixgr.phy.mimo.MatrixContract.digest(B)), ...
                        'TotalTransmitPower',10^((power-30)/10)/(12*carrier.NSizeGrid), ...
                        'CRI',cri,'Coordinates0Based',coords, ...
                        'RFProfileID',string(obj.Policy.rfProfileID),'SourceClassification',string(p.sourceClassification));
                    if ~isempty(emitted)
                        o.ReferenceResourceID=emitted.ResourceID;
                        o.ReferenceEmissionSHA256=emitted.SHA256;
                    end
                    if logical(sixgr.util.structGet(obj.Cfg, ...
                            'system.linkAbstraction.dynamicPUCCH.powerReference.enabled',false))
                        o.ModeledPowerReference=sixgr.system.abstraction.modelCSIRSPowerReference(obj.Cfg,o,emitted);
                    end
                    observations=[observations o]; %#ok<AGROW>
                end
            end
        end
        function observations=observeSRS(obj,state)
            created=obj.prepareSRSObservations(state);
            observations=obj.completeReferenceFeedback("SRS",created,state);
        end
        function observations=prepareSRSObservations(obj,state)
            observations=struct([]);
            assert(logical(sixgr.util.structGet(obj.Cfg,'phy.srs.enable',false)), ...
                'sixgr:abstraction:NetworkSRSDisabled','Enable configured SRS occasions before enabling modeled SRS feedback.');
            assert(any(string(obj.Policy.soundingRankReference)==["full_carrier_pusch_thermal_noise_only", ...
                "full_carrier_pusch_finite_shared_data_interference"]), ...
                'sixgr:abstraction:NetworkSoundingPolicy','Declare the rank-reference power/interference assumption.');
            delay=obj.Policy.srsDeliveryDelaySlots;
            validateattributes(delay,{'numeric'},{'scalar','integer','positive','finite'});
            for u=1:numel(state.ServingCells)
            c=state.ServingCells(u);
            userCfg=obj.Cfg;
            bindingCatalog=sixgr.util.structGet(obj.Cfg,'phy.srs.ueResourceBindings',[]);
            scenarioCatalog=sixgr.util.structGet(obj.Cfg, ...
                'lls6g.reference_signals.srs.ue_resource_bindings',[]);
            if ~isempty(bindingCatalog) || ~isempty(scenarioCatalog)
                assert(isfield(state,'RNTIByUE') && numel(state.RNTIByUE)==numel(state.ServingCells), ...
                    'sixgr:abstraction:SRSReferenceIdentity', ...
                    'UE-specific SRS resources require the actual installed protocol identities.');
                userCfg=sixgr.phy.srs.bindConfiguredUEFrequencyResource( ...
                    obj.Cfg,u,state.RNTIByUE(u),c);
            end
            strict=sixgr.phy.srs.buildSRSConfigFromScenario(userCfg);
            sri=sixgr.system.abstraction.singleSRSResourceIndicator(strict);
            srs=strict.ToolboxSRS; slot=state.AbsoluteSlot0;
            assert(isnumeric(srs.SRSPeriod) && numel(srs.SRSPeriod)==2 && srs.NumSRSPorts==obj.Policy.uePorts, ...
                'sixgr:abstraction:NetworkSRSConfig','Use configured periodic SRS covering all UE transmit ports.');
            if mod(slot-srs.SRSPeriod(2),srs.SRSPeriod(1))~=0, continue; end
            slots=sixgr.util.structGet(obj.Cfg,'phy.srs.slotNumbers',[]);
            if ~isempty(slots) && ~ismember(slot,slots), continue; end
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
                H=obj.channel("UL",u,c,slot,state.LargeScaleState,coords);
                emitted=struct([]);
                if includesSRS(obj.Policy)
                    population=obj.committedSRSEmissions(state.TTI);
                    assert(~isempty(population),'sixgr:abstraction:SRSReferenceIdentity', ...
                        'A sounding calendar cannot replace a missing native SRS emission.');
                    selected=find([population.UEIndex]==u & [population.ServingCellID]==c & ...
                        [population.ResourceID]==double(strict.ResourceId));
                    assert(isscalar(selected),'sixgr:abstraction:SRSReferenceIdentity', ...
                        'Bind exactly one committed native SRS from the observed UE, cell and resource.');
                    emitted=population(selected);
                    assert(emitted.RNTI==state.RNTIByUE(u) && emitted.AbsoluteSlot0==slot && ...
                        isequal(sortrows(coords),sortrows(emitted.Coordinates0Based)), ...
                        'sixgr:abstraction:SRSReferenceIdentity', ...
                        'The sounding observation must retain the emitted RNTI, slot and RE population.');
                end
                tx=obj.Cfg.scenario.ue.txPower_dBm; if ~isscalar(tx), tx=tx(u); end
                available=slot+delay;
                if string(obj.Policy.soundingRankReference)=="full_carrier_pusch_finite_shared_data_interference"
                    ctx=struct('TTI',slot+1,'Direction',"UL",'UEIndex',u,'ServingCellID',c);
                    [~,support]=obj.referenceReceptionAvailability(ctx,coords);
                    available=max(available,support.RequiredCommittedThroughTTI);
                end
                o=struct('ObservationID',string(obj.Cfg.run.executionID)+"_srs_"+u+"_"+c+"_"+slot, ...
                    'ExecutionID',string(obj.Cfg.run.executionID),'ChannelOwnerID',"reciprocal_link_"+u+"_"+c, ...
                    'UEIndex',u,'ServingCell',c,'SourceAbsoluteSlot0',slot,'AvailableAbsoluteSlot0',available, ...
                    'SRI',sri,'ChannelEstimate',H,'ExternalCovariance',noise*eye(size(H,1)), ...
                    'TotalPUSCHPower',10^((tx-30)/10)/(12*carrier.NSizeGrid), ...
                    'SourceClassification',"modeled_srs_not_waveform_measurement", ...
                    'ReceiverType',string(obj.Cfg.system.linkAbstraction.receiverType), ...
                    'EstimationAssumption',"ideal_delayed_channel_estimate", ...
                    'RFProfileID',string(obj.Policy.rfProfileID), ...
                    'RankReferenceAssumption',string(obj.Policy.soundingRankReference), ...
                    'Coordinates0Based',coords);
                if ~isempty(emitted)
                    o.ReferenceResourceID=emitted.ResourceID;
                    o.ReferenceEmissionSHA256=emitted.SHA256;
                    o.ReferenceRNTI=emitted.RNTI;
                end
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
                startSample=sixgr.phy.frame.slotStartSample(obj.Carrier,slot,obj.OFDM.SampleRate);
                stopSample=sixgr.phy.frame.slotStartSample(obj.Carrier,slot+1,obj.OFDM.SampleRate);
                ch.InitialTime=startSample/obj.OFDM.SampleRate;
                carrier=obj.Carrier; carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
                % Match the calibration predictor's nominal FFT plane.
                % Native direct 'ofdm-response' uses a different temporal
                % response reduction on moving channels. Generate the same
                % path snapshots and padding as the waveform invocation,
                % then reconstruct at the implementation-filter trim only.
                % Physical synchronization/decoding errors remain in BLER;
                % this modeled channel is never passed into the receiver.
                nativeInfo=info(ch);
                trim=double(nativeInfo.ChannelFilterDelay);
                pad=round(trim+ceil(max(double(nativeInfo.PathDelays))*obj.OFDM.SampleRate));
                ofdm=nrOFDMInfo(carrier);
                ch.NumTimeSamples=stopSample-startSample+pad;
                [gains,times]=ch();
                response=nrPerfectChannelEstimate(carrier,gains,getPathFilters(ch), ...
                    trim,times,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate, ...
                    'CyclicPrefixFraction',0.5);
                response=response(:,1:carrier.SymbolsPerSlot,:,:);
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
        function observations=completeReferenceFeedback(obj,kind,created,state)
            finite=string(obj.Policy.soundingRankReference)=="full_carrier_pusch_finite_shared_data_interference";
            direction="UL"; clock="LastSRSObservationSlot0";
            if kind=="CSI"
                finite=string(obj.Cfg.system.linkAbstraction.dlFeedback.disturbanceAssumption)=="finite_committed_shared_data";
                direction="DL"; clock="LastCSIObservationSlot0";
            end
            observations=created;
            if ~finite, return; end
            now=state.AbsoluteSlot0;
            assert(state.TTI==now+1 && now>obj.(clock) && ...
                isequaln(state,obj.ScheduledHistory.scheduledState(state.TTI)), ...
                'sixgr:abstraction:FeedbackCaptureClock', ...
                'Finite reference capture requires a new actual committed population, not a scheduling preview.');
            for k=1:numel(created)
                o=created(k);
                ctx=struct('TTI',o.SourceAbsoluteSlot0+1,'Direction',direction, ...
                    'UEIndex',o.UEIndex,'ServingCellID',o.ServingCell);
                if kind=="CSI", ctx.CRI=o.CRI; end
                item=struct('Kind',kind,'Observation',o,'Context',ctx, ...
                    'SourceObservationSHA256',string(sixgr.util.sha256Hex( ...
                    uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(o)),'UTF-8')))));
                obj.PendingReferenceFeedback{end+1}=item;
            end
            observations=struct([]); keep=true(1,numel(obj.PendingReferenceFeedback));
            for k=1:numel(obj.PendingReferenceFeedback)
                item=obj.PendingReferenceFeedback{k};
                if item.Kind~=kind, continue; end
                o=item.Observation;
                [ready,support]=obj.referenceReceptionAvailability(item.Context,o.Coordinates0Based);
                if ~ready, continue; end
                assert(support.RequiredCommittedThroughTTI==state.TTI, ...
                    'sixgr:abstraction:FeedbackCaptureClock', ...
                    'A completed reference must be published at its first complete committed slot.');
                interference=obj.evaluateReferenceInterference(item.Context,o.Coordinates0Based);
                o.ExternalCovariance=interference.ExternalCovariance;
                o.CompletionAbsoluteSlot0=now;
                o.PublicationAbsoluteSlot0=now;
                o.DisturbanceAssumption="finite_committed_shared_data";
                o.ReferenceCompletionEvidence=struct('Support',support, ...
                    'ReceiveWindow',interference.ReceiveWindow, ...
                    'SourceObservationSHA256',item.SourceObservationSHA256, ...
                    'InterferencePopulation',string(obj.Policy.interferencePopulation), ...
                    'SRSInterferenceIncluded',interference.SRSInterferenceIncluded, ...
                    'SRSEmissionPopulation',interference.SRSEmissionPopulation, ...
                    'CSIRSInterferenceIncluded',interference.CSIRSInterferenceIncluded, ...
                    'CSIRSEmissionPopulation',interference.CSIRSEmissionPopulation, ...
                    'PDCCHInterferenceIncluded',interference.PDCCHInterferenceIncluded, ...
                    'PDCCHEmissionPopulation',interference.PDCCHEmissionPopulation, ...
                    'SSBInterferenceIncluded',interference.SSBInterferenceIncluded, ...
                    'SSBEmissionPopulation',interference.SSBEmissionPopulation, ...
                    'PUCCHInterferenceIncluded',interference.PUCCHInterferenceIncluded, ...
                    'PUCCHEmissionPopulation',interference.PUCCHEmissionPopulation, ...
                    'CommonControlInterferenceQualified',false,'ReferenceSignalInterferenceQualified',false, ...
                    'WaveformMeasured',false,'PrimaryStudyAccepted',false);
                sixgr.system.abstraction.validateFeedbackCompletionClock(o,now);
                observations=[observations o]; %#ok<AGROW>
                keep(k)=false;
            end
            obj.PendingReferenceFeedback=obj.PendingReferenceFeedback(keep);
            obj.(clock)=now;
        end
        function realization=sampledWindowChannel(obj,direction,u,c,states)
            % Same per-link seed and absolute clock as channel(). Sampling
            % densely also gives the exact constant trace at zero Doppler.
            seedText=string(obj.Cfg.run.seed)+"_network_link_"+u+"_"+c;
            hash=char(sixgr.util.sha256Hex(uint8(char(seedText))));
            ch=clone(obj.Template); release(ch);
            ch.RandomStream='mt19937ar with seed';
            ch.Seed=mod(hex2dec(hash(1:8)),2^32-1);
            ch.InitialTime=sixgr.phy.frame.slotStartSample(obj.Carrier, ...
                states{1}.TTI-1,obj.OFDM.SampleRate)/obj.OFDM.SampleRate;
            if isa(ch,'nrTDLChannel'), ch.PathGainSampleRate='signal'; else, ch.SampleDensity=Inf; end
            if direction=="UL", swapTransmitAndReceive(ch); end
            native=info(ch); trim=double(native.ChannelFilterDelay);
            cp=reshape(double(obj.OFDM.CyclicPrefixLengths),obj.Carrier.SymbolsPerSlot,[]);
            samples=zeros(1,numel(states));
            for k=1:numel(states)
                samples(k)=sum(obj.OFDM.Nfft+cp(:,mod(states{k}.TTI-1,size(cp,2))+1));
            end
            padding=trim+ceil(max(double(native.PathDelays))*obj.OFDM.SampleRate);
            ch.NumTimeSamples=sum(samples)+padding;
            [gains,times]=ch();
            assert(size(gains,1)==ch.NumTimeSamples, ...
                'sixgr:abstraction:FiniteOFDMSampleClock','Native path gains must cover every declared sample, without interpolation.');
            offset=0;
            for k=1:numel(states)
                loss=states{k}.LargeScaleState.Pathloss_dB(u,c);
                assert(isfinite(loss),'sixgr:abstraction:NetworkPathloss','Require the retained per-slot link loss.');
                count=samples(k); if k==numel(states), count=count+padding; end
                ix=offset+(1:count);
                gains(ix,:,:,:)=gains(ix,:,:,:).*10^(-loss/20);
                offset=offset+count;
            end
            realization=struct('PathFilters',getPathFilters(ch),'PathGains',gains,'SampleTimes',times, ...
                'SampleRateHz',double(obj.OFDM.SampleRate),'TrimSamples',trim, ...
                'NumberOfSymbols',numel(states)*double(obj.Carrier.SymbolsPerSlot), ...
                'Nfft',double(obj.OFDM.Nfft),'CyclicPrefixFraction',0.5);
        end
        function support=receiveSupport(obj,slot,coords)
            assert(~isempty(coords),'sixgr:abstraction:NetworkAllocation','A receive grant needs actual FFT symbols.');
            support=sixgr.phy.waveform.receiveSlotSupport(getPathFilters(obj.Template), ...
                obj.CPChannelSupport.TrimSamples,double(obj.OFDM.Nfft), ...
                double(obj.OFDM.CyclicPrefixLengths),double(obj.Carrier.SymbolsPerSlot), ...
                double(slot),double(unique(coords(:,2))),0.5);
        end
        function p=power(obj,direction,u,c,g,coords,grants,cells,largeScale,resourceMaps)
            n=size(coords,1);
            if direction=="DL"
                watts=10^((largeScale.TxPower_dBm(u,c)-30)/10);
                count=zeros(n,1);
                for j=1:numel(grants)
                    if cells(j)==c, count=count+resourceOverlap(coords,grants(j),resourceMaps,j); end
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
function yes=includesSRS(policy)
yes=any(string(policy.interferencePopulation)==["scheduled_shared_data_and_srs", ...
    "scheduled_shared_data_and_srs_and_csirs","scheduled_shared_data_and_srs_and_csirs_and_pdcch"]);
end
function yes=includesSSB(policy)
value=sixgr.util.structGet(policy,'ssbInterferenceEnabled',false);
assert((isnumeric(value)||islogical(value)) && isscalar(value) && isreal(value) && ...
    isfinite(value) && any(value==[0 1]), 'sixgr:abstraction:SSBEmissionPolicy', ...
    'networkSpatial.ssbInterferenceEnabled must be an explicit boolean.');
yes=logical(value);
end
function yes=includesPUCCH(policy)
value=sixgr.util.structGet(policy,'pucchInterferenceEnabled',false);
assert((isnumeric(value)||islogical(value)) && isscalar(value) && isreal(value) && ...
    isfinite(value) && any(value==[0 1]), 'sixgr:abstraction:PUCCHEmissionPolicy', ...
    'networkSpatial.pucchInterferenceEnabled must be an explicit boolean.');
yes=logical(value);
end
function assertSSBResources(cfg,state,ssb,csirs)
% Reserve the complete block, including zero-valued REs; only the actual
% occupied native symbols enter interference/power. Other cells may overlap.
for e=ssb
    reserved=e.ReservedCoordinates0Based;
    for rs=csirs
        if rs.ServingCellID~=e.ServingCellID, continue; end
        assert(~any(ismember(rs.Coordinates0Based,reserved,'rows')), ...
            'sixgr:abstraction:SSBCSIRSCollision', ...
            'Same-cell emitted CSI-RS overlaps the SS/PBCH block; correct its configured resource map.');
    end
    for k=1:numel(state.GrantsDL)
        if state.GrantCellsDL(k)~=e.ServingCellID, continue; end
        [map,carrier,pdsch]=sixgr.system.abstraction.scheduledDataREMap(cfg,state.GrantsDL(k),state.AbsoluteSlot0);
        dmrs=nrPDSCHDMRSIndices(carrier,pdsch); ptrs=nrPDSCHPTRSIndices(carrier,pdsch);
        pilot=double([dmrs(:);ptrs(:)])-1; K=12*carrier.NSizeGrid;
        pilots=[mod(pilot,K),mod(floor(pilot/K),carrier.SymbolsPerSlot)];
        assert(~any(ismember([map.Coordinates0Based;pilots],reserved,'rows')), ...
            'sixgr:abstraction:SSBDataCollision', ...
            'Same-cell PDSCH data/DM-RS/PT-RS must exclude the actual SS/PBCH block.');
    end
end
end
function yes=includesCSIRS(policy)
yes=any(string(policy.interferencePopulation)==["scheduled_shared_data_and_srs_and_csirs", ...
    "scheduled_shared_data_and_srs_and_csirs_and_pdcch"]);
end
function yes=includesPDCCH(policy)
yes=string(policy.interferencePopulation)=="scheduled_shared_data_and_srs_and_csirs_and_pdcch";
end
function overlap=finiteSymbolsOverlap(carrier,ofdm,source,receive,nsym,trim,filters)
% Only exact finite sample support can rule out an opposite-direction emitter.
% Use the same half-CP FFT clock as sampledWindowChannel, never slot labels.
cp=ofdm.CyclicPrefixLengths;
cp=cp(mod(carrier.NSlot*carrier.SymbolsPerSlot+(0:nsym-1),numel(cp))+1);
starts=[0 cumsum(ofdm.Nfft+cp(1:end-1))];
delays=find(any(filters~=0,2))-1; overlap=false;
for r=reshape(unique(receive(:,2)),1,[])
    first=starts(r+1)+fix(.5*cp(r+1))+trim;
    last=first+ofdm.Nfft-1;
    for s=reshape(unique(source(:,2)),1,[])
        if any(first-delays<starts(s+1)+cp(s+1)+ofdm.Nfft & last-delays>=starts(s+1))
            overlap=true; return;
        end
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
function mask=resourceOverlap(x,g,maps,index)
if isempty(maps)
    mask=overlap(x,g);
else
    mask=ismember(x,maps{index}.Coordinates0Based,'rows');
end
end
function yes=hasOverlap(grants,g)
yes=false;
for k=1:numel(grants)
    other=grants(k);
    yes=yes || (~isempty(intersect(other.PRBSet,g.PRBSet)) && ...
        max(other.SymbolAllocation(1),g.SymbolAllocation(1))<min(sum(other.SymbolAllocation),sum(g.SymbolAllocation)));
end
end
