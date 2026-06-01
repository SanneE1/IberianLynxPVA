{vs. 1.0  1/9/2015
Revilla, E. (in press). Individual and agent based models in population ecology and conservation biology.
In: Population Ecology in Practice: Underused, Misused, and Abused Methods.
Eds Murray DL, Sandercock B. John Wiley & Sons Ltd. ISBN/ISSN: 9780470674130}

program lynx_model;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, tachartlazaruspkg, lynx_population_dynamics;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Initialize;
  Application.CreateForm(Tspatial_Form, spatial_Form);
  Application.Run;
end.

