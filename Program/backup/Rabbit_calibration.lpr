program Rabbit_calibration;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  general_functions, general_define_units, Population_dynamics,
  lynx_population_dynamics, lynx_input_output_functions, lynx_dispersal_assist_functions,
  rabbit_population_dynamics, rabbit_input_output_functions;

{$R *.res}
var
  LineSplit: TStringArray;
  settings_file, Line: string;

begin

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
            if (StrToInt(LineSplit[1]) = 1) then create_maps := True
            else if (StrToInt(LineSplit[0]) = 2) then rabbit_census_maps := True;
      end
    else if (LineSplit[0] = 'rabbit_demography') then paramname_rabbit := LineSplit[1]
    else if (LineSplit[0] = 'mapname_rabbit') then mapname_rabbit := LineSplit[1]
    else if (LineSplit[0] = 'climate_folder') then climate_folder := LineSplit[1]
    else if (LineSplit[0] = 'habitat_folder') then habitat_folder := LineSplit[1]
  end;

n_years := (end_year - start_year) + 1;

paramname_rabbit := ExpandFileName(paramname_rabbit);
mapname_rabbit := ExpandFileName(mapname_rabbit);

if not (habitat_folder = '0') then habitat_folder := ExpandFileName(habitat_folder);

randomize; {initialize the pseudorandom number generator}

WriteLn('Reading Rabbit parameters');
ReadParameters_Rabbit(paramname_rabbit);

{Assign demographic variables with current run's values}
if ParamCount > 2 then
  begin
  kCapacity_high := StrToInt(ParamStr(3));
  kCapacity_low := StrToInt(ParamStr(4));
  R_dens_opt := StrToInt(ParamStr(5));
  Val(Trim(ParamStr(6)), R_lambda);
  Val(Trim(ParamStr(7)), R_sigma);
  end;

{Setting up the spatial and output variables}
WriteLn('Reading Maps');
MapDimX := 0;
MapDimY := 0;

HabitatMapRabbit := ReadMap(mapname_rabbit);
SetLength(HabitatMapLynx, 1, 1);
SetLength(PopsMap, 1, 1);

WriteLn('Creating output folders if they dont exist');
if not DirectoryExists(output_dir) then MkDir(output_dir);

output_maps := output_dir + PathDelim + 'maps';
if not DirectoryExists(output_maps) then MkDir(output_maps);

WriteLn('Start rabbit population');
Startpopulation_rabbit;

WriteLn('Start simulation');

for current_year := start_year to end_year do
    begin

      WriteLn('Simulation Year ' + IntToStr(current_year));

      ReadClim;

      for month := 1 to 12 do
      begin
        Rabbit_monthly_demography(current_year, month);

        if (rabbit_census_maps) and (((month = 3) or (month = 9)) or ((current_year = 2017) or (current_year = 2018) or (current_year = 2023) or (current_year = 2024)))then
          WritePopsizeMap((output_dir + PathDelim + 'maps' + PathDelim + 'Rabbit_Population_distribution_' + IntToStr(current_year) + '_' + IntToStr(month) + '.csv'), RabbitPopulationSpatial, mapdimX, mapdimy);

        if month = 6 then
          begin
          if not (habitat_folder = '0') then
            if current_year > 2016 then
              begin
              Write('Reading new habitat maps - ');
              HabitatMapRabbit := ReadMap(habitat_folder + PathDelim + 'Rabbit_HabitatMap_' + IntToStr(current_year) + '.txt');
              end;
          end;
        end;
      end;


WriteLn('Simulation finished');


end.


