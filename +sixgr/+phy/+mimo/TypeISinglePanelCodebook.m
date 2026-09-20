classdef TypeISinglePanelCodebook
    %TYPEISINGLEPANELCODEBOOK Type-I rank-1/2 and four-port rank-3/4 PMI.
    % TS 38.214 V18.9.0, clause 5.2.2.2.1, Tables -2 through -8.
    % A scalar PMI is only an internal lossless index, NOT an on-air field.
    % Ordering: i2 fastest, then i11, i12, i13; all indices are zero-based.
    methods (Static)
        function layout = layout(request)
            n1=localInteger(request,'N1'); n2=localInteger(request,'N2');
            o1=localInteger(request,'O1'); o2=localInteger(request,'O2');
            ports=localInteger(request,'Ports'); rank=localInteger(request,'Rank');
            mode=localInteger(request,'CodebookMode');
            % Normative geometry table, not a scenario default or DFT proxy.
            geometries=[2 1;2 2;4 1;3 2;6 1;4 2;8 1;4 3;6 2;12 1;4 4;8 2;16 1];
            if ~ismember([n1 n2],geometries,'rows') || ports~=2*n1*n2 || ...
                    o1~=4 || o2~=(1+3*(n2>1)) || ~ismember(mode,[1 2])
                error('sixgr:mimo:UnsupportedAntennaTuple', ...
                    'Type-I panel/oversampling tuple must satisfy TS 38.214 Table 5.2.2.2.1-2.');
            end
            if ~(ismember(rank,[1 2]) || (ports==4 && ismember(rank,[3 4])))
                error('sixgr:mimo:UnsupportedRank', ...
                    'Implemented Type-I ranks are 1/2 and four-port ranks 3/4.');
            end
            offsets=[0 0];
            if rank==2
                if n1==2 && n2==1
                    offsets=[0 0;o1 0];
                elseif n2==1
                    offsets=[0 0;o1 0;2*o1 0;3*o1 0];
                elseif n1==n2
                    offsets=[0 0;o1 0;0 o2;o1 o2];
                else
                    offsets=[0 0;o1 0;0 o2;2*o1 0];
                end
            end
            if rank>=3
                % Table -4: N1=2,N2=1 has only i13=0, (k1,k2)=(O1,0).
                % Tables -7/-8 use the same layout for modes 1 and 2.
                offsets=[o1 0];
                dims=[2,n1*o1,n2*o2,1];
            else
                dims=[2^(3-rank),n1*o1,n2*o2,size(offsets,1)];
            end
            if mode==2 && rank<=2
                dims(1)=4*dims(1);
                dims(2)=dims(2)/2;
                if n2>1, dims(3)=dims(3)/2; end
            end
            layout=struct('Ports',ports,'Rank',rank,'N1',n1,'N2',n2, ...
                'O1',o1,'O2',o2,'CodebookMode',mode,'Dimensions',dims, ...
                'Offsets',offsets,'ComponentNames',["PMI_I2","PMI_I11","PMI_I12","PMI_I13"], ...
                'Specification',"TS38.214-V18.9.0-Tables5.2.2.2.1-2-3-5-6");
            if rank>=3
                layout.Specification="TS38.214-V18.9.0-Tables5.2.2.2.1-2-4-7-8";
            end
        end

        function [W,components] = matrix(request,index)
            layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
            localCheckIndex(index,prod(layout.Dimensions));
            components=localComponents(layout,double(index));
            [W,allowed]=localMatrix(layout,components,request);
            if ~allowed
                error('sixgr:mimo:RestrictedPMI','Received/selected PMI is excluded by the active codebook restriction.');
            end
        end

        function index = linearIndex(request,components)
            layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
            subs=zeros(1,4);
            for k=1:4
                name=layout.ComponentNames(k);
                if ~isfield(components,name) || isempty(components.(name))
                    if layout.Dimensions(k)==1
                        % A zero-width component is fixed by configuration,
                        % not inferred from transmitter measurement metadata.
                        value=0;
                    else
                        error('sixgr:mimo:MissingCSIReportMeasurement','Received PMI requires %s.',name);
                    end
                else
                    value=components.(name);
                end
                localCheckIndex(value,layout.Dimensions(k));
                subs(k)=double(value)+1;
            end
            index=sub2ind(layout.Dimensions,subs(1),subs(2),subs(3),subs(4))-1;
            [~,allowed]=localMatrix(layout,localComponents(layout,index),request);
            if ~allowed
                error('sixgr:mimo:RestrictedPMI','Decoded PMI is excluded by the active codebook restriction.');
            end
        end

        function [matrices,indices,components,layout] = enumerate(request)
            layout=sixgr.phy.mimo.TypeISinglePanelCodebook.layout(request);
            n=prod(layout.Dimensions);
            matrices=complex(zeros(layout.Ports,layout.Rank,n));
            indices=(0:n-1).';
            components=repmat(localComponents(layout,0),n,1);
            allowed=false(n,1);
            for k=1:n
                components(k)=localComponents(layout,k-1);
                [matrices(:,:,k),allowed(k)]=localMatrix(layout,components(k),request);
            end
            matrices=matrices(:,:,allowed); indices=indices(allowed); components=components(allowed);
            if isempty(indices)
                error('sixgr:mimo:EmptyCodebookSubset','No allowed Type-I candidates remain for this rank.');
            end
        end
    end
