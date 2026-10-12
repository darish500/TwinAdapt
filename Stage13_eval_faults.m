function Stage13_eval_faults()
rng(1);
P  = sortrows(readtable('Stage13_Fault_Manifest.csv'), 'run');
fa = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
fd = {'Stage11_Features_D_PV.csv','Stage11_Features_D_Battery.csv'};
assets  = {'PV','Battery'};
chanCol = {'pvChannel','bChannel'};   typeCol = {'pvType','bType'};
resCol  = {'T_PV_Residual_Current','T_Battery_Residual_Voltage'};
regCol  = {'splitA','splitB'};        regName = {'A: unseen levels','B: unseen profile'};
H = {};  G = {};  Dt = {};
for a = 1:2
    FA = readtable(fa{a});  FA = [FA engineer(FA, assets{a})];
    FD = readtable(fd{a});  FD = [FD engineer(FD, assets{a})];
    assert(isequal(FA.run, FD.run) && isequal(FA.t, FD.t), 'rows of A and D do not line up');
    assert(max(abs(FA.D - FD.D)) < 1e-9, 'health labels differ');
    vn = FA.Properties.VariableNames;
    Sc = vn(startsWith(vn,'S_'));  Ec = vn(startsWith(vn,'E_'));  Tc = vn(startsWith(vn,'T_'));
    chan = string(P.(chanCol{a}));  typ = string(P.(typeCol{a}));
    types = ["bias","stuck","noise","drift"];

    % ---- (3) does the Twin residual flag the fault? ----
    [ur, ~, gi] = unique(FA.run);
    assert(isequal(ur, P.run), 'run list differs from the fault plan');
    cleanRes = accumarray(gi, abs(FA.(resCol{a})), [], @mean);     % per-run mean |residual|, clean data
    faultRes = accumarray(gi, abs(FD.(resCol{a})), [], @mean);     % same, faulted data
    thr = max(cleanRes);                                           % largest value any CLEAN run reaches (all health levels)
    hit = faultRes > thr;
    Dt(end+1,:) = {assets{a}, 'ALL', 'all', numel(ur), round(100*mean(hit)), round(median(faultRes./cleanRes),2)}; %#ok<AGROW>
    for v = types
        k = typ == v;
        Dt(end+1,:) = {assets{a}, 'fault type', char(v), nnz(k), round(100*mean(hit(k))), round(median(faultRes(k)./cleanRes(k)),2)}; %#ok<AGROW>
    end
    for v = unique(chan)'
        k = chan == v;
        Dt(end+1,:) = {assets{a}, 'channel', char(v), nnz(k), round(100*mean(hit(k))), round(median(faultRes(k)./cleanRes(k)),2)}; %#ok<AGROW>
    end

    % ---- (1)+(2) health-prediction error, clean vs faulted ----
    for r = 1:2
        sp = string(FA.(regCol{r}));  tr = sp == "train";  te = sp == "test";
        y  = FA.D(te);
        cs = [Sc Ec];  ct = [Sc Ec Tc];
        for m = ["ridge","trees"]
            ms = fit_model(m, FA{tr,cs}, FA.D(tr));
            mt = fit_model(m, FA{tr,ct}, FA.D(tr));
            psc = apply_model(m, ms, FA{te,cs});   psf = apply_model(m, ms, FD{te,cs});
            ptc = apply_model(m, mt, FA{te,ct});   ptf = apply_model(m, mt, FD{te,ct});
            a1 = mean(abs(psc-y));  a2 = mean(abs(psf-y));  b1 = mean(abs(ptc-y));  b2 = mean(abs(ptf-y));
            H(end+1,:) = {assets{a}, regName{r}, char(m), round(a1,4), round(a2,4), round(b1,4), round(b2,4), ...
                          round(a2-a1,4), round(b2-b1,4), ternary2(b2 < a2)}; %#ok<AGROW>
            if m == "ridge"
                [uu, ~, g2] = unique(FA.run(te));
                pr = @(p) accumarray(g2, abs(p - y), [], @mean);
                e1 = pr(psc); e2 = pr(psf); e3 = pr(ptc); e4 = pr(ptf);
                [~, loc] = ismember(uu, P.run);
                ty = typ(loc);  ch = chan(loc);
                G = [G; grp(assets{a}, regName{r}, 'ALL', 'all', true(size(uu)), e1, e2, e3, e4)]; %#ok<AGROW>
                for v = types
                    G = [G; grp(assets{a}, regName{r}, 'fault type', char(v), ty == v, e1, e2, e3, e4)]; %#ok<AGROW>
                end
                for v = unique(ch)'
                    G = [G; grp(assets{a}, regName{r}, 'channel', char(v), ch == v, e1, e2, e3, e4)]; %#ok<AGROW>
                end
            end
        end
    end
end
H  = cell2table(H,  'VariableNames', {'Asset','Regime','Model','MAE_sensor_clean','MAE_sensor_fault','MAE_twin_clean','MAE_twin_fault', ...
                                       'Sensor_damage','Twin_damage','Twin_better_when_faulted'});
G  = cell2table(G,  'VariableNames', {'Asset','Regime','GroupBy','Group','nRuns','MAE_sensor_clean','MAE_sensor_fault','MAE_twin_clean','MAE_twin_fault','Better_when_faulted'});
Dt = cell2table(Dt, 'VariableNames', {'Asset','GroupBy','Group','nRuns','Pct_faults_flagged','Median_residual_ratio'});
fprintf('\n=== D1: overall error, clean vs faulted (trees in Regime A cannot interpolate, ignore those rows) ===\n');  disp(H);
fprintf('\n=== D2: ridge, broken down by fault type and sensor channel (test runs only) ===\n');                       disp(G);
fprintf('\n=== D3: does the Twin residual flag the fault? (flag = per-run mean |residual| above the largest clean run) ===\n'); disp(Dt);
writetable(H,'Stage13_Eval_D1.csv'); writetable(G,'Stage13_Eval_D2.csv'); writetable(Dt,'Stage13_Eval_D3.csv');
end

function row = grp(asset, regime, by, label, mask, e1, e2, e3, e4)
n = nnz(mask);
if n == 0, row = cell(0,10); return; end
a = mean(e1(mask)); b = mean(e2(mask)); c = mean(e3(mask)); d = mean(e4(mask));
if d < b, w = 'Twin'; else, w = 'Sensor'; end
row = {asset, regime, by, label, n, round(a,3), round(b,3), round(c,3), round(d,3), w};
end

function s = ternary2(ok)
if ok, s = 'yes'; else, s = 'no'; end
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

function mdl = fit_model(m, X, y)
if m == "trees"
    mdl = fitrensemble(X, y, 'Method','Bag', 'NumLearningCycles',100, 'Learners', templateTree('MinLeafSize',5));
else
    mu = mean(X);  sd = std(X) + 1e-12;  Z = (X - mu) ./ sd;
    beta = (Z'*Z + eye(size(Z,2))) \ (Z' * (y - mean(y)));
    mdl = struct('mu',mu,'sd',sd,'beta',beta,'ybar',mean(y));
end
end

function yhat = apply_model(m, mdl, X)
if m == "trees", yhat = predict(mdl, X);
else, yhat = mdl.ybar + ((X - mdl.mu) ./ mdl.sd) * mdl.beta; end
yhat = min(max(yhat, 0), 1);
end