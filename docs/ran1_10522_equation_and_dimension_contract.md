# RAN1 AI 10.5.2.2 equation and dimension contract

For allocation length `N_sym`, group length `X`, first start `l0`, last start is `l_max=N_sym-X` and `D=l_max-l0`. Implicit group count is `1` for `D=0`, otherwise `1+ceil(D/G)`, followed by the minimum supported `L` satisfying `l0+L*X<=N_sym`. Supported counts are `1:6` for `X=1`, `1:3` for `X=2`, and `1` for `X=4`.

For `L>1`, `q=floor(D/(L-1))` and `r=D-q(L-1)`. The first `L-1-r` gaps are `q`; the final `r` gaps are `q+1`. Consequently the last start equals `l_max`, gap spread is at most one, and longer gaps are placed at the end. Invalid tuples throw and never shift.

Pre-estimation storage is `2 Q_IQ N_rx N_sc N_wait` bits. TD-OCC post-despreading noise variance is `sigma_pre^2/X`. Region bundles use inclusive zero-based `[start_PRB,end_PRB]` intervals and restart at each region boundary; each region has at most one shortened edge bundle. RBG compatibility requires both `P mod N=0` and region-start alignment. Residual phase is represented by the configured affine frequency/time/differential-delay expression in `FrequencyStructure.residualPhase`.
