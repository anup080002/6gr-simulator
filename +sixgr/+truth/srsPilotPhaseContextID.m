function id=srsPilotPhaseContextID(cfg,epoch,ue,servingCell)
% Identity of the installed SRS resource and spatial basis, not TX samples.
% A changed resource, endpoint, BWP, port mapping or stream epoch must not
% reuse phase history. Runtime slot and measured/configured Doppler are not
% part of this identity: neither is a receiver frequency observation.
validateattributes(ue,{'numeric'},{'scalar','integer','positive'});
validateattributes(servingCell,{'numeric'},{'scalar','integer','positive'});
assert(strlength(string(epoch))>0,'sixgr:truth:MissingSRSPilotClockEpoch', ...
    'Bind SRS history to the active receiver stream epoch.');
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
carrier=sixgr.phy.grid.makeCarrier(cfg);
resource=struct();
for name=string(properties(strict.ToolboxSRS)).'
    resource.(name)=strict.ToolboxSRS.(name);
end
context=struct('Epoch',string(epoch),'UE',ue,'ServingCell',servingCell, ...
    'NCellID',carrier.NCellID,'NSizeGrid',carrier.NSizeGrid, ...
    'NStartGrid',carrier.NStartGrid,'SCS_kHz',carrier.SubcarrierSpacing, ...
    'CyclicPrefix',string(carrier.CyclicPrefix),'BWPId',strict.BWPId, ...
    'ResourceSetId',strict.ResourceSetId,'Resource',resource);
tx=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','signal','srs', ...
    'numPorts',strict.ToolboxSRS.NumSRSPorts);
rx=sixgr.util.structGet(cfg,'lls6g.userContext.RuntimeServingBSAntenna',struct());
if isempty(fieldnames(rx)), rx=sixgr.rf.AntennaArrayFactory.build(cfg,'bs'); end
context.TxBasisReal=real(tx.PortToElementMatrix);
context.TxBasisImag=imag(tx.PortToElementMatrix);
context.RxElements=rx.NumElements;
% The shared SRS receiver observes physical elements before combining.
% Retain their installed order/basis, not a propagation channel realization.
context.RxBasisReal=real(rx.PortToElementMatrix);
context.RxBasisImag=imag(rx.PortToElementMatrix);
id=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(context),'UTF-8'))));
end
