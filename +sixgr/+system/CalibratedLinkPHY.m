classdef CalibratedLinkPHY < handle
%CALIBRATEDLINKPHY Explicit SLS estimates, never waveform decoder truth.
% Each calibrated curve is keyed to physical/coding/allocation identity and
% an RV sequence. Retx probability is conditional on ALL previous failures,
% evaluated against the full effective-SINR history; not first-TX BLER reuse.
    properties (SetAccess=private)
        ExecutionBackend string = "CALIBRATED_LINK_ABSTRACTION"
        PHYMode string = "CONDITIONAL_BLER_SLS_ESTIMATE"
        LastReplay struct = struct()
        CalibrationID string
        CalibrationSHA256 string
        CalibrationQualified logical = false
        SpatialFeedbackTrace table = table()
        NetworkSpatialTrace table = table()
        DLCSITrace table = table()
        DLCSIReferences struct = struct([])
        FeedbackCaptureTrace table = table()
        PUCCHEmissionTrace table = table()
    end
    properties (Access=private)
        Cfg struct
        Curves struct
        Provider
        SlotContext struct = struct()
        Stream
        Processes
        ReceiverType string
        EffectiveSINRMethod string
        SpatialFeedbackBuffer = []
        DLCSIBuffer = []
        DynamicUCI = []
        LastFeedbackCaptureTTI (1,1) double = 0
    end
    methods
        function obj=CalibratedLinkPHY(cfg,params,seed)
            obj.Cfg=cfg;
            p=sixgr.util.structGet(cfg,'system.linkAbstraction',struct());
            required={'calibrationFile','calibrationSHA256','spatialProviderClass','receiverType','effectiveSINRMethod', ...
                'allowDevelopmentFixtures','minimumCalibrationTrials', ...
                'minimumCalibrationErrors','minimumValidationTrials', ...
                'calibrationConfidenceLevel','maximumCalibrationWilsonHalfWidth', ...
                'maximumValidationAbsoluteBLERError','outOfRangePolicy', ...
                'harqPolicy','resultClassification'};
            assert(all(isfield(p,required)), 'sixgr:abstraction:Configuration', ...
                'Install the explicit system.linkAbstraction configuration fragment.');
            assert(isscalar(string(p.receiverType)) && any(string(p.receiverType)==["lmmse","zf"]), ...
                'sixgr:abstraction:Configuration','Select an explicitly calibrated lmmse or zf receiver.');
            obj.ReceiverType=string(p.receiverType);
            obj.EffectiveSINRMethod=string(p.effectiveSINRMethod);
            assert(isscalar(obj.EffectiveSINRMethod) && ...
                any(obj.EffectiveSINRMethod==["calibrated_eesm","calibrated_miesm"]), ...
                'sixgr:abstraction:Configuration','Select calibrated EESM or tabulated MIESM explicitly.');
            assert(string(p.outOfRangePolicy)=="reject" && ...
                string(p.harqPolicy)=="conditional_error_given_prior_failures" && ...
                string(p.resultClassification)=="calibrated_sls_estimate_not_waveform_truth", ...
                'sixgr:abstraction:Configuration','No extrapolation, uncalibrated HARQ gain or truth relabeling is supported.');
            validateattributes(p.minimumCalibrationTrials,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(p.minimumCalibrationErrors,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(p.minimumValidationTrials,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(p.calibrationConfidenceLevel,{'numeric'},{'scalar','>',0,'<',1});
            validateattributes(p.maximumCalibrationWilsonHalfWidth,{'numeric'},{'scalar','>',0,'<',0.5});
            validateattributes(p.maximumValidationAbsoluteBLERError,{'numeric'},{'scalar','positive','<',1,'finite'});
            assert(islogical(p.allowDevelopmentFixtures) && isscalar(p.allowDevelopmentFixtures), ...
                'sixgr:abstraction:Configuration','allowDevelopmentFixtures must be an explicit boolean.');
            assert(isfile(p.calibrationFile) && strlength(string(p.calibrationSHA256))==64, ...
                'sixgr:abstraction:MissingCalibration','A retained calibration MAT and its frozen SHA256 are required.');
            obj.CalibrationSHA256=sixgr.csi.studyFileSHA256(string(p.calibrationFile));
            assert(strcmpi(obj.CalibrationSHA256,string(p.calibrationSHA256)), ...
                'sixgr:abstraction:CalibrationDigest','Calibration content changed after binding.');
            loaded=load(p.calibrationFile,'calibration');
            assert(isfield(loaded,'calibration'),'sixgr:abstraction:CalibrationSchema','Missing calibration variable.');
            data=loaded.calibration;
            assert(all(isfield(data,{'Schema','CalibrationID','SourceClassification','Curves'})) && ...
                any(string(data.Schema)==["sixgr.calibrated_sls_link/v1","sixgr.grant_calibrated_sls_link/v1"]) && ~isempty(data.Curves), ...
                'sixgr:abstraction:CalibrationSchema','Missing versioned calibrated curve population.');
            fixture=string(data.SourceClassification)=="development_fixture_not_physical_calibration";
            assert((fixture && p.allowDevelopmentFixtures) || ...
                string(data.SourceClassification)=="executed_waveform_calibration", ...
                'sixgr:abstraction:CalibrationSource','Only waveform-derived calibration is permitted outside explicit development fixtures.');
            if string(data.Schema)=="sixgr.grant_calibrated_sls_link/v1"
                assert(~fixture,'sixgr:abstraction:CalibrationSource','Grant-backed packages cannot contain development fixtures.');
                sixgr.system.abstraction.validateGrantCalibrationPackage(data,p.calibrationFile,p);
            elseif ~fixture
                sixgr.system.abstraction.validateCalibrationSources(data,p.calibrationFile);
            end
            obj.CalibrationID=string(data.CalibrationID);
            assert(isscalar(obj.CalibrationID) && strlength(strtrim(obj.CalibrationID))>0, ...
                'sixgr:abstraction:CalibrationSchema','A nonempty calibration identity is required.');
            obj.Curves=data.Curves;
            ids=strings(numel(obj.Curves),1);
            for k=1:numel(obj.Curves)
                c=obj.Curves(k);
                sixgr.system.abstraction.validateBLERCurve(c,p);
                if ~fixture
                    assert(isfield(c.Key,'MCSTable') && isfield(c.Key,'MCSIndex') && ...
                        strlength(strtrim(string(c.Key.MCSTable)))>0 && ...
                        isscalar(c.Key.MCSIndex) && isfinite(double(c.Key.MCSIndex)) && ...
                        double(c.Key.MCSIndex)>=0, ...
                        'sixgr:abstraction:CalibrationMCSIdentity', ...
                        'Production BLER curves require an installed MCS table and index.');
                end
                ids(k)=string(jsonencode(c.Key))+"|"+string(jsonencode(c.RVSequence));
                if isfield(c,'HARQSlotOffsets0')
                    ids(k)=ids(k)+"|"+string(jsonencode(c.HARQSlotOffsets0));
                end
            end
            assert(numel(unique(ids))==numel(ids),'sixgr:abstraction:DuplicateCalibration', ...
                'Multiple curves cannot own the same physical key and RV history.');
            curveIDs=string({obj.Curves.CurveID});
            assert(all(strlength(strtrim(curveIDs))>0) && numel(unique(curveIDs))==numel(curveIDs), ...
                'sixgr:abstraction:DuplicateCalibration','Curve identifiers must be nonempty and unique.');
            obj.CalibrationQualified=~fixture;
            % Parameters inject only a provider object, never a BLER override.
            % Production class identity must agree with resolved YAML policy.
            obj.Provider=sixgr.util.structGet(params,'SpatialGrantProvider',[]);
            if isempty(obj.Provider) && strlength(string(p.spatialProviderClass))>0
                obj.Provider=feval(char(p.spatialProviderClass),cfg);
            end
            assert(isa(obj.Provider,'sixgr.system.abstraction.SpatialGrantProvider') && ...
                string(class(obj.Provider))==string(p.spatialProviderClass), ...
                'sixgr:abstraction:SpatialProvider','A YAML-bound spatial producer must supply actual scheduled-link model inputs.');
            obj.Stream=RandStream('mt19937ar','Seed',seed);
            obj.Processes=containers.Map('KeyType','char','ValueType','any');
            if logical(sixgr.util.structGet(p,'spatialFeedback.enabled',false))
                obj.SpatialFeedbackBuffer=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(p.spatialFeedback);
            end
            if logical(sixgr.util.structGet(p,'dlFeedback.enabled',false))
                obj.DLCSIBuffer=sixgr.system.abstraction.CausalDLCSIFeedback(cfg);
            end
        end
        function bindDynamicUCI(obj,ledger)
            assert(isa(ledger,'sixgr.system.SLSDynamicPUCCH'),'sixgr:abstraction:UCIClock','Require the runtime UCI ledger.');
            obj.DynamicUCI=ledger;
            if ismethod(obj.Provider,'bindUCIResources'), obj.Provider.bindUCIResources(ledger); end
        end
        function captureCommittedSpatialFeedback(obj)
            % Observe only after the actual scheduled population is frozen.
            % Pre-scheduling selection must not ask a producer to evaluate
            % current-slot interference against an unfinished population.
            if isempty(obj.DLCSIBuffer) && isempty(obj.SpatialFeedbackBuffer), return; end
            state=obj.SlotContext;
            assert(all(isfield(state,{'TTI','AbsoluteSlot0','ServingCells', ...
                'GrantsDL','GrantsUL','GrantCellsDL','GrantCellsUL','LargeScaleState'})) && ...
                state.AbsoluteSlot0==state.TTI-1 && state.TTI==obj.LastFeedbackCaptureTTI+1, ...
                'sixgr:abstraction:FeedbackCaptureClock', ...
                'Capture once per committed slot, in order, including idle slots; never from a scheduler preview.');
            csi=struct([]); srs=struct([]);
            if ~isempty(obj.DLCSIBuffer), csi=obj.Provider.observeCSI(state); end
            if ~isempty(obj.SpatialFeedbackBuffer), srs=obj.Provider.observeSRS(state); end
            for k=1:numel(csi)
                o=csi(k);
                sixgr.system.abstraction.validateFeedbackCompletionClock(o,state.AbsoluteSlot0);
                obj.DLCSIBuffer.append(o,state.AbsoluteSlot0);
                ref=struct('UEIndex',o.UEIndex,'ServingCell',o.ServingCell, ...
                    'SourceAbsoluteSlot0',o.SourceAbsoluteSlot0,'ReportAbsoluteSlot0',o.ReportAbsoluteSlot0, ...
                    'ReferenceAvailableAtSlot0',o.ReferenceAvailableAtSlot0);
                obj.DLCSIReferences=[obj.DLCSIReferences ref];
            end
            for k=1:numel(srs)
                o=srs(k);
                sixgr.system.abstraction.validateFeedbackCompletionClock(o,state.AbsoluteSlot0);
                sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateReferenceEmission(obj.Cfg,o);
                assert(string(o.ExecutionID)==string(obj.Cfg.run.executionID), ...
                    'sixgr:abstraction:FeedbackIdentity','The SRS producer belongs to another execution.');
                assert(strcmpi(string(o.ReceiverType),string(obj.Cfg.system.linkAbstraction.receiverType)), ...
                    'sixgr:abstraction:FeedbackReceiver','Rank selection must use the configured receive algorithm.');
                obj.SpatialFeedbackBuffer.append(o,state.AbsoluteSlot0);
            end
            obj.LastFeedbackCaptureTTI=state.TTI;
            row=table(state.TTI,state.AbsoluteSlot0,numel(state.GrantsDL),numel(state.GrantsUL), ...
                numel(csi),numel(srs),"after_committed_scheduled_population",false, ...
                'VariableNames',{'TTI','CaptureAbsoluteSlot0','CommittedDLGrants','CommittedULGrants', ...
                'CSIObservations','SRSObservations','CapturePhase','WaveformBacked'});
            row.DeferredCSICompletions=sum(arrayfun(@(o)o.SourceAbsoluteSlot0<state.AbsoluteSlot0,csi));
            row.DeferredSRSCompletions=sum(arrayfun(@(o)o.SourceAbsoluteSlot0<state.AbsoluteSlot0,srs));
            obj.FeedbackCaptureTrace=[obj.FeedbackCaptureTrace;row];
        end
        function pending=pendingReferenceFeedback(obj)
            pending=table();
            if ismethod(obj.Provider,'referenceFeedbackPending')
                pending=obj.Provider.referenceFeedbackPending();
            end
        end
        function payload=csiPayloadAtSlotStart(obj,ue,cellID,reportSlot,now)
            assert(~isempty(obj.DLCSIBuffer),'sixgr:abstraction:DLCSIReportDisabled', ...
                'CSI waveform payloads require the configured causal modeled CSI producer.');
            payload=obj.DLCSIBuffer.reportForTransmission(ue,cellID,reportSlot,now);
        end
        function reference=pucchPowerReferenceAtSlotStart(obj,ue,cellID,now)
            assert(~isempty(obj.DLCSIBuffer),'sixgr:abstraction:PowerReferencePolicy', ...
                'Native PUCCH modeled power requires the causal CSI reference producer.');
            reference=obj.DLCSIBuffer.powerReferenceAtSlotStart(ue,cellID,now);
        end
        function prepared=preparePUCCHAtSlotStart(obj,obligation,now)
            assert(~isempty(obj.DynamicUCI),'sixgr:abstraction:MissingUCILedger', ...
                'Bind the production UCI ledger before preparing modeled feedback.');
            csi=struct();
            if obligation.Transport=="PUCCH" && obligation.CSIPart1Bits+obligation.CSIPart2Bits>0
                csi=obj.csiPayloadAtSlotStart(obligation.UEIndex,obligation.CellID, ...
                    obligation.AbsoluteSlot0,now);
            end
            prepared=obj.DynamicUCI.preparePUCCHAtSlotStart(obligation,now,csi);
        end
        function [prepared,emission,tx]=generatePUCCHAtSlotStart(obj,obligation,now)
            assert(~isempty(obj.DynamicUCI),'sixgr:abstraction:MissingUCILedger', ...
                'Bind the production UCI ledger before generating modeled-control symbols.');
            csi=struct();
            if obligation.Transport=="PUCCH" && obligation.CSIPart1Bits+obligation.CSIPart2Bits>0
                csi=obj.csiPayloadAtSlotStart(obligation.UEIndex,obligation.CellID, ...
                    obligation.AbsoluteSlot0,now);
            end
            reference=struct();
            if obligation.Transport=="PUCCH" && logical(sixgr.util.structGet(obj.Cfg, ...
                    'system.linkAbstraction.dynamicPUCCH.powerReference.enabled',false))
                reference=obj.pucchPowerReferenceAtSlotStart(obligation.UEIndex,obligation.CellID,now);
            end
            [prepared,emission,tx]=obj.DynamicUCI.generatePUCCHAtSlotStart( ...
                obligation,now,csi,reference);
        end
        function state=materializeUCIPopulation(obj,state,issued)
            % Called after transport/grant selection and BEFORE committing
            % this slot. No current-slot received samples or ACKs exist yet.
            assert(~isempty(obj.DynamicUCI) && state.TTI==state.AbsoluteSlot0+1 && ...
                state.AbsoluteSlot0==obj.LastFeedbackCaptureTTI, ...
                'sixgr:abstraction:PUCCHPopulationClock','Generate once against prior completed feedback and the current final grant population.');
            now=state.AbsoluteSlot0;
            due=obj.DynamicUCI.snapshot(now,now,state.ServingCells,obj.DLCSIReferences);
            obj.DynamicUCI.assertPUSCHExecution(state.GrantsUL,state.GrantCellsUL,due,now);
            emissions=struct([]); audit=table();
            for k=1:numel(due)
                o=due(k); digest=""; native=false; replacement="";
                srKnown=o.SRBits==0; positiveSR=NaN;
                if srKnown, positiveSR=0; end
                if o.Transport=="PUSCH"
                    sixgr.system.validateSLSPUSCHUCIReservation(o, ...
                        struct('AsOfAbsoluteSlot0',now,'IssuedPUSCHGrants',{issued}));
                    hashes=cellfun(@localGrantDigest,num2cell(state.GrantsUL),'UniformOutput',false);
                    assert(nnz(string(hashes)==o.PUSCHGrantSHA256)==1, ...
                        'sixgr:system:SLSUCINotExecuted','A selected but absent PUSCH cannot replace a PUCCH emission.');
                    replacement=o.PUSCHGrantSHA256;
                    disposition="validated_PUSCH_transport_no_PUCCH_emission";
                else
                    [prepared,e]=obj.generatePUCCHAtSlotStart(o,now);
                    assert(prepared.Available,'sixgr:abstraction:PUCCHMissingProducer', ...
                        'Obligation %s has no causal payload producer: %s.',o.ResourceID,prepared.Status);
                    if o.SRBits>0
                        srKnown=prepared.SREvidence.Available;
                        positiveSR=numel(prepared.SREvidence.PositiveSchedulingRequestIDs);
                    end
                    if isempty(e)
                        assert(prepared.Status=="negative_SR_no_transmission" && ...
                            o.HARQBits+o.CSIPart1Bits+o.CSIPart2Bits==0 && o.SRBits>0, ...
                            'sixgr:abstraction:PUCCHMissingProducer','Only an owned negative standalone SR is silent.');
                        disposition="owned_negative_SR_no_transmission";
                    else
                        assert(isscalar(e),'sixgr:abstraction:PUCCHEmissionPopulation','One obligation must produce one actual PUCCH emission.');
                        digest=e.SHA256; native=true; disposition="native_PUCCH_transmitted_modeled_control";
                        emissions=[emissions e]; %#ok<AGROW>
                    end
                end
                row=table(string(o.ResourceID),now,o.UEIndex,o.RNTI,o.CellID,string(o.Transport), ...
                    o.HARQBits,o.SRBits,o.CSIPart1Bits,o.CSIPart2Bits,disposition,native,digest,replacement,false, ...
                    "modeled_SLS_ideal_delayed_control", ...
                    'VariableNames',{'ObligationID','AbsoluteSlot0','UEIndex','RNTI','CellID','Transport', ...
                    'HARQBits','SRBits','CSIPart1Bits','CSIPart2Bits','Disposition','NativeWaveformExecuted', ...
                    'EmissionSHA256','ReplacementPUSCHGrantSHA256','PhysicalReceptionQualified','SourceClassification'});
                row.SRPayloadKnown=srKnown; row.PositiveSRCount=positiveSR;
                audit=[audit;row]; %#ok<AGROW>
            end
            state.UCIEmissionObligations=due;
            state.PUCCHEmissions=emissions;
            state.PUCCHEmissionAudit=audit;
        end
        function snapshot=publishLiveEvidence(obj,runFolder)
            % A bounded view of retained model rows, not a new measurement
            % or a replacement for the final full-history primary CSVs.
            limit=100;
            names=["DLCSI","SRS","NetworkSpatial","FeedbackCapture","PendingReference", ...
                "UCIObligations","UCICompletions","HARQDecisions","PUCCHEmissions"];
            tables={obj.DLCSITrace,obj.SpatialFeedbackTrace,obj.NetworkSpatialTrace, ...
                obj.FeedbackCaptureTrace,obj.pendingReferenceFeedback(),table(),table(),table(),obj.PUCCHEmissionTrace};
            if ~isempty(obj.DynamicUCI)
                tables{6}=obj.DynamicUCI.Trace;
                tables{7}=obj.DynamicUCI.CompletionTrace;
                tables{8}=obj.DynamicUCI.HARQDecisionTrace;
            end
            entries=struct();
            for k=1:numel(names)
                t=tables{k}; count=height(t);
                rows=cell(1,min(count,limit));
                if count>0
                    records=table2struct(t(max(1,count-limit+1):count,:));
                    for r=1:numel(records), rows{r}=records(r); end
                end
                entries.(names(k))=struct('Rows',{rows}, ...
                    'TotalRows',count,'RetainedRows',min(count,limit),'Truncated',count>limit);
            end
            snapshot=struct('Schema',"sixgr.sls_live_evidence/v1", ...
                'ExecutionID',string(obj.Cfg.run.executionID), ...
                'CommittedThroughAbsoluteSlot0',obj.SlotContext.TTI-1, ...
                'RowLimit',limit,'Evidence',entries,'WaveformBacked',false, ...
                'CalibrationQualified',obj.CalibrationQualified,'PrimaryStudyAccepted',false, ...
                'SourceClassification',"retained_calibrated_sls_runtime_rows_not_final_results");
            text=jsonencode(sixgr.util.jsonSafeValue(snapshot));
            sixgr.runtime.RuntimeArtifactTransaction.writeTextAtomic(runFolder, ...
                'live/sls_evidence.json',text,'ProducerStage','sls_network_progress', ...
                'ProducerBlock','CalibratedLinkPHY');
        end
        function ueStates=advanceDLCSIFeedback(obj,ueStates,state,target)
            if isempty(obj.DLCSIBuffer), return; end
            for k=1:numel(ueStates)
                ueStates(k).ModeledCSIFeedback=struct(); ueStates(k).ModeledCSICausalUsable=false;
                r=obj.DLCSIBuffer.select(k,state.ServingCells(k),state.AbsoluteSlot0,target);
                ueStates(k).CausalFeedbackUsable=false;
                ueStates(k).CausalFeedbackStatus='awaiting_causal_modeled_csi';
                if isempty(r), continue; end
                if ~isempty(obj.DynamicUCI) && ~obj.DynamicUCI.reportCompleted(k,state.ServingCells(k),r.ReportAbsoluteSlot0)
                    continue; % delayed CSI cannot bypass its actual modeled transport completion
                end
                r.RNTI=ueStates(k).RNTI;
                r.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(r)),'UTF-8'))));
                ueStates(k).ModeledCSIFeedback=r; ueStates(k).ModeledCSICausalUsable=true;
                ueStates(k).RI=r.RI; ueStates(k).NumLayers=r.RI; ueStates(k).PMI=r.PMI;
                ueStates(k).CQI=r.CQI; ueStates(k).CausalFeedbackUsable=true;
                ueStates(k).CausalFeedbackStatus='ideal_delayed_modeled_csi';
                ueStates(k).FeedbackValid=true; ueStates(k).FeedbackAgeSlots=r.AgeSlots;
                ueStates(k).SchedulerCQIRawCQI=r.CQI;
                ueStates(k).SchedulerCQISource=char(r.SourceClassification);
                ueStates(k).BootstrapCQIUsableForScheduling=false;
                ueStates(k).BootstrapCQISource='';
                ueStates(k).SchedulerAdjustedSINR_dB=r.ModeledSINR_dB;
                ueStates(k).MeasuredSINR_dB=NaN; % no waveform measurement
                row=table(k,state.ServingCells(k),state.AbsoluteSlot0,target,r.SourceAbsoluteSlot0, ...
                    r.AvailableAbsoluteSlot0,r.RI,r.PMI,r.CRI,r.CQI,r.ModeledSINR_dB, ...
                    string(r.BindingSHA256),string(r.SourceClassification),string(r.CQIQualification),false, ...
                    size(r.MatrixElements,1),size(r.MatrixPorts,1),string(r.PortBasisSHA256), ...
                    'VariableNames',{'UEIndex','ServingCell','ControlAbsoluteSlot0','DataAbsoluteSlot0', ...
                    'SourceAbsoluteSlot0','AvailableAbsoluteSlot0','RI','PMI','CRI','CQI','ModeledSINR_dB', ...
                    'BindingSHA256','SourceClassification','CQIQualification','WaveformBacked', ...
                    'PhysicalTransmitDimensions','CSILogicalPorts','PortBasisSHA256'});
                row.ReferenceResourceID=double(sixgr.util.structGet(r,'ReferenceResourceID',NaN));
                row.ReferenceEmissionSHA256=string(sixgr.util.structGet(r,'ReferenceEmissionSHA256',""));
                row.ReferenceEmissionBound=isfield(r,'ReferenceResourceID') && isfield(r,'ReferenceEmissionSHA256');
                obj.DLCSITrace=[obj.DLCSITrace;row];
            end
        end
        function ueStates=advanceULSpatialFeedback(obj,ueStates,state,targetSlot0)
            if isempty(obj.SpatialFeedbackBuffer), return; end
            for k=1:numel(ueStates)
                ueStates(k).ModeledSRSFeedback=struct();
                ueStates(k).ModeledSRSCausalUsable=false;
                r=obj.SpatialFeedbackBuffer.select(k,state.ServingCells(k),state.AbsoluteSlot0,targetSlot0);
                if isempty(r)
                    ueStates(k).CausalFeedbackUsable=false;
                    ueStates(k).CausalFeedbackStatus='awaiting_causal_modeled_srs';
                    continue;
                end
                r.RNTI=ueStates(k).RNTI;
                r.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(r)),'UTF-8'))));
                ueStates(k).ModeledSRSFeedback=r;
                ueStates(k).RI=r.RI; ueStates(k).NumLayers=r.RI;
                ueStates(k).PMI=r.TPMI; ueStates(k).TPMI=r.TPMI; ueStates(k).SRI=r.SRI;
                ueStates(k).ModeledSRSCausalUsable=true;
                ueStates(k).ModeledSRSAgeSlots=r.AgeSlots;
                % Spatial selection is not a calibrated CQI measurement.
                % Preserve CQI validity/status/age from its separate queue.
                % A fresh rank must never rescue stale or absent CQI.
                row=table(k,state.ServingCells(k),state.AbsoluteSlot0,targetSlot0, ...
                    r.SourceAbsoluteSlot0,r.AvailableAbsoluteSlot0,r.AgeSlots,r.RI,r.TPMI,r.SRI, ...
                    string(r.ObservationID),string(r.BindingSHA256),string(r.EstimationAssumption), ...
                    string(r.SourceClassification),false,string(r.RankReferenceAssumption), ...
                    'VariableNames',{'UEIndex','ServingCell','ControlAbsoluteSlot0','DataAbsoluteSlot0', ...
                    'SourceAbsoluteSlot0','AvailableAbsoluteSlot0','AgeSlots','RI','TPMI','SRI', ...
                    'ObservationID','BindingSHA256','EstimationAssumption','SourceClassification','WaveformBacked','RankReferenceAssumption'});
                row.ReferenceResourceID=double(sixgr.util.structGet(r,'ReferenceResourceID',NaN));
                row.ReferenceEmissionSHA256=string(sixgr.util.structGet(r,'ReferenceEmissionSHA256',""));
                row.ReferenceRNTI=double(sixgr.util.structGet(r,'ReferenceRNTI',NaN));
                row.ReferenceEmissionBound=isfield(r,'ReferenceResourceID') && ...
                    isfield(r,'ReferenceEmissionSHA256') && isfield(r,'ReferenceRNTI');
                obj.SpatialFeedbackTrace=[obj.SpatialFeedbackTrace;row];
            end
        end
        function setSlotContext(obj,state)
            assert(all(isfield(state,{'TTI','GrantsDL','GrantsUL','GrantCellsDL','GrantCellsUL'})), ...
                'sixgr:abstraction:SlotContext','Provide the current complete scheduled-grant population.');
            if ismethod(obj.Provider,'commitSlotPopulation')
                obj.Provider.commitSlotPopulation(state);
            end
            if isfield(state,'PUCCHEmissionAudit') && ...
                    (~isfield(obj.SlotContext,'TTI') || state.TTI>obj.SlotContext.TTI)
                obj.PUCCHEmissionTrace=[obj.PUCCHEmissionTrace;state.PUCCHEmissionAudit];
            end
            obj.SlotContext=state;
        end
        function [ok,bler]=decode(obj,ctx)
            assert(isfield(ctx,'TransportBlockIdentity') && strlength(string(ctx.TransportBlockIdentity))>0 && ...
                isfield(ctx,'IsRetransmission') && isfield(obj.SlotContext,'TTI') && obj.SlotContext.TTI>=ctx.TTI, ...
                'sixgr:abstraction:GrantIdentity','Bind immutable TB identity and a committed scheduled slot before abstraction.');
            state=obj.SlotContext;
            if sixgr.system.abstraction.resolveNetworkSINRModel(obj.Cfg)=="finite_committed_shared_data"
                [available,~,state]=obj.Provider.receptionAvailability(ctx);
                assert(available,'sixgr:abstraction:ReceiveWindowNotAvailable', ...
                    'No decode/ACK decision exists before all required receive samples are committed.');
            else
                assert(state.TTI==ctx.TTI,'sixgr:abstraction:GrantIdentity', ...
                    'The synchronous diagonal receiver requires the current scheduled slot.');
            end
            observation=obj.Provider.evaluate(ctx,state);
            if string(ctx.Direction)=="DL" && ~isempty(obj.DLCSIBuffer)
                sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(obj.Cfg,ctx.Grant);
                r=ctx.Grant.ModeledCSIFeedback;
                expected=r.MatrixElements;
                assert(isequal(size(expected),size(observation.Precoder)) && ...
                    norm(expected-observation.Precoder,'fro')<1e-12 && r.ServingCell==ctx.ServingCellID && ...
                    string(r.RFProfileID)==string(observation.RFProfileID), ...
                    'sixgr:abstraction:DLCSIExecution','Execution must retain selected CSI precoder, cell and RF branch.');
            end
            required={'Channel','Precoder','TotalTransmitPower','ExternalCovariance', ...
                'RFProfileID','ReceiverProfileID','ChannelProfileID','ModelObservationID','SourceClassification'};
            assert(isstruct(observation) && isscalar(observation) && all(isfield(observation,required)) && ...
                string(observation.SourceClassification)=="modeled_spatial_channel_not_waveform_measurement", ...
                'sixgr:abstraction:SpatialObservation','Require explicit modeled spatial/power/covariance evidence.');
            if string(ctx.Direction)=="UL" && ~isempty(obj.SpatialFeedbackBuffer)
                r=ctx.Grant.ModeledSRSFeedback;
                sixgr.system.abstraction.CausalSpatialFeedbackBuffer.validateGrant( ...
                    obj.Cfg,ctx.Grant,ctx.NumLayers,size(observation.Channel,2),ctx.Grant.TPMI);
                assert(r.ServingCell==ctx.ServingCellID && ...
                    isequal(size(observation.Precoder),size(r.MatrixPorts)) && ...
                    norm(observation.Precoder-r.MatrixPorts,'fro')<=1e-12 && ...
                    string(observation.RFProfileID)==string(r.RFProfileID), ...
                    'sixgr:abstraction:FeedbackExecutionMismatch', ...
                    'Execution must retain the scheduled cell, codebook and RF branch.');
            end
            requiredRF=string(sixgr.util.structGet(obj.Cfg,'system.linkAbstraction.requiredRFProfileID',''));
            assert(strlength(requiredRF)==0 || string(observation.RFProfileID)==requiredRF, ...
                'sixgr:abstraction:RFProfileMismatch', ...
                'Spatial producer RF/compensation identity differs from the selected study branch.');
            predictorModel=sixgr.system.abstraction.resolveNetworkSINRModel(obj.Cfg);
            declaredModel=string(sixgr.util.structGet(observation,'SINRPredictorModel','diagonal_nominal_fft'));
            assert(declaredModel==predictorModel,'sixgr:abstraction:NetworkSINRModel', ...
                'Spatial observation and configured calibration predictor disagree.');
            if predictorModel=="finite_committed_shared_data"
                assert(isfield(observation,'FiniteWindow') && observation.ResidualISIICIIncluded && ...
                    observation.FiniteWindow.ReceiveWindow.ObservationTTI==ctx.TTI && ...
                    isequal(observation.FiniteWindow.Coordinates0Based,observation.Coordinates0Based), ...
                    'sixgr:abstraction:FiniteSpatialEvidence','Require the exact committed grant receive window.');
                sixgr.system.abstraction.validateFiniteInterferencePopulation(obj.Cfg,observation);
                spatial=sixgr.system.abstraction.evaluateFiniteOFDMSpatialSINR( ...
                    observation.FiniteWindow.DesiredObservation,observation.FiniteWindow.ExternalCovariance,obj.ReceiverType);
            else
                spatial=sixgr.system.abstraction.evaluateSpatialSINR(observation.Channel, ...
                    observation.Precoder,observation.TotalTransmitPower,observation.ExternalCovariance,obj.ReceiverType);
            end
            assert(size(spatial.SINRLinear,2)==ctx.NumLayers, ...
                'sixgr:abstraction:GrantRank','Spatial producer changed issued grant rank.');
            key=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,observation,obj.ReceiverType,obj.EffectiveSINRMethod);
            keyJSON=string(jsonencode(key));
            keySHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(keyJSON,'UTF-8'))));
            processKey=char(join([string(ctx.Direction),string(ctx.ServingCellID), ...
                string(ctx.Grant.RNTI),string(sixgr.util.structGet(ctx.Grant,'HARQ.HarqID',NaN))],'|'));
            rv=double(sixgr.util.structGet(ctx.Grant,'HARQ.RV',0));
            if ctx.IsRetransmission
                assert(isKey(obj.Processes,processKey),'sixgr:abstraction:MissingHARQHistory','No first transmission for this HARQ process.');
                h=obj.Processes(processKey);
                assert(h.TBID==string(ctx.TransportBlockIdentity) && isequaln(h.Key,key) && ~h.Ack && ctx.TTI>h.TTI, ...
                    'sixgr:abstraction:HARQIdentity','Retx changed TB/coding/allocation identity, follows success, or has a noncausal clock.');
            else
                h=struct('TBID',string(ctx.TransportBlockIdentity),'Key',key, ...
                    'RVs',[],'SINR',[],'SINRResourceHistory',{{}}, ...
                    'BetaLinear',NaN,'MappingSHA256',"",'Ack',false,'TTI',ctx.TTI,'TTIHistory',[]);
                if isKey(obj.Processes,processKey)
                    old=obj.Processes(processKey);
                    assert(old.TBID~=h.TBID,'sixgr:abstraction:DuplicateTB','A new transmission must have a new TB identity.');
                end
            end
            rvs=[h.RVs rv]; matched=[];
            ttiHistory=[h.TTIHistory ctx.TTI]; slotOffsets=ttiHistory-ttiHistory(1);
            for k=1:numel(obj.Curves)
                historyMatches=~isfield(obj.Curves(k),'HARQSlotOffsets0') || ...
                    isequal(double(obj.Curves(k).HARQSlotOffsets0(:).'),slotOffsets);
                if historyMatches && isequaln(obj.Curves(k).Key,key) && isequal(double(obj.Curves(k).RVSequence(:).'),rvs)
                    matched=k; break;
                end
            end
            assert(~isempty(matched),'sixgr:abstraction:CalibrationCoverage', ...
                ['No exact calibration for this grant/profile/allocation, RV and slot-gap history; ' ...
                 'no first-TX or rank fallback is used. KeySHA256=%s KeyJSON=%s HARQSlotOffsets0=%s'], ...
                keySHA256,keyJSON,jsonencode(slotOffsets));
            curve=obj.Curves(matched);
            mapping=struct('Method',obj.EffectiveSINRMethod,'BetaLinear',curve.BetaLinear);
            if obj.EffectiveSINRMethod=="calibrated_miesm", mapping.MILookup=curve.MILookup; end
            mappingSHA=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(mapping),'UTF-8'))));
            resourceHistory=[h.SINRResourceHistory {spatial.SINRLinear}];
            history=sixgr.system.abstraction.mapHARQHistory(resourceHistory,curve);
            axes=curve.SINRAxes_dB;
            for k=1:numel(history)
                assert(isfinite(history(k)) && history(k)>=min(axes{k}) && history(k)<=max(axes{k}), ...
                    'sixgr:abstraction:SINROutOfCalibration','An attempted SINR history lies outside measured calibration coverage.');
            end
            supported=true(size(curve.TrialCount));
            if isfield(curve,'SupportedMask'), supported=logical(curve.SupportedMask); end
            sixgr.system.abstraction.assertSupportedSINRHistory(axes,supported,history);
            probability=zeros(size(curve.TrialCount));
            probability(supported)=double(curve.ErrorCount(supported))./double(curve.TrialCount(supported));
            if numel(history)==1
                bler=interp1(axes{1},probability,history(1),'linear');
            else
                lookup=griddedInterpolant(axes,probability,'linear','none');
                query=num2cell(history); bler=lookup(query{:});
            end
            assert(isfinite(bler) && bler>=0 && bler<=1,'sixgr:abstraction:InvalidBLER','Invalid calibrated probability.');
            ok=rand(obj.Stream)>=bler;
            h.RVs=rvs; h.SINR=history; h.SINRResourceHistory=resourceHistory; h.TTIHistory=ttiHistory;
            h.BetaLinear=curve.BetaLinear; h.MappingSHA256=mappingSHA; h.Ack=ok; h.TTI=ctx.TTI;
            obj.Processes(processKey)=h;
            obj.LastReplay=struct('Ok',ok,'BLER',bler,'TransportBlockSize',ctx.TBSBits, ...
                'TransportBlockIdentity',string(ctx.TransportBlockIdentity), ...
                'TransmissionAbsoluteSlot0',ctx.TTI-1, ...
                'ReceiveCompletionAbsoluteSlot0',obj.SlotContext.TTI-1, ...
                'ApplicationPayloadBits',sixgr.util.structGet(ctx,'ApplicationPayloadBits',NaN), ...
                'ExecutionBackend',obj.ExecutionBackend,'PHYMode',obj.PHYMode, ...
                'PHYDecisionRole',"calibrated_sls_estimate",'PHYDecisionStatus',"OK", ...
                'PHYDecisionSource',"sixgr.system.CalibratedLinkPHY", ...
                'PHYDecisionReason',"sampled_conditional_bler_not_executed_crc", ...
                'WaveformReplayExecuted',false,'WaveformReplayReused',false, ...
                'ChannelEstimateAvailable',false,'EqualizationAvailable',false, ...
                'CalibrationID',obj.CalibrationID,'CalibrationSHA256',obj.CalibrationSHA256, ...
                'CalibrationQualified',obj.CalibrationQualified,'CalibrationCurveID',string(curve.CurveID), ...
                'CalibrationKeySHA256',keySHA256, ...
                'ModeledEffectiveSINR_dB',history(end),'ModeledSINRPerResourceLayer_dB',spatial.SINR_dB, ...
                'ModeledInterLayerInterferencePower',spatial.InterLayerInterferencePower, ...
                'SINRPredictorModel',predictorModel, ...
                'ResidualISIICIIncluded',logical(sixgr.util.structGet(observation,'ResidualISIICIIncluded',false)), ...
                'ReceiverType',obj.ReceiverType, ...
                'EffectiveSINRMethod',obj.EffectiveSINRMethod,'EffectiveSINRMappingSHA256',mappingSHA, ...
                'ModelObservationID',string(observation.ModelObservationID), ...
                'HARQSINRHistory_dB',history,'HARQRVHistory',rvs, ...
                'HARQSlotOffsets0',slotOffsets, ...
                'HARQHistoryMappingBetaLinear',curve.BetaLinear, ...
                'SourceClassification',"calibrated_sls_estimate_not_waveform_truth");
            if ~obj.CalibrationQualified
                obj.LastReplay.SourceClassification="development_fixture_not_study_result";
            end
            if isfield(observation,'ActiveInterferersPerRE')
                row=table(ctx.TTI-1,string(ctx.Direction),double(ctx.Grant.RNTI),double(ctx.ServingCellID), ...
                    ctx.NumLayers,size(observation.Channel,3), ...
                    mean(observation.TotalTransmitPower),observation.NoisePowerPerRE_W, ...
                    mean(observation.ActiveInterferersPerRE),max(observation.ActiveInterferersPerRE), ...
                    mean(spatial.InterLayerInterferencePower,'all'),history(end), ...
                    string(observation.PowerPlane),string(observation.ResourcePopulation),string(observation.InterferencePopulation), ...
                    string(observation.ChannelProfileID),string(observation.RFProfileID), ...
                    logical(observation.ArrayQualified),logical(observation.RFQualified), ...
                    logical(observation.CommonControlInterferenceQualified),false, ...
                    string(obj.LastReplay.SourceClassification),predictorModel, ...
                    logical(sixgr.util.structGet(observation,'ResidualISIICIIncluded',false)),obj.SlotContext.TTI-1, ...
                    'VariableNames',{'AbsoluteSlot0','Direction','RNTI','ServingCell','Rank','ResourceCount', ...
                    'MeanTxPowerPerRE_W','NoisePowerPerRE_W','MeanActiveInterferersPerRE','MaxActiveInterferersPerRE', ...
                    'MeanInterLayerOutputPower','ModeledEffectiveSINR_dB','PowerPlane','ResourcePopulation','InterferencePopulation', ...
                    'ChannelProfileID','RFProfileID','ArrayQualified','RFQualified','CommonControlInterferenceQualified','WaveformBacked','SourceClassification', ...
                    'SINRPredictorModel','ResidualISIICIIncluded','ReceiveCompletionAbsoluteSlot0'});
                row.UEIndex=sixgr.system.resolveGrantUEIndex(ctx.Grant);
                row.SRSInterferenceIncluded=logical(sixgr.util.structGet(observation,'SRSInterferenceIncluded',false));
                row.SRSEmissionCount=double(sixgr.util.structGet(observation,'SRSEmissionCount',0));
                row.CSIRSInterferenceIncluded=logical(sixgr.util.structGet(observation,'CSIRSInterferenceIncluded',false));
                row.CSIRSEmissionCount=double(sixgr.util.structGet(observation,'CSIRSEmissionCount',0));
                row.PDCCHInterferenceIncluded=logical(sixgr.util.structGet(observation,'PDCCHInterferenceIncluded',false));
                row.PDCCHEmissionCount=double(sixgr.util.structGet(observation,'PDCCHEmissionCount',0));
                row.SSBInterferenceIncluded=logical(sixgr.util.structGet(observation,'SSBInterferenceIncluded',false));
                row.SSBEmissionCount=double(sixgr.util.structGet(observation,'SSBEmissionCount',0));
                row.PUCCHInterferenceIncluded=logical(sixgr.util.structGet(observation,'PUCCHInterferenceIncluded',false));
                row.PUCCHEmissionCount=double(sixgr.util.structGet(observation,'PUCCHEmissionCount',0));
                row.ReferenceSignalInterferenceQualified=logical(sixgr.util.structGet( ...
                    observation,'ReferenceSignalInterferenceQualified',false));
                obj.NetworkSpatialTrace=[obj.NetworkSpatialTrace;row];
            end
        end
        function available=isReceptionReady(obj,ctx)
            assert(isfield(obj.SlotContext,'TTI') && ctx.TTI<=obj.SlotContext.TTI, ...
                'sixgr:abstraction:GrantIdentity','A reception cannot precede its committed transmission.');
            if sixgr.system.abstraction.resolveNetworkSINRModel(obj.Cfg)=="finite_committed_shared_data"
                available=obj.Provider.receptionAvailability(ctx);
            else
                assert(ctx.TTI==obj.SlotContext.TTI,'sixgr:abstraction:GrantIdentity', ...
                    'Only the finite receiver supports deferred slot completion.');
                available=true;
            end
        end
    end
    methods (Static)
        function key=calibrationKey(ctx,o,receiverType,effectiveSINRMethod)
            if nargin<3, receiverType="lmmse"; end
            if nargin<4, effectiveSINRMethod="calibrated_eesm"; end
            assert(isscalar(string(receiverType)) && any(string(receiverType)==["lmmse","zf"]), ...
                'sixgr:abstraction:Configuration','Calibration receiver must be lmmse or zf.');
            % The full grant allocation/DMRS identity prevents a full-band
            % BLER curve silently standing in for a shorter scheduled TB.
            g=ctx.Grant;
            [bits,~]=sixgr.util.resolveGrantTBSBits(g,'CalibratedLinkPHY');
            assert(bits==ctx.TBSBits,'sixgr:abstraction:GrantTBS','Use the immutable actual grant TBS.');
            assert(isfield(g,'PRBSet') && isfield(g,'SymbolAllocation'), ...
                'sixgr:abstraction:AllocationIdentity','Exact allocated PRBs and symbols are required.');
            allocation=struct('PRBSet',double(g.PRBSet(:).'), ...
                'Symbols',double(g.SymbolAllocation(:).'), ...
                'DMRS',sixgr.util.structGet(g,'DMRS',struct()), ...
                'FrozenCoding',sixgr.util.structGet(g,'PHYGrant.CodingLayout',struct()), ...
                'FrozenResources',sixgr.util.structGet(g,'PHYGrant.ResourceAllocation',struct()));
            exactDataPopulation=string(sixgr.util.structGet(o,'ResourcePopulation',''))== ...
                "native_shared_channel_data_re";
            if exactDataPopulation || isfield(o,'DataREAllocationIdentity') || isfield(o,'DataREAllocationSHA256')
                assert(all(isfield(o,{'DataREAllocationIdentity','DataREAllocationSHA256'})) && ...
                    strcmpi(string(o.DataREAllocationSHA256),string(sixgr.util.sha256Hex( ...
                    uint8(unicode2native(jsonencode(o.DataREAllocationIdentity),'UTF-8'))))), ...
                    'sixgr:abstraction:DataREAllocationIdentity', ...
                    'Native resource population needs a matching content digest.');
                assert(string(o.DataREAllocationIdentity.Schema)=="sixgr.scheduled_data_re_identity/v1" && ...
                    o.DataREAllocationIdentity.NumLayers==ctx.NumLayers && ...
                    o.DataREAllocationIdentity.SubcarrierSpacing==ctx.SCS_kHz, ...
                    'sixgr:abstraction:DataREAllocationIdentity', ...
                    'Native population rank/numerology differs from the executed grant.');
                allocation.NativeDataRE=o.DataREAllocationIdentity;
            end
            uci=sixgr.util.structGet(g,'SLSUCIAllocation',struct());
            if ~isempty(fieldnames(uci))
                assert(isfield(uci,'Schema') && string(uci.Schema)=="sixgr.native_pusch_uci_resources/v1" && ...
                    string(uci.SHA256)==string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(rmfield(uci,'SHA256')),'UTF-8')))), ...
                    'sixgr:abstraction:UCIAllocationIdentity','UCI-bearing PUSCH needs an immutable native resource plan.');
                assert(upper(string(ctx.Direction))=="UL" && uci.TBSBits==bits && ...
                    uci.NumLayers==ctx.NumLayers && uci.TargetCodeRate==ctx.TargetCodeRate && ...
                    string(uci.Modulation)==string(g.Modulation) && ...
                    isequal(uci.PRBSet,double(g.PRBSet(:).')) && ...
                    isequal(uci.SymbolAllocation,double(g.SymbolAllocation(:).')), ...
                    'sixgr:abstraction:UCIAllocationIdentity','UCI resource plan belongs to another grant/allocation.');
                allocation.UCIAllocation=uci;
            end
            key=struct('Direction',upper(string(ctx.Direction)), ...
                'Modulation',string(g.Modulation),'TargetCodeRate',double(ctx.TargetCodeRate), ...
                'MCSTable',string(sixgr.util.structGet(g,'MCSTable','')), ...
                'MCSIndex',double(sixgr.util.structGet(g,'MCSIndex',NaN)), ...
                'Rank',double(ctx.NumLayers),'TBSBits',double(ctx.TBSBits), ...
                'SCS_kHz',double(ctx.SCS_kHz),'ChannelProfile',string(ctx.ChannelModel), ...
                'TxPorts',size(o.Channel,2),'RxPorts',size(o.Channel,1), ...
                'RFProfileID',string(o.RFProfileID),'ReceiverProfileID',string(o.ReceiverProfileID), ...
                'ReceiverType',string(receiverType), ...
                'EffectiveSINRMethod',string(effectiveSINRMethod), ...
                'ChannelProfileID',string(o.ChannelProfileID), ...
                'AllocationSHA256',string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(allocation),'UTF-8')))));
        end
    end
end
function h=localGrantDigest(g)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(g)),'UTF-8'))));
end
