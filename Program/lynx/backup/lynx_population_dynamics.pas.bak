unit lynx_population_dynamics;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  lynx_vital_rates, lynx_input_output_functions, lynx_dispersal_assist_functions,
  general_functions, general_define_units;

procedure Startpopulation_lynx;
procedure Lynx_reintroduction(current_year: integer);
procedure Lynx_age_and_settle;

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
  L_ID_tracker := 0;

  WriteLn('Lynx start pop file:' + start_pop_file);

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
     
     WriteLn('Creating ' + IntToStr(N) + ' individuals at coordinates:' + IntToStr(X) + ' ' + IntToStr(Y) + 'for population ' + IntToStr(whichPop(X, Y)));

     if (X < MapDimX) and (Y < MapDimY) then
     for a := 1 to N do
    begin
      new(Lynx);

      Lynx^.age := random(3) + 3;   {alternative: Lynx^.age:=0; }

      if random < 0.5 then Lynx^.sex := 'f'
      else
        Lynx^.sex := 'm';
        Lynx^.status := 1;

        Lynx^.ID := L_ID_tracker;
        L_ID_tracker := L_ID_tracker + 1;

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

  CloseFile(popFile);

  {Create a start breeding habitat map}
  {SetLength(BreedingHabitatMap, Mapdimx + 1, mapdimy + 1);

  for x := 1 to Mapdimx do
  for y := 1 to Mapdimy do
  begin
    if HabitatMapLynx[x,y] = 2 then BreedingHabitatMap[x,y] := 1 else BreedingHabitatMap[x,y] := 0;
  end; }

  {Go through some dispersal cycles, to get Lynxs settled}
  WriteLn('Starting dispersal circles to get lynxes with territories at the beginning');
    
  with LynxPopulation do
  for a := 1 to n_cycles do
    begin
      WriteLn('Starting dispersal cycle nr. ' + IntToStr(a));

      dispersal(a);

      WriteLn('Assigning Territories');
      
      for b := 0 to LynxPopulation.count - 1 do
      begin
      Lynx := Items[b];

      if (Lynx^.Status = 2) then
      if (Lynx^.Age < L_max_rep_age) then
      begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Lynx^.TerritoryX[xy] > 0) and (Lynx^.TerritoryY[xy] > 0)) then
          Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          begin
          Lynx^.Status := 3;
          
          for xy := 0 to Tcheck - 1 do
            begin
            if Lynx^.Sex = 'f' then
            begin
            FemalesMap[Lynx^.TerritoryX[xy], Lynx^.TerritoryY[xy], 0] := Lynx^.Status;
            FemalesMap[Lynx^.TerritoryX[xy], Lynx^.TerritoryY[xy], 1] := Lynx^.Age;
            end
            else
            begin
            MalesMap[Lynx^.TerritoryX[xy], Lynx^.TerritoryY[xy], 0] := Lynx^.Status;
            MalesMap[Lynx^.TerritoryX[xy], Lynx^.TerritoryX[xy], 1] := Lynx^.Age;
            end;
          end;
          end;

      end;
    end;

  end;
    WriteLn('Started with Lynx population size of: ' + IntToStr(LynxPopulation.Count));
  end;

procedure Lynx_reintroduction(current_year: integer);
var
  X, Y, N, A: integer;
  lineData: TStringList;
  popFile: TextFile;
  popName, S: string;
begin
    
    WriteLn('Releasing individuals');
    lineData := TStringList.Create;

    AssignFile(popFile, reintro_file);
    reset(popFile);

    while not Eof(popFile) do
    begin
    ReadLn(popFile, popName);

     if (Pos('Year', popName) = 1) then Continue;

     lineData.Delimiter := ' ';
     lineData.DelimitedText := popName;

     if StrToIntDef(lineData[0], 0) = current_year then
     begin

     X := StrToIntDef(lineData[1], 0);
     Y := StrToIntDef(lineData[2], 0);
     S := lineData[3];
     A := StrToIntDef(lineData[4], 0);

     new(Lynx);

     Lynx^.age := A;
     Lynx^.sex := S;
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
      
      //Writeln('Re-introduced lynx: age' + Lynx^.Age + 'at coordinates' + Lynx^.Coor_X + Lynx.Coor_Y);

    end;
    end;

    CloseFile(popFile);

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
          if (Lynx^.Status = 2) and (Lynx^.Age < L_max_rep_age) then
          begin
          Tcheck := 0;
          for xy := 0 to Tsize - 1 do
          if ((Lynx^.TerritoryX[xy] > 0) and (Lynx^.TerritoryY[xy] > 0)) then Tcheck := Tcheck + 1;

          if Tcheck = Tsize then
          begin
          Lynx^.Status := 3;

          new(MigrationEvent);

          MigrationEvent^.year := current_year;
          MigrationEvent^.sex := Lynx^.Sex;
          MigrationEvent^.age := Lynx^.Age;
          MigrationEvent^.natal_pop := Lynx^.Natal_pop;
          MigrationEvent^.old_pop := Lynx^.Previous_pop;
          MigrationEvent^.new_pop := Lynx^.Current_pop;

           SettledList.Add(MigrationEvent);
          end;
          end;

          each_pop_sizes[Lynx^.current_pop, (current_year - start_year)] := each_pop_sizes[Lynx^.current_pop, (current_year - start_year)] + 1;

        end;
      end;

      UpdateAbundanceMap;

    end;


end.

