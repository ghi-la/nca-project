#!/bin/bash
#SBATCH --job-name=mini-swe-agent
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=2
#SBATCH --partition=gpu
#SBATCH --mem=12G
#SBATCH --time=3:50:00
#SBATCH --output=log-%j.out
#SBATCH --error=error-%j.err

module load uv/0.12.7
module load cuda/13.2

# Create your own scratch folder in the nca-course directory to avoid conflicts with other users
mkdir -p /scratch/nca-course/$USER

export UV_CACHE_DIR="/scratch/nca-course/$USER/.uv-cache"
export UV_PYTHON_INSTALL_DIR="/scratch/nca-course/$USER/.uv-python"
export APPTAINER_CACHEDIR="/scratch/nca-course/$USER/.apptainer"

export HF_HOME="/scratch/nca-course/$USER/.cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export HF_DATASETS_CACHE="$HF_HOME/datasets"

if [ ! -d .venv ]; then
    uv init --python 3.12
    uv venv .venv
fi
source .venv/bin/activate

# Setup mini-swe-agent and vLLM
git clone https://github.com/SWE-agent/mini-swe-agent.git
cd mini-swe-agent
git checkout bc85a45654e6348dcc6e4c5a40ad146ed0bb144d
uv pip install -e .
cd ..

uv pip install vllm==0.32.0

# Run mini-swe-agent evaluation script
bash eval.sh
