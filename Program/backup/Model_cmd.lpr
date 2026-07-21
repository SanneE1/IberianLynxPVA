program Model_cmd;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  general_functions, general_define_units, Population_dynamics,
  lynx_input_output_functions, lynx_dispersal_assist_functions, lynx_population_dynamics;

{$R *.res}
var
  LineSplit: TStringArray;
  settings_file, Line: string;
  x,y: integer;

begin
  randomize; {initialize the pseudorandom number generator}

  settings_file := ParamStr(1);
  output_dir := ParamStr(2);

  Assign(filename, ExpandFileName(settings_file));
  reset(filename);

  while not EOF(filename) do
  begin
    ReadLn(filename, Line);
    LineSplit := Line.Split(' ');

    if (LineSplit[0] = 'start_year') then start_year := StrToInt(LineSplit[1])
    else if (LineSplit[0] = 'end_year') then end_year := StrToInt(LineSplit[1])
    else if (LineSplit[0] = 'create_maps') then
      begin
            if (StrToInt(LineSplit[1]) = 1) then
              create_maps := True;
      end
    else if (LineSplit[0] = 'create_maps_25yrs') then
      begin
            if (StrToInt(LineSplit[1]) = 1) then
              create_maps_25yrs := True;
      end
    else if (LineSplit[0] = 'all_year_maps') then
      begin
            if (StrToInt(LineSplit[1]) = 1) then
              all_year_maps := True;
      end
    else if (LineSplit[0] = 'lynx_demography') then paramname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'mapname_lynx') then mapname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'breeding_file') then breeding_file := LineSplit[1]
    else if (LineSplit[0] = 'map_lynx_pops') then mapPops := LineSplit[1]
    else if (LineSplit[0] = 'lynx_start_size') then start_pop_file := LineSplit[1]
    else if (LineSplit[0] = 'lynx_reintro') then reintro_file := LineSplit[1]
    else if (LineSplit[0] = 'habitat_folder') then habitat_folder := LineSplit[1]
    else if (LineSplit[0] = 'breeding_folder') then breeding_folder := LineSplit[1]
  end;

  WriteLn('start_year = ' + IntToStr(start_year));
  WriteLn('end_year = ' + IntToStr(end_year));
  WriteLn('create_maps_25yrs = ' + create_maps_25yrs.ToString(TUseBoolStrs.true));
  WriteLn('all_year_maps = ' + all_year_maps.ToString(TUseBoolStrs.true));
  WriteLn('habitat_folder = ' + habitat_folder);
  WriteLn('breeding_folder = ' + breeding_folder);
  WriteLn('lynx_demography = ' + ExpandFileName(paramname_lynx));

  n_years := (end_year - start_year) + 1;

WriteLn('Reading Lynx parameters');
paramname_lynx := ExpandFileName(paramname_lynx);
ReadParameters_lynx(paramname_lynx);

mapname_lynx := ExpandFileName(mapname_lynx);
mapPops := ExpandFileName(mapPops);
start_pop_file := ExpandFileName(start_pop_file);

{Assign demographic variables with current run's values}
if ParamCount > 2 then Tsize := StrToInt(ParamStr(3));
if ParamCount > 3 then breeding_folder := ParamStr(4);

if not (breeding_folder = '0') then breeding_folder := ExpandFileName(breeding_folder);

{Setting up the spatial and output variables}
WriteLn('Reading Maps');
MapDimX := 0;
MapDimY := 0;

if not (habitat_folder = '0') then
  begin
  WriteLn(habitat_folder + PathDelim + 'Lynx_HabitatMap_' + IntToStr(start_year) + '.txt');
  BreedingHabitatMap := ReadMap(ExpandFileName(habitat_folder + PathDelim + 'Lynx_HabitatMap_' + IntToStr(start_year) + '.txt'))
  end
  else
  begin
  HabitatMapLynx := ReadMap(mapname_lynx);
  end;

if not (breeding_folder = '0') then
  begin
  WriteLn(breeding_folder + PathDelim + 'Lynx_BreedingMap_' + IntToStr(start_year) + '.txt');
  BreedingHabitatMap := ReadMap(ExpandFileName(breeding_folder + PathDelim + 'Lynx_BreedingMap_' + IntToStr(start_year) + '.txt'))
  end
  else
  begin
  BreedingHabitatMap := ReadMap(ExpandFileName(breeding_file));
  end;

PopsMap := ReadMap(mapPops);

SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);
SetLength(ConnectionMap, Mapdimx + 1, Mapdimy + 1, 2);




WriteLn('Creating output folders if they dont exist');
if not DirectoryExists(output_dir) then MkDir(output_dir);

