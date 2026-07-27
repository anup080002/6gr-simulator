classdef CentralMACTimingService
    %CENTRALMACTIMINGSERVICE Exact K0/K1/K2 and TDD legality authority.

    methods (Static)
        function decision = resolve(request)
            arguments
                request (1,1) struct
            end
            required = ["Mu","PDCCHSlot","K0","K1","K2", ...
                "TDDPattern","DLStartSymbol","DLLengthSymbols", ...
                "ULStartSymbol","ULLengthSymbols","SourceDCIEventID"];
            for field = required
                if ~isfield(request, field) || isempty(request.(field))
                    error("sixgr:mac:MissingTimingSource", ...
                        "Central timing request requires %s.", field);
                end
            end
            for field = ["K0","K1","K2","PDCCHSlot","Mu"]
                value = double(request.(field));
                if ~isscalar(value) || ~isfinite(value) || value < 0 || value ~= fix(value)
                    error("sixgr:mac:IllegalTimingRelation", ...
                        "%s must be a nonnegative integer.",field);
                end
            end
            pdcch=double(request.PDCCHSlot);
            k0=double(request.K0); k1=double(request.K1); k2=double(request.K2);
            pdsch=pdcch+k0; pusch=pdcch+k2; feedback=pdsch+k1;
            pattern=char(upper(string(request.TDDPattern)));
            if isempty(pattern) || any(~ismember(pattern, ['D','U','F']))
                error("sixgr:mac:InvalidTDDPattern", ...
                    "TDDPattern must contain only D, U, or F symbols.");
            end
            dlLegal=sixgr.l2.mac.CentralMACTimingService.isTDDLegal( ...
                pattern,"DL",request.DLStartSymbol,request.DLLengthSymbols);
            ulLegal=sixgr.l2.mac.CentralMACTimingService.isTDDLegal( ...
                pattern,"UL",request.ULStartSymbol,request.ULLengthSymbols);
            flexPolicy=string(localField(request,"FlexibleResolution",""));
            if contains(pattern,'F') && strlength(flexPolicy)==0
                error("sixgr:mac:FlexibleDirectionUnresolved", ...
                    "Flexible TDD symbols require an explicit resolution.");
            end
            processingLegal = logical(localField(request,"ProcessingLegal",true));
            resourceLegal = logical(localField(request,"ResourceLegal",true));
            data=struct("K0",k0,"K1",k1,"K2",k2, ...
                "PDCCHSlot",pdcch,"PDSCHSlot",pdsch,"PUSCHSlot",pusch, ...
                "FeedbackSlot",feedback,"TDDLegal",dlLegal&&ulLegal, ...
                "ProcessingLegal",processingLegal, ...
                "ResourceLegal",resourceLegal, ...
                "SourceDCIEventID",string(request.SourceDCIEventID));
            decision=sixgr.l2.mac.MACTimingDecision(data);
            if ~(decision.TDDLegal && decision.ProcessingLegal && decision.ResourceLegal)
                error("sixgr:mac:IllegalTimingRelation", ...
                    "K0/K1/K2 request is not legal for the supplied resources.");
            end
        end

        function legal = isTDDLegal(pattern, direction, startSymbol, lengthSymbols)
            pattern=char(upper(string(pattern)));
            direction=upper(string(direction));
            startSymbol=double(startSymbol); lengthSymbols=double(lengthSymbols);
            if startSymbol<0 || lengthSymbols<1 || ...
                    startSymbol+lengthSymbols>numel(pattern)
                legal=false; return;
            end
            segment=pattern(startSymbol+(1:lengthSymbols));
            if direction=="DL"
                legal=all(segment=='D' | segment=='F');
            elseif direction=="UL"
                legal=all(segment=='U' | segment=='F');
            else
                error("sixgr:mac:InvalidDirection","Direction must be DL or UL.");
            end
        end

        function legal = isSegmentLegal(pattern,requested,startSymbol, ...
                lengthSymbols,flexibleResolution)
            pattern=char(upper(string(pattern)));
            requested=upper(string(requested));
            resolution=upper(string(flexibleResolution));
            startSymbol=double(startSymbol); lengthSymbols=double(lengthSymbols);
            if startSymbol<0 || lengthSymbols<1 || ...
                    startSymbol+lengthSymbols>numel(pattern)
                legal=false; return;
            end
            segment=pattern(startSymbol+(1:lengthSymbols));
            if any(segment=='F')
                if strlength(resolution)==0
                    legal=false; return;
                end
                if resolution~=requested
                    legal=false; return;
                end
                segment(segment=='F')=char(extractBefore(requested,2));
                if requested=="GUARD", segment(:)='G'; end
                if requested=="UNUSED", segment(:)='N'; end
            end
            switch requested
                case "DL", legal=all(segment=='D');
                case "UL", legal=all(segment=='U');
                case "GUARD", legal=all(segment=='G');
                case "UNUSED", legal=all(segment=='N');
                otherwise, legal=false;
            end
        end
    end
end

function value=localField(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
