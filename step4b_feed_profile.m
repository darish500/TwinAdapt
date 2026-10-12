function step4b_feed_profile()
model = 'Reformable_AI_2025';
D = 0.5;

% ---- 1. the same profile as 4a ----
t = (0:0.5:150)';
ramp = @(x) (min(max(x,0),1).^2) .* (3 - 2*min(max(x,0),1));
G = 900*ones(size(t));
starts = [20 55 85 115]; lens = [10 8 12 6]; depth = [0.5 0.6 0.4 0.7];
for k = 1:4
    dip = ramp((t-starts(k))/3) .* (1 - ramp((t-(starts(k)+lens(k)))/3));
    G = G - 900*depth(k)*dip;
end
Tc = zeros(size(t)); Tc(1) = 20 + 0.02*G(1);
for k = 2:numel(t)
    Tc(k) = Tc(k-1) + 0.5/40 * ((20 + 0.02*G(k)) - Tc(k-1));
end
I = 1.0*ones(size(t));
I = I + (2.5-1.0)*ramp((t-40)/2);
I = I + (0.6-2.5)*ramp((t-90)/2);

% ---- 2. hand the tables to the base workspace ----
assignin('base','S10_G',  [t G ]);
assignin('base','S10_Tc', [t Tc]);
assignin('base','S10_I',  [t I ]);

% ---- 3. load model fresh, never save ----
if bdIsLoaded(model), close_system(model, 0); end
evalin('base','reformable_AI;');
load_system(model);
c = onCleanup(@() close_system(model, 0));
set_param(model,'FastRestart','off');
set_param(model,'StopTime','150');

% ---- 4. hold health at D (Step 3) and swap the sources ----
const_time(model,'PV_Degradation_Model',      D*evalin('base','T_life'));
const_time(model,'Battery_Degradation_Model', D*evalin('base','T_life_batt'));
swap_to_fromws(model,'G_test', 'S10_G');
swap_to_fromws(model,'Tc_test','S10_Tc');
swap_to_fromws(model,'Constant','S10_I');

% ---- 5. run and compare ----
out = sim(model);
g  = @(s) interp1(s.Time, squeeze(s.Data), t);
Gm = g(out.True_PV_Irradiance);
Tm = g(out.True_PV_Temperature);
Im = g(out.True_Battery_Current);

eG = max(abs(Gm-G)); eT = max(abs(Tm-Tc)); eI = max(abs(Im-I));
fprintf('max |G_model  - G_in | = %.4g W/m^2   %s\n', eG, pf(eG<1));
fprintf('max |Tc_model - Tc_in| = %.4g degC    %s\n', eT, pf(eT<0.05));
fprintf('max |I_model  - I_in | = %.4g A       %s\n', eI, pf(eI<0.01));

figure;
subplot(3,1,1); plot(t,G,'k',t,Gm,'r--'); ylabel('G'); legend('input','model');
subplot(3,1,2); plot(t,Tc,'k',t,Tm,'r--'); ylabel('T_c');
subplot(3,1,3); plot(t,I,'k',t,Im,'r--'); ylabel('I_{batt}'); xlabel('time (s)');
end

function swap_to_fromws(model, name, var)
blk = [model '/' name];                       % the box we are replacing
pos = get_param(blk,'Position');              % remember where it sits
ph  = get_param(blk,'PortHandles');
ln  = get_param(ph.Outport(1),'Line');        % the wire leaving the box
dst = get_param(ln,'DstPortHandle');          % the socket(s) that wire plugs into
delete_block(blk);                            % delete the old box

for k = 1:numel(dst)                          % NEW: pull out the loose wire
    l2 = get_param(dst(k),'Line');
    if l2 > 0, delete_line(l2); end
end

add_block('simulink/Sources/From Workspace', blk, 'Position', pos, ...
    'VariableName', var, 'Interpolate','on', 'OutputAfterFinalValue','Holding final value');
np = get_param(blk,'PortHandles');            % the new box
for k = 1:numel(dst)
    add_line(model, np.Outport(1), dst(k));   % plug it into the same socket(s)
end
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

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end