function [threshold,source]=resolveDetectionThreshold(assignment,policy,override)
% One configured metric threshold; no payload or measured signal enters it.
% Empty policy is only the standalone API's named YAML default, not rescue
% of missing live runtime configuration.
if nargin<2, policy=[]; end
if nargin<3, override=[]; end
if ~isempty(override)
    threshold=override; source="explicit_receiver_argument";
else
    source="yaml.pucch.";
    if isempty(policy)
        root=fileparts(which('setup6GRSimToolkit'));
        catalog=sixgr.lls6g.config.readConfigFile(fullfile(root, ...
            'simulator','configs','control','pucch_receiver_thresholds.yaml'));
        policy=catalog.pucch;
        source="standalone_yaml_default.pucch.";
    end
    if assignment.Format==0
        count=double(assignment.Resource.Data.NumSymbols);
        assert(any(count==[1 2]),'sixgr:phy:pucch:InvalidFormat0SymbolCount', ...
            'Format 0 must have one or two OFDM symbols.');
        field="detection_threshold_format0_one_symbol";
        if count==2, field="detection_threshold_format0_two_symbols"; end
    else
        field="detection_threshold_format"+string(assignment.Format);
    end
    assert(isstruct(policy) && isscalar(policy) && isfield(policy,field), ...
        'sixgr:phy:pucch:MissingDetectionThreshold', ...
        'Configured PUCCH receiver policy requires %s.',field);
    threshold=policy.(field); source=source+field;
end
assert(isnumeric(threshold) && isscalar(threshold) && isreal(threshold) && ...
    isfinite(threshold) && threshold>=0 && threshold<=1, ...
    'sixgr:phy:pucch:InvalidDetectionThreshold','Detection threshold must be a finite scalar in [0,1].');
threshold=double(threshold);
end
