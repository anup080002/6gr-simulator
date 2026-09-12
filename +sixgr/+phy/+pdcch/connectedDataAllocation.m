function allocation = connectedDataAllocation(installed, assignment)
% Materialize allocation from received control and installed RRC policy.
% DL: UE receive allocation. UL: UE transmit allocation (NOT gNB RX truth).
% NominalTBSBits is the new-TB sizing result, not stored HARQ TB authority.
sixgr.phy.pdcch.validateConnectedAssignment(installed,assignment);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,assignment.DataAbsoluteSlot+1);
root='pdsch'; channel="PDSCH"; role="ue_downlink_receive_allocation";
if assignment.Direction=="UL", root='pusch'; channel="PUSCH"; role="ue_uplink_transmit_allocation"; end
p=cfg.phy.(root);
p.RNTI=assignment.RNTI;
p.prbSet=assignment.PRBStart+(0:assignment.NumPRB-1);
p.nPRB=assignment.NumPRB;
p.symbolAllocation=assignment.SymbolAllocation;
p.modulation=char(assignment.Modulation);
p.codeRate=assignment.TargetCodeRate;
p.mcsIndex=assignment.MCS; p.mcs=assignment.MCS;
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
if assignment.Direction=="DL"
    [indices,info,data]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg);
    overhead=sixgr.phy.dl.resolvePDSCHXOverhead(cfg,assignment.SymbolAllocation);
else
    [indices,info,data]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg);
    overhead=double(cfg.phy.pusch.xOverhead);
end
validateattributes(overhead,{'double'},{'scalar','finite','integer','nonnegative'});
assert(isequal(double(data.PRBSet(:).'),p.prbSet) && ...
    isequal(double(data.SymbolAllocation(:).'),assignment.SymbolAllocation) && ...
    isequal(double(data.DMRS.DMRSPortSet(:).'),assignment.DMRSPortSet) && ...
    data.DMRS.NSCID==assignment.NSCID && ...
    data.DMRS.NumCDMGroupsWithoutData==assignment.NumCDMGroupsWithoutData && ...
    data.NumLayers==assignment.NumLayers && string(data.Modulation)==assignment.Modulation, ...
    'sixgr:phy:pdcch:ReceivedAllocationOverridden', ...
    'An installed catalog or legacy alias must not override received dynamic fields.');
account=sixgr.phy.resource.computeResourceAccounting(channel,carrier,data, ...
    'ChannelIndices',indices,'AllocationInfo',info,'IndexBase','1based', ...
    'TargetCodeRate',assignment.TargetCodeRate,'XOverhead',overhead);
nominalTBS=nrTBS(data.Modulation,data.NumLayers,numel(data.PRBSet), ...
    account.NREPerPRBForTBS,assignment.TargetCodeRate,overhead);
allocation=struct('Config',cfg,'Carrier',carrier,'ChannelConfig',data, ...
    'Indices',indices,'ResourceAccounting',account,'XOverhead',overhead, ...
    'NominalTBSBits',double(nominalTBS),'RateMatchedCapacityBits',account.CodedBitCountG, ...
    'AssignmentDigest',assignment.AssignmentDigest,'EndpointRole',role, ...
    'Source',"received_dci_and_installed_reference_policy", ...
    'TBSRole',"new_transport_block_nominal_size_not_HARQ_state", ...
    'ExecutionQualified',false);
end