end

function value=localInteger(request,name)
if ~isfield(request,name), value=NaN; else, value=request.(name); end
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && value>=1 && value==fix(value))
    error('sixgr:mimo:UnsupportedAntennaTuple','%s must be an explicit positive integer.',name);
end
value=double(value);
end

function localCheckIndex(value,count)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
        value>=0 && value<count && value==fix(value))
    error('sixgr:mimo:InvalidPMI','PMI index must be an integer in [0,%d].',count-1);
end
end

function c=localComponents(layout,index)
[i2,i11,i12,i13]=ind2sub(layout.Dimensions,index+1);
c=struct('PMI_I11',i11-1,'PMI_I12',i12-1,'PMI_I13',i13-1,'PMI_I2',i2-1);
end

function [W,allowed]=localMatrix(t,c,request)
l=c.PMI_I11; m=c.PMI_I12; phase=c.PMI_I2;
if t.CodebookMode==2 && t.Rank<=2
    phaseCount=2^(3-t.Rank);
    offset=floor(phase/phaseCount);
    phase=mod(phase,phaseCount);
    if t.N2==1
        l=2*l+offset;
    else
        l=2*l+mod(offset,2); m=2*m+floor(offset/2);
    end
end
% Standard-defined steering vectors, with N2 varying fastest within each
% polarization. Unit total precoder power, NOT one unit per layer.
v=localSteering(t,l,m);
phi=exp(1i*pi*phase/2);
if t.Rank==1
    W=[v;phi*v]/sqrt(t.Ports);
else
    delta=t.Offsets(c.PMI_I13+1,:);
    w=localSteering(t,l+delta(1),m+delta(2));
    if t.Rank==2
        W=[v w;phi*v -phi*w]/sqrt(2*t.Ports);
    elseif t.Rank==3
        W=[v w v;phi*v phi*w -phi*v]/sqrt(3*t.Ports);
    else
        W=[v w v w;phi*v phi*w -phi*v -phi*w]/sqrt(4*t.Ports);
    end
end
% Empty bitmaps mean no subset restriction. Bit a_0 is the first entry.
beamBit=t.N2*t.O2*l+m;
allowed=localAllowed(request,'CodebookSubsetRestriction',t.N1*t.O1*t.N2*t.O2,beamBit) && ...
    localAllowed(request,'I2Restriction',16,c.PMI_I2);
end

function v=localSteering(t,l,m)
horizontal=exp(2i*pi*l*(0:t.N1-1).'/(t.N1*t.O1));
vertical=exp(2i*pi*m*(0:t.N2-1).'/(t.N2*t.O2));
v=kron(horizontal,vertical);
end

function allowed=localAllowed(request,name,count,index)
allowed=true;
if ~isfield(request,name) || isempty(request.(name)), return; end
bits=request.(name);
if ~((isnumeric(bits)||islogical(bits)) && isreal(bits) && isvector(bits) && ...
        numel(bits)==count && all(bits(:)==0 | bits(:)==1))
    error('sixgr:mimo:InvalidCodebookRestriction','%s must be empty or a %d-bit a_0-first bitmap.',name,count);
end
% Mode-2, N2=1 permits l at the oversampled boundary; periodic v(l,m)
% still represents the same beam. Restriction applies modulo beam count.
allowed=logical(bits(mod(index,count)+1));
end
