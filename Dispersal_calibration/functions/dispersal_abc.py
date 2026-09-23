"""
ABC-SMC calibration of the lynx dispersal parameters.

Runs Program/Executables/dispersal_calibration for sampled parameter sets and
compares where the simulated individuals end up after one day of dispersal with
the observed GPS end points.

Called by Dispersal_calibration/Dispersal_calibration_pipeline.R, run from the
repository root.
"""

import argparse
import subprocess
import tempfile
from os import path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyabc
from pyabc.transition import AggregatedTransition, DiscreteJumpTransition, MultivariateNormalTransition

parser = argparse.ArgumentParser()
parser.add_argument("--executable", required=True)
parser.add_argument("--settings", required=True)
parser.add_argument("--observed", required=True)
parser.add_argument("--output-dir", required=True)
parser.add_argument("--n-repeats", type=int, required=True)
parser.add_argument("--population-size", type=int, default=25)
parser.add_argument("--max-populations", type=int, default=3)
parser.add_argument("--min-epsilon", type=float, default=1)
parser.add_argument("--min-acceptance-rate", type=float, default=0.2)
args = parser.parse_args()

pyabc.settings.set_figure_params("pyabc")

all_params = ["L_alpha_steps", "L_theta_d", "L_delta_theta_long", "L_delta_theta_f",
              "L_L", "L_N_d", "L_beta", "L_gamma"]

# Observed steps: one row per start location, in the same order as the starting file
obs_data = pd.read_csv(args.observed, skipinitialspace=True)
obs_end = obs_data[["col1", "row1"]].to_numpy()
travelled = np.linalg.norm(obs_end - obs_data[["col0", "row0"]].to_numpy(), axis=1)
travelled[travelled == 0] = 0.01

# The model writes n_repeats rows per start location, one after the other
obs_end = np.repeat(obs_end, args.n_repeats, axis=0)
travelled = np.repeat(travelled, args.n_repeats)


# -----------------------------------------------------------------------------
# Model and distance
# -----------------------------------------------------------------------------

def model(parameters):
    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [args.executable, args.settings, tmpdir] + [str(parameters[p]) for p in all_params]
        subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        sim_data = pd.read_csv(path.join(tmpdir, "dispersal_results.csv"),
                               skipinitialspace=True)[["end_col", "end_row"]]
    return {"sim_data": sim_data}


def distance(sim_data, _):
    # Distance between simulated and observed end point, relative to the
    # observed distance travelled, averaged over all individuals
    sim_end = sim_data["sim_data"].to_numpy()[:len(obs_end)]
    accuracy = np.linalg.norm(sim_end - obs_end[:len(sim_end)], axis=1)

    with np.errstate(invalid="ignore", divide="ignore"):
        rel_accuracy = accuracy / travelled[:len(sim_end)]

    return float(np.nan_to_num(rel_accuracy.mean(), nan=0.0, posinf=1e6, neginf=1e6))


# -----------------------------------------------------------------------------
# Priors and transitions
# -----------------------------------------------------------------------------

domain_L = np.arange(4, 11)
domain_Nd = np.arange(3, 9)

prior = pyabc.Distribution(
    L_alpha_steps=pyabc.RV("uniform", 0, 0.1),
    L_theta_d=pyabc.RV("uniform", 0.0, 1),
    L_delta_theta_long=pyabc.RV("uniform", 0.0, 1),
    L_delta_theta_f=pyabc.RV("uniform", 0.0, 1),
    L_L=pyabc.RV("rv_discrete", values=(domain_L, np.ones_like(domain_L) / len(domain_L))),
    L_N_d=pyabc.RV("rv_discrete", values=(domain_Nd, np.ones_like(domain_Nd) / len(domain_Nd))),
    L_beta=pyabc.RV("uniform", 0.0, 1),
    L_gamma=pyabc.RV("uniform", 0.001, 1))

transition = AggregatedTransition(mapping={
    "L_alpha_steps": MultivariateNormalTransition(),
    "L_theta_d": MultivariateNormalTransition(),
    "L_delta_theta_long": MultivariateNormalTransition(),
    "L_delta_theta_f": MultivariateNormalTransition(),
    "L_L": DiscreteJumpTransition(domain=domain_L, p_stay=0.5),
    "L_N_d": DiscreteJumpTransition(domain=domain_Nd, p_stay=0.5),
    "L_beta": MultivariateNormalTransition(),
    "L_gamma": MultivariateNormalTransition()})

# -----------------------------------------------------------------------------
# Run ABC
# -----------------------------------------------------------------------------

abc = pyabc.ABCSMC(model, prior, distance, population_size=args.population_size,
                   transitions=transition, sampler=pyabc.sampler.SingleCoreSampler())
abc.new("sqlite:///" + path.abspath(path.join(args.output_dir, "lynx_dispersal_abc.db")))

history = abc.run(minimum_epsilon=args.min_epsilon, max_nr_populations=args.max_populations,
                  min_acceptance_rate=args.min_acceptance_rate)

# -----------------------------------------------------------------------------
# Parameter estimates (weighted mean and sd of the last population)
# -----------------------------------------------------------------------------

df_final, w_final = history.get_distribution(m=0, t=history.max_t)

estimates = {}
for param in all_params:
    weighted_mean = np.average(df_final[param], weights=w_final)
    weighted_std = np.sqrt(np.average((df_final[param] - weighted_mean) ** 2, weights=w_final))
    estimates[param] = {"weighted_mean": weighted_mean, "weighted_std": weighted_std}
    print(f"{param}: {weighted_mean:.6f}")

estimates_df = pd.DataFrame.from_dict(estimates, orient="index")
estimates_df.index.name = "parameter"
estimates_df.to_csv(path.join(args.output_dir, "Lynx_dispersal_params_estimated_weighted_mean.csv"))

# -----------------------------------------------------------------------------
# Plots
# -----------------------------------------------------------------------------

param_ranges = {"L_alpha_steps": (0, 0.1), "L_theta_d": (0.0, 1.0),
                "L_delta_theta_long": (0.0, 1.0), "L_delta_theta_f": (0.0, 1.0),
                "L_L": (1, 12), "L_N_d": (1, 12),
                "L_beta": (0.0, 1.0), "L_gamma": (0.001, 1.0)}

fig, axes = plt.subplots(2, 4, figsize=(16, 8))
for i, (param, ax) in enumerate(zip(all_params, axes.flatten())):
    for t in range(history.max_t + 1):
        df, w = history.get_distribution(m=0, t=t)
        xmin, xmax = param_ranges[param]
        pyabc.visualization.plot_kde_1d(df, w, xmin=xmin, xmax=xmax, x=param,
                                        xname=param.replace("L_", ""), ax=ax,
                                        label=f"t={t}" if i == 0 else "")
    ax.set_title(param.replace("L_", ""))
    if i == 0:
        ax.legend()
plt.tight_layout()
plt.savefig(path.join(args.output_dir, "Lynx_dispersal_abc_parameter_post.png"))

fig, arr_ax = plt.subplots(1, 3, figsize=(12, 4))
pyabc.visualization.plot_sample_numbers(history, ax=arr_ax[0])
pyabc.visualization.plot_epsilons(history, ax=arr_ax[1])
pyabc.visualization.plot_effective_sample_sizes(history, ax=arr_ax[2])
fig.tight_layout()
plt.savefig(path.join(args.output_dir, "Lynx_dispersal_abc_diagnostics.png"))
