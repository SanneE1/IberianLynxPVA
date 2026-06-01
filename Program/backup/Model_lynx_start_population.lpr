program Model_lynx_start_population;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  lynx_population_dynamics, lynx_define_units, lynx_vital_rates, lynx_input_output_functions;

var
  i, j: integer;
  csvFile: Text;

begin
  randomize; {initialize the pseudorandom number generator}

  {Organise input documents}

  paramname := 'input_data/parameter_values_Peninsula_6.txt';
  ReadParameters(paramname);
  readmap(mapname, mapBHname, mapiPname, mapPops);

  SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);

  {Get output documents started}
  SetLength(pop_status_array, 6);
  for i := 0 to High(pop_status_array) do
    SetLength(pop_status_array[i], 4);

  AssignFile(csvFile, 'output_data/start_pop_calibration.txt');
  Rewrite(csvFile);
  WriteLn(csvFile, 'n_disp_cycles, sim, population, status_0, status_1, status_2, status_3');


  // Calculate array of step probabilities (here once) to be used in dispersal procedure later
  Step_probabilities;

  for n_cycles := 1 to 5 do
    //if (n_cycles mod 25 = 0) then
  for current_sim := 1 to 3 do
  begin
    WriteLn('Starting simulation ', current_sim, ' with ', n_cycles, ' dispersal cycles' );

    for i := 0 to High(pop_status_array) do
    for j := 0 to High(pop_status_array[i]) do
    pop_status_array[i][j] := 0;

    Startpopulation;

    with population do
    for i := 0 to population.Count - 1 do
    begin
      Individual := items[i];
    pop_status_array[individual^.current_pop][individual^.status] := pop_status_array[individual^.current_pop][individual^.status]  + 1;
    end;

    append(csvFile);
    for i := 0 to High(pop_status_array) do
  begin
    Write(csvFile, n_cycles, ',', current_sim, ',', i, ',');
    WriteLn(csvFile, pop_status_array[i][0], ',', pop_status_array[i][1], ',',pop_status_array[i][2], ',',pop_status_array[i][3])
  end;
    CloseFile(csvFile);

  end;

  WriteLn('All simulations finished');
  ReadLn;

end.

