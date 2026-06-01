unit lynx_dispersal_assist_functions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, math,
  lynx_define_units;

function Nsteps(step_probs: array of double): integer;
procedure Step_probabilities;

function CanMoveHere(x,y: integer): boolean;
function whichPop(x,y:integer):integer;
Function ReproductionQuality(x,y:integer):boolean;

function MoveDir: integer;

function FindTerrOwner(population: TList; targetSex: string; targetX, targetY: word): PAgent;
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

  SetLength(step_probs, max_steps);
  for steps := 0 to max_steps - 1 do
    step_probs[steps] := (1 / (1 + alpha_steps * Power(steps, 3)));

end;


function CanMoveHere(x,y: integer): boolean;
begin
  // outside of map dimensions
  if (x < 0) or (x > Mapdimx) or (y < 0) or (y > Mapdimy) then Result := False
  else
  // barrier cell
    if (HabitatMap[x, y] = 0) then Result := False
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
  if (BreedingHabitatMap[x,y] = 1) and (whichPop(x,y) > 0) then Result := True

end;


function MoveDir: integer;
var
  nOpen, nDisp, nBarr, i, h, f: integer;
  fragmented: boolean;
  theta, P_d, P_o, dist_min, dist_act: real;
  p: double;
begin

  new_dir := 99;
  mem := Individual^.mov_mem;
  tohome := Individual^.return_home;
  homeX := Individual^.homeX;
  homeY := Individual^.homeY;

  {Set base autocorrelation on either short distance or long}
  if (steps / 10.5 > L) then
    theta := theta_d + delta_theta_long
  else
    theta := theta_d;

  {Check if individual is in open habitat, and if so, model probability
  to return from an excursion}
  if (HabitatMap[xp, yp] = 1) and (tohome = False) then
  begin
    P_d := (10.5 * (s / steps)) * gamma;
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
      if (HabitatMap[(xp + dx[i]), (yp + dy[i])] = 1) then
        nOpen := nOpen + 1
      else
        if (HabitatMap[(xp + dx[i]), (yp + dy[i])] = 2) then
          nDisp := nDisp + 1;
    end
    else
      NBarr := NBarr + 1;
    ;
  end;

  {Determine if surroundings is fragmented}
  if nDisp < N_d then fragmented := True
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
          new_dir := i;
        end;
      end;
    end
    else
  {Move to the nearby dispersal cell if there's any in sight.
  Consider autocorrelatin in movement - add to autocorrelation in fragmented area}
    begin
        h := random(nDisp) + 1;
        f := 0;
        for i := 1 to 8 do
        begin
          if CanMoveHere((xp + dx[i]), (yp + dy[i])) and (HabitatMap[(xp + dx[i]), (yp + dy[i])] = 2) then
          begin
            f := f + 1;
            if f = h then
            begin
              new_dir := i;
              Break;
            end;
          end;
        end;
      end;
  end
  else
  begin
    if fragmented = False then
    begin
      {movement in non-fragmented area}
      if (p < theta) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) then new_dir := mem
      else
        if f < (theta + theta * theta_delta) then
        begin
          if (mem > 4) and CanMoveHere((xp + dx[mem-4]), (yp + dy[mem-4])) then new_dir := mem - 4
          else
            if (mem > 0) and (mem <= 4) and CanMoveHere((xp + dx[mem+4]), (yp + dy[mem+4])) then new_dir := mem + 4;
        end;
      if new_dir > 10 then  // If new direction has not yet been assigned through autocorrelation, random movement
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
              new_dir := i;
              Break;
            end;
          end;
        end;
      end;
    end
    else
    begin
      {movement in fragmented area}
      theta := theta + delta_theta_f;
      P_o := (1 / (nOpen + nDisp)) * beta;
      if ((random < P_o) and (nOpen > 0)) or (nDisp = 0) then
        {moving to open habitat}
      begin
    {If memory movement is same type as chosen habitat type (here Open) then use
    autocorrelation to see if ind. moves in memory direction.}
        if CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMap[(xp + dx[mem]), (yp + dy[mem])] = 1) and (p < theta) then
          new_dir := mem
        else
        if (new_dir > 10) and (nOpen > 0) then
        begin
          h := random(nOpen) + 1;
          f := 0;
          for i := 1 to 8 do
          begin
            if CanMoveHere((xp + dx[i]), (yp + dy[i])) and (HabitatMap[(xp + dx[i]), (yp + dy[i])] = 1) then
            begin
              f := f + 1;
              if f = h then
              begin
                new_dir := i;
                Break;
              end;
            end;
          end;
        end;
      end
      else
      begin
        {Move to dispersal habitat}
   {If memory movement is same type as chosen habitat type (here Dispersal) then
   use autocorrelation to see if ind. moves in memory direction.}
        if CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMap[(xp + dx[mem]), (yp + dy[mem])] = 2) and (p < theta) then
          new_dir := mem
        else
        {probability of moving backwards to autocorrelation}
          if (p < (theta + theta * theta_delta)) then
          begin
            if (mem = 0) and CanMoveHere((xp + dx[mem]), (yp + dy[mem])) and (HabitatMap[(xp + dx[mem]), (yp + dy[mem])] = 2) then
              new_dir := mem
            else
              if (mem > 4) and CanMoveHere((xp + dx[mem-4]), (yp + dy[mem-4])) and (HabitatMap[(xp + dx[mem - 4]), (yp + dy[mem - 4])] = 2) then
                new_dir := mem - 4
              else
                if (mem > 0) and (mem <= 4) and CanMoveHere((xp + dx[mem+4]), (yp + dy[mem+4])) and (HabitatMap[(xp + dx[mem + 4]), (yp + dy[mem + 4])] = 2) then
                  new_dir := mem + 4;
          end;
        {Otherwise a random choise of Dispersal habitat cells}
        if (new_dir > 10) and (nDisp > 0) then
        begin
          h := random(nDisp) + 1;
          f := 0;

          for i := 1 to 8 do
          begin
            if CanMoveHere((xp + dx[i]), (yp + dy[i])) and (HabitatMap[(xp + dx[i]), (yp + dy[i])] = 2) then
            begin
              f := f + 1;
              if f = h then
              begin
                new_dir := i;
                Break;
              end;
            end;
          end;
        end;
      end;
    end;
  end;
  if new_dir > 10 then
    Exit;
  if HabitatMap[(xp + dx[new_dir]), (yp + dy[new_dir])] < 1 then
    Exit;
  if CanMoveHere((xp + dx[new_dir]), (yp + dy[new_dir])) = False then
    Exit;

  Result := new_dir;
