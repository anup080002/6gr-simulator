function out = sixgr_build_mex_accel(varargin)
% sixgr_build_mex_accel
% Build optional MEX acceleration kernels used by campaign hot loops.
%
% Usage:
%   out = sixgr_build_mex_accel();
%   out = sixgr_build_mex_accel("Verbose", true);

ip = inputParser;
ip.addParameter("Verbose", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
verbose = logical(ip.Results.Verbose);

setup6GRSimToolkit("Verbose", verbose);

out = struct();
out.Ok = true;
out.Built = strings(0,1);
out.Failed = strings(0,1);
out.Notes = strings(0,1);

cfg = coder.config("mex");
cfg.EnableMemcpy = true;
cfg.IntegrityChecks = false;
cfg.SaturateOnIntegerOverflow = false;
cfg.DynamicMemoryAllocation = "Threshold";
cfg.DynamicMemoryAllocationThreshold = 65536;

% Optional acceleration kernels for heavy PHY blocks (do not fail campaign).
try
    C = coder.typeof(complex(0), [inf inf], [1 1]);
    codegen -config cfg sixgr_fft_papr_kernel ...
        -args {C, 0};
    out.Built(end+1,1) = "sixgr_fft_papr_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_fft_papr_kernel_mex";
    out.Notes(end+1,1) = "FFT PAPR kernel build skipped: " + string(ME.message);
end

try
    M = coder.typeof(0, [inf inf], [1 1]);
    codegen -config cfg sixgr_ldpc_decode_batch_kernel ...
        -args {M, 0, 0, uint8(0)};
    out.Built(end+1,1) = "sixgr_ldpc_decode_batch_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_ldpc_decode_batch_kernel_mex";
    out.Notes(end+1,1) = "LDPC batch kernel build skipped: " + string(ME.message);
end

try
    Vc = coder.typeof(complex(0), [inf 1], [1 0]);
    codegen -config cfg sixgr_channel_est_ls_kernel ...
        -args {Vc, Vc};
    out.Built(end+1,1) = "sixgr_channel_est_ls_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_channel_est_ls_kernel_mex";
    out.Notes(end+1,1) = "Channel-est LS kernel build skipped: " + string(ME.message);
end

try
    Vb = coder.typeof(uint8(0), [inf 1], [1 0]);
    codegen -config cfg sixgr_tb_bytes_to_bits_kernel ...
        -args {Vb};
    out.Built(end+1,1) = "sixgr_tb_bytes_to_bits_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_tb_bytes_to_bits_kernel_mex";
    out.Notes(end+1,1) = "TB bytes->bits kernel build skipped: " + string(ME.message);
end

try
    V = coder.typeof(0, [inf 1], [1 0]);
    codegen -config cfg sixgr_tb_bits_to_bytes_kernel ...
        -args {V};
    out.Built(end+1,1) = "sixgr_tb_bits_to_bytes_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_tb_bits_to_bytes_kernel_mex";
    out.Notes(end+1,1) = "TB bits->bytes kernel build skipped: " + string(ME.message);
end

try
    C = coder.typeof(complex(0), [inf inf], [1 1]);
    codegen -config cfg sixgr_awgn_complex_kernel ...
        -args {C, 0};
    out.Built(end+1,1) = "sixgr_awgn_complex_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_awgn_complex_kernel_mex";
    out.Notes(end+1,1) = "AWGN kernel build skipped: " + string(ME.message);
end

try
    C = coder.typeof(complex(0), [inf inf], [1 1]);
    codegen -config cfg sixgr_freq_shift_kernel ...
        -args {C, 0, 0};
    out.Built(end+1,1) = "sixgr_freq_shift_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_freq_shift_kernel_mex";
    out.Notes(end+1,1) = "Freq-shift kernel build skipped: " + string(ME.message);
end

try
    Vc = coder.typeof(complex(0), [inf 1], [1 0]);
    codegen -config cfg sixgr_corr_metric_kernel ...
        -args {Vc, Vc};
    out.Built(end+1,1) = "sixgr_corr_metric_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_corr_metric_kernel_mex";
    out.Notes(end+1,1) = "Correlation metric kernel build skipped: " + string(ME.message);
end

try
    Vc = coder.typeof(complex(0), [inf 1], [1 0]);
    Vhz = coder.typeof(0, [inf 1], [1 0]);
    codegen -config cfg sixgr_freq_corr_search_kernel ...
        -args {Vc, Vc, Vhz, 0};
    out.Built(end+1,1) = "sixgr_freq_corr_search_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_freq_corr_search_kernel_mex";
    out.Notes(end+1,1) = "Freq-corr batch kernel build skipped: " + string(ME.message);
end

try
    Vi8 = coder.typeof(int8(0), [inf 1], [1 0]);
    codegen -config cfg sixgr_tb_resize_bits_kernel ...
        -args {Vi8, 0};
    out.Built(end+1,1) = "sixgr_tb_resize_bits_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_tb_resize_bits_kernel_mex";
    out.Notes(end+1,1) = "TB resize kernel build skipped: " + string(ME.message);
end

try
    V = coder.typeof(0, [inf 1], [1 0]);
    codegen -config cfg sixgr_truth_grant_hash_kernel ...
        -args {V, coder.typeof(0,[2 1],[0 0]), 0, 0, 0, 0, 0, 0};
    out.Built(end+1,1) = "sixgr_truth_grant_hash_kernel_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_truth_grant_hash_kernel_mex";
    out.Notes(end+1,1) = "Grant-hash kernel build skipped: " + string(ME.message);
end

try
    mex("-output", "sixgr_struct_get_mex", "sixgr_struct_get_mex.c");
    out.Built(end+1,1) = "sixgr_struct_get_mex";
catch ME
    out.Failed(end+1,1) = "sixgr_struct_get_mex";
    out.Notes(end+1,1) = "structGet MEX build skipped: " + string(ME.message);
end

if verbose
    disp(out);
end
end
