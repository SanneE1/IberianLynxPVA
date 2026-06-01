unit general_define_units;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type           {here you declare the data structure for you individuals}
  Array2DInteger = array of array of integer;
  Array3DInteger = array of array of array of integer;

  MapOfLists = array of array of Tlist;

  PLynx = ^LynxAgent;

  LynxAgent = record
    sex: string[1];
    Age: byte;         // In years
    Status: shortint;  // 0=pre-dispersal cubs and subadults, 1=dispersing individuals, 2=early settled adults, 3 = fully settled adults
    ID: integer;

    Coor_X: integer;
    Coor_Y: integer;

    Natal_pop: byte;
    Current_pop: byte;
    Previous_pop: byte;

    TerritoryX: array of integer;
    TerritoryY: array of integer;

    DailySteps: byte;
    DailyStepsOpen: byte;
    mov_mem: byte;
    return_home: boolean;  // not to be confused with Territory. This is for when individuals go on an excursion
    // into Open habitat, for them to return to the last known Dispersal habitat they've visited
    homeX: integer;
    homeY: integer;
  end;

  PRabbit = ^RabbitAgent;

  RabbitAgent = record
    sex: string[1];
    Age: integer;      // months
    Pregnant: boolean;  // Individual pregnant?
    Lactating: boolean; // Is Individual lactating (i.e. have dependent pups)
  end;

   TRHDCellData = record
    NextOutbreakMonth: Integer;      // When next outbreak occurs
    OutbreakFrequency: Integer;      // 24-36 months between outbreaks
    OutbreakMortality: Real;         // 0.15-0.25 mortality rate
  end;

    PMigration = ^Migration;
    Migration = record
      year: integer;
      sex: string[1];
      age: byte;
      natal_pop: integer;
      old_pop: integer;
      new_pop: integer;
  end;

    POutRep = ^OutRep;
    OutRep = record
      year: integer;
      X: integer;
      Y: integer;
    end;

var
  {Simulation info}
  current_year, n_years, start_year, end_year, month, day: integer;
  max_pop_size: integer;
  sum_pop_size: array[1..100] of integer;
  each_pop_sizes: array of array of integer;
  output_dir, habitat_folder, breeding_folder: string;
  create_maps: boolean = True;
  all_month_maps: boolean = False;
  create_maps_25yrs: boolean = False;
  create_2yr_month_maps: boolean = False;

  {General variables}
  Mapdimx, Mapdimy: integer;
  filename: Text;
  xp, yp: integer;

  {Lynx - population info}
  LynxPopulation: TList;
  Lynx: PLynx;
  L_ID_tracker: integer;
  LynxPopulationSize: integer;
  paramname_lynx, start_pop_file, reintro_file, breeding_file: string;
  pop_status_array: Array2Dinteger;
  to_file_out: TextFile;

  {Lynx - maps}
  mapname_lynx, mapPops: string;
  HabitatMapLynx: Array2Dinteger;
  BreedingHabitatMap: Array2Dinteger;
  PopsMap: Array2Dinteger;
  MalesMap: Array3Dinteger;
  FemalesMap: Array3Dinteger;
  ConnectionMap: Array3Dinteger;

  {Lynx - Connectivity}
  MigrationList: TList;
  SettledList: TList;
  OutRepList: TList;
  MigrationEvent: PMigration;
  RepOutsidePop: POutRep;
  mig_file_out, migS_file_out, Orep_file_out: TextFile;

  {Lynx - Movement}
  dx: array[0..8] of integer = (0, 0, 1, 1, 1, 0, -1, -1, -1);
  dy: array[0..8] of integer = (0, 1, 1, 0, -1, -1, -1, 0, 1);
  step_probs: array of double;
  check_daily_movement: Array2Dinteger;
  check_daily_movement_i: integer;
  check_move_file_out: TextFile;
  steps, s, mem: integer;
  tohome: boolean;
  homeX, homeY: integer;

  {Lynx - Demography}
  n_cycles: integer;
  L_min_rep_age, L_min_rep_age_m, L_max_rep_age, L_max_age: integer;
  Tsize: integer;
  L_litter_size, L_litter_size_sd, L_rep_prob: real;
  L_surv_array: array of array of real;
  L_surv_disp_rho: real;
  L_alpha_steps: real;
  L_theta_d, L_theta_delta, L_delta_theta_long, L_delta_theta_f, L_L, L_N_d, L_beta, L_gamma: real;

  {Missceleneous // or however you spell that}
   a, i, b, taskID:integer;
   output_maps: string;


const
    days_in_month: array[1..12] of integer = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

    L_max_steps = 100;

implementation

finalization

 HabitatMapLynx := nil;
 BreedingHabitatMap := nil;
 PopsMap := nil;

 for a := 0 to LynxPopulation.Count - 1 do
   begin
   Dispose(PLynx(LynxPopulation[a]));
   end;
 LynxPopulation.Clear;
end.

