function mm = Stage11_mismatch(level, socPts, seed)
% level  : parameter mismatch size, e.g. 0.05 means each Twin parameter is multiplied by 1 +/- up to 5%
% socPts : starting-SOC error in percentage points (the Twin starts this far from the true SOC)
% seed   : makes the draw reproducible
rng(seed);
u = @() 2*rand - 1;                                   % random number in [-1, 1]
mm.pvIph = 1 + level*u();     mm.pvRsh = 1 + level*u();
mm.pvN   = 1 + level*u();     mm.pvKi  = 1 + level*u();
mm.bR0   = 1 + level*u();     mm.bR1   = 1 + level*u();     mm.bCap = 1 + level*u();
mm.socOff = socPts*u();
end