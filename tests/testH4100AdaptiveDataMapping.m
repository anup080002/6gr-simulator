function ok=testH4100AdaptiveDataMapping(receiverCheck,scenarioPath,dlSlot)
% Full H4 TX mapping with declared delivered-feedback boundary inputs.
% These are not measured CSI/SRS, received DCI, BLER or array qualification.
% Exercise the production scheduler, exact allocation and transmitters on
% the unchanged 273-PRB carrier: no smaller grid or fixed-rank substitution.
if nargin<1, receiverCheck=[]; end
if nargin<2
    scenarioPath='simulator/configs/scenarios/h4_100_cdlc100_connected_adaptive.yaml';
end
if nargin<3, dlSlot=16; end
validateattributes(dlSlot,{'numeric'},{'scalar','integer','>=',3});
assert(isempty(receiverCheck) || isa(receiverCheck,'function_handle'));
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
assert(cfg.phy.fc_Hz==4e9 && cfg.phy.carrier.NSizeGrid==273 && ...
    cfg.phy.carrier.SubcarrierSpacing==30 && cfg.phy.nTxAnt==64 && ...
    cfg.phy.nRxAnt==4 && cfg.phy.pdsch.numLayers==1 && cfg.phy.pusch.numLayers==1);
initial=cfg;
count=0;
for direction=["DL" "UL"]
    % Native slot 15 is DL; its K2=4 PUSCH is native slot 19 (UL).
    slot=dlSlot;
    root='pdsch';
    if direction=="UL", slot=20; root='pusch'; end
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    sch=sixgr.l2.mac.SchedulerPF(current,'Direction',direction);
    for layers=[1 2 4]
        beams=0;
        if direction=="DL", beams=[0 7]; end
        for cri=beams
            link=current.phy.(root);
            grant=struct('Direction',direction,'Frame',1,'Slot',slot, ...
                'ControlAbsoluteSlot',slot-1,'RNTI',double(link.RNTI), ...
                'UEIndex',1,'ServingCell',1,'PRBSet',double(link.prbSet), ...
                'SymbolAllocation',double(link.symbolAllocation), ...
                'NumLayers',1,'Layers',1,'MCSIndex',double(link.mcsIndex), ...
                'MCS',double(link.mcsIndex),'Modulation',string(link.modulation), ...
                'TargetCodeRate',double(link.codeRate),'CRI',cri, ...
                'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
            sourceSlot=slot-2;
            % UL slot 20 may use SRS from UL slot 15 (age five), not the
            % six-slot-old DL fixture above. Keep the installed age gate.
            if direction=="UL", sourceSlot=15; grant.ControlAbsoluteSlot=15; end
            feedback=struct('Valid',true,'CQI',10,'RI',layers,'PMI',0, ...
                'SourceSlot',sourceSlot,'DeliveredSlot',sourceSlot+1);
            grant=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime( ...
                grant,feedback,[],current,direction);
            assert(grant.NumLayers==layers && grant.PMI==0);
            if direction=="DL"
                request=current.phy.csi.reportConfiguration; request.Rank=layers;
                W=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
                expected=current.phy.csirs.precoderMatrices(:,:,cri+1)*W;
                % Let the production PMI/CRI resolver construct the
                % matrix. Supplying our expected element matrix here
                % would bypass the feedback-to-beam composition under test.
            else
                % Explicit fixture at the delivered-SRS boundary. Keep the
                % missing-SRS guard in production; do not claim RF sounding.
                grant.TPMI=0; grant.SRSValid=true; grant.SRSCausalUsable=true;
                grant.SRSCausalMeasurementId="declared_SRS_boundary_H4_TX_component";
                grant.LastSuccessfulSRSSlot=sourceSlot;
                grant.SRSAgeSlots=slot-sourceSlot;
            end
            grant=sch.attachCanonicalTimingDecision(grant);
            grant=sch.finalizeExactPHYFeasibility(grant);
            assert(grant.ExactPHYFeasible && grant.Valid, ...
                'H4 exact grant materialization failed: %s', ...
                string(sixgr.util.structGet(grant,'ExactPHYInfeasibilityReason','')));
            grant.DCI=sch.buildDCIBitfield(grant);
            frozen=sixgr.phy.grant.freezePHYGrant(current,direction,grant);
            assert(frozen.CodingLayout.NumLayers==layers && ...
                isequal(double(frozen.ResourceAllocation.PRBSet(:).'),0:272));
            if direction=="DL"
                [tx,info]=sixgr.phy.dl.PDSCH_Tx(current,'PHYGrant',frozen, ...
                    'SchedulerGrantContext',grant,'CompactOutput',false);
                assert(size(tx.PDSCHLayerSymbols,2)==layers && size(tx.Waveform,2)==64);
                assert(norm(frozen.PrecodingState.MatrixPorts-expected,'fro')<1e-12);
                assert(abs(norm(frozen.PrecodingState.MatrixPorts,'fro')^2-1)<1e-12);
                assert(info.CodewordLayerMapping.ActualLayersEqualGrantLayers);
                decoded=sixgr.phy.pdcch.decodeDCIPayload( ...
                    grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
                assert(tx.PDSCH.DMRS.NumCDMGroupsWithoutData==2 && ...
                    decoded.Fields.dmrs_num_cdm_groups_without_data==2 && ...
                    decoded.Fields.num_layers==layers && ...
                    isequal(decoded.Fields.dmrs_port_set,tx.PDSCH.DMRS.DMRSPortSet));
            else
                [tx,info]=sixgr.phy.ul.PUSCH_Tx(current,'PHYGrant',frozen,'CompactOutput',false);
                assert(size(tx.PUSCHLayerSymbols,2)==layers && size(tx.Waveform,2)==4);
                assert(info.Precoding.AuthoritativeSRSDecisionUsed);
                % NR UL codebooks are not all unit-Frobenius matrices.
                % Compare their actual scale to the native reference; do
                % not introduce a power boost to satisfy the DL convention.
                expectedUL=double(nrPUSCHCodebook(layers,4,0,false)).';
                assert(norm(frozen.PrecodingState.MatrixLogicalPorts-expectedUL,'fro')<1e-12);
                assert(norm(frozen.PrecodingState.MatrixPorts-expectedUL,'fro')<1e-12);
            end
            assert(size(tx.Grid,1)==273*12 && size(tx.Grid,2)==14 && ...
                size(tx.Waveform,1)==61440 && ...
                all(isfinite(real(tx.Waveform)) & isfinite(imag(tx.Waveform)),'all'));
            assert(numel(frozen.CodingLayout.DMRSPortSet)==layers);
            count=count+1;
            fprintf('H4_FULLBAND_TX direction=%s rank=%d beam=%d PRBs=273 samples=%d ports=%d\n', ...
                direction,layers,cri,size(tx.Waveform,1),size(tx.Waveform,2));
            if ~isempty(receiverCheck)
                receiverCheck(current,direction,grant,frozen,tx,info);
            end
            clear tx info
        end
    end
end
assert(isequaln(cfg,initial),'Per-grant adaptation must not rewrite the installed bootstrap.');
assert(count==9);
fprintf('H4_ADAPTIVE_DATA_MAPPING_PASS physical_TX=%d feedback=declared_boundary_fixture RX_qualification=0\n',count);
ok=true;
end
