program dispersal_calibration;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  general_functions, general_define_units,
  lynx_input_output_functions, lynx_vital_rates, lynx_dispersal_assist_functions
  { you can add units after this };

var
  a,b, Tcheck, xy, N, X, Y, d: integer;
  lineData: TStringList;
  LineSplit: TStringArray;
  settings_file, coordinates_file, Line: string;
  popFile: TextFile;
  popName: string;
  X_array, Y_array, XN_array, YN_array: array of integer;
  nrow_file, N_repeats: integer;

begin
  randomize; {initialize the pseudorandom number generator}

  settings_file := ExpandFileName(ParamStr(1));
  output_dir := ParamStr(2);

  Assign(filename, settings_file);
  reset(filename);

  while not EOF(filename) do
  begin
    ReadLn(filename, Line);
    LineSplit := Line.Split(' ');

    if (LineSplit[0] = 'lynx_demography') then paramname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'mapname_lynx') then mapname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'breeding_file') then breeding_file := LineSplit[1]
    else if (LineSplit[0] = 'starting_coordinates') then coordinates_file := LineSplit[1]
    else if (LineSplit[0] = 'nrow_file') then nrow_file := StrToInt(LineSplit[1])
    else if (LineSplit[0] = 'N_repeats') then N_repeats := StrToInt(LineSplit[1]);

  end;

  paramname_lynx := ExpandFileName(paramname_lynx);
  mapname_lynx := ExpandFileName(mapname_lynx);
  breeding_file := ExpandFileName(breeding_file);

  //WriteLn('Reading Lynx parameters');
  ReadParameters_lynx(paramname_lynx);

  if ParamCount > 2 then
    begin
    WriteLn('Running simulations with dispersal parameters from input');

    Val(Trim(ParamStr(3)), L_alpha_steps);
    Val(Trim(ParamStr(4)), L_theta_d);
    Val(Trim(ParamStr(5)), L_delta_theta_long);
    Val(Trim(ParamStr(6)), L_delta_theta_f);
    L_L := StrToInt(ParamStr(7));
    L_N_d := StrToInt(ParamStr(8));
    Val(Trim(ParamStr(9)), L_beta);
    Val(Trim(ParamStr(10)), L_gamma);

    end;

 WriteLn('Reading Maps');
 HabitatMapLynx := ReadMap(mapname_lynx);
 BreedingHabitatMap := ReadMap(breeding_file);
 //PopsMap := ReadMap(ExpandFileName('input_data' + PathDelim + 'maps' + PathDelim + 'Lynx_populations_500_Peninsula_IUCN75.txt'));

 WriteLn('Setting up Map variables');
  SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  //SetLength(BreedingHabitatMap, Mapdimx + 1, mapdimy + 1);
  SetLength(ConnectionMap, Mapdimx + 1, Mapdimy + 1, 2);

 //WriteLn('Creating output folders if they dont exist');
 if not DirectoryExists(output_dir) then
    MkDir(output_dir);

 if not DirectoryExists(output_dir + PathDelim + 'maps') then
    MkDir(output_dir + PathDelim + 'maps');

 AssignFile(to_file_out, output_dir + PathDelim + 'dispersal_results.csv');
 rewrite(to_file_out); {create txt file}
 writeln(to_file_out, 'start_col, start_row, end_col, end_row');
 CloseFile(to_file_out);

 //MigrationList := TList.Create;

 {Start bare minimum needed to get a day of dispersal for all individuals}
 WriteLn('Setting up additional variables');
 Step_probabilities;

 LynxPopulation := TList.Create;
 lineData := TStringList.Create;

 SetLength(X_array, (N_repeats * nrow_file));
 SetLength(Y_array, (N_repeats * nrow_file));
 SetLength(XN_array, (N_repeats * nrow_file));
 SetLength(YN_array, (N_repeats * nrow_file));

 b := 0; // Keep track of where in array coordinates need to be added

 WriteLn('Starting dispersal, creating one individual from file at a time: input_data/callibration_dispersal_starting_locations.txt');
 //WriteLn('Each row wil have ' + IntToStr(N_repeats) + 'repeat simulations');
 AssignFile(popFile, coordinates_file);
 reset(popFile);

 while not Eof(popFile) do
 begin
   ReadLn(popFile, popName);

   if (Pos('"', popName) = 1) then Continue;

   lineData.Delimiter := ' ';
   lineData.DelimitedText := popName;

   X := StrToIntDef(lineData[0], 0);
   Y := StrToIntDef(lineData[1], 0);

   for N := 1 to N_repeats do
     begin
     new(Lynx);

     Lynx^.age := 3;
     if random < 0.5 then Lynx^.sex := 'f'
     else
      Lynx^.sex := 'm';
     Lynx^.status := 1;

     Lynx^.Coor_X := X;
     Lynx^.Coor_Y := Y;

     Lynx^.Natal_pop := whichPop(X, Y);
     Lynx^.Current_pop := whichPop(X, Y);
     Lynx^.Previous_pop := whichPop(X, Y);
     setLength(Lynx^.TerritoryX, Tsize);
     setLength(Lynx^.TerritoryY, Tsize);
     ArrayToNegOne(Lynx^.TerritoryX);
     ArrayToNegOne(Lynx^.TerritoryY);
     Lynx^.mov_mem := random(8) + 1;
     Lynx^.homeX := Lynx^.Coor_X;
     Lynx^.homeY := Lynx^.Coor_Y;
     Lynx^.return_home := False;
     Lynx^.DailySteps := 0;
     Lynx^.DailyStepsOpen := 0;

     LynxPopulation.add(Lynx);

     Dispersal(1);

     X_array[b] := X;
     Y_array[b] := Y;
     XN_array[b] := PLynx(LynxPopulation[0])^.Coor_X;
     YN_array[b] := PLynx(LynxPopulation[0])^.Coor_Y;

     Dispose(PLynx(LynxPopulation[0]));
     LynxPopulation.Clear;

     b := b + 1;
   end;

 end;

 WriteLn('Done with simulation, proceding to write output file');

 {Get new coordinates of individuals and save to file}
 AssignFile(to_file_out, output_dir + PathDelim + 'dispersal_results.csv');
 append(to_file_out);

 for xy := 0 to Length(X_array) - 1 do
   WriteLn(to_file_out, X_array[xy], ',', Y_array[xy], ',', XN_array[xy], ',', YN_array[xy]);

 CloseFile(to_file_out);

 {Write connection map}
 WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'FemalesMap_traveled.csv', ConnectionMap, MapdimX, MapdimY, 0);
 WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'MalesMap_traveled.csv', ConnectionMap, MapdimX, MapdimY, 1);

 //WriteLn('Clear up memory');
 lineData.Clear;

 WriteLn('Done');

end.

