{Place to define all the lynx objects and variables}
unit lynx_define_unit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type           {here you declare the data structure for you individuals}
  Array2Dbyte = array of array of byte;
  Array3Dbyte = array of array of array of byte;

  PAgent = ^Agent;

  Agent = record
    sex: string[1];
    Age: byte;         // In years
    Status: shortint;  // 0=pre-dispersal cubs and subadults, 1=dispersing individuals, 2=early settled adults, 3 = fully settled adults

    Coor_X: byte;
    Coor_Y: byte;

    TerritoryX: array of integer;
    TerritoryY: array of integer;

    DailySteps: byte;
    DailyStepsOpen: byte;
    mov_mem: byte;
    return_home: boolean;  // not to be confused with Territory. This is for when individuals go on an excursion
    // into Open habitat, for them to return to the last known Dispersal habitat they've visited
    homeX: byte;
    homeY: byte;

  end;



var               {here you declare global variables}

  Population: TList;
  Individual: PAgent;
  n_ini: integer;
  max_years: integer;
  rep_prob: real;
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
  n_sim_no_ext: array[1..100] of integer;
  to_file_out: TextFile;
  filename: Text;
  HabitatMap: Array2Dbyte;
  MalesMap: Array3Dbyte;
  FemalesMap: Array3Dbyte;
  Mapdimx, Mapdimy: integer;
  mapname, paramname: string;
  dx: array[0..8] of integer = (0, 0, 1, 1, 1, 0, -1, -1, -1);
  dy: array[0..8] of integer = (0, 1, 1, 0, -1, -1, -1, 0, 1);
  xp, yp: integer;
  tempX, tempY: integer;
  homeX, homeY, steps, s, new_dir, mem: integer;
  tohome: boolean;

  {Vital rate variables}
  min_rep_age, min_rep_age_m, max_rep_age, max_age: integer;
  Tsize: integer;
  litter_size, litter_size_sd, rep_prob_oNP, rep_prob_iNP: real;
  surv_cub_iNP, surv_cub_oNP, surv_sub_iNP, surv_sub_oNP, surv_resident_iNP, surv_resident_oNP, surv_disperse_iNP, surv_disperse_oNP, surv_disp_rho, surv_old_iNP, surv_old_oNP: real;
  alpha_steps: real;
  theta_d, theta_delta, delta_theta_long, delta_theta_f, L, N_d, beta, gamma: real;

const             {here you declare constants}

  file_name = 'output.txt';

  max_steps = 100;

implementation

end.

