# preproc-fmri

Bash-based fMRI preprocessing pipelines (HeuDiConv, fMRIPrep) with shared libraries for config loading, queue execution, and status tracking.

## Repo layout

- `pipelines/`: pipeline entry scripts (currently `heudiconv`, `fmriprep`)
- `lib/`: shared Bash libraries (`bootstrap`, `status`, `queue`, `container`, `selected`, `common`)
- `config/`: configuration files (`project.env` + per-pipeline `*.env`)
- `stage/`, `bids/`, `derivatives/`, `work/`, `logs/`: runtime data directories (created as needed)

## Quick start

1. Configure your environment
   - `config/project.env` (e.g., `CONTAINERS_ROOT`, `N_JOBS_DEFAULT`)
   - `config/heudiconv.env`, `config/fmriprep.env` (container `.sif` paths, resources)

2. Build manifests
   - HeuDiConv:
     - `bash pipelines/heudiconv/10_make_manifest.sh`
   - fMRIPrep:
     - `bash pipelines/fmriprep/10_make_manifest.sh`

3. Run queues
   - HeuDiConv:
     - `bash pipelines/heudiconv/20_run_queue.sh pending|failed|all [FORCE]`
   - fMRIPrep:
     - `bash pipelines/fmriprep/20_run_queue.sh pending|failed|all [FORCE]`

## Conventions

- Status markers (`DONE`/`FAILED`/`RUNNING`/`LOCK`) make runs idempotent: completed jobs are skipped; failures can be rerun safely.
- `pending` excludes failed jobs by default; rerun failures via `failed` or `90_run_failed.sh`.
- Script naming under `pipelines/<pipeline>/`:
  - `NN_*.sh` (e.g., `05_...`, `10_...`, `20_...`, `90_...`): ordered pipeline steps
  - `run_one.sh`, `run_selected.sh`: helper entrypoints for targeted runs
