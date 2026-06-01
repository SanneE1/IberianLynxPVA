unit lynx_input_output_functions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  general_functions, general_define_units;

procedure ReadParameters_lynx(paramname: string);
procedure UpdateAbundanceMap;
procedure WriteMapCSV(filename: string; var arrayData: Array3Dinteger; dimx, dimy, dimz: integer);
procedure WritePopulationToCSV(population: TList; filename: string; current_sim, year: integer);

implementation

procedure ReadParameters_lynx(paramname: string);
var
  par_seq: array[1..28] of string;
  val_seq: array of real;
  r, spacePos: integer;
  a, param: string;
  value: real;
begin
  {This function is probably much longer than it needs to be. I just need to make absolutely sure
  that if I at some point change or mess with the param file, I get a warning here, so
  I don't accedentily work with parameter values in the wrong variable!}

   par_seq[1]:= 'min_rep_age';
   par_seq[2]:= 'max_rep_age';
   par_seq[3]:= 'max_age';
   par_seq[4]:= 'Tsize';
   par_seq[5]:= 'litter_size';
   par_seq[6]:= 'litter_size_sd';
   par_seq[7]:= 'rep_prob';
   par_seq[8]:= 'surv_cub';
   par_seq[9]:= 'surv_sub';
   par_seq[10]:= 'surv_resident';
   par_seq[11]:= 'surv_disperse';
   par_seq[12]:= 'surv_disp_rho';
   par_seq[13]:= 'surv_old';
   par_seq[14]:= 'alpha_steps';
   par_seq[15]:= 'theta_d';
   par_seq[16]:= 'theta_delta';
   par_seq[17]:= 'delta_theta_long';
   par_seq[18]:= 'delta_theta_f';
   par_seq[19]:= 'L';
   par_seq[20]:= 'N_d';
   par_seq[21]:= 'beta';
   par_seq[22]:= 'gamma';
   par_seq[23]:= 'max_years';
   par_seq[24]:= 'n_sim';
   par_seq[25]:= 'n_cycles';
   par_seq[26]:= 'mapname';
   par_seq[27]:= 'mapPops';
   par_seq[28]:= 'start_pop_file';


   SetLength(val_seq, High(par_seq)+1);

   Assign(filename, paramname);
   reset(filename);

     for r:=1 to High(par_seq) do
     begin
       readln(filename, a);
       // Find the first space to split the string
      spacePos := Pos(' ', a);

      if spacePos > 0 then
      begin
        // Extract parameter name and convert the rest to a real
        param := Copy(a, 1, spacePos - 1);                      // Get parameter name

        if (param = 'mapname') then
          mapname_lynx := Trim(Copy(a, spacePos + 1, Length(a)))
          else if (param = 'mapPops') then
          mapPops := Trim(Copy(a, spacePos + 1, Length(a)))
          else if (param = 'start_pop_file') then
          start_pop_file := Trim(Copy(a, spacePos + 1, Length(a)))
          else
        Val(Trim(Copy(a, spacePos + 1, Length(a))), value);     // Convert value part to real - any integers are converted below to correct type

    if (param = par_seq[r]) then
     val_seq[r] := value
     else
     // stop program and get error message that parameter name not expected
     ShowErrorAndExit('One of the parameter names is not as expected. Check parameter file');
     end
      else ShowErrorAndExit('No space found. Check parameter file');
     end;

     L_min_rep_age        := Round(val_seq[1]);
     L_max_rep_age        := Round(val_seq[2]);
     L_max_age            := Round(val_seq[3]);
     Tsize              := Round(val_seq[4]);
     L_litter_size        := val_seq[5];
   L_litter_size_sd     := val_seq[6];
   L_rep_prob           := val_seq[7];
   L_surv_cub           := val_seq[8];
   L_surv_sub           := val_seq[9];
   L_surv_resident      := val_seq[10];
   L_surv_disperse      := val_seq[11];
   L_surv_disp_rho      := val_seq[12];
   L_surv_old           := val_seq[13];
   L_alpha_steps        := val_seq[14];
   L_theta_d            := val_seq[15];
   L_theta_delta        := val_seq[16];
   L_delta_theta_long   := val_seq[17];
   L_delta_theta_f      := val_seq[18];
   L_L                  := val_seq[19];
   L_N_d                := val_seq[20];
   L_beta               := val_seq[21];
   L_gamma              := val_seq[22];
   max_years          := Round(val_seq[23]);
   n_sim              := Round(val_seq[24]);
   n_cycles           := Round(val_seq[25]);

   mapname_lynx := ExpandFileName(mapname_lynx);
   mapPops := ExpandFileName(mapPops);
   start_pop_file := ExpandFileName(start_pop_file);


end;

procedure UpdateAbundanceMap;
var
  a, b, c, x, y: integer;
  s: string;
begin

  for a := 0 to MapdimX - 1 do
    for b := 0 to Mapdimy - 1 do
      for c := 0 to 1 do           // where 0 is status, 1 is age
    begin
      Malesmap[a, b, c] := 0;      // Empty maps to fill with status and age below
      Femalesmap[a, b, c] := 0;
    end;


  with LynxPopulation do
  begin
    for a := 0 to LynxPopulationSize - 1 do
    begin
      Lynx := Items[a];
      if Lynx^.Status >=2 then
      begin
        for b := 0 to length(Lynx^.TerritoryX) - 1 do
        begin
          x := Lynx^.TerritoryX[b];
          y := Lynx^.TerritoryY[b];
          s := Lynx^.sex;

          if ((x < 0) and (y < 0)) or ((x > MapdimX) or (y > MapdimY)) then
            Continue;

          if (s = 'f') then
            begin
            Femalesmap[x, y, 0] := Lynx^.Status;
            Femalesmap[x, y, 1] := Lynx^.Age;
            end;
          if (s = 'm') then
            begin
            Malesmap[x, y, 0] := Lynx^.Status;
            Malesmap[x, y, 1] := Lynx^.Age;
            end;
        end;
      end;
    end;
  end;

end;

procedure WriteMapCSV(filename: string; var arrayData: Array3Dinteger; dimx, dimy, dimz: integer);
var
  ix, iy: integer;
  outfile: Text;
begin
  Assign(outfile, filename);
  rewrite(outfile);

  // Loop over the arrayData and write each element to the CSV
  for iy := 1 to dimy do
  begin
    for ix := 1 to dimx do
    begin
      // Write each value, followed by a comma, except for the last value in the row
      if ix < dimx then
        Write(outfile, arrayData[ix, iy, dimz], ',')
      else
        Write(outfile, arrayData[ix, iy, dimz]);  // No comma at the end of the row
    end;
    writeln(outfile);  // Move to the next line in the CSV file
  end;

  Close(outfile);
end;

procedure WritePopulationToCSV(population: TList; filename: string; current_sim, year: integer);
var
  csvFile: TextFile;
  i, j: integer;
begin

  AssignFile(csvFile, filename);

  if (current_sim = 1) and (year = 1) then
  begin
    Rewrite(csvFile);
    // Write header
    WriteLn(csvFile, 'Simulation,Year,Sex,Age,Status,Coor_X,Coor_Y,Natal_pop,Previous_pop,Current_pop,Territory_XY');
  end;

  append(csvFile);
  // Write data for each Lynx
  for i := 0 to population.Count - 1 do
  begin
    Write(csvFile, current_sim, ',', year, ',');
    Lynx := PLynx(population[i]);

    // Write Lynx information
    Write(csvFile, Lynx^.sex, ',');
    Write(csvFile, Lynx^.Age, ',');
    Write(csvFile, Lynx^.Status, ',');
    Write(csvFile, Lynx^.Coor_X, ',');
    Write(csvFile, Lynx^.Coor_Y, ',');
    Write(csvFile, Lynx^.Natal_pop, ',');
    Write(csvFile, Lynx^.Previous_pop, ',');
    Write(csvFile, Lynx^.Current_pop, ',');

    // Write territory coordinates
    for j := 0 to length(Lynx^.TerritoryX) - 1 do
    begin

      Write(csvFile, Lynx^.TerritoryX[j], '/');
      Write(csvFile, Lynx^.TerritoryY[j]);

      // Add comma if not last coordinate
      if j < length(Lynx^.TerritoryX) - 1 then
        Write(csvFile, ';');
    end;

    WriteLn(csvFile); // End of current Lynx's data
  end;

  CloseFile(csvFile);
end;

end.

