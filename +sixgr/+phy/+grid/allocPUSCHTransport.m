function [indices,info,geometry,transport]=allocPUSCHTransport(carrier,cfg,varargin)
% Allocate geometry and actual transport separately for installed lab MCS.
% Native callers retain allocREsPUSCH behavior byte-for-byte. The third
% output is always geometry; use info.Modulation/transport for coding/TBS.
transport=[];
name=string(sixgr.util.structGet(cfg,'phy.pusch.mcsTable',''));
if ~startsWith(name,"experimental_")
    [indices,info,geometry]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg,varargin{:});
    return;
end
definition=sixgr.phy.research.resolveExperimentalMCSTable(name);
root=cfg.phy.pusch; policy=sixgr.util.structGet(root,'researchTransportPolicy',struct());
assert(~isempty(definition) && isequaln(sixgr.util.structGet(root,'experimentalMCSTable',[]),definition), ...
    'sixgr:research:MCSTableContextMismatch','Allocation requires the installed experimental table contents.');
assert(string(sixgr.util.structGet(policy,'meta.research_class',''))==definition.ResearchClass && ...
    string(sixgr.util.structGet(policy,'research_pusch_uci.resource_mapping',''))== ...
    "symbol_preserving_single_codeword_ulsch", ...
    'sixgr:research:ExplicitUCIAdapterRequired','Explicit experimental allocation policy is required.');
modulation=string(root.modulation);
for k=1:2:numel(varargin)
    if strcmpi(string(varargin{k}),'Modulation'), modulation=string(varargin{k+1}); end
    if strcmpi(string(varargin{k}),'IndexBase')
        assert(strcmpi(string(varargin{k+1}),'1based'), ...
            'sixgr:research:UnsupportedIndexBase','Experimental resource accounting requires one-based native indices.');
    end
end
% Scheduler candidates may differ from bootstrap MCS, but cannot invent a
% modulation outside the installed experimental definition.
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
rows=catalog.value_maps.modulation_order_to_name;
qm=double([rows(string({rows.name})==modulation).order]);
assert(isscalar(qm) && any(definition.Rows(:,2)==qm), ...
    'sixgr:research:TransportMCSMismatch','Allocation modulation is absent from the installed experimental table.');
[indices,info,geometry]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg,varargin{:},'Modulation','QPSK');
assert(~geometry.TransformPrecoding && ~geometry.EnablePTRS && ~geometry.Interlacing && ...
    strcmpi(geometry.FrequencyHopping,'neither') && geometry.NumCodewords==1, ...
    'sixgr:research:UnsupportedUCIGeometry','Experimental allocation requires one-codeword CP-OFDM without PTRS, interlacing or hopping.');
transport=sixgr.phy.research.PUSCHUCIResourceAdapter(policy,geometry,modulation);
account=transport.resourceAccounting(carrier,indices,root.codeRate,root.xOverhead);
info.Modulation=char(modulation);
info.ResourceAccounting=account;
info.G=account.CodedBitCountG; info.CodedBitCountG=account.CodedBitCountG;
info.PUSCHIndicesInfo.G=account.CodedBitCountG;
info.NREPerPRB=account.NREPerPRBForTBS;
info.StandardNR=false; info.GeometryRole="native_geometry_only_not_transport_modulation";
info.ResearchClass=definition.ResearchClass;
end
