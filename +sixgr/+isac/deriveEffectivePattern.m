function state = deriveEffectivePattern(configuredMask,collisionMask,response,relationClass)
%DERIVEEFFECTIVEPATTERN Derive S_cfg/C/R/S_tx/S_rx/S_eff and segments.

arguments
    configuredMask logical
    collisionMask logical
    response (1,1) string
    relationClass (1,1) string = "preserved"
end
if ~isequal(size(configuredMask),size(collisionMask))
    error("sixgr:isac:PatternSizeMismatch", ...
        "Configured and collision masks must have identical dimensions.");
end
response = lower(strtrim(response));
valid = ["share_reuse","communication_muting","sensing_puncture", ...
    "time_relocation","frequency_relocation","comb_pattern_selection", ...
    "beam_precoder_change","known_ratio_power_scaling", ...
    "occasion_drop_defer","recoverable_relocation"];
if ~ismember(response,valid)
    error("sixgr:isac:UnknownCollisionResponse", ...
        "Unknown collision response %s.",response);
end
replacement = false(size(configuredMask));
transmitted = configuredMask;
switch response
    case {"sensing_puncture","occasion_drop_defer"}
        transmitted(collisionMask) = false;
    case {"time_relocation","recoverable_relocation"}
        transmitted(collisionMask) = false;
        [rows,cols] = find(configuredMask & collisionMask);
        for i = 1:numel(rows)
            targetColumn = cols(i)+1;
            if targetColumn <= size(configuredMask,2) && ...
                    ~configuredMask(rows(i),targetColumn)
                replacement(rows(i),targetColumn) = true;
            end
        end
        transmitted = transmitted | replacement;
    case "frequency_relocation"
        transmitted(collisionMask) = false;
        [rows,cols] = find(configuredMask & collisionMask);
        for i = 1:numel(rows)
            targetRow = rows(i)+1;
            if targetRow <= size(configuredMask,1) && ...
                    ~configuredMask(targetRow,cols(i))
                replacement(targetRow,cols(i)) = true;
            end
        end
        transmitted = transmitted | replacement;
    case "comb_pattern_selection"
        % Select the adjacent physical comb for collided sensing REs.  This
        % is deliberately expressed on the physical resource grid rather
        % than by renumbering the retained REs as a compressed sequence.
        transmitted(collisionMask) = false;
        [rows,cols] = find(configuredMask & collisionMask);
        for i = 1:numel(rows)
            targetRow = rows(i)+1;
            if targetRow > size(configuredMask,1)
                targetRow = rows(i)-1;
            end
            if targetRow >= 1 && ~configuredMask(targetRow,cols(i))
                replacement(targetRow,cols(i)) = true;
            end
        end
        transmitted = transmitted | replacement;
    otherwise
        % Sharing, communication muting, beam change and known power
        % scaling retain the declared sensing observations.  Their
        % non-resource-domain actions are classified separately by the
        % execution-evidence exporter.
end
received = transmitted;
effective = received;
activeBySymbol = any(effective,1);
segmentLabels = zeros(1,size(effective,2));
relationClass = lower(strtrim(relationClass));
if any(activeBySymbol) && ismember(relationClass,["preserved","known_transform"])
    % A TDD or puncturing gap is not itself a phase reset. When the
    % inter-observation relation is preserved/known, all active observations
    % remain one coherent segment even when their time indices are sparse.
    segment = 1;
    segmentLabels(activeBySymbol) = 1;
else
    segment = 0;
    inSegment = false;
    for symbol = 1:numel(activeBySymbol)
        if activeBySymbol(symbol)
            if ~inSegment
                segment = segment+1;
                inSegment = true;
            end
            segmentLabels(symbol) = segment;
        else
            inSegment = false;
        end
    end
end
segmentLengths = zeros(segment,1);
for i = 1:segment
    segmentLengths(i) = nnz(effective(:,segmentLabels == i));
end
state = struct( ...
    "ConfiguredMask",configuredMask,"CollisionMask",collisionMask, ...
    "ReplacementMask",replacement,"TransmittedMask",transmitted, ...
    "ReceivedMask",received,"EffectiveMask",effective, ...
    "SegmentLabels",segmentLabels,"SegmentLengths",segmentLengths, ...
    "CoherentSegmentCount",segment,"RelationClass",string(relationClass), ...
    "RetainedObservations",nnz(effective), ...
    "ConfiguredObservations",nnz(configuredMask), ...
    "Response",response);
end
