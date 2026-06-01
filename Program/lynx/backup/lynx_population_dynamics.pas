unit lynx_population_dynamics;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  lynx_vital_rates, lynx_input_output_functions, lynx_dispersal_assist_functions,
  general_functions, general_define_units;

procedure Startpopulation_lynx;
procedure Lynx_daily_demography(month, day: integer);
procedure Lynx_age_and_settle;
procedure Lynx_recalculate_BH(RabbitMap: Array2DInteger);

implementation

procedure Startpopulation_lynx;
var
  a,b, Tcheck, xy, N, X, Y: integer;
  lineData: TStringList;
  popFile: TextFile;
  popName: string;
begin
  LynxPopulation := TList.Create;
  lineData := TStringList.Create;

  AssignFile(popFile, start_pop_file);
  reset(popFile);

  with LynxPopulation do
  begin
  while not Eof(popFile) do
  begin
    ReadLn(popFile, popName);

     if (Pos('N', popName) = 1) then Continue;

     lineData.Delimiter := ' ';
     lineData.DelimitedText := popName;

     N := StrToIntDef(lineData[0], 0);
     X := StrToIntDef(lineData[1], 0);
     Y := StrToIntDef(lineData[2], 0);

     if (X < MapDimX) and (Y < MapDimY) then
     for a := 1 to N do
    begin
      new(Lynx);

      Lynx^.age := random(3) + 3;   {alternative: Lynx^.age:=0; }

      if random < 0.5 then Lynx^.sex := 'f'
      else
        Lynx^.sex := 'm';
        Lynx^.status := 1;

        Lynx^.Coor_X := X;
        Lynx^.Coor_Y := Y;


      Lynx^.Natal_pop := whichPop(Lynx^.Coor_X, Lynx^.Coor_Y);
      Lynx^.Current_pop := whichPop(Lynx^.Coor_X, Lynx^.Coor_Y);
      Lynx^.Previous_pop := whichPop(Lynx^.Coor_X, Lynx^.Coor_Y);


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

    end;
  end;
  end;

    {Go through some dispersal cycles, to get Lynxs settled}
    with LynxPopulation do
    for a := 1 to n_cycles do
    begin

      dispersal(a);

      for b := 0 to LynxPopulation.count - 1 do
      begin
      Lynx := Items[b];

      if (Lynx^.Status = 2) then
      if (Lynx^.Age < max_rep_age) then
      begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Lynx^.TerritoryX[xy] > 0) and (Lynx^.TerritoryY[xy] > 0)) then
          Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          Lynx^.Status := 3;

      end;

      UpdateAbundanceMap;

    end;

  end;
  end;

procedure Lynx_daily_demography(month, day: integer);
begin
  LynxPopulationSize := LynxPopulation.Count;

        if (month = 4) and (day = 1) then
          if LynxPopulationSize > 2 then
            reproduction;               // Reproduction happens at the end of March

        Dispersal(day);                 // Dispersal of surviving Lynxs (also includes dispersion start for subadults)

        survival;                       // Determine which individuals survive this day
 end;

procedure Lynx_age_and_settle;
var
 b, xy, Tcheck: integer;
begin

      LynxPopulationSize := LynxPopulation.Count;

      if LynxPopulationSize > 0 then
      begin
      for b := 0 to LynxPopulationSize - 1 do
        begin
          Lynx := LynxPopulation.Items[b];
          Lynx^.Age := Lynx^.Age + 1;
          if (Lynx^.Status = 2) and (Lynx^.Age < max_rep_age) then
          begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Lynx^.TerritoryX[xy] > 0) and (Lynx^.TerritoryY[xy] > 0)) then Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          begin
          Lynx^.Status := 3;

          new(MigrationEvent);

          MigrationEvent^.simulation := current_sim;
          MigrationEvent^.year := current_year;
          MigrationEvent^.sex := Lynx^.Sex;
          MigrationEvent^.age := Lynx^.Age;
          MigrationEvent^.natal_pop := Lynx^.Natal_pop;
          MigrationEvent^.old_pop := Lynx^.Previous_pop;
          MigrationEvent^.new_pop := Lynx^.Current_pop;

           SettledList.Add(MigrationEvent);
          end;
          end;

          each_pop_sizes[Lynx^.current_pop, current_year] := each_pop_sizes[Lynx^.current_pop, current_year] + 1;

        end;
      end;

      UpdateAbundanceMap;

    end;


procedure Lynx_recalculate_BH(RabbitMap: Array2DInteger);
var
  x,y : integer;
begin

    for x := 1 to MapdimX do
    for y := 1 to MapdimY do
    begin

    if RabbitMap[x][y] >= 10 then BreedingHabitatMap[x][y] := 1 else
     BreedingHabitatMap[x][y] := 0;

    RabbitMap[x][y] := 0;  // Reset for new year

    end;

end;

end.

