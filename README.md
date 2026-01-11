# preproc-fmri

A lightweight, Bash-first fMRI preprocessing framework that emphasizes **readability**, **reusability**, and **idempotent execution**.
The repository currently provides the following pipelines:

- **heudiconv**: DICOM → BIDS conversion (via container)
- **fMRIPrep**: BIDS → preprocessed derivatives (via container)
- **mriqc**: BIDS → MRIQC quality metrics + HTML reports (via container)

## Key design

1. **Project bootstrap is uniform**
   All pipeline scripts begin with `project_load <pipeline>` which:
   - locates `PROJECT_ROOT` (by finding `config/project.env`),
   - sources `config/project.env` and `config/<pipeline>.env`,
   - defines standard directories: `BIDS_ROOT`, `DERIV_ROOT`, `WORK_ROOT`, `LOG_ROOT`, etc.

2. **Idempotent jobs with explicit state markers**
   Each run is tracked via marker files under:

   - `logs/<pipeline>/state/done/`
   - `logs/<pipeline>/state/failed/`
   - `logs/<pipeline>/state/running/`
   - `logs/<pipeline>/state/lock/`

   This enables stable *pending/failed/all* queues and safe re-runs.

3. **Queue execution is backend-agnostic**
   - If **GNU parallel** is available, it will be used.
   - Otherwise, a minimal background-worker pool is used.

---

## Directory layout

```text
.
├─ config/                 # project-wide and pipeline-specific env files
├─ lib/                    # reusable bash library (project/container/state/queue)
├─ pipelines/              # entry scripts for each pipeline
├─ tools/                  # small helper tools (e.g., manifest generation)
├─ bids/                   # BIDS output (from heudiconv)
├─ derivatives/            # derivatives outputs (fMRIPrep/MRIQC)
├─ stage/                  # staging (heudiconv manifest, DICOM symlink tree)
├─ work/                   # temporary work dirs, participants lists, db, etc.
└─ logs/                   # pipeline logs + state markers
```

Generated directories (`logs/`, `work/`, `stage/`, `bids/`, `derivatives/`) are safe to gitignore.

---

## Requirements

### System

- Linux (recommended). macOS is feasible if your container runtime works.
- `bash` (>= 4 recommended)
- `python3` (standard library is sufficient for `tools/heudiconv_manifest.py`)

### Container runtime

- Singularity/Apptainer (either is acceptable)
  - The runtime is auto-detected; you may override via `SING_BIN`.

### Containers

You need `.sif` images for:

- heudiconv (e.g., `heudiconv-1.3.4.sif`)
- fMRIPrep (e.g., `fmriprep-25.2.3.sif`)
- MRIQC (e.g., `mriqc-24.0.2.sif`)

Store them under `CONTAINERS_ROOT` (default: `${HOME}/containers`) or override in config.

### Optional

- **GNU parallel**: recommended for robust job scheduling and richer `--joblog`.

---

## Installation

```bash
git clone https://github.com/EF-STUDY-FENG/preproc-fmri
cd preproc-fmri
```

1. Place container images:

    ```bash
    mkdir -p "${HOME}/containers"
    # Put *.sif here, or update CONTAINERS_ROOT in config/project.env
    ```

1. Confirm scripts are executable:

    ```bash
    chmod +x pipelines/*/*.sh
    ```

---

## Configuration

All configuration is done through env files:

- `config/project.env` (project-wide defaults)
- `config/heudiconv.env`
- `config/fmriprep.env`
- `config/mriqc.env`

You can edit these files directly, or override variables inline:

```bash
MAX_JOBS=8 MEM_MB=64000 bash pipelines/fmriprep/queue.sh pending 0
```

### Minimal variables you should verify

#### Project

- `CONTAINERS_ROOT` and `SING_BIN`
- `BIDS_ROOT`, `DERIV_ROOT`, `WORK_ROOT`, `LOG_ROOT`, `STAGE_ROOT` (optional overrides)

#### HeuDiConv

- `SRC_ROOT`: raw DICOM root
- `SIF`: heudiconv image path
- `HEURISTIC`: heuristic path
- `DICOM_TEMPLATE`: template used by heudiconv

#### fMRIPrep

- `FMRIPREP_SIF`: fMRIPrep image path
- `FS_LICENSE`: FreeSurfer license file path (required by fMRIPrep)
- resource knobs: `NTHREADS`, `OMP_NTHREADS`, `MEM_MB`, `MAX_JOBS`
- `OUTPUT_SPACES`, `CIFTI_OUTPUT`, `SKIP_BIDS_VALIDATION` (as needed)

---

## Quick start

### 1. heudiconv

