unit lynx_dispersal_assist_functions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, math,
  general_functions, general_define_units;

function Nsteps(step_probs: array of double): integer;
procedure Step_probabilities;

function CanMoveHere(x,y: integer): boolean;
function whichPop(x,y:integer):integer;
Function ReproductionQuality(x,y:integer):boolean;

function MoveDir: integer;

function FindTerrOwner(population: TList; targetSex: string; targetX, targetY: word): PLynx;
function Fight(AgeDisperser, AgeEarlySettler: integer; Sex: string): boolean;
function TerritoryCellAvailable(x,y: integer; Sex:string; disperser_age: integer): boolean;
procedure ClaimNewTerrOrStartDispersal;

implementation




function NSteps(step_probs: array of double): integer;
var
  r: double;
  s: integer;
begin

  r := Random;

  for s := 0 to length(step_probs) - 1 do
    if r > step_probs[s] then
    begin
      Result := s + 1;
      // Remember 1 step is indexed as 0 in step_prob array (in other words, that array starts at 0 not 1)
      Break;
    end;

end;

procedure Step_probabilities;
var
  steps: integer;
begin

  SetLength(step_probs, L_max_steps);
  for steps := 0 to L_max_steps - 1 do
    step_probs[steps] := (1 / (1 + L_alpha_steps * Power(steps, 3)));

end;


function CanMoveHere(x,y: integer): boolean;
begin
  // outside of map dimensions
  if (x < 0) or (x > Mapdimx) or (y < 0) or (y > Mapdimy) then Result := False
  else
  // barrier cell
    if (HabitatMapLynx[x, y] = 0) then Result := False
    else
      Result := True;
end;

function whichPop(x,y:integer):integer;
begin
  Result := PopsMap[x,y];
end;

Function ReproductionQuality(x,y:integer):boolean;

begin
  Result:=False;
  if BreedingHabitatMap[x,y] = 1 then Result := True;

end;


function MoveDir: integer;
var
  nOpen, nDisp, nBarr, i, h, f: integer;
  fragmented: boolean;
  theta, P_d, P_o, dist_min, dist_act: real;
  p: double;
