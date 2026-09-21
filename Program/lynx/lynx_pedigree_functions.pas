unit lynx_pedigree_functions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, Types,
  general_functions, general_define_units;


function CalculateIC(child_ID: integer; Famtree: Array2Dreal): real;
function FindClosestCommonAncestors(Famtree:  Array2Dreal; child_ID: integer): Array2Dinteger;


implementation


function CalculateIC(child_ID: integer; Famtree: Array2Dreal): real;
var
  CA: Array2Dinteger;
  a: integer;
  IC_sum, b, c: real;
begin

 setLength(CA, 2);
 CA := FindClosestCommonAncestors(Famtree,child_ID);

 if CA <> nil then
 begin
 IC_sum := 0;

 for a:=0 to Length(CA) - 1 do
 begin
  c:= Famtree[CA[a,0], 1];
  b := power(0.5, CA[a,1]-1) * (1 + c);
  IC_sum := IC_sum + b;
 end;

 Result := IC_sum;
 end
 else
 Result := 0;

end;


function FindClosestCommonAncestors(Famtree: Array2Dreal; child_ID: integer): Array2Dinteger;
type
  // Define a record to store ancestor ID and distance
  TAncestorInfo = record
    ID: Integer;
    Steps: Integer;
  end;

  // Fully specialized generic types
  TAncestorQueue = specialize TQueue<TAncestorInfo>;
  TAncestorDict = specialize TDictionary<Integer, Integer>;
  TPointList = specialize TList<TPoint>;
var
  i, ancestorID, steps, minSteps: integer;
  qMother, qFather: TAncestorQueue;
  visitedMother, visitedFather: TAncestorDict;
  commonAncestors: TPointList;
  current: TAncestorInfo;
  closestAncestors: Array2Dinteger;
begin
  // Create data structures
  qMother := TAncestorQueue.Create;
  qFather := TAncestorQueue.Create;
  visitedMother := TAncestorDict.Create;
  visitedFather := TAncestorDict.Create;
  commonAncestors := TPointList.Create;

  try
    // Initialize with parents (ID, steps)
    if (child_ID >= 0) and (child_ID < Length(Famtree)) then
    begin
      // Add father to father's queue
      ancestorID := Round(Famtree[child_ID, 2]);
      if ancestorID <> -1 then
      begin
        current.ID := ancestorID;
        current.Steps := 1;
        qFather.Enqueue(current);
        visitedFather.Add(ancestorID, 1);
      end;

      // Add mother to mother's queue
      ancestorID := Round(Famtree[child_ID, 3]);
      if ancestorID <> -1 then
      begin
        current.ID := ancestorID;
        current.Steps := 1;
        qMother.Enqueue(current);
        visitedMother.Add(ancestorID, 1);
      end;
    end;

    // Initialize minSteps before use
    minSteps := MaxInt;

    // Process mother's side ancestors with breadth-first search
    while qMother.Count > 0 do
    begin
      current := qMother.Dequeue;
      ancestorID := current.ID;
      steps := current.Steps;

      // Check if this ancestor is already found on father's side
      if visitedFather.ContainsKey(ancestorID) then
        commonAncestors.Add(TPoint.Create(ancestorID, steps + visitedFather[ancestorID]));

      // Only continue if we haven't found common ancestors yet or need more with same distance
      if (commonAncestors.Count = 0) or
         ((steps <= minSteps) and (ancestorID < Length(Famtree)) and (ancestorID <> -1)) then
      begin
        // Add father of current ancestor
        if (ancestorID < Length(Famtree)) then
        begin
          ancestorID := Round(Famtree[ancestorID, 2]);
          if (ancestorID <> -1) and not visitedMother.ContainsKey(ancestorID) then
          begin
            current.ID := ancestorID;
            current.Steps := steps + 1;
            qMother.Enqueue(current);
            visitedMother.Add(ancestorID, steps + 1);
          end;

          // Reset ancestorID to current.ID for mother lookup
          ancestorID := current.ID;

          // Add mother of current ancestor
          if (ancestorID < Length(Famtree)) then
          begin
            ancestorID := Round(Famtree[ancestorID, 3]);
            if (ancestorID <> -1) and not visitedMother.ContainsKey(ancestorID) then
            begin
              current.ID := ancestorID;
              current.Steps := steps + 1;
              qMother.Enqueue(current);
              visitedMother.Add(ancestorID, steps + 1);
            end;
          end;
        end;
      end;
    end;

    // Process father's side ancestors with breadth-first search
    while qFather.Count > 0 do
    begin
      current := qFather.Dequeue;
      ancestorID := current.ID;
      steps := current.Steps;

      // Check if this ancestor is already found on mother's side
      if visitedMother.ContainsKey(ancestorID) then
        commonAncestors.Add(TPoint.Create(ancestorID, steps + visitedMother[ancestorID]));

      // Only continue if we haven't found common ancestors yet or need more with same distance
      if (commonAncestors.Count = 0) or
         ((steps <= minSteps) and (ancestorID < Length(Famtree)) and (ancestorID <> -1)) then
      begin
        // Add father of current ancestor
        if (ancestorID < Length(Famtree)) then
        begin
          ancestorID := Round(Famtree[ancestorID, 2]);
          if (ancestorID <> -1) and not visitedFather.ContainsKey(ancestorID) then
          begin
            current.ID := ancestorID;
            current.Steps := steps + 1;
            qFather.Enqueue(current);
            visitedFather.Add(ancestorID, steps + 1);
          end;

          // Reset ancestorID to current.ID for mother lookup
          ancestorID := current.ID;

          // Add mother of current ancestor
          if (ancestorID < Length(Famtree)) then
          begin
            ancestorID := Round(Famtree[ancestorID, 3]);
            if (ancestorID <> -1) and not visitedFather.ContainsKey(ancestorID) then
            begin
              current.ID := ancestorID;
              current.Steps := steps + 1;
              qFather.Enqueue(current);
              visitedFather.Add(ancestorID, steps + 1);
            end;
          end;
        end;
      end;
    end;

    // Find minimum distance if any common ancestors were found
    if commonAncestors.Count > 0 then
    begin
      minSteps := MaxInt;
      for i := 0 to commonAncestors.Count - 1 do
        if commonAncestors[i].Y < minSteps then
          minSteps := commonAncestors[i].Y;

      // Count ancestors with minimum distance
      steps := 0;
      for i := 0 to commonAncestors.Count - 1 do
        if commonAncestors[i].Y = minSteps then
          Inc(steps);

      // Create result array
      SetLength(closestAncestors, steps);
      steps := 0;

      for i := 0 to commonAncestors.Count - 1 do
        if commonAncestors[i].Y = minSteps then
        begin
          SetLength(closestAncestors[steps], 2);
          closestAncestors[steps][0] := commonAncestors[i].X;
          closestAncestors[steps][1] := commonAncestors[i].Y;
          Inc(steps);
        end;

      Result := closestAncestors;
    end
    else
      Result := nil;

  finally
    // Clean up
    qMother.Free;
    qFather.Free;
    visitedMother.Free;
    visitedFather.Free;
    commonAncestors.Free;
  end;
end;


end.

