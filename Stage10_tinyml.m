function Stage10_tinyml()
% Desktop-side TinyML suitability estimates (no MCU is claimed). Candidate models are scored on
% Regime A and B, sized, and put through a simple model-selection rule.
rng(1);
assets = {'PV','Battery'};
files  = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
regCol = {'splitA','splitB'};
nMeas  = [4 3];                 % measured channels per asset (each can need a 60 s window buffer)
nRes   = [2 1];                 % residual signals that get Stage 9 windows (PV: current, power; battery: voltage)
twinFlops = [320 15];           % rough flops per 0.1 s sample: PV Newton solver (8 iterations x ~40), battery 1RC update
tol    = 0.10;                  % selection rule: any model within 10% of the best error is acceptable
seeds  = [1 2 3];               % neural-network seeds
rows = {};

for a = 1:2
    F  = readtable(files{a});  F = [F engineer(F, assets{a})];
    vn = F.Properties.VariableNames;
    S  = vn(startsWith(vn,'S_'));  E = vn(startsWith(vn,'E_'));  T = vn(startsWith(vn,'T_'));
    tW = endsWith(T,'_Mean') | endsWith(T,'_Std') | endsWith(T,'_MaxAbs') | endsWith(T,'_Trend');
    Tw = T(tW);

    %        model    name                            columns      sensor-buffers  Twin
    cand = { 'ridge', 'S2 sensor + windows',          S,           true,  false;
             'ridge', 'S3 sensor strong',             [S E],       true,  false;
             'ridge', 'T1 Twin only',                 T,           false, true;
             'ridge', 'C2 strong + residual windows', [S E Tw],    true,  true;
             'ridge', 'C3 strong + all Twin',         [S E T],     true,  true;
             'nn',    'S3 sensor strong',             [S E],       true,  false;
             'nn',    'T1 Twin only',                 T,           false, true;
             'nn',    'C2 strong + residual windows', [S E Tw],    true,  true;
             'nn',    'C3 strong + all Twin',         [S E T],     true,  true;
             'trees', 'S3 sensor strong',             [S E],       true,  false;
             'trees', 'C3 strong + all Twin',         [S E T],     true,  true };

    for c = 1:size(cand,1)
        m = cand{c,1};  cols = cand{c,3};  hasS = cand{c,4};  hasTwin = cand{c,5};
        X = F{:,cols};  nF = numel(cols);
        mae = nan(1,2);  nodes = nan(1,2);  sd = NaN;
        for r = 1:2
            sp = string(F.(regCol{r}));  tr = sp == "train";  te = sp == "test";
            y = F.D(te);
            switch m
                case 'ridge'
                    p = apply_ridge(fit_ridge(X(tr,:), F.D(tr), 1), X(te,:));
                    mae(r) = mean(abs(p - y));
                case 'nn'
                    e = nan(1,numel(seeds));
                    for k = 1:numel(seeds)
                        rng(seeds(k));
                        try
                            mn = fitrnet(X(tr,:), F.D(tr), 'LayerSizes', 8, 'Standardize', true, ...
                                         'Activations','relu', 'IterationLimit', 300, 'Verbose', 0);
                            p = min(max(predict(mn, X(te,:)), 0), 1);
                            e(k) = mean(abs(p - y));
                        catch
                        end
                    end
                    mae(r) = mean(e, 'omitnan');
                    if r == 1, sd = std(e, 'omitnan'); end
                case 'trees'
                    mt = fitrensemble(X(tr,:), F.D(tr), 'Method','Bag', 'NumLearningCycles',60, ...
                                      'Learners', templateTree('MinLeafSize',5));
                    p = min(max(predict(mt, X(te,:)), 0), 1);
                    mae(r) = mean(abs(p - y));
                    try, nodes(r) = sum(cellfun(@(q) q.NumNodes, mt.Trained)); catch, end
            end
        end

        % ----- size and cost estimates -----
        ramModel = 0;
        switch m
            case 'ridge'
                nP = nF + 1;            flash = 4*nP;   macs = nF;           % scaling folded into the weights
            case 'nn'
                nP = (nF+1)*8 + 9;      flash = 4*nP;   macs = nF*8 + 8;     ramModel = 8*4;
            case 'trees'
                nP = mean(nodes, 'omitnan');  flash = 12*nP;                 % about 12 bytes per node (feature, threshold, children)
                macs = 60 * ceil(log2((nP/60 + 1)/2));                       % comparisons, balanced-tree lower bound
        end
        nBuf  = hasS*nMeas(a) + hasTwin*nRes(a);                             % signals needing a 60 s window buffer
        ram10 = nBuf*600*4 + nF*4 + ramModel;                                % float32 samples at the simulated 10 Hz
        ram1  = nBuf*60*4  + nF*4 + ramModel;                                % if the signals are sampled at 1 Hz
        kflop = (nBuf*10*20 + hasTwin*10*twinFlops(a) + 2*macs) / 1000;      % thousand flops per second, rough
        if hasTwin, grp = 'Twin-using'; else, grp = 'sensor-only'; end
        rows(end+1,:) = {assets{a}, m, cand{c,2}, nF, round(nP), round(flash), round(macs), round(ram10), round(ram1), ...
                         round(kflop,1), round(mae(1),4), round(mae(2),4), round(mean(mae),4), round(sd,4), grp, ''}; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', {'Asset','Model','Candidate','nFeatures','nParams','Flash_B','MACs','RAM_B_10Hz','RAM_B_1Hz', ...
                                       'kFLOP_per_s','MAE_A','MAE_B','MeanMAE','NN_seed_SD','Group','Selected'});

