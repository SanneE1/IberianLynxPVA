unit general_functions_unit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Dialogs,
  lynx_define_unit;

function randomPoisson(mean: integer): integer;
procedure ArrayToNegOne(var arr: array of integer);
procedure ReadMap(mapname: string);
procedure ShowErrorAndExit(const errMsg: string);


implementation

function randomPoisson(mean: integer): integer;
  {pseudorandom Poisson distributed number genetrator, Donald Knuth's algorithm}
const
  RESOLUTION = 1000;
var
  k: integer;
  b, l: real;
begin
  //assert(mean > 0, 'mean < 1');
  k := 0;
  b := 1;
  l := exp(-mean);
  while b > l do
  begin
    k := k + 1;
    b := b * random(RESOLUTION) / RESOLUTION;
  end;
  if mean <= 0 then randomPoisson := 0
  else
    randomPoisson := k - 1;
end;

procedure ArrayToNegOne(var arr: array of integer);
var
  i: integer;
begin
  for i := Low(arr) to High(arr) do
    arr[i] := -1;
end;

procedure ReadMap(mapname: string);
var
  ix, iy, Value: integer;
begin
  Assign(filename, mapName);
  reset(filename);
  readln(filename, Mapdimx, Mapdimy);
  SetLength(HabitatMap, Mapdimx + 1, Mapdimy + 1);

  for iy := 1 to Mapdimy do
  begin
    begin
      for ix := 1 to Mapdimx do
      begin
        Read(filename, Value);
        // HabitatMap (and the others) are 'byte' types which is less memory
        // intensive than an integer, but that does mean it can only deal with 0:255
        // There are values in the map of -9999 that represent the sea. As its the same as a barrier, here set to 0!
        if Value < 0 then HabitatMap[ix, iy] := 0
        else
          HabitatMap[ix, iy] := Value;
      end;
    end;
    readln(filename);
  end;

  Close(filename);
end;

procedure ShowErrorAndExit(const errMsg: string);
begin
  {$IFDEF WINDOWS}
  if IsConsole then
    Writeln('Error: ', errMsg)  // Console error output
  else
    MessageDlg('Error: ' + errMsg, mtError, [mbOK], 0); // GUI error dialog
  {$ELSE}
  Writeln('Error: ', errMsg);  // For non-Windows systems or always CLI
  {$ENDIF}

  Halt(1);  // Exit the program with a non-zero code to indicate error
end;


end.

