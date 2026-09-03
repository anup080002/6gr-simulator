function fields = completeDCIFields(fields, context)
%COMPLETEDCIFIELDS Install context-present control fields explicitly.
%
% This routine does not infer payload width or add fields that are absent
% from the selected Release-18 schema. Builders provide scheduling values;
% context-only indicators receive their configured value or the schema's
% first valid value.

context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
for ii = 1:numel(schema.Definitions)
    definition = schema.Definitions(ii);
    name = char(definition.Name);
    if isfield(fields, name)
        continue;
    end
    switch string(definition.Name)
        case "carrier_indicator"
            value = double(context.Data.CarrierIndicatorValue);
        case "transmission_configuration_indication"
            value = double(context.Data.ActiveTCIStateID);
        otherwise
            value = double(definition.ValueMin);
    end
    fields.(name) = value;
end
end
