function Stage10_ml_compare()
rng(1);
files   = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
assets  = {'PV','Battery'};
regCol  = {'splitA','splitB'};
regName = {'A: unseen levels','B: unseen profile'};

out = {};
for a = 1:2
    F  = readtable(files{a});
    vn = F.Properties.VariableNames;
    Sc = vn(startsWith(vn,'S_'));          % sensor-only features
    Tc = vn(startsWith(vn,'T_'));          % Twin features
    sets = {'time only', {'t'}; 'sensor-only', Sc; 'sensor+Twin', [Sc Tc]};
    y = F.D;
    for r = 1:2
        sp = string(F.(regCol{r}));
        tr = sp == "train";   te = sp == "test";
        for s = 1:size(sets,1)
            X = F{:, sets{s,2}};
            for m = ["trees","ridge"]
                if sets{s,1} == "time only" && m == "ridge", continue; end   % one control is enough
                yhat = fit_predict(m, X(tr,:), y(tr), X(te,:));
                err  = yhat - y(te);
                mae  = mean(abs(err));
                r2   = 1 - sum(err.^2) / sum((y(te) - mean(y(te))).^2);
                out(end+1,:) = {assets{a}, regName{r}, sets{s,1}, char(m), mae, r2}; %#ok<AGROW>
            end
        end
        fprintf('%s | %s | train rows %d, test rows %d (%d / %d runs)\n', assets{a}, regName{r}, ...
            nnz(tr), nnz(te), numel(unique(F.run(tr))), numel(unique(F.run(te))));
    end
end
R = cell2table(out, 'VariableNames', {'Asset','Regime','Features','Model','MAE','R2'});
R.MAE = round(R.MAE, 4);  R.R2 = round(R.R2, 3);
disp(R);
writetable(R, 'Stage10_ML_Results_DatasetA.csv');
end

function yhat = fit_predict(m, Xtr, ytr, Xte)
if m == "trees"
    mdl  = fitrensemble(Xtr, ytr, 'Method','Bag', 'NumLearningCycles',200, ...
                        'Learners', templateTree('MinLeafSize',5));
    yhat = predict(mdl, Xte);
else                                                      % ridge regression on standardised features
    mu = mean(Xtr);  sd = std(Xtr) + 1e-12;
    Z  = (Xtr - mu) ./ sd;
    beta = (Z'*Z + 1*eye(size(Z,2))) \ (Z' * (ytr - mean(ytr)));
    yhat = mean(ytr) + ((Xte - mu) ./ sd) * beta;
end
yhat = min(max(yhat, 0), 1);                              % health is defined on [0,1]
end