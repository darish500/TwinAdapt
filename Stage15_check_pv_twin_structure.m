function Stage15_check_pv_twin_structure()
% Read-only audit check (does not touch any dataset, model or result).
% Question: with IDENTICAL parameters, does the PV Twin (PV_Digital_twin MATLAB Function) return the same current as the
% physical PV model (PV_model MATLAB Function, "PV_SingleDiode_Solver")?
% Both functions below are copied line for line from Reformable_AI_2025.slx (the code inside the two MATLAB Function blocks);
% only the function names and the way the parameters are passed differ. Parameters come from PV_Params_Stage1.mat (the file
% written by reformable_AI.m), with no mismatch and no ageing.
% Writes only: Stage15_PV_Twin_Structure_Check.csv  (refuses to overwrite).
here = fileparts(which('Stage15_check_pv_twin_structure'));
if isempty(here), error('Keep this file in the Reformable_AI folder.'); end
cd(here);
out = 'Stage15_PV_Twin_Structure_Check.csv';
if isfile(out), error('%s already exists; not overwriting.', out); end
P = load('PV_Params_Stage1.mat');           % Rs Rsh Iph_ref I0_ref n Ns Ki Eg Tref Gref ...
kB = 1.380649e-23;  q = 1.602176634e-19;
Gs  = [100 200 300 500 800 1000 1100];
Tcs = [5 15 25 35 45 55];
Vs  = [16 17 17.5 18 19];
rows = zeros(0, 7);
for G = Gs
  for Tc = Tcs
    for V = Vs
      Ip = plant_fcn(G, Tc, V, P.Rs, P.Rsh, P.Iph_ref, P.I0_ref, P.n, P.Ns, P.Ki, P.Eg, P.Gref, P.Tref);
      It = twin_fcn (G, Tc, V, P.Rs, P.Rsh, P.Iph_ref, P.I0_ref, P.n, P.Ns, P.Ki, P.Eg, P.Tref, P.Gref, kB, q);
      rows(end+1,:) = [G Tc V Ip It It-Ip, double(isfinite(It) && It >= 0)]; %#ok<AGROW>
    end
  end
end
T = array2table(rows, 'VariableNames', {'G','Tc','V','I_plant','I_twin','Twin_minus_plant','TwinCurrentValid'});
writetable(T, out);
ok = rows(:,7) == 1;
fprintf('Grid points: %d (valid Twin output at %d).\n', size(rows,1), nnz(ok));
fprintf('Largest |Twin - plant| over valid points: %.4g A\n', max(abs(rows(ok,6))));
fprintf('At Tc = 25 C (the reference temperature) largest |Twin - plant|: %.4g A\n', max(abs(rows(ok & rows(:,2)==25, 6))));
fprintf('At Tc = 55 C, G = 1000: Twin - plant = %.4g A (V = 17 V)\n', rows(rows(:,1)==1000 & rows(:,2)==55 & rows(:,3)==17, 6));
fprintf('Saved %s\n', out);
end

function [I, P] = plant_fcn(G, Tc_C, V, Rs, Rsh, Iph_ref, I0_ref, n, Ns, Ki, Eg, Gref, Tref)
% copied from PV_model/MATLAB Function (PV_SingleDiode_Solver)
k = 1.380649e-23;
q = 1.602176634e-19;
Tc = Tc_C + 273.15;
Vt = Ns*k*Tc/q;
Iph = (Iph_ref + Ki*(Tc - Tref)) * (G/Gref);
I0  = I0_ref * (Tc/Tref)^3 * exp((q*Eg/(n*k)) * (1/Tref - 1/Tc));
I = Iph;
for iter = 1:50
    expTerm = exp(min((V + I*Rs)/(n*Vt), 700));
    f  = Iph - I0*(expTerm - 1) - (V + I*Rs)/Rsh - I;
    df = -I0*(Rs/(n*Vt))*expTerm - Rs/Rsh - 1;
    dI = f/df;
    I  = I - dI;
    if abs(dI) < 1e-8
        break;
    end
end
I = max(I, 0);
P = V * I;
end

function PV_Twin_Current = twin_fcn(G, Tc_C, V, PV_Twin_Rs, PV_Twin_Rsh, PV_Twin_Iph_ref, PV_Twin_I0_ref, PV_Twin_n, PV_Twin_Ns, PV_Twin_Ki, PV_Twin_Eg, PV_Twin_Tref, PV_Twin_Gref, k_B, q)
% copied from PV_Digital_twin/MATLAB Function (inputs: measured G, Tc, V)
T_K = Tc_C + 273.15;
Iph = PV_Twin_Iph_ref * (G/PV_Twin_Gref) * (1 + PV_Twin_Ki*(T_K - PV_Twin_Tref));
I0 = PV_Twin_I0_ref * (T_K/PV_Twin_Tref)^3 * ...
     exp((q*PV_Twin_Eg/(PV_Twin_n*k_B)) * (1/PV_Twin_Tref - 1/T_K));
Vt = PV_Twin_n * PV_Twin_Ns * k_B * T_K / q;
I = Iph;
for k = 1:8
    expTerm = exp((V + I*PV_Twin_Rs)/Vt);
    f  = Iph - I0*(expTerm - 1) - (V + I*PV_Twin_Rs)/PV_Twin_Rsh - I;
    fp = -I0*(PV_Twin_Rs/Vt)*expTerm - PV_Twin_Rs/PV_Twin_Rsh - 1;
    I = I - f/fp;
end
PV_Twin_Current = I;
end