from os import path

import tempfile
import subprocess

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from scipy.spatial.distance import cdist

import pyabc
from pyabc.transition import DiscreteJumpTransition, AggregatedTransition, MultivariateNormalTransition

pyabc.settings.set_figure_params('pyabc')  # for beautified plots

# parameters = {
#     "L_alpha_steps": 0.01,
#     "L_theta_d": 0.5,
#     "L_delta_theta_long": 0.5,
#     "L_delta_theta_f": 0.5,
#     "L_L": 7,
#     "L_N_d": 6,
#     "L_beta": 0.01,
#     "L_gamma": 0.01}

# tmpdir = "test_output"


def model(parameters): 
    
    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [
            #"./dispersal_calibration",
            "./Program/Executables/dispersal_calibration.exe",
            "data/model_input/dispersal_calibration_settings.txt", 
            tmpdir, 
            str(parameters['L_alpha_steps']), 
            str(parameters['L_theta_d']), 
            str(parameters['L_delta_theta_long']), 
            str(parameters['L_delta_theta_f']), 
            str(parameters['L_L']), 
            str(parameters['L_N_d']), 
            str(parameters['L_beta']), 
            str(parameters['L_gamma'])
            ] 
        
        subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        sim_data = pd.read_csv(path.join(tmpdir, "dispersal_results.csv"),
                               skipinitialspace=True)[["end_col", "end_row"]]

    
    return {"sim_data": sim_data}


def distance(sim_data, _):
    
    obs_data = pd.read_csv(path.join("results", "calibration_dispersal_observed.csv"), skipinitialspace=True)[['col0', 'row0', 'col1', 'row1']]
    
    travelled = cdist(obs_data[['col0', 'row0']], obs_data[['col1', 'row1']], metric='euclidean')
    travelled = np.diag(travelled).copy()
    travelled[travelled == 0] = 0.01
    
    accuracy = cdist(sim_data['sim_data'], obs_data[['col1', 'row1']], metric='euclidean')
    accuracy = np.diag(accuracy)
    
    with np.errstate(invalid="ignore", divide="ignore"): 
        rel_accuracy = accuracy / travelled

    
    return(float(np.nan_to_num(rel_accuracy.mean(), nan=0.0, posinf=1e6, neginf=1e6)))
    

domain_L = np.arange(4,11)
domain_Nd = np.arange(3,9)

transition = AggregatedTransition(
    mapping = {
        "L_alpha_steps": MultivariateNormalTransition(),
        "L_theta_d": MultivariateNormalTransition(),
        "L_delta_theta_long": MultivariateNormalTransition(),
        "L_delta_theta_f": MultivariateNormalTransition(),
        "L_L": DiscreteJumpTransition(domain=domain_L, p_stay=0.5),
        "L_N_d": DiscreteJumpTransition(domain=domain_Nd, p_stay=0.5),
        "L_beta": MultivariateNormalTransition(),
        "L_gamma": MultivariateNormalTransition()
    })

    
prior = pyabc.Distribution(L_alpha_steps = pyabc.RV("uniform", 0, 0.1),
                           L_theta_d = pyabc.RV("uniform", 0.0, 1),
                           L_delta_theta_long = pyabc.RV("uniform", 0.0, 1), 
                           L_delta_theta_f = pyabc.RV("uniform", 0.0, 1),   
                           L_L = pyabc.RV("rv_discrete", values=(domain_L, np.ones_like(domain_L) / len(domain_L))),
                           L_N_d = pyabc.RV("rv_discrete", values=(domain_Nd, np.ones_like(domain_Nd) / len(domain_Nd))),
                           L_beta = pyabc.RV("uniform", 0.0, 1),             
                           L_gamma = pyabc.RV("uniform", 0.001, 1)
                           )


# Start ABC runs
sampler = pyabc.sampler.SingleCoreSampler()

abc = pyabc.ABCSMC(model, prior, distance, population_size=25, sampler=sampler)    
    
# Initialize database for results
db_path = path.join("results", "lynx_dispersal_abc.db")
abc.new("sqlite:///" + db_path)

# Run ABC
history = abc.run(minimum_epsilon=1, max_nr_populations=3, min_acceptance_rate=0.2)


# Save parameter estimates
df_final, w_final = history.get_distribution(m=0, t=history.max_t)

best_estimates = {}
all_params = ['L_alpha_steps', 'L_theta_d', 'L_delta_theta_long', 'L_delta_theta_f', 
              'L_L', 'L_N_d', 'L_beta', 'L_gamma']

for param in all_params:
    if param in df_final.columns:
        # Calculate various statistics
        weighted_mean = np.average(df_final[param], weights=w_final)
        weighted_std = np.sqrt(np.average((df_final[param] - weighted_mean)**2, weights=w_final))
        
        best_estimates[param] = {
            'weighted_mean': weighted_mean,
            'weighted_std': weighted_std
            }

# Convert to DataFrame and save
best_estimates_df = pd.DataFrame.from_dict(best_estimates, orient='index')
best_estimates_df.index.name = 'parameter'
best_estimates_df.to_csv(path.join('results', 'Lynx_dispersal_params_estimated_weighted_mean.csv'))



# Plot some of the results ------------------------------------------------------------------
fig, axes = plt.subplots(2, 4, figsize=(16, 8))
axes = axes.flatten()

all_params = ['L_alpha_steps', 'L_theta_d', 'L_delta_theta_long', 'L_delta_theta_f', 
              'L_L', 'L_N_d', 'L_beta', 'L_gamma']
all_param_ranges = {
    'L_alpha_steps': (0, 0.1),
    'L_theta_d': (0.0, 1.0),
    'L_delta_theta_long': (0.0, 1.0),
    'L_delta_theta_f': (0.0, 1.0),
    'L_L': (1, 12),
    'L_N_d': (1, 12),
    'L_beta': (0.0, 1.0),
    'L_gamma': (0.001, 1.0)
}

for i, param in enumerate(all_params):
    ax = axes[i]
    for t in range(history.max_t + 1):
        df, w = history.get_distribution(m=0, t=t)
        if param in df.columns:
            xmin, xmax = all_param_ranges[param]
            pyabc.visualization.plot_kde_1d(
                df,
                w,
                xmin=xmin,
                xmax=xmax,
                x=param,
                xname=param.replace('L_', ''),
                ax=ax,
                label=f"t={t}" if i == 0 else "",  # Only show legend on first plot
            )
    ax.set_title(param.replace('L_', ''))
    if i == 0:  # Only show legend on first subplot
        ax.legend()

plt.tight_layout()
plt.savefig(path.join('results','Lynx_dispersal_abc_parameter_post.png'))

## ABC diagnostics
fig, arr_ax = plt.subplots(1, 3, figsize=(12, 4))

pyabc.visualization.plot_sample_numbers(history, ax=arr_ax[0])
pyabc.visualization.plot_epsilons(history, ax=arr_ax[1])
pyabc.visualization.plot_effective_sample_sizes(history, ax=arr_ax[2])

fig.tight_layout()
plt.savefig(path.join('results','Lynx_dispersal_abc_diagnostics.png'))


df_final, w_final = history.get_distribution(m=0, t=history.max_t)
print("\nFinal parameter estimates (weighted means):")
for param in all_params:
    if param in df_final.columns:
        weighted_mean = np.average(df_final[param], weights=w_final)
        print(f"{param}: {weighted_mean:.6f}")


