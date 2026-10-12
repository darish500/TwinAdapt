function T = Stage13_run_one(Dpv, Db, seed, pvID, bID, pvSeed, bSeed, fl)
% fl : one row of the fault plan (Stage13_fault_plan). Twin parameters are exact (no mismatch).
model = 'Reformable_AI_2025';
tg = (0:0.1:150)';

pv = Stage10_profile('pv',   pvID, pvSeed);
bt = Stage10_profile('batt', bID,  bSeed);
assignin('base','S10_G',  [pv.t pv.G ]);
assignin('base','S10_Tc', [pv.t pv.Tc]);
assignin('base','S10_V',  [pv.t pv.V ]);
assignin('base','S10_I',  [bt.t bt.I ]);

if bdIsLoaded(model), close_system(model, 0); end
evalin('base','reformable_AI;');
load_system(model);
c = onCleanup(@() close_system(model, 0));
set_param(model,'FastRestart','off'); set_param(model,'StopTime','150');
set_param(model,'DefaultParameterBehavior','Tunable');

% ---- sensor faults: selectors, severity 1, and fault size (set AFTER the reload) ----
set_param([model '/Constant7'],  'Value', num2str(fl.pvTarget));
set_param([model '/Constant8'],  'Value', num2str(fl.pvCode));
set_param([model '/Constant9'],  'Value', '1');
set_param([model '/Constant10'], 'Value', num2str(fl.bTarget));
set_param([model '/Constant11'], 'Value', num2str(fl.bCode));
set_param([model '/Constant12'], 'Value', '1');
assignin('base', char(fl.pvParam), fl.pvValue);
assignin('base', char(fl.bParam),  fl.bValue);

const_time(model,'PV_Degradation_Model',      Dpv*evalin('base','T_life'));
const_time(model,'Battery_Degradation_Model', Db *evalin('base','T_life_batt'));
swap_to_fromws(model,'G_test', 'S10_G');
swap_to_fromws(model,'Tc_test','S10_Tc');
swap_to_fromws(model,'V_test', 'S10_V');
swap_to_fromws(model,'Constant','S10_I');
set_param([model '/Constant1'], 'Value', num2str(bt.Tbat, '%.6g'));
set_param([model '/Constant2'], 'Value', num2str(bt.soc0, '%.6g'));
set_param([model '/Battery_Digital_Twin/Integrator'], 'InitialCondition', num2str(bt.soc0, '%.6g'));

patch_noise(model, seed);
out = sim(model);

meas  = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final', ...
         'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
twin  = {'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
         'Battery_Twin_Voltage','Battery_Residual_Voltage'};
feat  = {'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
         'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend', ...
         'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend', ...
         'PV_Feature_Window_Valid','PV_Trend_Window_Valid','Battery_Feature_Window_Valid','Battery_Trend_Window_Valid'};
sus   = {'Battery_Twin_SOC_Estimate'};
lab   = {'D_index','D_batt','Rs_aged','Rsh_aged','Iph_ref_aged','R0_aged','R1_aged','Capacity_aged','OCV_deltaV'};
tru   = {'True_PV_Current','True_Battery_Voltage'};
flt   = {'Fault_Active','PV_SensorFault_Active','Battery_SensorFault_Active','Battery_Fault_Active'};

T = table(tg, 'VariableNames', {'t'});
for nm = [meas twin feat sus lab tru flt]
    T.(nm{1}) = grab(out, nm{1}, tg);
end
clear c
fprintf('rows = %d, NaN cells = %d | PV fault %s/%s, battery fault %s/%s | sensor-fault flags on: PV %d, batt %d\n', ...
    height(T), sum(ismissing(T),'all'), char(fl.pvChannel), char(fl.pvType), char(fl.bChannel), char(fl.bType), ...
    any(T.PV_SensorFault_Active ~= 0), any(T.Battery_SensorFault_Active ~= 0));
end

function v = grab(out, name, tg)
s = out.get(name);
if numel(s.Time) == 1, v = repmat(double(squeeze(s.Data)), size(tg));
else, v = interp1(s.Time, double(squeeze(s.Data)), tg); end
end

function n = patch_noise(model, seed)
charts = sfroot().find('-isa','Stateflow.EMChart');
n = 0;
for i = 1:numel(charts)
    ch = charts(i);
    if ~startsWith(ch.Path, model), continue; end
    s = ch.Script;
    if isempty(regexp(s, '\<randn\>', 'once')), continue; end
    n = n + 1;
    skip = mod(seed, 100000)*20000 + n*10007;
    s = regexprep(s, '\<randn\>', 's10_randn()');
    s = [s newline newline 'function r = s10_randn()' newline 'persistent started;' newline ...
        'if isempty(started)' newline '    started = true;' newline ...
        '    for kk = 1:' num2str(skip) newline '        r0 = randn; %#ok<NASGU>' newline ...
        '    end' newline 'end' newline 'r = randn;' newline 'end' newline];
    ch.Script = s;
end
end

function swap_to_fromws(model, name, var)
blk = [model '/' name];
pos = get_param(blk,'Position');
ph  = get_param(blk,'PortHandles');
ln  = get_param(ph.Outport(1),'Line');
dst = get_param(ln,'DstPortHandle');
delete_block(blk);
for k = 1:numel(dst)
    l2 = get_param(dst(k),'Line');
    if l2 > 0, delete_line(l2); end
end
add_block('simulink/Sources/From Workspace', blk, 'Position', pos, ...
    'VariableName', var, 'Interpolate','on', 'OutputAfterFinalValue','Holding final value');
np = get_param(blk,'PortHandles');
for k = 1:numel(dst), add_line(model, np.Outport(1), dst(k)); end
end

function const_time(model, subName, tval)
sub = [model '/' subName];
ph  = get_param(sub,'PortHandles'); inP = ph.Inport(1);
ln  = get_param(inP,'Line');
srcP = get_param(ln,'SrcPortHandle');
delete_line(model, srcP, inP);
cb = [model '/S10_time_' subName];
add_block('simulink/Sources/Constant', cb, 'Value', num2str(tval,'%.15g'));
cph = get_param(cb,'PortHandles');
add_line(model, cph.Outport(1), inP);
end