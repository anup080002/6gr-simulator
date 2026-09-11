function subcarriers=linearReferenceSubcarriers(grid,indices)
% nrExtractResources consumes linear NR resource indices, not [k,l] pairs.
% A matrix column identifies a reference port; reduce every linear index
% modulo K before grouping by RB. Keep column-major ordering for extraction.
validateattributes(indices,{'numeric'},{'real','finite','integer','positive'});
K=size(grid,1);
assert(K>0,'sixgr:phy:ul:MissingReferenceGrid','Reference indices require a nonempty receive-grid frequency axis.');
subcarriers=mod(double(indices(:))-1,K)+1;
end
