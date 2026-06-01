unit lynx_vital_rates;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math,
  lynx_define_units, lynx_dispersal_assist_functions, general_functions;


procedure Reproduction;
procedure Survival;
procedure Dispersal(day: integer);



implementation


procedure Reproduction;
var
  a, x,y, current_litter_size, ls, xy, FatherX, FatherY, CurrentDist: integer;
  rep_prob: real;
  temp_X, temp_Y, Temp_mem: word;
  male_present: boolean;
begin

  with population do
  begin
    populationsize := population.Count;
    if (populationsize > 1) then
      for a := 0 to populationsize - 1 do
      begin
        Individual := Items[a];
        if Individual^.Sex = 'm' then Continue;

        male_present:= false;

        {Check that the individual is capable of reproduction}
          if Individual^.status = 3 then
            // Individual is settled
            if Individual^.age >= min_rep_age then
              if Individual^.age <= max_rep_age then
              // Check that there is a local male
              begin
                if Malesmap[Individual^.Coor_X, Individual^.Coor_Y, 0] >= 2 then
                begin
                  FatherX := Individual^.Coor_X;
                  FatherY := Individual^.Coor_Y;
                  male_present := true;
                end
                else
                  begin
                   for CurrentDist := 0 to 30 do
                   begin
                     // Check all cells at the current distance from the starting point
                       for x := Individual^.Coor_X - CurrentDist to Individual^.Coor_X + CurrentDist do
                       begin
                         for y := Individual^.Coor_Y - CurrentDist to Individual^.Coor_Y + CurrentDist do
                         begin
        // only checks cells on the "ring" at CurrentDist
                             if (Max(Abs(x- Individual^.Coor_X), Abs(y - Individual^.Coor_Y)) <> CurrentDist) then
                             Continue;

        // Skip coordinates where lynx couldn't move (so also no coordinates for territory)
                             if not canMoveHere(x, y) then Continue;

        // Check if this cell has a male
                             if Malesmap[x, y, 0] >= 2 then
                             begin
                             FatherX := x;
                             FatherY := y;
                             male_present := True;
                             Break;
          // Don't break here - we need to check all cells at this distance
          // to make sure we find the closest one(s)
                             end;
                         end;
                         if male_present then Break;
                       end;
                       if male_present then Break;
                   end;
                  end;
                  //
                  //

                if male_present then
                  if random < rep_prob then
                  begin
                    current_litter_size := Round(randg(litter_size, litter_size_sd));

                    //Save location of the mother, to give to offspring
                    Temp_X := Individual^.Coor_X;
                    Temp_Y := Individual^.Coor_Y;
                    Temp_mem := Individual^.mov_mem;

                    {Create a number of new individuals}
                    for ls := 1 to current_litter_size do
                    begin

                      New(Individual);
                      Individual^.age := 0;
                      if random < 0.5 then Individual^.sex := 'f'
                      else
                        Individual^.sex := 'm';
                      Individual^.status := 0;
                      Individual^.Coor_X := Temp_X;
                      Individual^.Coor_Y := Temp_Y;

                      Individual^.Natal_pop := whichPop(temp_X, temp_Y);
                      Individual^.Current_pop := whichPop(temp_X, temp_Y);
                      Individual^.Previous_pop := whichPop(temp_X, temp_Y);

                      setLength(Individual^.TerritoryX, Tsize);
                      setLength(Individual^.TerritoryY, Tsize);
                      ArrayToNegOne(Individual^.TerritoryX);
                      ArrayToNegOne(Individual^.TerritoryY);

                      Individual^.mov_mem := Temp_mem;
                      Individual^.homeX := Individual^.Coor_X;
                      Individual^.homeY := Individual^.Coor_Y;
                      Individual^.return_home := False;

                      Individual^.DailySteps := 0;
                      Individual^.DailyStepsOpen := 0;

                      Population.add(Individual);
                    end;
                  end;
              end;
      end;
  end;
end;

procedure Survival;
var
  a, b: integer;
  surv_p, surv_day, daily_mortality_p: real;
  die: boolean;

  //temp_X,temp_Y:word;
