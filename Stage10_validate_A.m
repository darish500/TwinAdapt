function Stage10_validate_A()
PV = readtable('Stage10_PV_Controlled.csv');
BT = readtable('Stage10_Battery_Controlled.csv');
cc = @(a,b) sum((a-mean(a)).*(b-mean(b))) / sqrt(sum((a-mean(a)).^2)*sum((b-mean(b)).^2));
pf = @(ok) ternary(ok);
runs = unique(PV.run);  nrun = numel(runs);  n = 1501;

% 1. shape: 100 runs x 1501 rows, in run order
ok = nrun==100 && height(PV)==nrun*n && height(BT)==nrun*n && issorted(PV.run);
fprintf('1  100 runs x 1501 rows                        %s\n', pf(ok));

% 2. health is constant inside each run, and equals the planned level
sdP = accumarray(PV.run, PV.D_index, [], @std);  sdB = accumarray(BT.run, BT.D_batt, [], @std);
mP  = accumarray(PV.run, PV.D_index, [], @mean); mB  = accumarray(BT.run, BT.D_batt, [], @mean);
lvP = accumarray(PV.run, PV.level,   [], @mean); lvB = accumarray(BT.run, BT.level,  [], @mean);
ok = max(sdP)<1e-9 && max(sdB)<1e-9 && max(abs(mP-lvP/4))<1e-6 && max(abs(mB-lvB/4))<1e-6;
fprintf('2  health constant in a run, equals plan        %s\n', pf(ok));

% 3. health is NOT related to time (the Stage 9 confound)
cP = cc(PV.D_index, PV.t);  cB = cc(BT.D_batt, BT.t);
fprintf('3  corr(health, time): PV %.3f  Battery %.3f      %s   (Stage 9 was ~0.5-1.0)\n', cP, cB, pf(abs(cP)<0.05 && abs(cB)<0.05));

% 4. noise is independent between runs
eP = reshape(PV.PV_Current_Final - PV.True_PV_Current, n, nrun);
eB = reshape(BT.Battery_Voltage_Final - BT.True_Battery_Voltage, n, nrun);
CP = corrcoef(eP - movmean(eP,21)); CB = corrcoef(eB - movmean(eB,21));
CP(1:nrun+1:end) = 0; CB(1:nrun+1:end) = 0;
fprintf('4  max |noise corr| between any 2 runs: PV %.3f  Battery %.3f   %s\n', max(abs(CP(:))), max(abs(CB(:))), pf(max(abs(CP(:)))<0.2 && max(abs(CB(:)))<0.2));

% 5. each run sits wholly in one split
ok = true;
for r = runs', ok = ok && numel(unique(string(PV.splitA(PV.run==r))))==1 && numel(unique(string(PV.splitB(PV.run==r))))==1 ...
                       && numel(unique(string(BT.splitA(BT.run==r))))==1 && numel(unique(string(BT.splitB(BT.run==r))))==1; end
fprintf('5  every run entirely in one split              %s\n', pf(ok));

% 6. the Twin residual responds to health, and in the expected direction
rp = accumarray(PV.level+1, PV.PV_Residual_Current, [], @mean);
rb = accumarray(BT.level+1, BT.Battery_Residual_Voltage, [], @mean);
fprintf('6  PV current residual by level (D=0..1):   %s   %s\n', mat2str(round(rp',4)), pf(all(diff(rp)<0)));
fprintf('   battery voltage residual by level:        %s   %s\n', mat2str(round(rb',4)), pf(all(diff(rb)>0)));

% 7. anti-clock check on the Twin SOC, now with varied profiles
S = reshape(BT.Battery_Twin_SOC_Estimate, n, nrun);  tg = BT.t(1:n);
ct = arrayfun(@(k) cc(S(:,k), tg), 1:nrun);
ce = cc(S(end,:)', lvB);
fprintf('7  Twin SOC: median corr with time %.3f ; corr(final SOC, health level) %.3f\n', median(ct), ce);
if median(ct) < -0.9, v = 'SUSPECT (clock-like) -> excluded from the primary Twin model'; else, v = 'acceptable'; end
fprintf('   verdict: %s\n', v);

% 8. sensor noise level
fprintf('8  PV current noise std %.4f A, battery voltage noise std %.4f V\n', std(eP(:)), std(eB(:)));
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end