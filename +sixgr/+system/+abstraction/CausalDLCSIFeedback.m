classdef CausalDLCSIFeedback < handle
    % Ideal delayed SLS CSI. NR codebook; explicitly study-owned objective.
    % Never a decoded waveform CSI record or a calibrated BLER result.
    properties (Access=private)
        Cfg struct
        Records cell = cell(0,1)
    end
    methods
        function obj=CausalDLCSIFeedback(cfg)
            p=cfg.system.linkAbstraction.dlFeedback;
            assert(string(p.codebook)=="typeI-SinglePanel" && ...
                string(p.selectionObjective)=="mean_sum_log2_one_plus_layer_sinr" && ...
                string(p.estimationAssumption)=="ideal_delayed_channel_estimate" && ...
                string(p.sourceClassification)=="modeled_csi_not_waveform_measurement", ...
                'sixgr:abstraction:DLCSIConfiguration','Install explicit supported modeled CSI policy.');
            validateattributes(p.maximumAgeSlots,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(p.deliveryDelaySlots,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(p.allowedRanks,{'numeric'},{'vector','integer','positive','finite'});
            request=sixgr.util.structGet(cfg,'phy.csi.reportConfiguration',struct());
            if ~isempty(fieldnames(request))
                report=sixgr.phy.mimo.CSIReportConfiguration(request,cfg.phy.csi.reportConfigurationEpoch);
                report.assertQualifiedWireLayout();
                assert(strcmpi(report.CodebookType,'typeI-SinglePanel') && ...
                    report.Ports==p.panel.Ports && all(ismember(p.allowedRanks,report.AllowedRanks)), ...
                    'sixgr:abstraction:DLCSIConfiguration','Modeled selector must match installed CSI codebook/ports/rank restriction.');
                if report.Ports>2
                    for f=["N1","N2","O1","O2","CodebookMode"]
                        assert(isequal(request.(f),p.panel.(f)), ...
                            'sixgr:abstraction:DLCSIConfiguration','Modeled panel %s differs from installed CSI configuration.',f);
                    end
                end
                for f=["CodebookSubsetRestriction","I2Restriction"]
                    if isfield(request,f), p.panel.(f)=request.(f); end
                end
                cfg.system.linkAbstraction.dlFeedback=p;
            end
            for r=p.allowedRanks(:).'
                request=p.panel; request.Rank=r;
                if request.Ports==2
                    sixgr.phy.mimo.TypeI2PortCodebook.enumerate(r);
                else
                    sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
                end
            end
            obj.Cfg=cfg;
        end
        function append(obj,o,now)
            p=obj.Cfg.system.linkAbstraction.dlFeedback;
            assert(o.SourceAbsoluteSlot0<=now && o.AvailableAbsoluteSlot0>o.SourceAbsoluteSlot0 && ...
                string(o.ExecutionID)==string(obj.Cfg.run.executionID) && ...
                string(o.SourceClassification)==string(p.sourceClassification), ...
                'sixgr:abstraction:DLCSIClock','CSI must have a causal source, delayed delivery and matching execution.');
            validateattributes([now o.SourceAbsoluteSlot0 o.AvailableAbsoluteSlot0],{'numeric'}, ...
                {'integer','nonnegative','finite','numel',3});
            validateattributes([o.UEIndex o.ServingCell],{'numeric'},{'integer','positive','finite','numel',2});
            digest=localHash(o);
            for k=1:numel(obj.Records)
                if obj.Records{k}.ObservationID==string(o.ObservationID)
                    assert(obj.Records{k}.ObservationDigest==digest,'sixgr:abstraction:DLCSIMutation','Observation identity changed.');
                    return;
                end
            end
            H=o.ChannelEstimate;
            assert(size(H,2)==p.panel.Ports,'sixgr:abstraction:DLCSIPortBasis', ...
                'CSI logical ports must match the explicit channel basis; no TXRU-to-port identity shortcut.');
            best=-Inf; selected=struct();
            for r=p.allowedRanks(:).'
                if r>size(H,1), continue; end
                req=p.panel; req.Rank=r;
                if req.Ports==2
                    matrices=sixgr.phy.mimo.TypeI2PortCodebook.enumerate(r); indices=0:size(matrices,3)-1;
                else
                    [matrices,indices]=sixgr.phy.mimo.TypeISinglePanelCodebook.enumerate(req);
                end
                for n=1:numel(indices)
                    W=matrices(:,:,n); W=W/norm(W,'fro');
                    if string(obj.Cfg.system.linkAbstraction.receiverType)=="zf"
                        feasible=true;
                        for q=1:size(H,3), feasible=feasible && rank(H(:,:,q)*W)>=r; end
                        if ~feasible, continue; end
                    end
                    s=sixgr.system.abstraction.evaluateSpatialSINR(H,W,o.TotalTransmitPower, ...
                        o.ExternalCovariance,obj.Cfg.system.linkAbstraction.receiverType);
                    value=mean(sum(log2(1+s.SINRLinear),2));
                    if value>best
                        best=value;
                        selected=struct('RI',r,'PMI',double(indices(n)),'CRI',o.CRI, ...
                            'MatrixPorts',W,'NumPorts',size(H,2),'ObjectiveValue',value, ...
                            'ModeledSINR_dB',10*log10(expm1(mean(log1p(s.SINRLinear),'all'))));
                    end
                end
            end
            assert(isfinite(best),'sixgr:abstraction:DLCSIRank','No supported observable rank.');
            cq=sixgr.link.resolveWidebandCQI(selected.ModeledSINR_dB,obj.Cfg,"DL");
            selected.CQI=cq.WidebandCQI;
            selected.CQIQualification="configured_mapping_not_statistically_qualified_here";
            selected.ReportAbsoluteSlot0=sixgr.util.structGet(o,'ReportAbsoluteSlot0',o.SourceAbsoluteSlot0);
            B=sixgr.util.structGet(o,'PortToElementMatrix',eye(size(H,2)));
            assert(size(B,2)==size(H,2) && all(isfinite(B),'all') && ...
                norm(B'*B-eye(size(H,2)),'fro')<1e-10, ...
                'sixgr:abstraction:DLCSIPortBasis','Require a power-preserving CSI port basis.');
            selected.PortToElementMatrix=B;
            selected.PortBasisSHA256=string(sixgr.phy.mimo.MatrixContract.digest(B));
            selected.MatrixElements=B*selected.MatrixPorts;
            for f=["ObservationID","ExecutionID","UEIndex","ServingCell","SourceAbsoluteSlot0", ...
                    "AvailableAbsoluteSlot0","RFProfileID","SourceClassification"]
                selected.(f)=o.(f);
            end
            selected.ObservationDigest=digest;
            selected.EstimationAssumption=string(p.estimationAssumption);
            selected.WaveformBacked=false;
            obj.Records{end+1}=selected;
        end
        function r=select(obj,ue,cellID,now,target)
            assert(now<=target,'sixgr:abstraction:DLCSIClock','No future knowledge.');
            r=[];
            for k=1:numel(obj.Records)
                x=obj.Records{k};
                if x.UEIndex~=ue || x.ServingCell~=cellID || x.AvailableAbsoluteSlot0>now || ...
                    target-x.SourceAbsoluteSlot0>obj.Cfg.system.linkAbstraction.dlFeedback.maximumAgeSlots, continue; end
                % Compare beams in the same report occasion even when the
                % configured sweep measured them in different source slots.
                % A repeated measurement of a CRI supersedes its older one.
                superseded=any(cellfun(@(y) y.UEIndex==ue && y.ServingCell==cellID && ...
                    y.CRI==x.CRI && y.ReportAbsoluteSlot0==x.ReportAbsoluteSlot0 && ...
                    y.SourceAbsoluteSlot0>x.SourceAbsoluteSlot0 && y.AvailableAbsoluteSlot0<=now,obj.Records));
                if superseded, continue; end
                if isempty(r) || x.ReportAbsoluteSlot0>r.ReportAbsoluteSlot0 || ...
                    (x.ReportAbsoluteSlot0==r.ReportAbsoluteSlot0 && x.ObjectiveValue>r.ObjectiveValue), r=x; end
            end
            if ~isempty(r)
                r.KnownAtAbsoluteSlot0=now; r.TargetAbsoluteSlot0=target;
                r.AgeSlots=target-r.SourceAbsoluteSlot0;
            end
        end
    end
    methods (Static)
        function validateGrant(cfg,g)
            r=g.ModeledCSIFeedback;
            replay=sixgr.phy.grant.isExplicitHARQRetransmission(g);
            assert(strcmpi(string(cfg.system.phyBackend),'calibrated_link_abstraction') && ...
                cfg.system.linkAbstraction.dlFeedback.enabled && ~r.WaveformBacked && ...
                r.SourceClassification=="modeled_csi_not_waveform_measurement" && ...
                string(r.ExecutionID)==string(cfg.run.executionID) && ...
                localHash(rmfield(r,'BindingSHA256'))==string(r.BindingSHA256) && ...
                r.RNTI==g.RNTI && r.RI==g.NumLayers && r.PMI==g.PMI && ...
                r.ServingCell==g.ServingCell && ...
                r.AvailableAbsoluteSlot0<=r.KnownAtAbsoluteSlot0 && r.KnownAtAbsoluteSlot0<=g.ControlAbsoluteSlot && ...
                r.SourceAbsoluteSlot0<r.AvailableAbsoluteSlot0 && ...
                r.TargetAbsoluteSlot0-r.SourceAbsoluteSlot0<=cfg.system.linkAbstraction.dlFeedback.maximumAgeSlots && ...
                (replay || (r.KnownAtAbsoluteSlot0==g.ControlAbsoluteSlot && r.TargetAbsoluteSlot0==g.ScheduledAbsoluteSlot)), ...
                'sixgr:abstraction:DLCSIBinding','Invalid, stale or mutated modeled CSI binding.');
            B=r.PortToElementMatrix;
            assert(string(sixgr.phy.mimo.MatrixContract.digest(B))==r.PortBasisSHA256 && ...
                isequal(r.MatrixElements,B*r.MatrixPorts), ...
                'sixgr:abstraction:DLCSIBinding','Physical beam composition changed after selection.');
            if string(sixgr.util.structGet(cfg,'system.linkAbstraction.networkSpatial.dlAntennaBasis','direct_ports'))=="configured_csirs_elements"
                configured=cfg.phy.csirs.precoderMatrices;
                assert(r.CRI>=0 && r.CRI==fix(r.CRI) && r.CRI<size(configured,3) && ...
                    isequal(B,configured(:,:,r.CRI+1)), ...
                    'sixgr:abstraction:DLCSIBinding','Selected CRI must retain its installed physical beam basis.');
            end
        end
    end
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(v)),'UTF-8'))));
end
