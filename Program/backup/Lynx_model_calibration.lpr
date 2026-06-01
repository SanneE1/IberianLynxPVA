program Lynx_model_calibration;

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

    WriteLn('Using values from command line');
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
      if (StrToInt(LineSplit[1]) = 1) then create_maps := True;
      end
    else if (LineSplit[0] = 'rabbit_demography') then paramname_rabbit := LineSplit[1]
    else if (LineSplit[0] = 'lynx_demography') then paramname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'mapname_lynx') then mapname_lynx := LineSplit[1]
    else if (LineSplit[0] = 'mapname_rabbit') then mapname_rabbit := LineSplit[1]
    else if (LineSplit[0] = 'map_lynx_pops') then mapPops := LineSplit[1]
    else if (LineSplit[0] = 'lynx_start_size') then start_pop_file := LineSplit[1]
    else if (LineSplit[0] = 'lynx_reintro') then reintro_file := LineSplit[1]
    else if (LineSplit[0] = 'climate_folder') then climate_folder := LineSplit[1]
    else if (LineSplit[0] = 'habitat_folder') then habitat_folder := LineSplit[1]
  end;

n_years := (end_year - start_year) + 1;

paramname_rabbit := ExpandFileName(paramname_rabbit);
mapname_rabbit := ExpandFileName(mapname_rabbit);

paramname_lynx := ExpandFileName(paramname_lynx);
mapname_lynx := ExpandFileName(mapname_lynx);
mapPops := ExpandFileName(mapPops);
start_pop_file := ExpandFileName(start_pop_file);

if not (habitat_folder = '0') then habitat_folder := ExpandFileName(habitat_folder);

randomize; {initialize the pseudorandom number generator}

WriteLn('Reading Lynx parameters');
ReadParameters_lynx(paramname_lynx);
WriteLn('Reading Rabbit parameters');
ReadParameters_Rabbit(paramname_rabbit);

{Set up command line parameter values in case they're provided}
if ParamCount > 2 then
   begin
   Tsize := StrToInt(ParamStr(3));
   L_surv_disp_rho := StrToInt(ParamStr(4));
   n_months_above_R_threshold := StrToInt(ParamStr(5));
   threshold_density_for_lynx := StrToInt(ParamStr(6));
   end;


{Setting up the spatial and output variables}
WriteLn('Reading Maps');
MapDimX := 0;
MapDimY := 0;

HabitatMapRabbit := ReadMap(mapname_rabbit);
HabitatMapLynx := ReadMap(mapname_lynx);
PopsMap := ReadMap(mapPops);
{BreedingHabitatMap := ReadMap(ExpandFileName('input_data/maps/Lynx_Breeding_Habitat.txt'));}

WriteLn('Setting up Map variables');
SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);
SetLength(BreedingHabitatMap, Mapdimx + 1, mapdimy + 1);

SetLength(ConnectionMap, Mapdimx + 1, Mapdimy + 1, 2);

WriteLn('Creating output folders if they dont exist');
if not DirectoryExists(output_dir) then MkDir(output_dir);

output_maps := output_dir + PathDelim + 'maps';
if not DirectoryExists(output_maps) then MkDir(output_maps);

for a := 1 to n_years do sum_pop_size[a] := 0;
SetLength(each_pop_sizes, 10);

for i := 0 to High(each_pop_sizes) do
    SetLength(each_pop_sizes[i], n_years+1);

// Calculate array of step probabilities (here once) to be used in dispersal procedure later
Step_probabilities;

MigrationList := TList.Create;
SettledList := Tlist.Create;
OutRepList := TList.Create;

//max_pop_size := 0;
WriteLn('Start rabbit population');
Startpopulation_rabbit;
WriteLn('Start lynx population');
Startpopulation_lynx;

WriteLn('Start simulation');
RunSimulation;    {call the procedure to run the population dynamics}

{save the results to a text file}
AssignFile(to_file_out,output_dir + PathDelim + 'lynx_pop_size_5pops.csv');
rewrite(to_file_out); {create txt file}
writeln(to_file_out, 'year, Vale, Donana, Matachel, Morena, Toledo, external_pop');

for b := 0 to n_years do
begin
  writeln(to_file_out, start_year + b, ',',
  each_pop_sizes[1,b], ',',
  each_pop_sizes[2,b], ',',
  each_pop_sizes[3,b] + each_pop_sizes[5,b], ',',
  each_pop_sizes[4,b] + each_pop_sizes[8,b] + each_pop_sizes[9,b], ',',
  each_pop_sizes[6,b] + each_pop_sizes[7,b], ',',
  each_pop_sizes[0,b], ',');
end;

CloseFile(to_file_out);

WriteLn('All simulations finished');

end.