begin

  with population do
  begin
    populationsize := population.Count;
    for a := populationsize - 1 downto 0 do  //the index in the list starts at 0
    begin
      Individual := items[a];

      surv_p := -1;

      {Assign yearly survival probabilities}
      if (Individual^.Status = 1) then surv_p := surv_disperse
      else
        begin
          if (Individual^.Status = 0) and (Individual^.Age = 0) then
            surv_p := surv_cub
            else
          // the status statement shouldn't be necessary (cubs shouldn't be able to have another status but just to make sure)
          if (Individual^.Status = 0) and (Individual^.Age > 0) then
            surv_p := surv_sub
            else
          if (Individual^.Status > 1) and (Individual^.Age <= max_rep_age) then
            surv_p := surv_resident
            else
          if (Individual^.Age > max_rep_age) then surv_p := surv_old;
        end;


      {Transform annual survival (surv_p) to daily survival (surv_day)}
        surv_day := Power(surv_p, (1 / 365));
        if (Individual^.Status = 1) then
      begin
       daily_mortality_p := (1-surv_day) + ((1-surv_day) * surv_disp_rho * (Individual^.DailyStepsOpen / Individual^.DailySteps));
       surv_day := 1-daily_mortality_p;
      end;

      {Determine fate of individuals}
      die := False;
      if Individual^.age > max_age then die := True
      else
        if random > surv_day then die := True;
      if die then
      begin
       if Individual^.Status >= 2 then
       for b := 0 to length(Individual^.TerritoryX) - 1 do
          begin
            if (Individual^.TerritoryX[b] = -1) then Continue;
            if Individual^.Sex = 'f' then
            begin
            FemalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 0]:= 0;
            FemalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 1]:= 0;
            end
            else
            begin
            MalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 0]:= 0;
            MalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 1]:= 0;
            end;
            Individual^.TerritoryX[b] := -1;
            Individual^.TerritoryY[b] := -1;
          end;
        Delete(a);
      end;
    end;
  end;
end;

procedure Dispersal(day: integer);
var
  a, b, d, e, f, g, i, j, new_dir, TestCoordX, TestCoordY, TCount, first_Tcount, FCount, xi, yi, xy, competitor_age : integer;
  age_m, P_disp_start: real;
  temp_terrX, temp_terrY: array of integer;
  temp_ind: PAgent;
  Iwin, test_cell_available, c_available, already_terr: boolean;

