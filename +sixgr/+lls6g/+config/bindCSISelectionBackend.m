function cfg=bindCSISelectionBackend(cfg,s)
id='sixgr:lls6g:config:InvalidCSISelectionBackend';
b=string(sixgr.util.structGet(s,'csi_acquisition_and_reporting.selection_backend',cfg.phy.csi.selectionBackend));
assert(isscalar(b)&&ismember(b,["native_maxse_r2026a","portable_typeI_mmse"]),id,'Unknown CSI backend.');
cfg.phy.csi.selectionBackend=b;
if b=="native_maxse_r2026a",return;end
q=cfg.phy.csi.reportConfiguration;
assert(q.Ports==4 && lower(string(q.CodebookType))=="typei-singlepanel" && ...
    lower(string(q.FrequencyGranularity))=="wideband" && upper(string(cfg.phy.rx.detector))=="MMSE",id,'Portable backend supports four-port wideband Type-I/MMSE only.');
m=sixgr.util.structGet(s,'csi_acquisition_and_reporting.portable_cqi_model',struct());
assert(isstruct(m)&&all(isfield(m,{'model_id','source','cqi_table','thresholds_db','comparison_tolerance_db','calibration_qualified'})),id,'Explicit portable CQI model required.');
a=double(m.thresholds_db(:).');tol=double(m.comparison_tolerance_db);
assert(numel(a)==15&&all(isfinite(a))&&all(diff(a)>0)&& ...
    isscalar(tol)&&isfinite(tol)&&tol>=0&&tol<=1e-3 && ...
    islogical(m.calibration_qualified)&&isscalar(m.calibration_qualified)&&~m.calibration_qualified && ...
    strlength(string(m.model_id))>0&&strlength(string(m.source))>0 && ...
    string(m.cqi_table)==string(cfg.phy.csi.cqiTable),id,'Invalid/unqualified CQI model authority.');
cfg.phy.csi.portableCQIModel=struct('ModelID',string(m.model_id),'Source',string(m.source), ...
    'CQITable',string(m.cqi_table),'ThresholdsDB',a,'ComparisonToleranceDB',tol,'CalibrationQualified',false);
q.ProfileID=string(cfg.phy.mimo.profileID);q.Direction=string(cfg.phy.mimo.direction);
ranks=1:double(q.MaxRank); installed=sixgr.util.structGet(cfg,'phy.csi.rankDomain',[]);
if ~isempty(installed),ranks=intersect(ranks,double(installed),'stable');end
allowed=sixgr.util.structGet(q,'AllowedRanks',[]);
if ~isempty(allowed),ranks=intersect(ranks,double(allowed),'stable');end
p=sixgr.mimo.resolveRankPolicy(cfg);
if p.FixedRankAnchor,ranks=intersect(ranks,double(cfg.phy.pdsch.numLayers),'stable');end
assert(~isempty(ranks)&&all(ismember(ranks,1:4)),id,'Unsupported installed rank domain.');
cfg.phy.csi.rankDomain=ranks;
q.RankDomain=ranks; cfg.phy.csi.reportConfiguration=q;
for rank=ranks
    candidate=q; candidate.Rank=rank;
    sixgr.phy.mimo.CodebookEngine.enumerate(candidate);
end
end
