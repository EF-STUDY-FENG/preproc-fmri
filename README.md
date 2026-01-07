# preproc-fmri

This repository provides Bash-based fMRI preprocessing pipelines (HeuDiConv, fMRIPrep) plus reusable libraries for config loading, queue execution, and status tracking.

## Layout

- pipelines/: pipeline entry scripts (heudiconv, fmriprep; extensible to mriqc, xcp_d, etc.)
- lib/: shared Bash libraries (bootstrap/status/queue/container/selected/common)
- config/: configuration files (project.env + per-pipeline *.env)
- stage/, bids/, derivatives/, work/, logs/: runtime data directories (created as needed)

## Quick start

1. Edit configs for your machine:

   - config/project.env (e.g., CONTAINERS_ROOT, N_JOBS_DEFAULT)
   - config/heudiconv.env, config/fmriprep.env (container .sif paths, resources)

1. Build manifests:

   - HeuDiConv: `bash pipelines/heudiconv/10_make_manifest.sh`
   - fMRIPrep: `bash pipelines/fmriprep/10_make_manifest.sh`

1. Run queues:

   - `bash pipelines/heudiconv/20_run_queue.sh pending|failed|all [FORCE]`
   - `bash pipelines/fmriprep/20_run_queue.sh pending|failed|all [FORCE]`

## Conventions

- Status markers (DONE/FAILED/RUNNING/LOCK) make runs idempotent: skip completed jobs and rerun failures safely.
- `pending` excludes failed jobs by default; rerun failures via `failed` or `90_run_failed.sh`.
- Script naming in `pipelines/<pipeline>/`: `NN_*.sh` (e.g., `05_...`, `10_...`, `20_...`, `90_...`) are ordered pipeline steps; non-numbered scripts (e.g., `run_one.sh`, `run_selected.sh`) are helper entrypoints for targeted runs.