#### Step A: Build staging + manifest

```bash
bash pipelines/heudiconv/manifest.sh
```

Artifacts:

- `stage/dicom/` (symlink tree)
- `stage/manifest.tsv` (queue source)
- `stage/duplicates.tsv` (audit list if duplicates exist)
- `stage/overrides.tsv` (optional manual override file)

#### Step B: Run conversion

```bash
# MODE: pending | failed | all
# FORCE: 0 (default) or 1 (ignore DONE markers)
bash pipelines/heudiconv/queue.sh pending 0
```

#### Run a single job

```bash
bash pipelines/heudiconv/run_one.sh 0 <SUBJECT> <SESSION>
# Example:
bash pipelines/heudiconv/run_one.sh 0 001 REST
```

#### Re-run selected pairs

```bash
bash pipelines/heudiconv/run_selected.sh 0 001 REST 001 TASK 002 REST
```

---

### 2. fMRIPrep

#### Optional: build PyBIDS DB

```bash
bash pipelines/fmriprep/bids_db.sh
```

#### Step A: Build fMRIPrep participants list

```bash
bash pipelines/fmriprep/manifest.sh
# outputs: work/fmriprep_participants.tsv (one label per line)
```

#### Step B: Run fMRIPrep

```bash
bash pipelines/fmriprep/queue.sh pending 0
```

#### Run a single subject

```bash
bash pipelines/fmriprep/run_one.sh 0 <SUBJECT>
# Example:
bash pipelines/fmriprep/run_one.sh 0 001
```

---

### 3. MRIQC

#### Step A: Build MRIQC participants list

```bash
bash pipelines/mriqc/manifest.sh
# outputs: work/mriqc/participants.tsv (one label per line)
```

#### Step B: Run MRIQC (participant level)

```bash
bash pipelines/mriqc/queue.sh pending 0
```

#### Optional: Run group-level report

```bash
bash pipelines/mriqc/run_group.sh
```

---

## Execution modes

Queue scripts accept:

- **MODE**
  - `pending`: run only jobs with no DONE/FAILED markers
  - `failed`: run only jobs previously marked FAILED
  - `all`: run everything (still respects locks/running markers)

- **FORCE**
  - `0`: default; skip DONE jobs
  - `1`: ignore DONE markers and rerun

Example:

```bash
bash pipelines/fmriprep/queue.sh failed 1
```

Parallelism:

- `MAX_JOBS` controls concurrency (per pipeline; defaults to `N_JOBS_DEFAULT` in `config/project.env`).
- If `parallel` is installed, it will be used automatically.

---

## Outputs and provenance

- Logs:
  - `logs/<pipeline>/...`
  - per-job logs are stored under `logs/<pipeline>/jobs/`
- State markers:
  - `logs/<pipeline>/state/{done,failed,running,lock}/`
- BIDS:
  - `bids/` (default)
- Derivatives:
  - `derivatives/` (default)
- Work:
  - `work/` (default; may be cleaned upon success depending on pipeline config)

This design allows reproducible re-execution:

- delete selected marker files to re-run a subset, or
- use `FORCE=1` for programmatic reruns.

---

## Troubleshooting

### Container not found / runtime mismatch

- Check `CONTAINERS_ROOT` and `SIF`/`FMRIPREP_SIF`/`MRIQC_SIF`.
- Check runtime:
  - auto-detection prefers Apptainer if available;
  - you may override by setting `SING_BIN=apptainer` or `SING_BIN=singularity`.

### heudiconv duplicates / unexpected session mapping

- Inspect `stage/duplicates.tsv`.
- Use `stage/overrides.tsv` to pin specific DICOM directories.

### fMRIPrep resource errors (OOM / killed)

- Increase `MEM_MB`, reduce `NTHREADS`, or lower `MAX_JOBS`.
- Verify bind mounts point to fast storage (especially `WORK_ROOT`).

### “Nothing to do”

- You are likely in `pending` mode with DONE/FAILED markers already present.
- Use `failed` mode or `FORCE=1`.

---

## Contributing

- Prefer minimal abstractions and keep functions at a readable size.
- Follow “Bash strict mode” (`set -euo pipefail`) in entry scripts.
- Add pipeline-specific behavior only inside `pipelines/<pipeline>/`.

---

## License

Specify your license here (e.g., MIT, Apache-2.0, or internal).

---

## Acknowledgements

This project builds upon the community tooling ecosystem:

- HeuDiConv
- fMRIPrep
- MRIQC
- BIDS / PyBIDS
- Singularity/Apptainer
- GNU parallel *(optional)*

For official documentation and citations, please refer to the upstream projects. For example:

```text
https://fmriprep.org/
