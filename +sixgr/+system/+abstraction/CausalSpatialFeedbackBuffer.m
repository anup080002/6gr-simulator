classdef CausalSpatialFeedbackBuffer < handle
    % Delayed modeled SRS, never a received waveform or decoded control.
    % Selection uses the NR UL codebook and per-resource colored disturbance.
    % The objective is an explicit study algorithm, not a mandated NR rule.
    properties (Access=private)
        Policy struct
        Records cell = cell(0,1)
        IDs string = strings(0,1)
    end
    methods
        function obj=CausalSpatialFeedbackBuffer(policy)
            required={'maximumAgeSlots','allowedRanks','selectionObjective','sourceClassification','estimationAssumption'};
            assert(isstruct(policy) && all(isfield(policy,required)), ...
                'sixgr:abstraction:FeedbackConfiguration','Install the complete spatialFeedback policy.');
            validateattributes(policy.maximumAgeSlots,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(policy.allowedRanks,{'numeric'},{'vector','integer','positive','finite'});
            assert(numel(unique(policy.allowedRanks))==numel(policy.allowedRanks) && ...
                string(policy.selectionObjective)=="mean_sum_log2_one_plus_layer_sinr" && ...
                string(policy.sourceClassification)=="modeled_srs_not_waveform_measurement" && ...
                string(policy.estimationAssumption)=="ideal_delayed_channel_estimate", ...
                'sixgr:abstraction:FeedbackConfiguration','Declare distinct ranks, objective and modeled provenance.');
            obj.Policy=policy;
        end
        function append(obj,o,knownSlot0)
            fields={'ObservationID','ExecutionID','ChannelOwnerID','UEIndex','ServingCell', ...
                'SourceAbsoluteSlot0','AvailableAbsoluteSlot0','SRI','ChannelEstimate', ...
                'ExternalCovariance','TotalPUSCHPower','SourceClassification','ReceiverType', ...
                'EstimationAssumption','RFProfileID'};
            assert(isstruct(o) && isscalar(o) && all(isfield(o,fields)), ...
                'sixgr:abstraction:FeedbackObservation','Incomplete modeled SRS observation.');
            validateattributes([o.UEIndex o.ServingCell],{'numeric'},{'integer','positive','finite','numel',2});
            validateattributes([o.SourceAbsoluteSlot0 o.AvailableAbsoluteSlot0 o.SRI knownSlot0], ...
                {'numeric'},{'integer','nonnegative','finite','numel',4});
            assert(o.SourceAbsoluteSlot0<=knownSlot0 && o.AvailableAbsoluteSlot0>o.SourceAbsoluteSlot0, ...
                'sixgr:abstraction:FeedbackClock','A produced SRS observation must precede its delivery.');
            assert(string(o.SourceClassification)==string(obj.Policy.sourceClassification) && ...
                string(o.EstimationAssumption)==string(obj.Policy.estimationAssumption), ...
                'sixgr:abstraction:FeedbackSource','Never label modeled feedback as a waveform measurement.');
            for f=["ObservationID","ExecutionID","ChannelOwnerID","RFProfileID"]
                assert(isscalar(string(o.(f))) && ~ismissing(string(o.(f))) && strlength(strtrim(string(o.(f))))>0, ...
                    'sixgr:abstraction:FeedbackIdentity','Feedback identities must be nonempty scalar text.');
            end
            digest=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(o)),'UTF-8'))));
            old=find(obj.IDs==string(o.ObservationID),1);
            if ~isempty(old)
                assert(obj.Records{old}.ObservationDigest==digest, ...
                    'sixgr:abstraction:FeedbackMutation','An observation ID cannot acquire different content.');
                return;
            end
            H=o.ChannelEstimate; nr=size(H,1); nt=size(H,2);
            ranks=sort(double(obj.Policy.allowedRanks)); ranks=ranks(ranks<=min(nr,nt));
            assert(~isempty(ranks),'sixgr:abstraction:FeedbackRank','No configured rank fits the observed link.');
            best=-Inf; selected=struct();
            for rank=ranks(:).'
                catalog=sixgr.phy.ul.puschCodebookCatalog(rank,nt,false);
                assert(catalog.Valid,'sixgr:abstraction:FeedbackCodebook','Unsupported configured rank/port combination.');
                for tpmi=double(catalog.ValidTPMISet)
                    % Native mapping is layers-by-ports. Normalize total
                    % power once; rank does not create extra transmit power.
                    W=double(nrPUSCHCodebook(rank,nt,tpmi)).';
                    W=W/norm(W,'fro');
                    if string(o.ReceiverType)=="zf"
                        observable=true;
                        for resource=1:size(H,3)
                            observable=observable && rankOf(H(:,:,resource)*W)>=rank;
                        end
                        if ~observable, continue; end
                    end
                    q=sixgr.system.abstraction.evaluateSpatialSINR(H,W,o.TotalPUSCHPower,o.ExternalCovariance,o.ReceiverType);
                    score=mean(sum(log2(1+q.SINRLinear),2));
                    if score>best
                        best=score;
                        selected=struct('RI',rank,'TPMI',tpmi,'SRI',double(o.SRI), ...
                            'NumPorts',nt,'ReceiveDimensions',nr,'MatrixPorts',W, ...
                            'SINRPerResourceLayer_dB',q.SINR_dB,'ObjectiveValue',score);
                    end
                end
            end
            assert(isfinite(best),'sixgr:abstraction:FeedbackNumerics','No finite spatial objective.');
            selected.ObservationID=string(o.ObservationID); selected.ObservationDigest=digest;
            for f=["ExecutionID","ChannelOwnerID","UEIndex","ServingCell","SourceAbsoluteSlot0", ...
                    "AvailableAbsoluteSlot0","SourceClassification","EstimationAssumption","RFProfileID","ReceiverType"]
                selected.(f)=o.(f);
            end
            selected.SelectionObjective=string(obj.Policy.selectionObjective);
            selected.RankReferenceAssumption=string(sixgr.util.structGet(o,'RankReferenceAssumption','observation_external_covariance'));
            selected.WaveformBacked=false;
            obj.Records{end+1,1}=selected; obj.IDs(end+1,1)=string(o.ObservationID);
        end
        function r=select(obj,ue,cellID,knownSlot0,targetSlot0)
            validateattributes([ue cellID],{'numeric'},{'integer','positive','finite','numel',2});
            validateattributes([knownSlot0 targetSlot0],{'numeric'},{'integer','nonnegative','finite','numel',2});
            assert(knownSlot0<=targetSlot0,'sixgr:abstraction:FeedbackClock','Future knowledge cannot schedule past data.');
            r=[];
            for k=1:numel(obj.Records)
                x=obj.Records{k};
                if x.UEIndex~=ue || x.ServingCell~=cellID || x.AvailableAbsoluteSlot0>knownSlot0 || ...
                        targetSlot0-x.SourceAbsoluteSlot0>obj.Policy.maximumAgeSlots
                    continue;
                end
                if isempty(r) || x.SourceAbsoluteSlot0>r.SourceAbsoluteSlot0
                    r=x;
                elseif x.SourceAbsoluteSlot0==r.SourceAbsoluteSlot0 && x.ObservationID~=r.ObservationID
                    error('sixgr:abstraction:AmbiguousFeedback','Equal-time SRS resources require an explicit selection policy.');
                end
            end
            if ~isempty(r)
                r.KnownAtAbsoluteSlot0=knownSlot0; r.TargetAbsoluteSlot0=targetSlot0;
                r.AgeSlots=targetSlot0-r.SourceAbsoluteSlot0;
            end
        end
    end
    methods (Static)
        function validateGrant(cfg,g,nLayers,nPorts,tpmi)
            r=g.ModeledSRSFeedback;
            assert(strcmpi(string(sixgr.util.structGet(cfg,'system.phyBackend','')),'calibrated_link_abstraction') && ...
                logical(sixgr.util.structGet(cfg,'system.linkAbstraction.spatialFeedback.enabled',false)), ...
                'sixgr:abstraction:FeedbackBackend','Modeled feedback cannot authorize a waveform-truth grant.');
            fields={'SourceClassification','EstimationAssumption','WaveformBacked','RNTI','RI','TPMI','SRI','NumPorts', ...
                'KnownAtAbsoluteSlot0','TargetAbsoluteSlot0','AvailableAbsoluteSlot0', ...
                'SourceAbsoluteSlot0','ExecutionID','BindingSHA256','RFProfileID'};
            assert(isstruct(r) && isscalar(r) && all(isfield(r,fields)), ...
                'sixgr:abstraction:FeedbackBinding','Retain the full modeled feedback binding.');
            assert(~logical(sixgr.util.structGet(g,'TransformPrecoding', ...
                sixgr.util.structGet(cfg,'phy.pusch.transformPrecoding',false))), ...
                'sixgr:abstraction:FeedbackWaveform','This modeled rank/TPMI selector supports CP-OFDM only.');
            hash=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(rmfield(r,'BindingSHA256'))),'UTF-8'))));
            assert(hash==string(r.BindingSHA256) && ...
                string(r.SourceClassification)=="modeled_srs_not_waveform_measurement" && ~r.WaveformBacked && ...
                string(r.EstimationAssumption)==string(cfg.system.linkAbstraction.spatialFeedback.estimationAssumption) && ...
                string(r.ExecutionID)==string(cfg.run.executionID) && r.RNTI==g.RNTI && ...
                r.RI==nLayers && ismember(r.RI,cfg.system.linkAbstraction.spatialFeedback.allowedRanks) && ...
                r.NumPorts==nPorts && r.TPMI==tpmi && r.SRI==g.SRI && ...
                r.KnownAtAbsoluteSlot0==g.ControlAbsoluteSlot && r.TargetAbsoluteSlot0==g.ScheduledAbsoluteSlot && ...
                r.SourceAbsoluteSlot0<r.AvailableAbsoluteSlot0 && r.AvailableAbsoluteSlot0<=g.ControlAbsoluteSlot && ...
                g.ScheduledAbsoluteSlot-r.SourceAbsoluteSlot0<=cfg.system.linkAbstraction.spatialFeedback.maximumAgeSlots, ...
                'sixgr:abstraction:FeedbackBinding','Stale, future, mutated or mismatched modeled SRS feedback.');
            rf=string(sixgr.util.structGet(cfg,'system.linkAbstraction.requiredRFProfileID',''));
            assert(strlength(rf)==0 || rf==string(r.RFProfileID), ...
                'sixgr:abstraction:RFProfileMismatch','Feedback uses another RF branch.');
        end
    end
end

function n=rankOf(matrix)
% Keep candidate feasibility separate from the issued-grant ZF guard.
n=rank(matrix);
end
