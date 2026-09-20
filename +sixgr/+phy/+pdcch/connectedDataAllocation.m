function allocation = connectedDataAllocation(installed, assignment, retainedTargetCodeRate)
% Materialize allocation from received control and installed RRC policy.
% DL: UE receive allocation. UL: UE transmit allocation (NOT gNB RX truth).
% NominalTBSBits is the new-TB sizing result, not stored HARQ TB authority.
sixgr.phy.pdcch.validateConnectedAssignment(installed,assignment);
if nargin<3, retainedTargetCodeRate=[]; end
requiresHistory=logical(sixgr.util.structGet(assignment,'RequiresHARQHistory',false));
allocationRate=assignment.TargetCodeRate;
if requiresHistory
    assert(isscalar(retainedTargetCodeRate) && isfinite(retainedTargetCodeRate) && ...
        retainedTargetCodeRate>0 && retainedTargetCodeRate<1, ...
        'sixgr:phy:pdcch:ReceivedHARQHistoryRequired', ...
        'A modulation-only MCS cannot authorize a new TB; retained HARQ coding history is required.');
    allocationRate=retainedTargetCodeRate;
else
    assert(isempty(retainedTargetCodeRate), ...
        'sixgr:phy:pdcch:UnexpectedHARQRateOverride','A defined received MCS owns nominal allocation sizing.');
end
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,assignment.DataAbsoluteSlot+1);
root='pdsch'; channel="PDSCH"; role="ue_downlink_receive_allocation";
if assignment.Direction=="UL", root='pusch'; channel="PUSCH"; role="ue_uplink_transmit_allocation"; end
p=cfg.phy.(root);
p.RNTI=assignment.RNTI;
p.prbSet=assignment.PRBStart+(0:assignment.NumPRB-1);
p.nPRB=assignment.NumPRB;
p.symbolAllocation=assignment.SymbolAllocation;
p.modulation=char(assignment.Modulation);
p.codeRate=allocationRate;
p.mcsIndex=assignment.MCS; p.mcs=assignment.MCS;
if assignment.Direction=="DL"
    % The per-codeword compatibility aliases must not retain bootstrap MCS
    % after actual received control has selected the current allocation.
    p.mcsIndexPerCodeword=assignment.MCS;
    p.mcsTablePerCodeword=assignment.MCSTable;
end
p.numLayers=assignment.NumLayers; p.nLayers=assignment.NumLayers;
p.rv=assignment.RV;
p.dmrs.NSCID=assignment.NSCID;
p.dmrs.scheduledPortSet=assignment.DMRSPortSet;
p.dmrs.portSet=assignment.DMRSPortSet;
p.dmrs.DMRSPortSet=assignment.DMRSPortSet;
p.dmrs.numCDMGroupsWithoutData=assignment.NumCDMGroupsWithoutData;
p.dmrs.NumCDMGroupsWithoutData=assignment.NumCDMGroupsWithoutData;
p.dmrs.maxLength=assignment.DMRSFrontLoadSymbols;
p.receivedDCIAssignment=assignment;
if assignment.Direction=="UL"
    p.TPMI=assignment.TPMI; p.PMI=assignment.TPMI;
end
cfg.phy.(root)=p;
carrier=sixgr.phy.grid.makeCarrier(cfg);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=assignment.DataAbsoluteSlot*1e-3*15/carrier.SubcarrierSpacing;
researchTransport=[];
if assignment.Direction=="DL"
    [indices,info,data]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg);
    overhead=sixgr.phy.dl.resolvePDSCHXOverhead(cfg,assignment.SymbolAllocation);
else
    researchTransport=sixgr.phy.research.configuredPUSCHTransport(cfg,carrier);
    if isempty(researchTransport)
        [indices,info,data]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg);
    else
        data=researchTransport.Geometry;
        [indices,info]=nrPUSCHIndices(carrier,data);
    end
    overhead=double(cfg.phy.pusch.xOverhead);
end
actualModulation=string(data.Modulation);
if ~isempty(researchTransport), actualModulation=researchTransport.Modulation; end
validateattributes(overhead,{'double'},{'scalar','finite','integer','nonnegative'});
assert(isequal(double(data.PRBSet(:).'),p.prbSet) && ...
    isequal(double(data.SymbolAllocation(:).'),assignment.SymbolAllocation) && ...
    isequal(double(data.DMRS.DMRSPortSet(:).'),assignment.DMRSPortSet) && ...
    data.DMRS.NSCID==assignment.NSCID && ...
    data.DMRS.NumCDMGroupsWithoutData==assignment.NumCDMGroupsWithoutData && ...
    data.NumLayers==assignment.NumLayers && actualModulation==assignment.Modulation, ...
    'sixgr:phy:pdcch:ReceivedAllocationOverridden', ...
    'An installed catalog or legacy alias must not override received dynamic fields.');
account=sixgr.phy.resource.computeResourceAccounting(channel,carrier,data, ...
    'ChannelIndices',indices,'AllocationInfo',info,'IndexBase','1based', ...
    'TargetCodeRate',allocationRate,'XOverhead',overhead);
if ~isempty(researchTransport)
    account=researchTransport.resourceAccounting(carrier,indices,allocationRate,overhead);
end
nominalTBS=NaN;
tbsRole="retained_HARQ_TBS_required_no_nominal_size";
if ~requiresHistory
    nominalTBS=nrTBS(char(actualModulation),data.NumLayers,numel(data.PRBSet), ...
        account.NREPerPRBForTBS,assignment.TargetCodeRate,overhead);
    tbsRole="new_transport_block_nominal_size_not_HARQ_state";
end
allocation=struct('Config',cfg,'Carrier',carrier,'ChannelConfig',data, ...
    'Indices',indices,'ResourceAccounting',account,'XOverhead',overhead, ...
    'NominalTBSBits',double(nominalTBS),'RateMatchedCapacityBits',account.CodedBitCountG, ...
    'AssignmentDigest',assignment.AssignmentDigest,'EndpointRole',role, ...
    'Source',"received_dci_and_installed_reference_policy", ...
    'TBSRole',tbsRole, ...
    'ExecutionQualified',false);
if ~isempty(researchTransport)
    allocation.ResearchTransport=researchTransport;
    allocation.StandardNR=false;
    allocation.ChannelConfigRole="native_geometry_only_not_transport_modulation";
end
end
