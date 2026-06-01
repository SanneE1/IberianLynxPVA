{Place to define all the lynx objects and variables}
unit lynx_define_units;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type           {here you declare the data structure for you individuals}
  Array2Dinteger = array of array of integer;
  Array3Dinteger = array of array of array of integer;

  PAgent = ^Agent;

  Agent = record
    sex: string[1];
    Age: byte;         // In years
    Status: shortint;  // 0=pre-dispersal cubs and subadults, 1=dispersing individuals, 2=early settled adults, 3 = fully settled adults

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



  PMigration = ^Migration;
  Migration = record

    simulation: integer;
    year: integer;
    // Add ID here (like Chiara will be using) to track if single individuals move through multiple populations
    // and/or to keep track to see if they're actually going to breed in population
    sex: string[1];
    age: byte;
    natal_pop: integer;
    old_pop: integer;
    new_pop: integer;

  end;


var               {here you declare global variables}

  Population: TList;
  Individual: PAgent;

  MigrationList: TList;
  SettledList: TList;
  MigrationEvent: PMigration;

  max_years: integer;
  AlphaR: real;
  BetaR: real;
  surv_prob: real;
  AlphaS: real;
  BetaS: real;
  sett_prob: real;
  avg_steps: integer;
  AlphaD: real;
  BetaD: real;
  sink: real;
  populationsize: longint;
  n_sim: integer;
  n_extint: integer;
  sum_distance_X: integer;
  sum_distance_Y: integer;
  current_sim: integer;
  max_pop_size: integer;
  step_probs: array of double;
  pop_size: array[1..100] of integer;
  sum_pop_size: array[1..100] of integer;
  each_pop_sizes: array of array of integer;
  n_sim_no_ext: array[1..100] of integer;
  to_file_out, mig_file_out, migS_file_out: TextFile;
  filename: Text;
  HabitatMap: Array2Dinteger;
  BreedingHabitatMap: Array2Dinteger;
  PopsMap: Array2Dinteger;
  MalesMap: Array3Dinteger;
  FemalesMap: Array3Dinteger;
  ConnectionMap: Array3Dinteger;
  Mapdimx, Mapdimy: integer;
  mapname, mapBHname, mapPops, paramname: string;
  dx: array[0..8] of integer = (0, 0, 1, 1, 1, 0, -1, -1, -1);
  dy: array[0..8] of integer = (0, 1, 1, 0, -1, -1, -1, 0, 1);
  xp, yp: integer;
  tempX, tempY: integer;
  homeX, homeY, startpoint_X, startpoint_Y, steps, s, new_dir, mem: integer;
  tohome: boolean;
  current_year: integer;
  n_cycles: integer;
  pop_status_array: Array2Dinteger;
  check_daily_movement: Array2Dinteger;
  check_daily_movement_i: integer;
  check_move_file_out: TextFile;

  {Vital rate variables}
  min_rep_age, min_rep_age_m, max_rep_age, max_age: integer;
  Tsize: integer;
  litter_size, litter_size_sd, rep_prob: real;
  surv_cub, surv_sub, surv_resident, surv_disperse, surv_disp_rho, surv_old: real;
  alpha_steps: real;
  theta_d, theta_delta, delta_theta_long, delta_theta_f, L, N_d, beta, gamma: real;

const             {here you declare constants}

  file_name = 'output_data/PopulationSizes.txt';

  max_steps = 100;

implementation

end.

