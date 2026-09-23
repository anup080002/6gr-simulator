classdef TypeIICodebook
    %TYPEIICODEBOOK Exact wideband Type-II PMI-to-precoder reconstruction.
    % TS 38.214 V18.9.0 5.2.2.2.3, Tables -1/-2/-5. All component indices
    % here are zero-based. Component codecs do not qualify a full runtime
    % CSI report or select PMI from a channel estimate.
    % No channel matrix, transmitted symbols or preferred rank are inputs.
    methods (Static)
        function report = serializeCountIndicators(request,counts,allowedRanks)
            % TS 38.212 Tables 6.3.1.1.2-5 and 6.3.2.1.2-3.
            % M includes the implicit strongest coefficient. Its indicator
            % encodes the remaining M-1 nonzero coefficients. Keep the
            % second field when rank two is allowed, even for reported RI=1.
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            [width,fields]=localCountIndicatorLayout(layout,allowedRanks);
            counts=localNonzeroCounts(counts,layout.NumberOfBeams,layout.Rank);
            codepoints=zeros(1,fields);
            codepoints(1:layout.Rank)=counts-1;
            bits=int8(zeros(fields*width,1)); owners=strings(fields*width,1);
            for layer=1:fields
                span=(layer-1)*width+(1:width);
                bits(span)=int8(bitget(uint32(codepoints(layer)),width:-1:1)).';
                owners(span)="NONZERO_AMPLITUDE_COUNT_L"+(layer-1);
            end
            report=struct('Bits',bits,'Owners',owners,'CompleteCSIReport',false);
        end

        function counts = deserializeCountIndicators(request,bits,allowedRanks)
            % request.Rank must be the decoded RI. This accepts only the
            % received count fields, never transmitter component metadata.
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            [width,fields]=localCountIndicatorLayout(layout,allowedRanks);
            assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
                isvector(bits) && all(bits(:)==0 | bits(:)==1), ...
                'sixgr:mimo:InvalidTypeIICountBits','Count indicators must be binary received fields.');
            assert(numel(bits)==fields*width, ...
                'sixgr:mimo:InvalidTypeIICountLength', ...
                'Count indicator length is fixed by allowed ranks and NumberOfBeams.');
            words=reshape(double(bits),width,fields);
            codepoints=2.^((width-1):-1:0)*words;
            assert(all(codepoints(layout.Rank+1:end)==0), ...
                'sixgr:mimo:InvalidTypeIIInactiveCount', ...
                'The inactive second-layer indicator must be all zeros for received rank one.');
            counts=localNonzeroCounts(codepoints(1:layout.Rank)+1, ...
                layout.NumberOfBeams,layout.Rank);
        end

        function [components,W] = deserializePMIFromCountIndicators(request,bits,countBits,allowedRanks)
            % Bridge received Part-1 count fields to variable-length PMI.
            % An inconsistent Part 1/2 is an error, not a layout hypothesis.
            counts=sixgr.phy.mimo.TypeIICodebook.deserializeCountIndicators( ...
                request,countBits,allowedRanks);
            [components,W]=sixgr.phy.mimo.TypeIICodebook.deserializePMI(request,bits,counts);
        end

        function report = serializePMI(request,components)
            % TS 38.212 Table 6.3.2.1.2-1, X1 followed by wideband X2.
            % This encodes PMI only, not LI or the full CSI Part 1/2 report.
            % TS 38.214 5.2.3: component indices increase MSB to LSB.
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            [~,info]=sixgr.phy.mimo.TypeIICodebook.matrix(request,components);
            L=layout.NumberOfBeams; r=layout.Rank;
            bits=int8(zeros(0,1)); owners=strings(0,1);
            append(components.Q1,log2(layout.O1),"PMI_I11_Q1");
            append(components.Q2,log2(layout.O2),"PMI_I11_Q2");
            append(components.BeamGroupIndex, ...
                ceil(log2(nchoosek(layout.N1*layout.N2,L))),"PMI_I12");
            for layer=1:r
                strongest=components.StrongestCoefficientIndices(layer);
                append(strongest,ceil(log2(2*L)),"PMI_I13_L"+(layer-1));
                for coefficient=0:2*L-1
                    if coefficient~=strongest
                        append(components.WidebandAmplitudeIndices(coefficient+1,layer), ...
                            3,"PMI_I14_L"+(layer-1)+"_C"+coefficient);
                    end
                end
            end
            for layer=1:r
                strongest=components.StrongestCoefficientIndices(layer);
                for coefficient=0:2*L-1
                    if coefficient~=strongest && components.WidebandAmplitudeIndices(coefficient+1,layer)>0
                        append(components.PhaseIndices(coefficient+1,layer), ...
                            log2(layout.PhaseAlphabetSize),"PMI_I21_L"+(layer-1)+"_C"+coefficient);
                    end
                end
            end
            report=struct('Bits',bits,'Owners',owners, ...
                'NonzeroCoefficientCount',info.NonzeroCoefficientCount, ...
                'Specification',"TS38.212-V18.8.0-Table6.3.2.1.2-1", ...
                'CompleteCSIReport',false);

            function append(value,width,owner)
                word=int8(bitget(uint32(value),width:-1:1)).';
                bits=[bits;word]; %#ok<AGROW>
                owners=[owners;repmat(owner,width,1)]; %#ok<AGROW>
            end
        end

        function count = pmiBitCount(request,receivedNonzeroCounts)
            % Counts must come from received CSI Part 1 at the receiver.
            % No transmitted matrix, layout, selected coefficients or bits
            % are inputs to determine the receive obligation.
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            L=layout.NumberOfBeams; r=layout.Rank;
            counts=localNonzeroCounts(receivedNonzeroCounts,L,r);
            count=log2(layout.O1*layout.O2) + ...
                ceil(log2(nchoosek(layout.N1*layout.N2,L))) + ...
                r*(ceil(log2(2*L))+3*(2*L-1)) + ...
                sum(counts-1)*log2(layout.PhaseAlphabetSize);
        end

        function [components,W] = deserializePMI(request,bits,receivedNonzeroCounts)
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            L=layout.NumberOfBeams; r=layout.Rank;
            expected=sixgr.phy.mimo.TypeIICodebook.pmiBitCount(request,receivedNonzeroCounts);
            assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
                isvector(bits) && all(bits(:)==0 | bits(:)==1), ...
                'sixgr:mimo:InvalidTypeIIPMIBits','Received Type-II PMI must be a binary vector.');
            assert(numel(bits)==expected,'sixgr:mimo:InvalidTypeIIPMILength', ...
                'Type-II PMI has %d bits; received Part-1 obligation requires %d.',numel(bits),expected);
            bits=double(bits(:)); offset=0;
            components=struct('Q1',take(log2(layout.O1)), ...
                'Q2',take(log2(layout.O2)), ...
                'BeamGroupIndex',take(ceil(log2(nchoosek(layout.N1*layout.N2,L)))), ...
                'StrongestCoefficientIndices',zeros(1,r), ...
                'WidebandAmplitudeIndices',zeros(2*L,r), ...
                'PhaseIndices',zeros(2*L,r));
            for layer=1:r
                strongest=take(ceil(log2(2*L)));
                assert(strongest<2*L,'sixgr:mimo:InvalidPMI', ...
                    'Received strongest-coefficient index is a spare codepoint.');
                components.StrongestCoefficientIndices(layer)=strongest;
                for coefficient=0:2*L-1
                    if coefficient==strongest
                        components.WidebandAmplitudeIndices(coefficient+1,layer)=7;
                    else
                        components.WidebandAmplitudeIndices(coefficient+1,layer)=take(3);
                    end
                end
            end
            % Reject inconsistent received parts before consuming phases;
            % never truncate, try prefixes, or fill absent coefficient bits.
            assert(isequal(sum(components.WidebandAmplitudeIndices>0,1), ...
                double(receivedNonzeroCounts)), ...
                'sixgr:mimo:TypeIICoefficientCountMismatch', ...
                'Received PMI amplitudes disagree with received Part-1 coefficient counts.');
            for layer=1:r
                strongest=components.StrongestCoefficientIndices(layer);
                for coefficient=0:2*L-1
                    if coefficient~=strongest && components.WidebandAmplitudeIndices(coefficient+1,layer)>0
                        components.PhaseIndices(coefficient+1,layer)=take(log2(layout.PhaseAlphabetSize));
                    end
                end
            end
            assert(offset==expected,'sixgr:mimo:InvalidTypeIIPMILength', ...
                'Type-II PMI decoder did not consume the complete received obligation.');
            W=sixgr.phy.mimo.TypeIICodebook.matrix(request,components);

            function value=take(width)
                value=sum(bits(offset+(1:width)).'.*2.^((width-1):-1:0));
                offset=offset+width;
            end
        end

        function [W,info] = matrix(request,components)
            layout = sixgr.phy.mimo.TypeIICodebook.layout(request);
            n1=layout.N1; n2=layout.N2; L=layout.NumberOfBeams; r=layout.Rank;
            q1=localIndices(components,'Q1',[1 1],layout.O1-1);
            q2=localIndices(components,'Q2',[1 1],layout.O2-1);
            group=localIndices(components,'BeamGroupIndex',[1 1],nchoosek(n1*n2,L)-1);
            strongest=localIndices(components,'StrongestCoefficientIndices',[1 r],2*L-1);
            amplitudes=localIndices(components,'WidebandAmplitudeIndices',[2*L r],7);
            phases=localIndices(components,'PhaseIndices',[2*L r],layout.PhaseAlphabetSize-1);
            anchors=sub2ind([2*L r],strongest+1,1:r);
            assert(all(amplitudes(anchors)==7) && all(phases(anchors)==0) && ...
                all(phases(amplitudes==0)==0), ...
                'sixgr:mimo:InvalidTypeIICoefficients', ...
                'Strongest coefficients require amplitude index 7 and phase 0; omitted zero-amplitude phases must be 0.');
            % Reversed lexicographic combinations implement the normative
            % combinatorial index sum C(N1*N2-1-n(i),L-i), not a beam search.
            groups=flipud(nchoosek(0:n1*n2-1,L));
            beams=groups(group+1,:);
            m1=layout.O1*mod(beams,n1)+q1;
            m2=layout.O2*floor(beams/n1)+q2;
            B=complex(zeros(n1*n2,L));
            for beam=1:L
                horizontal=exp(2i*pi*(0:n1-1).'*m1(beam)/(layout.O1*n1));
                vertical=exp(2i*pi*(0:n2-1).'*m2(beam)/(layout.O2*n2));
                B(:,beam)=kron(horizontal,vertical);
            end
            % Table -2 contains square roots, not rounded decimal amplitudes.
            amplitudeValues=sqrt([0 1/64 1/32 1/16 1/8 1/4 1/2 1]);
            p=reshape(amplitudeValues(amplitudes+1),2*L,r);
            coefficients=p.*exp(2i*pi*phases/layout.PhaseAlphabetSize);
            W=blkdiag(B,B)*coefficients;
            W=W./sqrt(r*n1*n2*sum(p.^2,1));
            info=sixgr.phy.mimo.MatrixContract.validate(W,layout.Ports,r);
            info.Specification="TS38.214-V18.9.0-5.2.2.2.3-Tables1-2-5";
            info.MatrixAuthority="normative_typeII_wideband_reported_components";
            info.BeamIndices=beams;
            info.NonzeroCoefficientCount=sum(amplitudes>0,1);
            info.WireLayoutQualified=false;
        end

        function components = fromToolboxPMI(request,pmi)
            % R2026a nrPMIReport returns one-based i1 components/amplitudes
            % and zero-based i2 phases. Convert metadata, never infer bits.
            layout=sixgr.phy.mimo.TypeIICodebook.layout(request);
            L=layout.NumberOfBeams; r=layout.Rank;
            assert(isstruct(pmi) && isfield(pmi,'i1') && isfield(pmi,'i2') && ...
                isnumeric(pmi.i1) && isreal(pmi.i1) && isvector(pmi.i1) && ...
                numel(pmi.i1)==3+(2*L+1)*r && all(isfinite(pmi.i1(:))), ...
                'sixgr:mimo:InvalidPMI','Unexpected Type-II toolbox i1 layout.');
            i1=double(pmi.i1(:).');
            perLayer=reshape(i1(4:end),2*L+1,r);
            phases=localIndices(pmi,'i2',[2*L r],layout.PhaseAlphabetSize-1);
            amplitudes=perLayer(2:end,:)-1;
            % Non-reported phases for zero coefficients carry no information.
            % The toolbox retains their pre-quantization phase; the normative
            % expanded component representation fixes them to zero.
            phases(amplitudes==0)=0;
            components=struct('Q1',i1(1)-1,'Q2',i1(2)-1, ...
                'BeamGroupIndex',i1(3)-1, ...
                'StrongestCoefficientIndices',perLayer(1,:)-1, ...
                'WidebandAmplitudeIndices',amplitudes,'PhaseIndices',phases);
            sixgr.phy.mimo.TypeIICodebook.matrix(request,components);
        end

        function out = layout(request)
            fields=["Ports","Rank","N1","N2","O1","O2","NumberOfBeams","PhaseAlphabetSize"];
            out=struct();
            for name=fields
                assert(isfield(request,name) && isnumeric(request.(name)) && ...
                    isreal(request.(name)) && isscalar(request.(name)) && ...
                    isfinite(request.(name)) && request.(name)>0 && ...
                    request.(name)==fix(request.(name)), ...
                    'sixgr:mimo:UnsupportedTypeIIProfile','Type-II requires explicit positive integer %s.',name);
                out.(name)=double(request.(name));
            end
            geometries=[2 1;2 2;4 1;3 2;6 1;4 2;8 1;4 3;6 2;12 1;4 4;8 2;16 1];
            assert(ismember([out.N1 out.N2],geometries,'rows') && ...
                out.Ports==2*out.N1*out.N2 && out.O1==4 && ...
                out.O2==1+3*(out.N2>1) && ismember(out.Rank,[1 2]) && ...
                ismember(out.NumberOfBeams,2:4) && out.NumberOfBeams<=out.Ports/2 && ...
                (out.Ports~=4 || out.NumberOfBeams==2) && ...
                ismember(out.PhaseAlphabetSize,[4 8]), ...
                'sixgr:mimo:UnsupportedTypeIIProfile','Invalid TS 38.214 Type-II geometry/rank/beam/phase tuple.');
            assert(isfield(request,'CodebookType') && strcmpi(string(request.CodebookType),"typeII") && ...
                isfield(request,'FrequencyGranularity') && strcmpi(string(request.FrequencyGranularity),"wideband"), ...
                'sixgr:mimo:UnsupportedTypeIIProfile','This reconstruction requires explicit wideband Type-II, not enhanced Type-II or port selection.');
            assert(~isfield(request,'SubbandAmplitude') || isequal(request.SubbandAmplitude,false) || ...
                isequal(request.SubbandAmplitude,0), ...
                'sixgr:mimo:UnsupportedTypeIIProfile','Subband-amplitude reconstruction is not enabled.');
            assert(~isfield(request,'CodebookSubsetRestriction') || isempty(request.CodebookSubsetRestriction), ...
                'sixgr:mimo:UnsupportedTypeIIProfile','Nonempty Type-II subset restrictions require a separately validated restriction decoder.');
        end
    end
end

function [width,fields]=localCountIndicatorLayout(layout,allowedRanks)
assert(isnumeric(allowedRanks) && isreal(allowedRanks) && isrow(allowedRanks) && ...
    ~isempty(allowedRanks) && all(ismember(allowedRanks,[1 2])) && ...
    isequal(allowedRanks,unique(allowedRanks,'sorted')) && ...
    ismember(layout.Rank,allowedRanks), ...
    'sixgr:mimo:InvalidRI','Type-II requires explicit allowed ranks containing the received RI.');
width=ceil(log2(2*layout.NumberOfBeams-1));
fields=1+ismember(2,allowedRanks);
end

function counts=localNonzeroCounts(counts,L,r)
assert(isnumeric(counts) && isreal(counts) && isequal(size(counts),[1 r]) && ...
    all(isfinite(counts)) && all(counts==fix(counts) & counts>=1 & counts<=2*L), ...
    'sixgr:mimo:InvalidTypeIINonzeroCounts', ...
    'Received Type-II coefficient counts require one integer in [1,2L] per received layer.');
counts=double(counts);
end

function value=localIndices(s,name,shape,maximum)
assert(isfield(s,name) && isnumeric(s.(name)) && isreal(s.(name)) && ...
    isequal(size(s.(name)),shape) && all(isfinite(s.(name)(:))) && ...
    all(s.(name)(:)>=0 & s.(name)(:)<=maximum & s.(name)(:)==fix(s.(name)(:))), ...
    'sixgr:mimo:InvalidPMI','Type-II %s has invalid dimensions or index range.',name);
value=double(s.(name));
end
