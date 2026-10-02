function [histories,axis]=historyGrid(p,role)
%HISTORYGRID Separate reference coverage from target operating points.
role=string(role);
assert(isscalar(role) && any(role==["reference","reference_validation","fit","validation"]), ...
    'sixgr:calibration:Role','Unknown collection role.');
if isfield(p,'reference_snr_axis_db') || isfield(p,'target_snr_axis_db')
    assert(isfield(p,'reference_snr_axis_db') && isfield(p,'target_snr_axis_db') && ...
        ~isfield(p,'snr_axis_db'),'sixgr:calibration:History', ...
        'Declare both reference_snr_axis_db and target_snr_axis_db, without legacy snr_axis_db.');
    axis=p.target_snr_axis_db;
    if any(role==["reference","reference_validation"]), axis=p.reference_snr_axis_db; end
else
    axis=p.snr_axis_db;
end
axis=double(axis(:).');
assert(numel(axis)>=2 && all(isfinite(axis)) && all(diff(axis)>0), ...
    'sixgr:calibration:History','SNR axes must be finite and strictly increasing.');
grids=cell(1,numel(p.rv_sequence)); [grids{:}]=ndgrid(axis);
histories=zeros(numel(grids{1}),numel(grids));
for k=1:numel(grids), histories(:,k)=grids{k}(:); end
end
