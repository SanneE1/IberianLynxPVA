unit lynx_population_dynamics;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  lynx_define_units, lynx_vital_rates, general_functions, lynx_input_output_functions;

procedure Startpopulation;
procedure Pop_dynamics;
procedure RunPopSim;

implementation

procedure Startpopulation;
var
  a, b, TCheck, xy: integer;
begin
  Population := TList.Create;
  with population do
  begin
    for a := 1 to n_ini do
    begin
      new(Individual);

      Individual^.age := random(3) + 3;   {alternative: Individual^.age:=0; }

      if random < 0.5 then Individual^.sex := 'f'
      else
        Individual^.sex := 'm';
      Individual^.status := 1;

      if a < 75 then
      begin
        Individual^.Coor_X := 546;   // Donana for Peninsula
        Individual^.Coor_Y := 1572;
      end
      else if a < 103 then
      begin
        Individual^.Coor_X := 687;   // Matachel for Peninsula
        Individual^.Coor_Y := 1266;
      end
      else if a < 126 then
      begin
        Individual^.Coor_X := 833;  // Montes de Toledo for Peninsula
        Individual^.Coor_Y := 1001;
      end
      else if a < 465 then
      begin
        Individual^.Coor_X := 726;   // Sierra Morena for Peninsula
        Individual^.Coor_Y := 1463;
      end
      else
      begin
        Individual^.Coor_X := 336;   // Vale do Guadiana
        Individual^.Coor_Y := 1400;
      end;

      Individual^.Natal_pop := whichPop(Individual^.Coor_X, Individual^.Coor_Y);
      Individual^.Current_pop := whichPop(Individual^.Coor_X, Individual^.Coor_Y);
      Individual^.Previous_pop := whichPop(Individual^.Coor_X, Individual^.Coor_Y);


      setLength(Individual^.TerritoryX, Tsize);
      setLength(Individual^.TerritoryY, Tsize);
      ArrayToNegOne(Individual^.TerritoryX);
      ArrayToNegOne(Individual^.TerritoryY);

      Individual^.mov_mem := random(8) + 1;
      Individual^.homeX := Individual^.Coor_X;
      Individual^.homeY := Individual^.Coor_Y;
      Individual^.return_home := False;

      Individual^.DailySteps := 0;
      Individual^.DailyStepsOpen := 0;

      Population.add(Individual);

    end;

    {Go through some dispersal cycles, to get individuals settled}
    with population do
    for a := 1 to n_cycles do
    begin
      writeLn('Dispersal cycle ', a);

      dispersal(a);

      for b := 0 to population.count - 1 do
      begin
      Individual := Items[b];

      if (Individual^.Status = 2) then
      if (Individual^.Age < max_rep_age) then
      begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Individual^.TerritoryX[xy] > 0) and (Individual^.TerritoryY[xy] > 0)) then
          Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          Individual^.Status := 3;

      end;

      UpdateAbundanceMap;

    end;

  end;
end;

end;

procedure Pop_dynamics;
var
  a, b, xy, day, Tcheck: integer;