begin

  Result := 99;
  mem := Lynx^.mov_mem;
  tohome := Lynx^.return_home;
  homeX := Lynx^.homeX;
  homeY := Lynx^.homeY;

  {Set base autocorrelation on either short distance or long}
  if (steps / 10.5 > L_L) then
    theta := L_theta_d + L_delta_theta_long
  else
    theta := L_theta_d;

  {Check if Lynx is in open habitat, and if so, model probability
  to return from an excursion}
  if (HabitatMapLynx[xp, yp] = 1) and (tohome = False) then
  begin
    P_d := (10.5 * (s / steps)) * L_gamma;
    if random < P_d then
      tohome := True;
  end;

  {Look around}
  nOpen := 0;
  nDisp := 0;
  nBarr := 0;

  for i := 1 to 8 do
  begin
    if CanMoveHere((xp + dx[i]), (yp + dy[i])) then
    begin
      if (HabitatMapLynx[(xp + dx[i]), (yp + dy[i])] = 1) then
        nOpen := nOpen + 1
      else
        if (HabitatMapLynx[(xp + dx[i]), (yp + dy[i])] = 2) then
          nDisp := nDisp + 1;
    end
    else
      NBarr := NBarr + 1;
  end;

  {move towards center of map if individual is in barrier area}
  if (nOpen = 0) and (nDisp = 0) then
  begin
    if (xp < (Mapdimx div 2)) and (yp < (Mapdimy div 2)) then Result := 2
    else if (xp < (Mapdimx div 2)) and (yp >= (Mapdimy div 2)) then Result := 4
    else if (xp >= (Mapdimx div 2)) and (yp < (Mapdimy div 2)) then Result := 8
    else if (xp >= (Mapdimx div 2)) and (yp >= (Mapdimy div 2)) then Result := 6;
    Assert(Result <= 8, 'MoveDir: Result out of range');
    Exit;
  end;

  {Determine if surroundings is fragmented}
  if nDisp < L_N_d then fragmented := True
  else
    fragmented := False;

  p := random;

  if tohome = True then
  begin
    {return to last dispersal location if no dispersal habitat is in sight}
    if nDisp = 0 then
    begin
      dist_min := 1000;
      for i := 1 to 8 do
      begin
        if CanMoveHere((xp + dx[i]), (yp + dy[i])) then
          dist_act := sqrt(sqr((xp + dx[i]) - homeX) + sqr((yp + dy[i]) - homeY))
        else
          dist_act := 1001;
        if dist_act <= dist_min then
        begin
          dist_min := dist_act;
          Result := i;
          Exit;
        end;
      end;
      Assert(Result <= 8, 'MoveDir: Result out of range');
    end
    else
  {Move to the nearby dispersal cell if there's any in sight.}
    begin
        h := random(nDisp) + 1;
        f := 0;
        for i := 1 to 8 do
        begin
          if (HabitatMapLynx[(xp + dx[i]), (yp + dy[i])] = 2) then
          begin
            f := f + 1;
            if f = h then
            begin
              Result := i;
              Exit;
            end;
          end;
        end;
        Assert(Result <= 8, 'MoveDir: Result out of range');
      end;
  end
  else if fragmented = False then
    begin
      {movement in non-fragmented area}
      if (p < theta) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) then
      begin
      Result := mem;
      Exit;
      end
      else
        if (p < (theta + theta * L_theta_delta)) and (mem > 4) and CanMoveHere((xp + dx[mem-4]), (yp + dy[mem-4])) then
        begin
          Result := mem - 4;
          Exit;
        end
        else if (p < (theta + theta * L_theta_delta)) and (mem > 0) and (mem <= 4) and CanMoveHere((xp + dx[mem+4]), (yp + dy[mem+4])) then
            begin
            Result := mem + 4;
            Exit;
            end
        else
        begin
        h := random(nDisp + nOpen) + 1;
        f := 0;
        for i := 1 to 8 do
        begin
          if CanMoveHere((xp + dx[i]), (yp + dy[i])) then
          begin
            f := f + 1;
            if f = h then
            begin
              Result := i;
              Exit;
            end;
          end;
      end;
        Assert(Result <= 8, 'MoveDir: Result out of range');
      end;
    end
    else
    begin
      {movement in fragmented area}
      theta := theta + L_delta_theta_f;
      P_o := (1 / (nOpen + nDisp)) * L_beta;
      if ((random < P_o) and (nOpen > 0)) or (nDisp = 0) then
        {moving to open habitat}
      begin
    {If memory movement is same type as chosen habitat type (here Open) then use
    autocorrelation to see if ind. moves in memory direction.}
        if CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem]), (yp + dy[mem])] = 1) and (p < theta) then
          begin
          Result := mem;
          Exit;
          end
        else
        {probability of moving backwards to autocorrelation}
          if (p < (theta + theta * L_theta_delta)) and (mem = 0) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem]), (yp + dy[mem])] = 1) then
              begin
              Result := mem;
              Exit;
              end
          else if (p < (theta + theta * L_theta_delta)) and (mem > 4) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem - 4]), (yp + dy[mem - 4])] = 1) then
                begin
                Result := mem - 4;
                Exit
                end
          else if (p < (theta + theta * L_theta_delta)) and (mem > 0) and (mem <= 4) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem + 4]), (yp + dy[mem + 4])] = 1) then
                  begin
                  Result := mem + 4;
                  Exit;
                  end
        else
        begin
          h := random(nOpen) + 1;
          f := 0;
          for i := 1 to 8 do
          begin
            if CanMoveHere((xp + dx[i]), (yp + dy[i])) and (HabitatMapLynx[(xp + dx[i]), (yp + dy[i])] = 1) then
            begin
              f := f + 1;
              if f = h then
              begin
                Result := i;
                Exit;
              end;
            end;
          end;
        end;
        Assert(Result <= 8, 'MoveDir: Result out of range');
      end
      else
      begin
        {Move to dispersal habitat}
        if CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem]), (yp + dy[mem])] = 2) and (p < theta) then
          begin
          Result := mem;
          Exit;
          end
        else
        {probability of moving backwards to autocorrelation}
          if (p < (theta + theta * L_theta_delta)) and (mem = 0) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem]), (yp + dy[mem])] = 2) then
              begin
              Result := mem;
              Exit;
              end
          else if (p < (theta + theta * L_theta_delta)) and (mem > 4) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem - 4]), (yp + dy[mem - 4])] = 2) then
                begin
                Result := mem - 4;
                Exit
                end
          else if (p < (theta + theta * L_theta_delta)) and (mem > 0) and (mem <= 4) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMapLynx[(xp + dx[mem + 4]), (yp + dy[mem + 4])] = 2) then
                  begin
                  Result := mem + 4;
                  Exit;
                  end
          else
        {Otherwise a random choise of Dispersal habitat cells}
          begin
          h := random(nDisp) + 1;
          f := 0;

          for i := 1 to 8 do
          begin
            if CanMoveHere((xp + dx[i]), (yp + dy[i])) and (HabitatMapLynx[(xp + dx[i]), (yp + dy[i])] = 2) then
            begin
              f := f + 1;
              if f = h then
              begin
                Result := i;
                Exit;
              end;
            end;
          end;
          Assert(Result <= 8, 'MoveDir: Result out of range');
        end;
      end;
    end;

  Assert(Result <= 8, 'MoveDir: Result out of range');