end;


function FindTerrOwner(population: TList; targetSex: string; targetX, targetY: word): PAgent;
var
  i, j, x, y: integer;
  temp: PAgent;
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
  {Get ranking of both individuals}
  rank_disp := 10;
  rank_settler := 10;

  for i := 1 to Length(ageseq) - 1 do
  begin
    if AgeDisperser = ageseq[i] then rank_disp := i;
    if AgeEarlySettler = ageseq[i] then rank_settler := i;
  end;

  {See which has the best ranking - if equal ranking, the earlier settled individuals "wins"}
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
    if ((Sex = 'f') and (Femalesmap[x, y, 0] = 0)) or
    ((Sex = 'm') and (Malesmap[x, y, 0] = 0) and (Femalesmap[x, y, 0] = 3)) then
    Result := True
    else
      if ((Sex = 'f') and (Femalesmap[x, y, 0] = 2)) or
      ((Sex = 'm') and (Malesmap[x, y, 0] = 2) and (FemalesMap[x,y,0] = 3)) then
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
  temp_ind: PAgent;
  b,first_Tcount, TCount,d, e, f, j, i, g, xi, yi, xy: integer;
  already_terr, c_available: boolean;
 begin
        SetLength(temp_terrX, Tsize);
        SetLength(temp_terrY, Tsize);
        ArrayToNegOne(temp_terrX);
        ArrayToNegOne(temp_terrY);

        {Get all current claimed territory} //not already done above, as TCount < TSize for status = 2 should be less common throughout the year once individuals are more settled}
        for b := 0 to length(Individual^.TerritoryX) - 1 do
        begin
          if (Individual^.TerritoryX[b] > -1) and (Individual^.TerritoryY[b] > -1) then
          begin
          if (Individual^.Sex = 'f') or
            ((Individual^.Sex = 'm') and (FemalesMap[Individual^.TerritoryX[b], Individual^.TerritoryY[b], 0] = 3)) then
          temp_terrX[b] := Individual^.TerritoryX[b];
          temp_terrY[b] := Individual^.TerritoryY[b];
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

        {If there's enough territory available, assign to individual, and make sure individual is located within territory}
        if (TCount = Tsize) then
        begin
          {use temp_terr to remove those coordinates from existing territories}
                    for xy := 0 to TCount - 1 do
                      begin

                        with population do
                        begin
                          for d := 0 to population.Count - 1 do
                          begin
                            temp_ind := Items[d];
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
        end
        else
        {Reset territory information to empty and restart dispersal if there's not enough territory}
        begin
          for b := 0 to length(Individual^.TerritoryX) - 1 do
          begin
            if (Individual^.TerritoryX[b] = -1) then Continue;   // If the territory is already set to -1 then it's been 'taken away' already, and we don't need to update the info below
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
          Individual^.Status := 1;
        end;
      end;


end.