output_maps := output_dir + PathDelim + 'maps';
if not DirectoryExists(output_maps) then MkDir(output_maps);

for a := 1 to n_years do sum_pop_size[a] := 0;
SetLength(each_pop_sizes, 23);

for i := 0 to High(each_pop_sizes) do
    SetLength(each_pop_sizes[i], n_years+1);

// Calculate array of step probabilities (here once) to be used in dispersal procedure later
Step_probabilities;

MigrationList := TList.Create;
SettledList := Tlist.Create;
OutRepList := TList.Create;

WriteLn('Start lynx population');
Startpopulation_lynx;

WriteLn('Start simulation');
RunSimulation;    {call the procedure to run the population dynamics}

{save the results to a text file}
AssignFile(to_file_out,output_dir + PathDelim + 'lynx_pop_size.csv');
rewrite(to_file_out); {create txt file}
writeln(to_file_out, 'year, pop0, pop1, pop2, pop3, pop4, pop5, pop6, pop7, pop8, pop9');

for b := 0 to n_years do
    begin
    write(to_file_out, start_year + b, ',');
    for a := 0 to 21 do
        begin
        write(to_file_out, each_pop_sizes[a,b], ',');
        end;
    writeln(to_file_out);
    end;

CloseFile(to_file_out);

{save the biological population sizes}
AssignFile(to_file_out,output_dir + PathDelim + 'lynx_biopop_size.csv');
rewrite(to_file_out); {create txt file}
writeln(to_file_out, 'year, Vale, Doñana, SierraMorena, Matachel, MontesDeToledo, OutsidePop');

for b := 0 to n_years do
    begin
    write(to_file_out, start_year + b, ',');
    write(to_file_out, each_pop_sizes[22,b], ',');
    write(to_file_out, each_pop_sizes[4,b], ',');
    write(to_file_out, (each_pop_sizes[1,b] + each_pop_sizes[2,b] + each_pop_sizes[5,b] + each_pop_sizes[6,b] + each_pop_sizes[7,b] + each_pop_sizes[8,b] + each_pop_sizes[10,b] + each_pop_sizes[16,b] + each_pop_sizes[18,b] + each_pop_sizes[19,b]), ',');
    write(to_file_out, (each_pop_sizes[3,b] + each_pop_sizes[11,b] + each_pop_sizes[14,b] + each_pop_sizes[17,b] + each_pop_sizes[21,b]), ',');
    write(to_file_out, (each_pop_sizes[9,b] + each_pop_sizes[12,b] + each_pop_sizes[13,b] + each_pop_sizes[20,b]), ',');
    writeln(to_file_out, each_pop_sizes[0,b]);
    end;

CloseFile(to_file_out);

if create_maps then
  begin
  {Write Migration list to file}
  AssignFile(mig_file_out, output_dir + PathDelim + 'lynx_migration.csv');
  rewrite(mig_file_out); {create txt file}
  writeln(mig_file_out, 'EventID,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

  with MigrationList do
    for b := 0 to MigrationList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(mig_file_out, b , ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);

      Dispose(PMigration(MigrationList[b]));
    end;
    CloseFile(mig_file_out);
    MigrationList.Clear;


    {Write Settled Migrants list to file}
    AssignFile(migS_file_out, output_dir + PathDelim + 'lynx_migration_settled.csv');
    rewrite(migS_file_out); {create txt file}
    writeln(migS_file_out, 'EventID,Simulation,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

    with SettledList do
    for b := 0 to SettledList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(migS_file_out, b , ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);

      Dispose(PMigration(SettledList[b]));
    end;
    CloseFile(migS_file_out);

    SettledList.Clear;

    {Write Reproduction events outside populations to file}
    AssignFile(Orep_file_out, output_dir + PathDelim + 'lynx_reproduction_outside_populations.csv');
    rewrite(Orep_file_out); {create txt file}
    writeln(Orep_file_out, 'EventID,Year,X,Y');

    with OutRepList do
    for b := 0 to OutRepList.Count - 1 do
    begin
      RepOutsidePop := items[b];

      writeln(Orep_file_out, b , ',',
      RepOutsidePop^.year, ',',
      RepOutsidePop^.X, ',',
      RepOutsidePop^.Y);
    end;
    CloseFile(Orep_file_out);

    {Write connection map}
    WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'FemalesMap_traveled.csv', ConnectionMap, MapdimX, MapdimY, 0);
    WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'MalesMap_traveled.csv', ConnectionMap, MapdimX, MapdimY, 1);
    end;


WriteLn('All simulations finished');

end.

