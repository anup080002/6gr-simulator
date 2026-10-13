classdef RARIdentityAllocator
% gNB identity leases keyed by received occasion/RAPID, never by UE ordinal.
% No lease is reused inside one independent run. A finite configured pool
% can exhaust; it must not wrap onto pending or connected access identities.
properties (SetAccess=private)
    Pool double
    Allocations struct = struct([])
end
methods
    function obj=RARIdentityAllocator(pool)
        sixgr.mac.ra.RARIdentityAllocator.validatePool(pool);
        obj.Pool=double(reshape(pool,1,2));
    end
    function [obj,assignment,isNew]=reserve(obj,ra,det,installedRNTIs)
        if nargin<4, installedRNTIs=[]; end
        key=sixgr.mac.ra.RARIdentityAllocator.receivedKey(ra,det);
        rows=obj.Allocations; hit=false(1,numel(rows));
        for k=1:numel(rows)
            hit(k)=rows(k).Key==key;
        end
        if any(hit)
            assignment=rows(hit); isNew=false; return;
        end
        validateattributes(installedRNTIs,{'numeric'}, ...
            {'real','finite','integer','>=',1,'<=',65522});
        used=double(installedRNTIs(:));
        if ~isempty(rows)
            sameCell=[rows.ServingCell]==ra.ServingCell;
            used=[used;reshape([rows(sameCell).TemporaryCRNTI],[],1)];
        end
        available=setdiff(obj.Pool(1):obj.Pool(2),used,'stable');
        assert(~isempty(available),'sixgr:mac:ra:TemporaryCRNTIPoolExhausted', ...
            'The configured cell-scoped temporary C-RNTI pool is exhausted; no identity may be reused.');
        assignment=struct('Key',key,'ServingCell',double(ra.ServingCell),'CellId',double(ra.CellId), ...
            'PRACHAbsoluteSlot',double(ra.PRACHAbsoluteSlot), ...
            'PRACHOccasionSymbol',double(ra.PRACHOccasionSymbol), ...
            'PRACHFrequencyIndex',double(ra.PRACHFrequencyIndex), ...
            'RARNTI',double(ra.RARNTI),'RAPID',double(det.DetectedPreambleIndex), ...
            'TemporaryCRNTI',available(1),'Source',"gnb_received_prach_cell_allocator");
        if isempty(obj.Allocations), obj.Allocations=assignment;
        else, obj.Allocations(end+1)=assignment; end
        isNew=true;
    end
end
methods (Static)
    function validatePool(pool)
        assert(isnumeric(pool) && isreal(pool) && numel(pool)==2 && ...
            all(isfinite(pool(:))) && all(pool(:)==fix(pool(:))) && ...
            pool(1)>=1 && pool(2)<=65522 && pool(1)<=pool(2), ...
            'sixgr:mac:ra:InvalidTemporaryCRNTIPool', ...
            'random_access.temporary_crnti_pool must be ordered integer [first,last] inside NR range 0001..FFF2 (1..65522).');
    end
    function key=receivedKey(ra,det)
        assert(isequal(double(sixgr.util.structGet(det,'Detected',0)),1), ...
            'sixgr:mac:ra:UndetectedTemporaryCRNTI', ...
            'Only a received PRACH detection may allocate a RAR identity.');
        fields=["ServingCell","CellId","PRACHAbsoluteSlot","PRACHOccasionSymbol","PRACHFrequencyIndex","RARNTI"];
        values=zeros(1,numel(fields)+1);
        for k=1:numel(fields)
            value=sixgr.util.structGet(ra,fields(k),NaN);
            validateattributes(value,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            values(k)=value;
        end
        rapid=sixgr.util.structGet(det,'DetectedPreambleIndex',NaN);
        validateattributes(rapid,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',63});
        values(end)=rapid;
        key=compose("cell=%d|pci=%d|slot=%d|symbol=%d|frequency=%d|ra_rnti=%d|rapid=%d",values);
    end
    function ra=bind(ra,det,assignment)
        key=sixgr.mac.ra.RARIdentityAllocator.receivedKey(ra,det);
        assert(isstruct(assignment) && isscalar(assignment) && ...
            string(sixgr.util.structGet(assignment,'Key',""))==key && ...
            string(sixgr.util.structGet(assignment,'Source',""))=="gnb_received_prach_cell_allocator", ...
            'sixgr:mac:ra:TemporaryCRNTIAssignmentMismatch', ...
            'The gNB assignment must belong to this received cell/occasion/RAPID.');
        rnti=sixgr.util.structGet(assignment,'TemporaryCRNTI',NaN);
        validateattributes(rnti,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',65522});
        ra.TempCRNTI=double(rnti);
        % Prospective value for the existing bounded Msg4 encoder only;
        % connected adoption still requires received contention success.
        ra.FinalCRNTI=double(rnti);
    end
end
end