end;


function FindTerrOwner(population: TList; targetSex: string; targetX, targetY: word): PLynx;
var
  i, j, x, y: integer;
  temp: PLynx;
begin
  Result := nil;
  with population do
  begin
    for i := 0 to population.Count - 1 do
    begin
      temp := Items[i];
      if temp^.Sex = targetSex then
      begin
        for j := 0 to length(temp^.TerritoryX) - 1 do
        begin
          x := temp^.TerritoryX[j];
          y := temp^.TerritoryY[j];

          if (x = targetX) and (y = targetY) then
          begin
            Result := temp;
            Exit;   // Match found
          end;
        end;
      end;
    end;
  end;

end;

function Fight(AgeDisperser, AgeEarlySettler: integer; Sex: string): boolean;
  // Return 1 means "win" (Dispersal wins), 0 means lost (Settler wins)
var
  ageseq: array of integer;
  rank_disp, rank_settler, i: integer;
begin

  SetLength(ageseq, 0); // Initialize the dynamic array

  {Set age priority}
  if sex = 'f' then
  begin
    SetLength(ageseq, 9);
    ageseq[1] := 4;
    ageseq[2] := 5;
    ageseq[3] := 6;
    ageseq[4] := 7;
    ageseq[5] := 3;
    ageseq[6] := 2;
    ageseq[7] := 8;
    ageseq[8] := 9;
  end
  else
  begin
    SetLength(ageseq, 8);
    ageseq[1] := 4;
    ageseq[2] := 5;
    ageseq[3] := 6;
    ageseq[4] := 7;
    ageseq[5] := 3;
    ageseq[6] := 8;
    ageseq[7] := 9;
  end;
  {Get ranking of both Lynxs}
  rank_disp := 10;
  rank_settler := 10;

  for i := 1 to Length(ageseq) - 1 do
  begin
    if AgeDisperser = ageseq[i] then rank_disp := i;
    if AgeEarlySettler = ageseq[i] then rank_settler := i;
  end;

  {See which has the best ranking - if equal ranking, the earlier settled Lynxs "wins"}
  if rank_disp < rank_settler then Result := True
  else
    Result := False;

end;

function TerritoryCellAvailable(x,y: integer; Sex:string; disperser_age: integer): boolean;
var
  resident_age: integer;
  Iwin: boolean;
begin

  Result := False;

  if ((Sex = 'f') and (Femalesmap[x, y, 0] = 3)) or
  ((Sex = 'm') and (Malesmap[x, y, 0] = 3)) then
  Result := False
  else
    if ((Sex = 'f') and (Femalesmap[x, y, 0] = -1)) or
    ((Sex = 'm') and (Malesmap[x, y, 0] = -1) and (Femalesmap[x, y, 0] >= 2)) then
    Result := True
    else
      if ((Sex = 'f') and (Femalesmap[x, y, 0] = 2)) or
      ((Sex = 'm') and (Malesmap[x, y, 0] = 2) and (FemalesMap[x,y,0] >= 2) ) then
      begin
      resident_age := -1;
        if (Sex = 'f') then
        resident_age := Femalesmap[x, y, 1]
        else
          resident_age := Malesmap[x, y, 1];
        Iwin := fight(disperser_age, resident_age, Sex);
        if Iwin then Result := True;
      end;