begin
 with population do
  begin
    for a := 1 to max_years do
    begin
      day := 0;  // Start the year
      while (day < 366) and (populationsize > 0) do //Let's pretend there's no such thing as leap years
      begin
        day := day + 1;
        populationsize := population.Count;

        if day = 90 then
          if populationsize > 2 then
            reproduction;               // Reproduction happens at the end of March

        Dispersal(day);                 // Dispersal of surviving individuals (also includes dispersion start for subadults)

        survival;                       // Determine which individuals survive this day
      end;

      populationsize := population.Count;
      if populationsize > 0 then
      begin
      for b := 0 to populationsize - 1 do
        begin
          Individual := Items[b];
          Individual^.Age := Individual^.Age + 1;
          if (Individual^.Status = 2) and (Individual^.Age < max_rep_age) then
          begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Individual^.TerritoryX[xy] > 0) and (Individual^.TerritoryY[xy] > 0)) then Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          begin
          Individual^.Status := 3;

          new(MigrationEvent);

          MigrationEvent^.simulation := current_sim;
          MigrationEvent^.year := current_year;
          MigrationEvent^.sex := Individual^.Sex;
          MigrationEvent^.age := Individual^.Age;
          MigrationEvent^.natal_pop := Individual^.Natal_pop;
          MigrationEvent^.old_pop := Individual^.Previous_pop;
          MigrationEvent^.new_pop := Individual^.Current_pop;

           SettledList.Add(MigrationEvent);
          end;
          end;

          each_pop_sizes[Individual^.current_pop, current_year] := each_pop_sizes[Individual^.current_pop, current_year] + 1;

        end;
      end;

      UpdateAbundanceMap;

      if (current_year = max_years) then
    begin
    WriteMapCSV('output_data/FemalesMap_status_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 0);
    WriteMapCSV('output_data/FemalesMap_age_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 1);
    WriteMapCSV('output_data/MalesMap_status_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 0);
    WriteMapCSV('output_data/MalesMap_age_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 1);
    end;

    WritePopulationToCSV(population, 'output_data/Population_data.csv', current_sim, current_year);

    end;
  end;
end;

procedure RunPopSim;
var
  a,b, i: integer;
begin

  randomize; {initialize the pseudorandom number generator}
  ReadParameters(paramname);

  WriteLn('Running ', n_sim, ' lynx population simulation(s) with ',n_ini, ' initial population size, for ', max_years, ' years');
  WriteLn('Using parameter file: ', paramname);
  WriteLn('Map file name: ', mapname);

  readmap(mapname, mapBHname, mapPops);

  SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(ConnectionMap, Mapdimx + 1, Mapdimy + 1, 2);

  AssignFile(to_file_out, file_name);
  rewrite(to_file_out); {create txt file}
  writeln(to_file_out, 'current_sim,year,pop1, pop2, pop3, pop4, pop5');

  AssignFile(mig_file_out, 'output_data/migration.csv');
  rewrite(mig_file_out); {create txt file}
  writeln(mig_file_out, 'EventID,Simulation,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

  AssignFile(migS_file_out, 'output_data/migration_settled.csv');
  rewrite(migS_file_out); {create txt file}
  writeln(migS_file_out, 'EventID,Simulation,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

  for a := 1 to max_years do sum_pop_size[a] := 0;
  for a := 1 to max_years do n_sim_no_ext[a] := 0;

  SetLength(each_pop_sizes, 6);
  for i := 0 to High(each_pop_sizes) do
    SetLength(each_pop_sizes[i], max_years+1);

  // Calculate array of step probabilities (here once) to be used in dispersal procedure later
  Step_probabilities;

  MigrationList := TList.Create;
  SettledList := Tlist.Create;

  for current_sim := 1 to n_sim do
  begin
    WriteLn('Starting simulation ', current_sim);

    max_pop_size := 0;
    Startpopulation; {call the procedure to initialize your population}
    Pop_dynamics;    {call the procedure to run the population dynamics}

    {save the results to a text file}
    append(to_file_out);
    for b := 1 to max_years do
    begin
      writeln(to_file_out, current_sim, ',', b, ',',
      each_pop_sizes[0,b], ',',
      each_pop_sizes[1,b], ',',
      each_pop_sizes[2,b], ',',
      each_pop_sizes[3,b], ',',
      each_pop_sizes[4,b], ',',
      each_pop_sizes[5,b], ',');
    end;

    CloseFile(to_file_out);

    {Write Migration list to file}
    append(mig_file_out);
    with MigrationList do
    for b := 0 to MigrationList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(mig_file_out, b , ',', MigrationEvent^.simulation, ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);
    end;
    CloseFile(mig_file_out);


    {Write Migration list to file}
    append(migS_file_out);
    with SettledList do
    for b := 0 to SettledList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(migS_file_out, b , ',', MigrationEvent^.simulation, ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);
    end;
    CloseFile(migS_file_out);

    WriteLn('Done with simulation ', current_sim);
end;

end;



end.

