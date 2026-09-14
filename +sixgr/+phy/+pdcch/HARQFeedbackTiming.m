classdef HARQFeedbackTiming
    % K1 slot offsets are not encoded DCI indicator values.
    % TS 38.213 V18.8.0 9.2.3 / Table 9.2.3-1; ordinary unicast 1_0/1_1.
    % No scheduler ledger or transmitted payload is needed for decoding.
    methods (Static)
        function data = bindRuntime(cfg, data)
            % The supplied runtime config must identify the active PUCCH BWP.
            % Do not derive its numerology from the scheduled DL grant.
            ul = sixgr.util.structGet(cfg,'phy.bwp.ul',[]);
            if isempty(ul)
                scs = sixgr.util.structGet(cfg,'phy.carrier.SubcarrierSpacing',[]);
                source = "configured_single_carrier_without_UL_BWP_surface";
            else
                assert(isstruct(ul) && isscalar(ul), ...
                    'sixgr:phy:pdcch:InvalidFeedbackTimingContext', ...
                    'Feedback timing requires one active UL BWP, not a BWP list.');
                scs = sixgr.util.structGet(ul,'SubcarrierSpacing_kHz',[]);
                source = "configured_active_UL_BWP";
            end
            localInteger(scs,'PUCCH subcarrier spacing');
            assert(scs>0 && log2(double(scs)/15)==fix(log2(double(scs)/15)), ...
                'sixgr:phy:pdcch:InvalidFeedbackTimingContext', ...
                'Active PUCCH BWP SCS must be 15*2^mu kHz.');
            data.PUCCHSubcarrierSpacingKHz = double(scs);
            data.PUCCHNumerologySource = source;
            configured = sixgr.util.structGet(cfg,'phy.pucch.dlDataToULACK',[]);
            if isfield(data,'DLDataToULACK')
                assert(isequal(double(data.DLDataToULACK(:).'),double(configured(:).')), ...
                    'sixgr:phy:pdcch:InvalidFeedbackTimingContext', ...
                    'Context and runtime dl-DataToUL-ACK lists disagree.');
            end
            data.DLDataToULACK = configured;
            data.HARQFeedbackTimingConfigured = true;
            % Validate all monitored DL formats: their schemas share this context.
            formats = unique([string(data.DCIFormat),string(data.MonitoredFormats(:).')]);
            for fmt = formats
                if any(fmt==["1_0","1_1"])
                    peer=data; peer.DCIFormat=fmt;
                    sixgr.phy.pdcch.HARQFeedbackTiming.table(peer);
                end
            end
        end

        function [values, width] = table(data)
            if isa(data,'sixgr.phy.pdcch.DCIContext'), data=data.Data; end
            assert(isstruct(data) && isscalar(data) && isfield(data,'DCIFormat'), ...
                'sixgr:phy:pdcch:InvalidFeedbackTimingContext', ...
                'Feedback timing requires an explicit DCI context.');
            fmt=string(data.DCIFormat);
            assert(isscalar(fmt) && any(fmt==["1_0","1_1"]), ...
                'sixgr:phy:pdcch:UnsupportedFeedbackTimingFormat', ...
                'This timing mapping supports unicast DCI 1_0 and 1_1 only.');
            if fmt=="1_0"
                scs=sixgr.util.structGet(data,'PUCCHSubcarrierSpacingKHz',[]);
                localInteger(scs,'PUCCH subcarrier spacing');
                mu=log2(double(scs)/15);
                assert(isfinite(mu) && any(mu==[0 1 2 3 5 6]), ...
                    'sixgr:phy:pdcch:UnsupportedFeedbackTimingNumerology', ...
                    'DCI 1_0 requires PUCCH mu in {0,1,2,3,5,6}; no table is inferred.');
                if mu<=3
                    values=1:8;
                elseif mu==5
                    values=[7 8 12 16 20 24 28 32];
                else
                    values=[13 16 24 32 40 48 56 64];
                end
                width=3;
            else
                values=sixgr.util.structGet(data,'DLDataToULACK',[]);
                assert(isnumeric(values) && isreal(values) && isvector(values) && ...
                    ~isempty(values) && numel(values)<=8 && all(isfinite(values(:))) && ...
                    all(values(:)>=0 & values(:)==fix(values(:))) && ...
                    numel(unique(values))==numel(values), ...
                    'sixgr:phy:pdcch:InvalidFeedbackTimingList', ...
                    'DCI 1_1 requires an explicit ordered dl-DataToUL-ACK list of 1..8 distinct nonnegative integer slots.');
                values=double(values(:).');
                width=ceil(log2(numel(values)));
            end
        end

        function [indicator, width] = encode(data, slots)
            [values,width]=sixgr.phy.pdcch.HARQFeedbackTiming.table(data);
            localInteger(slots,'K1 slot offset');
            index=find(values==double(slots));
            assert(isscalar(index), ...
                'sixgr:phy:pdcch:FeedbackTimingNotConfigured', ...
                'K1 must equal one installed timing-table entry; clamping or direct slot encoding is forbidden.');
            indicator=index-1;
        end

        function slots = decode(data, indicator)
            [values,width]=sixgr.phy.pdcch.HARQFeedbackTiming.table(data);
            if isempty(indicator)
                assert(width==0, 'sixgr:phy:pdcch:MissingFeedbackTimingIndicator', ...
                    'An absent timing field is valid only for a single configured offset.');
                indicator=0;
            else
                localInteger(indicator,'DCI feedback timing indicator');
            end
            assert(indicator>=0 && indicator<numel(values), ...
                'sixgr:phy:pdcch:InvalidFeedbackTimingIndicator', ...
                'The decoded indicator must address an installed timing entry; reserved values reject.');
            slots=values(double(indicator)+1);
        end
    end
end

function localInteger(value,name)
assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value==fix(value), ...
    'sixgr:phy:pdcch:InvalidFeedbackTimingValue', ...
    '%s must be one explicit finite integer.',name);
end