begin
  check_daily_movement_i := 0;
  with population do
  begin
    populationsize := population.Count;
    for a := 0 to populationsize - 1 do

    begin
      Individual := items[a];

      {If the individual is a subadult determine if it starts dispersing}
      if (Individual^.Status = 0) and (Individual^.Age > 0) then
      begin
        age_m := (Individual^.Age * 12) + (day / 30);
        // Formula requires age in months
        P_disp_start := -1.55 + 2.62 * (1 - Exp(-0.115 * age_m));
        // Calculate probability of dispersing -> higher prob, more likely to start disp.
        if random <= P_disp_start then Individual^.Status := 1;
        // Change status to dispersing if random <= to p_disp_start
      end;

      {Check size of territory for newly established individuals.
      If they do not have enough, see if there is enough unclaimed territory around to add to their territory.
      If not, restart dispersal}
      if (Individual^.Status = 2) then
      begin
        TCount := 0;

        for b := 0 to length(Individual^.TerritoryX) - 1 do
        begin
          if (Individual^.TerritoryX[b] > -1) and (Individual^.TerritoryY[b] > -1) then
          begin
            if (Individual^.Sex = 'f') or
            ((Individual^.Sex = 'm') and (FemalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 0] = 3)) then
            Inc(TCount);
          end;
        end;

        {If there's not enough territory, see if there's any unclaimed available}
        if (TCount < Tsize) and (TCount > 0) then //If TCount is 0 that means that the individual will have to move for sure to find new territory
        ClaimNewTerrOrStartDispersal;
      end;

      {Now start dispersal IF individual has dispersal status}

      if (Individual^.Status = 1) then
      begin
        SetLength(temp_terrX, Tsize);
        SetLength(temp_terrY, Tsize);
        ArrayToNegOne(temp_terrX);
        ArrayToNegOne(temp_terrY);

        {This next section is weird, I know... However, for some reason the NSteps function would sometimes randomly produce
        a number of steps around the 66 milion.... This fixes it so *shrug*}
        steps := 200;
        while steps > 100 do steps := NSteps(step_probs);

        Individual^.DailySteps:= steps;
        Individual^.DailyStepsOpen := 0;
        s := 1;

        {Movement check - fill in array}
        if check_daily_movement_i < 1000 then
        begin
        if Individual^.sex = 'f' then check_daily_movement[check_daily_movement_i, 0] := 0
        else check_daily_movement[check_daily_movement_i, 0] := 1;
        check_daily_movement[check_daily_movement_i, 1] := Individual^.Age;
        end;

        while s <= steps do
        begin

          {Reset variables}
          xp := Individual^.Coor_X;
          yp := Individual^.Coor_Y;
          new_dir := -1;
          TestCoordX := -1;
          TestCoordY := -1;

          {Calculate new movement direction}
          new_dir := MoveDir;

          {Movement check - fill in array}
          if check_daily_movement_i < 1000 then
          check_daily_movement[check_daily_movement_i, s+1]:= new_dir;

          {Calculate coordinates to move to}
          TestCoordX := xp + dx[new_dir];
          TestCoordY := yp + dy[new_dir];

          {update home location if individual moves from dispersal to open habitat}
          if (HabitatMap[xp, yp] = 2) and (HabitatMap[TestCoordX, TestCoordY] = 1) then
          begin
            Individual^.homeX := xp;
            Individual^.homeY := yp;
          end;

          {change tohome to false if individual is back in dispersal habitat}
          if (HabitatMap[TestCoordX, TestCoordY] = 2) and tohome = True then
            Individual^.return_home := False;

          {Move individual and update memory and population}
          Individual^.Coor_X := TestCoordX;
          Individual^.Coor_Y := TestCoordY;
          if (new_dir <> 0) then Individual^.mov_mem := new_dir;

          {Add new location to connection map}
          if Individual^.Sex = 'f' then ConnectionMap[TestCoordX, TestCoordY, 0] := ConnectionMap[TestCoordX, TestCoordY, 0] + 1
          else ConnectionMap[TestCoordX, TestCoordY, 1] := ConnectionMap[TestCoordX, TestCoordY, 1] + 1;


          if  (Individual^.Current_pop = 0) and (whichPop(TestCoordX, TestCoordY) <> 0) and
          (Individual^.Previous_pop <> whichPop(TestCoordX, TestCoordY)) then
          begin
           new(MigrationEvent);

           MigrationEvent^.simulation := current_sim;
           MigrationEvent^.year := current_year;
           MigrationEvent^.sex := Individual^.Sex;
           MigrationEvent^.age := Individual^.Age;
           MigrationEvent^.natal_pop := Individual^.Natal_pop;
           MigrationEvent^.old_pop := Individual^.Previous_pop;
           MigrationEvent^.new_pop := whichPop(TestCoordX, TestCoordY);

           MigrationList.Add(MigrationEvent);
          end;

          if (Individual^.Current_pop <> whichPop(TestCoordX, TestCoordY)) then
          begin
           Individual^.Previous_pop := Individual^.Current_pop;
           Individual^.Current_pop := whichPop(TestCoordX, TestCoordY);
          end;


          {Increase daily steps in open, if new coordinates are in an open habitat}
          if HabitatMap[TestCoordX, TestCoordY] = 1 then Individual^.DailyStepsOpen:= Individual^.DailyStepsOpen + 1;


          {If in breeding habitat, check if settlement is possible}
          if (HabitatMap[TestCoordX, TestCoordY] = 2) and (ReproductionQuality(TestCoordX, TestCoordY)) then
          begin

            test_cell_available := False;
            test_cell_available := TerritoryCellAvailable(TestCoordX, TestCoordY, Individual^.Sex, Individual^.Age);

            if test_cell_available then
            begin
              if Individual^.Sex = 'f' then
              begin
              {Look for more breeding habitat until teritory is big enough}

              temp_terrX[0] := TestCoordX;
              temp_terrY[0] := TestCoordY;
              TCount := 1;

                // Walk through all 9 cells and find any available territory
                for i := 1 to 8 do
                  begin
                    xi := TestCoordX + dx[i];
                    yi := TestCoordY + dy[i];
                    if CanMoveHere(xi, yi) then
                    if ((HabitatMap[xi, yi] = 2) and (ReproductionQuality(xi, yi))) then
                    begin
                      c_available:= False;
                      c_available:= TerritoryCellAvailable(xi, yi, Individual^.Sex, Individual^.Age);

                      if c_available then
                    begin
                      temp_terrX[TCount] := xi;
                      temp_terrY[TCount] := yi;

                      Inc(TCount);


                      if TCount = Tsize then Break;
                      end;
                    end;

                  end;


              {Keep looking in adjacent cells if not enough territory has been found yet}
                if TCount < Tsize then
                begin
                  first_Tcount := TCount;
                  j := 0;
                while (TCount < Tsize) and (j < first_Tcount) do
                begin
                   for i := 1 to 8 do
                  begin
                   xi := temp_terrX[j] + dx[i];
                   yi := temp_terrY[j] + dy[i];

                   already_terr := false;
                   for g := 0 to TCount - 1 do
                     begin
                      if (xi = temp_terrX[g]) and (yi = temp_terrY[g]) then
                      begin
                      already_terr := true;
                      Break;
                      end;
                     end;

                   if not already_terr then
                    if CanMoveHere(xi, yi) then
                    if ((HabitatMap[xi, yi] = 2) and (ReproductionQuality(xi, yi))) then
                    begin
                    c_available := False;
                    c_available:= TerritoryCellAvailable(xi, yi, Individual^.Sex, Individual^.Age);

                      if c_available then
                    begin
                      temp_terrX[TCount] := xi;
                      temp_terrY[TCount] := yi;
                      Inc(TCount);

                      if TCount = Tsize then Break;
                      end;
                    end;
                  end;
                   j := j + 1;
                 end;
                  end;

              end
              else
              begin

               {Males just take all the territory of a single settled female}

               temp_ind := FindTerrOwner(population, 'f', TestCoordX, TestCoordY);

               for i := 0 to Length(temp_ind^.TerritoryX) - 1 do
               begin
                  temp_terrX[i] := temp_ind^.TerritoryX[i];
                  temp_terrY[i] := temp_ind^.TerritoryY[i];
               end;

               TCount := Length(temp_ind^.TerritoryX);

              end;


                  {Check that enough territory has been foundso territory can be removed and assigned according}
                  if TCount >= Tsize then
                  begin
                    {use temp_terr to remove those coordinates from existing territories}
                    for xy := 0 to TCount - 1 do
                      begin

                        with population do
                        begin
                          for d := 0 to population.Count - 1 do
                          begin
                            temp_ind := Items[d];
                            if temp_ind^.Status > 1 then
                            if temp_ind^.Sex = Individual^.Sex then
                            begin
                              with temp_ind^ do
                                for e := Length(TerritoryX) - 1 downto 0 do
                                begin
                                  if (TerritoryX[e] = temp_terrX[xy]) and (TerritoryY[e] = temp_terrY[xy]) then
                                  begin
                                    TerritoryX[e] := -1;
                                    TerritoryY[e] := -1;
                                  end;
                                end;
                            end;
                          end;
                        end;
                      end;

                    {Assign territory to individual and change status}
                    Individual^.status := 2;
                      for f := 0 to TCount - 1 do
                      begin
                        Individual^.TerritoryX[f] := temp_terrX[f];
                        Individual^.TerritoryY[f] := temp_terrY[f];

                        if Individual^.Sex = 'f' then
                        begin
                        FemalesMap[temp_terrX[f], temp_terrY[f], 0] := Individual^.Status;
                        FemalesMap[temp_terrX[f], temp_terrY[f], 1] := Individual^.Age;
                        end
                        else
                        begin
                          MalesMap[temp_terrX[f], temp_terrY[f], 0] := Individual^.Status;
                          MalesMap[temp_terrX[f], temp_terrY[f], 1] := Individual^.Age;
                        end;
                      end;

                      Break;  // No more steps required, as individual is now settled

                    end;

              ArrayToNegOne(temp_terrX);
              ArrayToNegOne(temp_terrY);
              TCount := 0;
              end;
              end;
              Inc(s);
          end;
        if check_daily_movement_i < 1000 then
        check_daily_movement_i := check_daily_movement_i + 1;
        end;

        end;
      end;

    end;



end.

