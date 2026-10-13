function section=resolveUEReportResources(cfg,ue)
% Resolve installed UE/cell/carrier/BWP CSI and SR associations, not UCI bits.
% TS 38.331 CSI-ReportConfig/PUCCH-CSI-Resource and
% SchedulingRequestResourceConfig. This implementation supports one CSI
% report per installed UE/BWP, as does the existing report calendar.
% An absent catalog preserves legacy shared resources, including collisions.
section=sixgr.util.structGet(cfg,'validation.pucch_resources',struct());
rows=sixgr.util.structGet(section,'ue_report_bindings',struct([]));
if isempty(rows), return; end
identity={'UEID','RNTI','ServingCell','PUCCHCell','ComponentCarrier','ActiveULBWP'};
assert(isstruct(ue) && isscalar(ue) && all(isfield(ue,identity)), ...
    'sixgr:phy:pucch:MissingUEReportIdentity', ...
    'Per-UE report resources require exact UE/RNTI/cell/carrier/UL-BWP identity.');
for field=identity
    integer(ue.(field{1}),0,flintmax,'sixgr:phy:pucch:MissingUEReportIdentity');
end
assert(ue.UEID>0 && ue.RNTI>0 && ue.RNTI<=65535 && ue.ServingCell>0 && ...
    ue.PUCCHCell==ue.ServingCell,'sixgr:phy:pucch:MissingUEReportIdentity', ...
    'Resolve the actual serving PUCCH cell and RNTI before resource selection.');
required={'ue_index','rnti','serving_cell_id','component_carrier_id','ul_bwp_id', ...
    'csi_report_config_id','csi_resource_id','scheduling_request_resources'};
assert(isstruct(rows) && all(isfield(rows,required)) && ...
    isempty(setdiff(fieldnames(rows),required)), ...
    'sixgr:phy:pucch:InvalidUEReportBinding', ...
    'UE report bindings accept only explicit identity and installed resource fields.');
owners=zeros(numel(rows),4);
for k=1:numel(rows)
    row=rows(k);
    for field=required(1:5)
        integer(row.(field{1}),0,flintmax,'sixgr:phy:pucch:InvalidUEReportBinding');
    end
    assert(row.ue_index>0 && row.rnti>0 && row.rnti<=65535 && row.serving_cell_id>0, ...
        'sixgr:phy:pucch:InvalidUEReportBinding','UE, RNTI and serving cell must be positive.');
    owners(k,:)=[row.ue_index row.serving_cell_id row.component_carrier_id row.ul_bwp_id];
end
assert(size(unique(owners,'rows'),1)==numel(rows), ...
    'sixgr:phy:pucch:DuplicateUEReportBinding', ...
    'Install exactly one report-resource binding per UE/cell/carrier/UL-BWP.');
match=all(owners==[ue.UEID ue.ServingCell ue.ComponentCarrier ue.ActiveULBWP],2);
assert(nnz(match)==1,'sixgr:phy:pucch:MissingUEReportBinding', ...
    'No installed report-resource binding matches this UE/cell/carrier/UL-BWP.');
row=rows(match);
assert(row.rnti==ue.RNTI,'sixgr:phy:pucch:UEReportBindingRNTI', ...
    'The installed report-resource binding belongs to a different RNTI.');
reportID=row.csi_report_config_id;
assert((ischar(reportID) && (isrow(reportID) || isempty(reportID)) || ...
    isstring(reportID) && isscalar(reportID)) && ...
    ~ismissing(string(reportID)), 'sixgr:phy:pucch:InvalidUEReportBinding', ...
    'CSI report configuration identity must be explicit text.');
resources=sixgr.util.structGet(section,'resources',struct([]));
assert(isstruct(resources) && ~isempty(resources) && all(isfield(resources,{'id','format'})), ...
    'sixgr:phy:pucch:InvalidResourceIndicator','Install the referenced PUCCH resources first.');
csiID=row.csi_resource_id;
if ~isempty(csiID)
    csiID=sixgr.phy.pucch.resolveConfiguredCSIResourceID(csiID);
    installedReportID=string(sixgr.util.structGet(cfg,'phy.csi.reportConfiguration.ReportConfigID',""));
    assert(strlength(string(reportID))>0 && isscalar(installedReportID) && ...
        ~ismissing(installedReportID) && string(reportID)==installedReportID, ...
        'sixgr:phy:pucch:UEReportConfigurationMismatch', ...
        'Bind the configured CSI report, not a resource from another report.');
    hit=[resources.id]==csiID;
    assert(nnz(hit)==1 && ismember(resources(hit).format,[2 3 4]), ...
        'sixgr:phy:pucch:InvalidResourceIndicator', ...
        'CSI requires exactly one installed format-2/3/4 PUCCH resource.');
else
    assert((isnumeric(csiID) || iscell(csiID)) && strlength(string(reportID))==0, ...
        'sixgr:phy:pucch:UEReportConfigurationMismatch', ...
        'An absent CSI binding must leave both report identity and resource empty.');
    csiID=[];
end
configs=row.scheduling_request_resources;
if isempty(configs), configs=struct([]); end
assert(isstruct(configs) && (isempty(configs) || isfield(configs,'resource_id')), ...
    'sixgr:phy:pucch:InvalidUEReportBinding','Install explicit per-UE SR configurations.');
srIDs=zeros(1,numel(configs));
for k=1:numel(configs)
    integer(configs(k).resource_id,0,flintmax,'sixgr:phy:pucch:InvalidResourceIndicator');
    srIDs(k)=configs(k).resource_id;
    hit=[resources.id]==srIDs(k);
    assert(nnz(hit)==1 && ismember(resources(hit).format,[0 1]), ...
        'sixgr:phy:pucch:InvalidResourceIndicator', ...
        'SR requires an installed format-0/1 PUCCH resource.');
end
% These are explicit installed associations. No resource-set PRI, report
% payload, UE pending state, observation energy or scheduling outcome enters.
section.csi_resource_ids=csiID;
section.sr_resource_ids=unique(srIDs,'stable');
section.scheduling_request_resources=configs;
end

function integer(value,minimum,maximum,id)
assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
    value==fix(value) && value>=minimum && value<=maximum,id,'Invalid installed identity/resource integer.');
end
