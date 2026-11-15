# Loaded at the top of every SLURM job:  source /scratch/nca-course/toscas/setup/env.sh
module load uv/0.12.7
module load cuda/13.2
export NCA=/scratch/nca-course/toscas        # where computations run
export OUT=/projects/nca-course/toscas       # where study outputs are kept
export UV_CACHE_DIR=$NCA/.uv-cache
export UV_PYTHON_INSTALL_DIR=$NCA/.uv-python
export APPTAINER_CACHEDIR=$NCA/.apptainer
export APPTAINER_TMPDIR=$NCA/.apptainer-tmp
export HF_HOME=$NCA/.cache/huggingface
export HF_HUB_CACHE=$HF_HOME/hub
export HF_DATASETS_CACHE=$HF_HOME/datasets
mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$HF_HOME" "$NCA/logs"
if [ -f "$NCA/.venv/bin/activate" ]; then source "$NCA/.venv/bin/activate"; fi
if [ -f "$HOME/.nca_openai" ]; then source "$HOME/.nca_openai"; fi
