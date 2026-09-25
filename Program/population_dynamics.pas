unit Population_dynamics;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  general_functions, general_define_units, lynx_vital_rates,
  lynx_population_dynamics, lynx_input_output_functions, lynx_dispersal_assist_functions;

procedure RunSimulation;

implementation


procedure RunSimulation;
var
  b, xy, day, month, Tcheck: integer;
begin

    for current_year := start_year to end_year do
    begin
      WriteLn();
      WriteLn('Simulation Year ' + IntToStr(current_year));
      WriteLn('Starting Population Size ' + IntToStr(LynxPopulation.Count));
      WriteLn();

      for month := 1 to 12 do
      begin

        if month = 6 then
        begin
        if not (habitat_folder = '0') then
          begin
          WriteLn('Reading new habitat map');
            HabitatMapLynx := ReadMap(habitat_folder + PathDelim + 'Lynx_HabitatMap_' + IntToStr(current_year) + '.txt');
          end;

        if not (breeding_folder = '0') then
          begin
          WriteLn('Reading new breeding maps');
            BreedingHabitatMap := ReadMap(breeding_folder + PathDelim + 'Lynx_BreedingMap_' + IntToStr(current_year) + '.txt');
          end;

        if not (prey_folder = '0') then
          begin
          WriteLn('Reading new prey suitability maps');
            PreySuitabilityMap := ReadMap(prey_folder + PathDelim + 'Lynx_PreyMap_' + IntToStr(current_year) + '.txt');
          end;

        Lynx_reintroduction(current_year);

        end;

        if (month = 4) then reproduction;               // Reproduction happens at the end of March

        for day := 1 to days_in_month[month] do
        begin
        Dispersal(day);
        Survival;
        end;

        if (month = 5) and ((current_year = start_year) or all_year_maps or (create_maps_25yrs and (current_year mod 25 = 0))) then
        begin
          WriteLn('Writing maps');
          WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'FemalesMap_status_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 0);
          WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'FemalesMap_IC_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 2);

          WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'MalesMap_status_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 0);
          WriteMap3CSV(output_dir + PathDelim + 'maps' + PathDelim + 'MalesMap_IC_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 2);

          //WritePopulationToCSV(LynxPopulation, output_dir + PathDelim + 'Lynx_population_data.csv');

        end;

      end;

      WriteLn('Lynx aging and settling');
      Lynx_age_and_settle;

    end;

end;


end.

