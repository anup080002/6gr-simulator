classdef MACCESchemaRegistry
    %MACCESCHEMAREGISTRY Bounded Release-18 LCID/CE schema.
    methods (Static)
        function schema=resolve(direction,lcid)
            direction=upper(string(direction)); lcid=double(lcid);
            if ~isscalar(direction) || ~ismember(direction,["DL","UL"]) || ...
                    ~isscalar(lcid) || ~isfinite(lcid) || lcid<0 || lcid>63 || lcid~=fix(lcid)
                error("sixgr:mac:ReservedLCID","Invalid direction or LCID.");
            end
            if lcid==63
                schema=struct("Name","Padding","Kind","PADDING", ...
                    "SizeType","implicit","FixedPayloadBytes",0); return;
            end
            % TS 38.321 Table 6.2.1-2: UL CCCH has a fixed R/R/LCID
            % subheader, not the variable-length DL CCCH header.
            if direction=="UL" && ismember(lcid,[0 52])
                count=8; if lcid==52, count=6; end
                schema=struct("Name","CCCH_"+string(8*count)+"bit","Kind","SDU", ...
                    "SizeType","fixed","FixedPayloadBytes",count); return;
            end
            if lcid<=32
                name="LogicalChannel"+string(lcid);
                if lcid==0, name=localTernary(direction=="DL","CCCH","CCCH_64bit"); end
                schema=struct("Name",name,"Kind","SDU", ...
                    "SizeType","variable","FixedPayloadBytes",NaN); return;
            end
            dl=containers.Map("KeyType","double","ValueType","any");
            % TS 38.321 6.1.3: sizes are payload octets, excluding header.
            dl(47)={"RecommendedBitRate","fixed",2}; dl(48)={"SP_ZP_CSI_RS","fixed",2};
            dl(52)={"TCI_State_Indication","fixed",2};
            dl(57)={"SCellActivation_4octet","fixed",4}; dl(58)={"SCellActivation_1octet","fixed",1};
            dl(59)={"Long_DRX","fixed",0}; dl(60)={"DRX","fixed",0};
            dl(61)={"TimingAdvanceCommand","fixed",1};
            dl(62)={"ContentionResolutionIdentity","fixed",6};
            ul=containers.Map("KeyType","double","ValueType","any");
            ul(44)={"TimingAdvanceReport","fixed",2}; ul(54)={"MultipleEntryPHR_4octet","variable",NaN};
            ul(55)={"ConfiguredGrantConfirmation","fixed",0}; ul(56)={"MultipleEntryPHR_1octet","variable",NaN};
            ul(57)={"SingleEntryPHR","fixed",2}; ul(58)={"C_RNTI","fixed",2};
            ul(59)={"ShortTruncatedBSR","fixed",1}; ul(60)={"LongTruncatedBSR","variable",NaN};
            ul(61)={"ShortBSR","fixed",1}; ul(62)={"LongBSR","variable",NaN};
            map=dl; if direction=="UL", map=ul; end
            if ~isKey(map,lcid)
                error("sixgr:mac:ReservedLCID","LCID %d is reserved.",lcid);
            end
            item=map(lcid);
            schema=struct("Name",string(item{1}),"Kind","CE", ...
                "SizeType",string(item{2}),"FixedPayloadBytes",double(item{3}));
        end
    end
end

function value=localTernary(condition,a,b)
if condition, value=a; else, value=b; end
end
