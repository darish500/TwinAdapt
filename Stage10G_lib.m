function varargout = Stage10G_lib(op, varargin)
% Shared helpers for the corrected Stage 10 evaluation ("Stage10G_*"). One file so that the validation/freeze step and the
% final test use byte-identical code (its SHA-256 is recorded in the frozen configuration).
%   [F, S] = Stage10G_lib('sets', F, asset)        add E_ ratio columns; S(k).name / S(k).cols = the feature sets
%   p      = Stage10G_lib('ridge', Xtr, ytr, Xte, lambda)     ridge, scaling from the TRAINING matrix only, output clipped to [0,1]
%   p      = Stage10G_lib('nn', Xtr, ytr, Xte, seed, hidden, iters)   one small ReLU network (fitrnet), Standardize = true
%   [mae, r2] = Stage10G_lib('metrics', y, p)
%   h      = Stage10G_lib('sha256', file)
switch op
    case 'sets',    [varargout{1}, varargout{2}] = make_sets(varargin{:});
    case 'ridge',   varargout{1} = ridge_predict(varargin{:});
    case 'nn',      varargout{1} = nn_predict(varargin{:});
    case 'metrics', [varargout{1}, varargout{2}] = metrics(varargin{:});
    case 'sha256',  varargout{1} = sha256(varargin{1});
    otherwise,      error('unknown op %s', op);
end
end

function [F, S] = make_sets(F, asset)
F = [F engineer(F, asset)];
vn = F.Properties.VariableNames;
Sc = vn(startsWith(vn,'S_'));  Ec = vn(startsWith(vn,'E_'));  T = vn(startsWith(vn,'T_'));
isW = endsWith(T,'_Mean') | endsWith(T,'_Std') | endsWith(T,'_MaxAbs') | endsWith(T,'_Trend');   % Stage 9 window summaries of the residuals
Tw = T(isW);  Ti = T(~isW);  Tr = Ti(contains(Ti,'Residual'));                                   % residual windows / raw residuals
S = struct('name', {}, 'cols', {});
S = add(S, 'S3 sensor strong (baseline)',     [Sc Ec]);
S = add(S, 'C1 strong + raw residuals',       [Sc Ec Tr]);
S = add(S, 'C2 strong + residual windows',    [Sc Ec Tw]);
S = add(S, 'C2-mean (window mean only)',      [Sc Ec Tw(endsWith(Tw,'_Mean'))]);
S = add(S, 'C2-std (window std only)',        [Sc Ec Tw(endsWith(Tw,'_Std'))]);
S = add(S, 'C2-maxabs (window max-abs only)', [Sc Ec Tw(endsWith(Tw,'_MaxAbs'))]);
S = add(S, 'C2-trend (window trend only)',    [Sc Ec Tw(endsWith(Tw,'_Trend'))]);
end

function S = add(S, name, cols)
S(end+1).name = name;
S(end).cols = cols;
end

function E = engineer(F, asset)                      % identical to the Stage 10 ablation script
E = table();
if strcmp(asset,'PV')
    G = max(F.S_PV_Irradiance_Final_mean20, 1);  I = F.S_PV_Current_Final_mean20;  V = F.S_PV_Voltage_Final_mean20;
    E.E_I_over_G     = I ./ G;
    E.E_P_over_G     = V .* I ./ G;
    E.E_Iinst_over_G = F.S_PV_Current_Final ./ max(F.S_PV_Irradiance_Final, 1);
else
    V = F.S_Battery_Voltage_Final_mean20;  I = max(F.S_Battery_Current_Final_mean20, 0.05);
    E.E_V_over_I       = V ./ I;
    E.E_P              = V .* I;
    E.E_Vstd_over_Istd = F.S_Battery_Voltage_Final_std20 ./ (F.S_Battery_Current_Final_std20 + 0.05);
end
end

function yhat = ridge_predict(Xtr, ytr, Xte, lam)
mu = mean(Xtr);  sd = std(Xtr) + 1e-12;              % scaling statistics come from the training matrix only
Z  = (Xtr - mu) ./ sd;
beta = (Z'*Z + lam*eye(size(Z,2))) \ (Z' * (ytr - mean(ytr)));
yhat = mean(ytr) + ((Xte - mu) ./ sd) * beta;
yhat = min(max(yhat, 0), 1);
end

function yhat = nn_predict(Xtr, ytr, Xte, seed, hidden, iters)
rng(seed);
mn = fitrnet(Xtr, ytr, 'LayerSizes', hidden, 'Standardize', true, 'Activations', 'relu', 'IterationLimit', iters, 'Verbose', 0);
yhat = min(max(predict(mn, Xte), 0), 1);
end

function [mae, r2] = metrics(y, p)
mae = mean(abs(p - y));
r2  = 1 - sum((y - p).^2) / sum((y - mean(y)).^2);
end

function h = sha256(f)
fid = fopen(f, 'r');  b = fread(fid, inf, '*uint8');  fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(b);
u = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(double(u), 2).', 1, []));
end