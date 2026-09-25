function decision=resolvePreparedSRSPUCCHPriority(srs,pucch)
% UE-side priority between ACTUAL prepared waveforms, never an RX hypothesis.
% The caller owns UE/carrier identity. No payload values enter the decision.
assert(isa(srs,'sixgr.link.PreparedUplinkControlTransmission') && ...
    isa(pucch,'sixgr.link.PreparedUplinkControlTransmission') && ...
    srs.Channel=="SRS" && pucch.Channel=="PUCCH", ...
    'sixgr:phy:frame:PreparedControlPriorityAuthority', ...
    'Priority requires typed SRS and actual UE PUCCH preparations.');
decision=struct('Collision',false,'DroppedSymbols0Based',[], ...
    'RetainedSymbols0Based',[],'Authority',"TS38.214_6.2.1", ...
    'PUCCHAssignmentDigest',pucch.Tx.AssignmentDigest);
if nominalStart(srs)~=nominalStart(pucch), return; end
a=srs.Tx.Carrier; b=pucch.Tx.Carrier;
assert(a.NCellID==b.NCellID && a.NSizeGrid==b.NSizeGrid && ...
    a.NStartGrid==b.NStartGrid && a.SubcarrierSpacing==b.SubcarrierSpacing && ...
    srs.SampleRateHz==pucch.SampleRateHz, ...
    'sixgr:phy:frame:PreparedControlCarrierMismatch', ...
    'The shared UE priority owner must compare the same physical carrier.');
srsSymbols=symbols(srs.Tx.SRSIndices,a);
pucchSymbols=symbols([pucch.Tx.PUCCHIndices(:);pucch.Tx.DMRSIndices(:)],b);
overlap=intersect(srsSymbols,pucchSymbols);
decision.RetainedSymbols0Based=srsSymbols;
if isempty(overlap), return; end
% TX report field lengths determine priority, not gNB decoding or energy.
layout=sixgr.phy.pucch.UCIReportContext.fromReport(pucch.Tx.Report);
resource=sixgr.phy.srs.buildSRSConfigFromScenario(srs.InputConfig);
if resource.ResourceType=="aperiodic" && layout.HARQACKBits+layout.SRBits==0
    error('sixgr:phy:frame:AperiodicSRSPUCCHPriorityTimingRequired', ...
        'CSI-only PUCCH versus aperiodic SRS needs received trigger/T_proc,2 authority.');
end
decision.Collision=true;
decision.DroppedSymbols0Based=overlap;
decision.RetainedSymbols0Based=setdiff(srsSymbols,overlap);
end

function value=nominalStart(p)
if isfield(p.PhysicalTiming,'NominalStartSample')
    value=p.PhysicalTiming.NominalStartSample;
else
    assert(p.PhysicalTiming.Source=="explicit_aligned_zero_TA_component_fixture");
    value=p.StartSample;
end
end

function value=symbols(indices,carrier)
k=double(carrier.NSizeGrid)*12; l=double(carrier.SymbolsPerSlot);
value=reshape(unique(floor(mod(double(indices(:))-1,k*l)/k)),1,[]);
end