end;

procedure ClaimNewTerrOrStartDispersal;
var
  temp_terrX, temp_terrY: array of integer;
  temp_ind: PLynx;
  b,first_Tcount, TCount,d, e, f, j, i, g, xi, yi, xy: integer;
  already_terr, c_available: boolean;
 begin
        SetLength(temp_terrX, Tsize);
        SetLength(temp_terrY, Tsize);
        ArrayToNegOne(temp_terrX);
        ArrayToNegOne(temp_terrY);

        {Get all current claimed territory} //not already done above, as TCount < TSize for status = 2 should be less common throughout the year once Lynxs are more settled}
        for b := 0 to length(Lynx^.TerritoryX) - 1 do
        begin
          if (Lynx^.TerritoryX[b] > -1) and (Lynx^.TerritoryY[b] > -1) then
          begin
          if (Lynx^.Sex = 'f') or
            ((Lynx^.Sex = 'm') and (FemalesMap[Lynx^.TerritoryX[b], Lynx^.TerritoryY[b], 0] = 3)) then
          temp_terrX[b] := Lynx^.TerritoryX[b];
          temp_terrY[b] := Lynx^.TerritoryY[b];
          end;
        end;

        {See if there's other available territory nearby}
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
                    if ((HabitatMapLynx[xi, yi] = 2) and (ReproductionQuality(xi, yi))) then
                    begin
                    c_available := False;
                    c_available:= TerritoryCellAvailable(xi, yi, Lynx^.Sex, Lynx^.Age);

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

        {If there's enough territory available, assign to Lynx, and make sure Lynx is located within territory}
        if (TCount = Tsize) then
        begin
          {use temp_terr to remove those coordinates from existing territories}
                    for xy := 0 to TCount - 1 do
                      begin

                        with LynxPopulation do
                        begin
                          for d := 0 to LynxPopulation.Count - 1 do
                          begin
                            temp_ind := Items[d];
                            if temp_ind^.Sex = Lynx^.Sex then
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

                    {Assign territory to Lynx and change status}
                    Lynx^.status := 2;
                      for f := 0 to TCount - 1 do
                      begin
                        Lynx^.TerritoryX[f] := temp_terrX[f];
                        Lynx^.TerritoryY[f] := temp_terrY[f];

                        if Lynx^.Sex = 'f' then
                        begin
                        FemalesMap[temp_terrX[f], temp_terrY[f], 0] := Lynx^.Status;
                        FemalesMap[temp_terrX[f], temp_terrY[f], 1] := Lynx^.Age;
                        end
                        else
                        begin
                          MalesMap[temp_terrX[f], temp_terrY[f], 0] := Lynx^.Status;
                          MalesMap[temp_terrX[f], temp_terrY[f], 1] := Lynx^.Age;
                        end;
                      end;
        end
        else
        {Reset territory information to empty and restart dispersal if there's not enough territory}
        begin
          for b := 0 to length(Lynx^.TerritoryX) - 1 do
          begin
            if (Lynx^.TerritoryX[b] = -1) then Continue;   // If the territory is already set to -1 then it's been 'taken away' already, and we don't need to update the info below
            if Lynx^.Sex = 'f' then
            begin
            FemalesMap[Lynx^.TerritoryX[b], Lynx^.TerritoryY[b], 0]:= -1;
            FemalesMap[Lynx^.TerritoryX[b], Lynx^.TerritoryY[b], 1]:= -1;
            end
            else
            begin
            MalesMap[Lynx^.TerritoryX[b], Lynx^.TerritoryY[b], 0]:= -1;
            MalesMap[Lynx^.TerritoryX[b], Lynx^.TerritoryY[b], 1]:= -1;
            end;
            Lynx^.TerritoryX[b] := -1;
            Lynx^.TerritoryY[b] := -1;
          end;
          Lynx^.Status := 1;
        end;
      end;


end.

