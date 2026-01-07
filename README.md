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
     ```bash
     bash pipelines/heudiconv/20_run_queue.sh [mode] [FORCE]
     # defaults: mode=$QUEUE_MODE_DEFAULT, FORCE=0
     ```

   - fMRIPrep:
     ```bash
     bash pipelines/fmriprep/20_run_queue.sh [mode] [FORCE]
     # defaults: mode=$QUEUE_MODE_DEFAULT, FORCE=0
     ```

Notes:

- `mode`: `pending` | `failed` | `all`
- `QUEUE_MODE_DEFAULT`: defined in `config/project.env` (default: `pending`)
- `FORCE`: `1` = force rerun (even if marked `DONE`), `0` = normal idempotent behavior

## Recommended: run via tmux (GNU parallel)

These pipelines can use GNU `parallel` for concurrent jobs. To avoid disconnects (SSH/terminal closing) interrupting a long run, we recommend running queues inside `tmux`.

Example workflow:

1. Start a session
   - `tmux new -s preproc`

2. Run a queue inside tmux
   - `bash pipelines/fmriprep/20_run_queue.sh`

3. Detach / re-attach
   - Detach: press `Ctrl-b`, then `d`
   - Re-attach: `tmux attach -t preproc`

### Adjust max jobs quickly (MAX_JOBS)

The maximum concurrent jobs is controlled by `MAX_JOBS` (defined in `config/heudiconv.env` and `config/fmriprep.env`).

By default, `MAX_JOBS` inherits from `N_JOBS_DEFAULT` in `config/project.env` (unless you override `MAX_JOBS` explicitly).

For quick changes without editing config, override it per run:

```bash
MAX_JOBS=8 \
  bash pipelines/fmriprep/20_run_queue.sh

MAX_JOBS=2 \
  bash pipelines/heudiconv/20_run_queue.sh
```

Note: `MAX_JOBS` is read when the queue starts. If you want to change it, stop the current queue and re-run with a new value.

## Conventions

- Status markers (`DONE`/`FAILED`/`RUNNING`/`LOCK`) make runs idempotent: completed jobs are skipped; failures can be rerun safely.
- `pending` excludes failed jobs by default; rerun failures via `failed` or `90_run_failed.sh`.
- Script naming under `pipelines/<pipeline>/`:
  - `NN_*.sh` (e.g., `05_...`, `10_...`, `20_...`, `90_...`): ordered pipeline steps
  - `run_one.sh`, `run_selected.sh`: helper entrypoints for targeted runs
