unit Population_dynamics_GUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, TAGraph, TASeries, Forms, Controls, Graphics,
  Dialogs, StdCtrls, ExtCtrls, Math, LCLType,
  general_functions, general_define_units,
  lynx_population_dynamics, lynx_input_output_functions, lynx_dispersal_assist_functions,
  rabbit_population_dynamics, rabbit_input_output_functions;

type

{ Tspatial_Form }

Tspatial_Form = class(TForm)
    Chart1: TChart;
    Chart1LineSeries1: TLineSeries;
    Chart1LineSeries2: TLineSeries;
    CheckBox1: TCheckBox;
    Edit1: TEdit;
    Edit10: TEdit;
    Edit2: TEdit;
    Edit3: TEdit;
    Edit5: TEdit;
    Exit_Button: TButton;
    Abort_Button: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Panel1: TPanel;
    Run_Button: TButton;
    procedure Abort_ButtonClick(Sender: TObject);
    procedure Exit_ButtonClick(Sender: TObject);
    procedure Run_ButtonClick(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
    procedure Pop_dynamics_GUI;
  end;

var
  spatial_Form: Tspatial_Form;

implementation

{$R *.lfm}

{ Tspatial_Form }

procedure Tspatial_Form.Pop_dynamics_GUI;
var
  b, xy, day, month, Tcheck: integer;
begin

    for current_year := 1 to max_years do
    begin

      for month := 1 to 12 do
      begin

        Rabbit_monthly_demography(current_year, month);

        if month = 6 then Lynx_recalculate_BH(RabbitMap);

        for day := 1 to days_in_month[month] do
        Lynx_daily_demography(month, day);

      end;

      Lynx_age_and_settle;


      {ploting pop size}
      if max_pop_size < LynxPopulationSize then max_pop_size := LynxPopulationSize;
      if max_pop_size > Chart1.extent.YMax then
      begin
        Chart1.extent.YMax := max_pop_size;
        application.ProcessMessages;
      end;
      pop_size[current_year] := LynxPopulationSize;
      sum_pop_size[current_year] := sum_pop_size[current_year] + LynxPopulationSize;
      {plot trajectory}
      Chart1LineSeries1.addxy(current_year, LynxPopulationSize);

    if (current_year = 1) or (current_year mod 10 = 0) then
    begin
    WriteMapCSV('output_data/maps/FemalesMap_status_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 0);
    WriteMapCSV('output_data/maps/FemalesMap_age_yr_' + IntToStr(current_year) + '.csv', Femalesmap, MapdimX, MapdimY, 1);
    WriteMapCSV('output_data/maps/MalesMap_status_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 0);
    WriteMapCSV('output_data/maps/MalesMap_age_yr_' + IntToStr(current_year) + '.csv', Malesmap, MapdimX, MapdimY, 1);
    end;

    WritePopulationToCSV(LynxPopulation, 'output_data/Lynx_population_data.csv', current_sim, current_year);

    end;

end;


procedure Tspatial_Form.Run_ButtonClick(Sender: TObject);
var
  a, b, c, i, r: integer;
  t: string;
begin
  randomize; {initialize the pseudorandom number generator}

  paramname_lynx := Edit3.Text;
  paramname_rabbit := Edit1.Text;

  ReadParameters_lynx(paramname_lynx);
  ReadParameters_Rabbit(paramname_rabbit);

  if CheckBox1.Checked then
  begin
  {These values overwrite the values in the file with the input from the GUI}
  val(Edit2.Text, max_years);
  mapname_lynx := Edit10.Text;
  end;

  HabitatMapRabbit := ReadMap(mapname_rabbit);
  HabitatMapLynx := ReadMap(mapname_lynx);
  PopsMap := ReadMap(mapPops);

  readclim(breedname, dryname);

  SetLength(MalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(FemalesMap, Mapdimx + 1, Mapdimy + 1, 2);
  SetLength(BreedingHabitatMap, Mapdimx + 1, mapdimy + 1);

  SetLength(ConnectionMap, Mapdimx + 1, Mapdimy + 1, 2);

  AssignFile(to_file_out,'output_data/lynx_pop_size.txt');
  rewrite(to_file_out); {create txt file}
  writeln(to_file_out, 'current_sim,year,pop1, pop2, pop3, pop4, pop5');

  AssignFile(mig_file_out, 'output_data/lynx_migration.csv');
  rewrite(mig_file_out); {create txt file}
  writeln(mig_file_out, 'EventID,Simulation,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

  AssignFile(migS_file_out, 'output_data/lynx_migration_settled.csv');
  rewrite(migS_file_out); {create txt file}
  writeln(migS_file_out, 'EventID,Simulation,Year,Sex,Age,Natal_pop,Old_pop,New_pop');

  for a := 1 to max_years do sum_pop_size[a] := 0;

  SetLength(each_pop_sizes, 6);
  for i := 0 to High(each_pop_sizes) do
    SetLength(each_pop_sizes[i], max_years+1);

  // Calculate array of step probabilities (here once) to be used in dispersal procedure later
  Step_probabilities;

  MigrationList := TList.Create;
  SettledList := Tlist.Create;

  for current_sim := 1 to n_sim do
  begin
    max_pop_size := 0;
    Startpopulation_rabbit;
    Startpopulation_lynx;
    Pop_dynamics_GUI;    {call the procedure to run the population dynamics}

    {plot population trayectories}
    Chart1LineSeries1.Clear;
    Chart1LineSeries2.Clear;

    for b := 1 to max_years do Chart1LineSeries1.addxy(b, pop_size[b]);
    application.ProcessMessages;
    if (current_sim > 1) then
      if (n_sim > 1) then
        //   for b:=1 to max_years do Chart1LineSeries2.addxy(b,sum_pop_size[b]/n_sim_no_ext[b]);  //now we calculate the avg only when the population is not extinct
        for b := 1 to max_years do
          Chart1LineSeries2.addxy(b, sum_pop_size[b] / current_sim);

    {save the results to a text file}
    append(to_file_out);
    for b := 1 to max_years do
    begin
      writeln(to_file_out, current_sim, ',', b, ',',
      each_pop_sizes[0,b], ',',
      each_pop_sizes[1,b], ',',
      each_pop_sizes[2,b], ',',
      each_pop_sizes[3,b], ',',
      each_pop_sizes[4,b], ',',
      each_pop_sizes[5,b], ',');
    end;

    CloseFile(to_file_out);

    {Write Migration list to file}
    append(mig_file_out);
    with MigrationList do
    for b := 0 to MigrationList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(mig_file_out, b , ',', MigrationEvent^.simulation, ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);
    end;
    CloseFile(mig_file_out);


    {Write Settled Migrants list to file}
    append(migS_file_out);
    with SettledList do
    for b := 0 to SettledList.Count - 1 do
    begin
      MigrationEvent := items[b];

      writeln(migS_file_out, b , ',', MigrationEvent^.simulation, ',',
      MigrationEvent^.year, ',',
      MigrationEvent^.sex, ',',
      MigrationEvent^.age, ',',
      MigrationEvent^.natal_pop, ',',
      MigrationEvent^.old_pop, ',',
      MigrationEvent^.new_pop);
    end;
    CloseFile(migS_file_out);

    {Write connection map}
    WriteMapCSV('output_data/maps/FemalesMap_traveled_' + IntToStr(current_sim) + '.csv', ConnectionMap, MapdimX, MapdimY, 0);
    WriteMapCSV('output_data/maps/MalesMap_traveled_' + IntToStr(current_sim) + '.csv', ConnectionMap, MapdimX, MapdimY, 1);

    end;

end;

procedure Tspatial_Form.Exit_ButtonClick(Sender: TObject);
begin
  Close;
end;

procedure Tspatial_Form.Abort_ButtonClick(Sender: TObject);
begin
  halt;
end;

end.