% ----- model-selection rule: within 10% of the best error of its group, take the smallest flash. Trees are reference only. -----
T.Selected = repmat({''}, height(T), 1);
for a = 1:2
    for g = {'sensor-only','Twin-using'}
        ix = find(strcmp(T.Asset, assets{a}) & strcmp(T.Group, g{1}) & ~strcmp(T.Model,'trees') & ~isnan(T.MeanMAE));
        best = min(T.MeanMAE(ix));
        ok = ix(T.MeanMAE(ix) <= (1+tol)*best);
        [~, j] = min(T.Flash_B(ok));
        T.Selected{ok(j)} = 'SELECTED';
    end
end
writetable(T, 'Stage10_TinyML_Estimates.csv');

fprintf('\n=== TinyML SUITABILITY ESTIMATES (desktop-side; float32; no MCU claimed) ===\n');
disp(T(:, {'Asset','Model','Candidate','nFeatures','nParams','Flash_B','MACs','RAM_B_10Hz','RAM_B_1Hz','kFLOP_per_s'}));
fprintf('\n=== ACCURACY (fixed ridge lambda = 1; NN = mean of 3 seeds; trees are reference only) ===\n');
disp(T(:, {'Asset','Model','Candidate','MAE_A','MAE_B','MeanMAE','NN_seed_SD','Group','Selected'}));

fprintf('\n=== IS THE TWIN WORTH ITS COST? (selected model of each group) ===\n');
for a = 1:2
    s = T(strcmp(T.Asset,assets{a}) & strcmp(T.Group,'sensor-only') & strcmp(T.Selected,'SELECTED'), :);
    t = T(strcmp(T.Asset,assets{a}) & strcmp(T.Group,'Twin-using')  & strcmp(T.Selected,'SELECTED'), :);
    fprintf('%s: sensor-only  %s %s: error %.4f, flash %d B, RAM %d B (10 Hz) / %d B (1 Hz), %.1f kFLOP/s\n', assets{a}, s.Model{1}, s.Candidate{1}, s.MeanMAE, s.Flash_B, s.RAM_B_10Hz, s.RAM_B_1Hz, s.kFLOP_per_s);
    fprintf('%s: Twin-using   %s %s: error %.4f, flash %d B, RAM %d B (10 Hz) / %d B (1 Hz), %.1f kFLOP/s\n', assets{a}, t.Model{1}, t.Candidate{1}, t.MeanMAE, t.Flash_B, t.RAM_B_10Hz, t.RAM_B_1Hz, t.kFLOP_per_s);
    fprintf('%s: error reduced by %.0f%% for %.1fx the flops per second\n\n', assets{a}, 100*(s.MeanMAE - t.MeanMAE)/s.MeanMAE, t.kFLOP_per_s/s.kFLOP_per_s);
end
fprintf('Saved Stage10_TinyML_Estimates.csv\n');
end

function E = engineer(F, asset)
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

function mdl = fit_ridge(X, y, lam)
mu = mean(X);  sd = std(X) + 1e-12;  Z = (X - mu) ./ sd;
beta = (Z'*Z + lam*eye(size(Z,2))) \ (Z' * (y - mean(y)));
mdl = struct('mu',mu,'sd',sd,'beta',beta,'ybar',mean(y));
end

function yhat = apply_ridge(mdl, X)
yhat = mdl.ybar + ((X - mdl.mu) ./ mdl.sd) * mdl.beta;
yhat = min(max(yhat, 0), 1);
end