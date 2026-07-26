classdef DPDTrainer
%DPDTRAINER Indirect-learning memoryless polynomial predistorter.

    methods(Static)
        function model=train(paInput,paOutput,order,memoryDepth,profileId)
            x=double(paInput(:)); y=double(paOutput(:));
            if numel(x)~=numel(y)||numel(x)<max(16,order*4)|| ...
                    any(~isfinite(x))||any(~isfinite(y))|| ...
                    order<1||order~=round(order)||mod(order,2)==0|| ...
                    memoryDepth<1||memoryDepth~=round(memoryDepth)
                error("RF:DPDProfileMissing", ...
                    "DPD training samples/order/memory are invalid.");
            end
            orders=1:2:order;
            basis=zeros(numel(y),numel(orders)*memoryDepth);
            column=0;
            for memoryIndex=0:memoryDepth-1
                delayed=[zeros(memoryIndex,1);y(1:end-memoryIndex)];
                for k=1:numel(orders)
                    column=column+1;
                    basis(:,column)=delayed.*abs(delayed).^(orders(k)-1);
                end
            end
            coefficients=basis\x;
            if any(~isfinite(coefficients))
                error("RF:DPDProfileMissing","DPD coefficient fit failed.");
            end
            bytes=typecast([real(coefficients(:));imag(coefficients(:))],"uint8");
            model=struct("ProfileID",string(profileId),"Order",order, ...
                "MemoryDepth",memoryDepth,"Orders",orders, ...
                "Coefficients",coefficients, ...
                "CoefficientSHA256",string(sixgr.util.sha256Hex(bytes)), ...
                "Converged",true,"Source","indirect_learning_measured_pa_pairs");
        end

        function output=apply(input,model)
            if ~isstruct(model)||~all(isfield(model, ...
                    ["Orders","Coefficients","Source"]))|| ...
                    ~contains(string(model.Source),"measured")
                error("RF:DPDProfileMissing", ...
                    "DPD execution requires trained/frozen coefficients.");
            end
            output=complex(zeros(size(input),"like",input));
            column=0;
            for memoryIndex=0:model.MemoryDepth-1
                delayed=complex(zeros(size(input),"like",input));
                if memoryIndex==0
                    delayed=input;
                elseif size(input,1)>memoryIndex
                    delayed(1+memoryIndex:end,:)=input(1:end-memoryIndex,:);
                end
                for k=1:numel(model.Orders)
                    column=column+1;
                    output=output+model.Coefficients(column).*delayed.* ...
                        abs(delayed).^(model.Orders(k)-1);
                end
            end
        end
    end
end
