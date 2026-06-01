program Model_lynx_cmd;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  lynx_population_dynamics, lynx_define_units, unit1;

begin

  if ParamCount <> 1 then
  {ShowErrorAndExit('Incorrect number of parameters given')
  else}
  begin

  WriteLn('A different number of parameters received than expected. Check submission line');

  paramname := ParamStr(1);
  if paramname = '' then paramname := 'input_data/parameter_values_Peninsula_6_250117.txt';
  end;

  RunPopSim;

  WriteLn('All simulations finished');
  ReadLn;

end.

