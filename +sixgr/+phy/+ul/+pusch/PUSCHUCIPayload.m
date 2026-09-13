classdef PUSCHUCIPayload
    %PUSCHUCIPAYLOAD Immutable typed UCI payload for PUSCH.

    properties (SetAccess = private)
        HARQACK
        HARQACKReport
        CSIPart1
        CSIPart2
        ConfiguredGrantUCI
        UCIOnly
        CSIPart2DependsOnPart1
    end

    methods
        function obj = PUSCHUCIPayload(varargin)
            ip = inputParser;
            ip.addParameter("HARQACK", [], @(x) isnumeric(x) || islogical(x) || ...
                isa(x,'sixgr.phy.pucch.HARQACKCodebookState'));
            ip.addParameter("CSIPart1", [], @(x) isnumeric(x) || islogical(x));
            ip.addParameter("CSIPart2", [], @(x) isnumeric(x) || islogical(x));
            ip.addParameter("ConfiguredGrantUCI", [], @(x) isnumeric(x) || islogical(x));
            ip.addParameter("SchedulingRequest", [], @(x) isnumeric(x) || islogical(x));
            ip.addParameter("UCIOnly", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
            ip.addParameter("CSIPart2DependsOnPart1", [], ...
                @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
            ip.parse(varargin{:});
            o = ip.Results;
            if ~isempty(o.SchedulingRequest) && any(logical(o.SchedulingRequest(:)))
                error("sixgr:pusch:SchedulingRequestNotCarriedOnPUSCH", ...
                    "Scheduling Request is routed to PUCCH and cannot enter the PUSCH UCI encoder.");
            end
            if isa(o.HARQACK,'sixgr.phy.pucch.HARQACKCodebookState')
                book=o.HARQACK;
                assert(isscalar(book) && isstruct(book.ProcedureContext) && ...
                    isfield(book.ProcedureContext,'Transport') && book.ProcedureContext.Transport=="PUSCH", ...
                    'sixgr:pusch:HARQACKProcedureRequired', ...
                    'Typed PUSCH HARQ payload requires its received-UL-DAI procedure.');
                obj.HARQACKReport=book;
                obj.HARQACK=book.Bits;
            else
                obj.HARQACKReport=[];
                obj.HARQACK = localBits(o.HARQACK, "HARQACK");
            end
            obj.CSIPart1 = localBits(o.CSIPart1, "CSIPart1");
            obj.CSIPart2 = localBits(o.CSIPart2, "CSIPart2");
            obj.ConfiguredGrantUCI = localBits(o.ConfiguredGrantUCI, "ConfiguredGrantUCI");
            obj.UCIOnly = logical(o.UCIOnly);
            if isempty(o.CSIPart2DependsOnPart1)
                obj.CSIPart2DependsOnPart1 = ~isempty(obj.CSIPart2);
            else
                obj.CSIPart2DependsOnPart1 = logical(o.CSIPart2DependsOnPart1);
            end
            if ~isempty(obj.CSIPart2) && isempty(obj.CSIPart1)
                error("sixgr:pusch:InvalidUCIBitBudget", ...
                    "CSI Part 2 requires an explicit CSI Part 1 payload and dependency state.");
            end
            if ~isempty(obj.CSIPart2) && ~obj.CSIPart2DependsOnPart1
                error("sixgr:pusch:InvalidUCIBitBudget", ...
                    "CSI Part 2 must declare its CSI Part 1 dependency.");
            end
        end

        function tf = hasPayload(obj)
            tf = obj.rawBitCount() > 0;
        end

        function value = rawBitCount(obj)
            value = numel(obj.HARQACK) + numel(obj.CSIPart1) + ...
                numel(obj.CSIPart2) + numel(obj.ConfiguredGrantUCI);
        end

        function value = toStruct(obj)
            value = struct( ...
                "HARQACK", obj.HARQACK, ...
                "CSIPart1", obj.CSIPart1, ...
                "CSIPart2", obj.CSIPart2, ...
                "ConfiguredGrantUCI", obj.ConfiguredGrantUCI, ...
                "UCIOnly", obj.UCIOnly, ...
                "CSIPart2DependsOnPart1", obj.CSIPart2DependsOnPart1, ...
                "OACK", numel(obj.HARQACK), ...
                "OCSI1", numel(obj.CSIPart1), ...
                "OCSI2", numel(obj.CSIPart2), ...
                "OCGUCI", numel(obj.ConfiguredGrantUCI));
            if ~isempty(obj.HARQACKReport)
                value.HARQACKReport=obj.HARQACKReport;
            end
        end
    end
end

function bits = localBits(value, label)
bits = double(value(:));
if any(~isfinite(bits) | (bits ~= 0 & bits ~= 1))
    error("sixgr:pusch:InvalidUCIPayload", ...
        "%s must contain only binary zero/one values.", label);
end
bits = int8(bits);
end
