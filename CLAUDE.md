# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

WanGP (Wan2GP) — a Gradio web app that runs a large catalog of open-source generative models (video, image, audio/TTS) on low-VRAM consumer GPUs. Memory management is delegated to `mmgp` (`from mmgp import offload, profile_type, quant_router`), which is what makes 6 GB-VRAM operation possible; almost every model load goes through `offload.profile(...)` in `load_models()`.

## Fork context

This is a personal fork, not upstream.

- `origin` → `github.com/TerminatedProcess/Wan2GP` (push here)
- `upstream` → `github.com/deepbeepmeep/Wan2GP` (read-only)
- Work happens on branch **`mryan`**; `main` tracks upstream.
- Sync with the **global** fish function `gitupdate` (`~/.config/fish/functions/gitupdate.fish`): it ff-only's `main` to `upstream/main`, rebases `mryan` on top, and force-with-lease pushes. `.salias` deliberately does *not* define a local `gitupdate` — a local definition is sourced on dir-entry and would shadow the global one. Prefer it over hand-rolled merges.
- **`mryan` must stay rebase-able.** History was flattened on 2026-07-30: `mryan` is now `upstream/main` + one fork commit. Upstream *rewrites its own history* (same commit titles reappear under new hashes), so the old merge-based workflow accumulated orphaned DeepBeepMeep commits — 31 of them — which is what made a rebase impossible. Keep fork changes to a single small commit and never merge `upstream/main` into `mryan`.

Because upstream merges land regularly, keep local changes small and well-isolated — most files are upstream-owned.

## Environment & commands

Python 3.11 in `.venv`, activated by direnv (`.envrc`). Managed with `uv`.

```bash
python wgp.py                      # launch web UI (http://localhost:7860)
python wgp.py --i2v                # preselect a mode
python wgp.py --process q.zip --output-dir ./out   # headless queue processing
python wgp.py --process q.json --dry-run           # validate without generating
python wgp.py --mcp                # run as an MCP server (preferred over shared.mcp_server)
python wgp.py --ask-deepy          # interactive Deepy agent
python setup.py                    # cross-platform installer/updater (envs, torch, deps)
```

### Running as a managed service

Registered in the local service fleet as **`wan-gpt`** (see the `services-layout` skill):

- Unit: `~/.config/systemd/user/wan-gpt.service` — port 7860, **disabled** (manual start, like the other GPU-heavy stacks).
- PortHub lease: `"7860 wan-gpt"` in `~/.config/porthub/leases.sh`.
- Dashboard: member of the **Media Stack** group (`~/.config/porthub_service_dash/groups.json`) alongside ComfyUI/InvokeAI — http://localhost:8090.

```bash
systemctl --user start|stop|restart wan-gpt.service
journalctl --user -u wan-gpt.service -f
```

The unit carries `UnsetEnvironment=LD_LIBRARY_PATH` — the systemd user manager exports `/opt/cuda/lib64`, and direnv does not apply to units, so without it the service hits the cuBLAS failure described below. Verify the right library is live with:
`grep cublasLt /proc/$(systemctl --user show -p MainPID --value wan-gpt.service)/maps` — it must resolve inside `.venv`, not `/opt/cuda`.

`.salias` also defines `run` (`python wgp.py`), `stop` (pkill), `install` (uv pip install torch cu130 + requirements), and `linkfolders` (symlinks `ckpts/`, `loras*/`, `outputs/` to `/mnt/llm`).

Useful flags when debugging: `--verbose 2`, `--debug-gen-form` (Gradio form build timings; also `WANGP_DEBUG_UI=1`), `--test` (load model then exit), `--check-loras`, `--profile N` (mmgp profile override), `--config <dir>`, `--settings <dir>`.

**There is no test suite and no lint config.** The `shared/mps/test_*.py` files are ad-hoc Apple-Silicon smoke scripts, not pytest. `ruff` is installed in the venv but unconfigured. Verify changes by actually launching the app or running a headless `--process` job.

## Architecture

### `wgp.py` — the monolith

~13.5k lines, ~750 KB. It is simultaneously the entry point, the config/model registry, the generation orchestrator, and the entire Gradio UI. Do not try to read it top-to-bottom; navigate by `grep -n "^def name"`. Key landmarks:

- **Config bootstrap** (top ~2600 lines, runs at import): parses `wgp_config.json`, resolves profiles/output paths, installs Gradio monkey-patches (`gradio_queue_focus_patch`, `gradio_model_switch_patch`), discovers plugins.
- **Model registry**: `refresh_model_defs()` → `models_def` dict; `get_model_def()`, `get_base_model_type()`, `get_model_handler()`, `get_model_filename()`.
- **Queue/task layer**: `process_prompt_and_add_tasks()` → `add_video_task()` → `process_tasks()` (UI) / `process_tasks_cli()` (headless).
- **Generation**: `load_models()` and `generate_media()` (the ~1600-line core inference loop) plus `edit_media()` / `edit_audio()`.
- **UI**: `create_ui()` and `generate_media_tab()` (~2000 lines of Gradio wiring).

### Model system — three layers

1. **`family_handler`** (Python) — one static-method class per model family, listed in the `family_handlers` array near `wgp.py:2404` and imported by `map_family_handlers()`. Contract: `query_supported_types()`, `query_model_def()`, `query_family_infos()`, `query_family_maps()`, `query_model_files()`, `load_model()`, `update_default_settings()`, `fix_settings()`, `get_lora_dir()`, plus optional hooks (`validate_generative_settings`, `custom_preprocess`, `custom_prompt_preprocess`, `set_cache_parameters`, `get_custom_prompt_enhancer_instructions`). `models/z_image/z_image_handler.py` (~195 lines) is the smallest complete example.
2. **`defaults/*.json`** — one file per shipped model type; filename (minus `.json`) is the model type id. Contains a `model` subtree (`architecture`, `URLs`, `modules`, `description`) merged over default generation settings. **Never edit `defaults/`** — it is upstream-owned.
3. **`finetunes/*.json`** — user-owned overrides using the same schema. A file here with the same name as a `defaults/` file is merged property-by-property on top of it, which is the sanctioned way to change a built-in model's title, weights, or defaults. `profiles/` holds built-in LoRA/preset groups; `settings/` holds per-model saved UI settings.

`architecture` in the JSON names the *base model type*, which resolves to a handler via `model_types_handlers`. `models_eqv_map` (bidirectional) and `models_comp_map` (one-directional derived-type) govern settings compatibility when importing settings across models.

### Plugins

`plugins/` is a discovered package directory managed by `shared/utils/plugins.py` (`PluginManager`, `WAN2GPApplication`). Plugins subclass `WAN2GPPlugin` in `plugin.py` and declare metadata in `plugin_info.json` with `type` ∈ `app` / `extension` / `processor` / `model`. **Model plugins can inject their own `family_handlers`, `defaults/`, and `profiles/` roots** — see `discover_plugin_model_extensions()` and `model_handler_sources` in `wgp.py`. Full API in `docs/PLUGINS.md`; specialized handler contracts in `docs/SPATIAL_UPSAMPLERS.md`, `docs/TEMPORAL_UPSAMPLERS.md`, `docs/AUDIO_PROCESSORS.md`.

`plugins/*` is fetched and updated by the in-app Plugin Manager. Treat dirty state there as expected; do not clean or commit it.

### Programmatic access

- `shared/api.py` — in-process API: `from shared.api import init; session = init(...)`, then `session.list_model_metadata()`, `session.get_model_schema()`, `session.run_task(settings)`. Docs: `docs/API.md`.
- `shared/mcp_server.py` — MCP adapter exposing `wangp_list_models`, `wangp_get_model_schema`, `wangp_generate`, `wangp_get_job`, `wangp_cancel_job`.
- `wangp-agent/SKILL.md` — the agent-facing playbook for driving WanGP (discovery → settings → generate → poll). Read it before scripting generation.

### Supporting trees

`shared/` (attention backends, LoRA handling, resolutions, Gradio widgets/patches, Deepy offline agent, LLM engines, prompt enhancer), `preprocessing/` (pose, depth, flow, matting, diarization — control-input extraction), `postprocessing/` (RIFE, FlashVSR, MMAudio, SeedVC, film grain — output enhancement). Spatial/temporal upsamplers and audio processors are all registered through the same plugin-style handler registries.

## Environment traps (both cost a full debugging cycle — check these first)

**1. System CUDA shadows torch's bundled cuBLAS.** `/opt/cuda` (Arch `cuda` package) ships `libcublasLt.so.13 → 13.6.0.2`, but torch 2.10.0+cu130 is built against `nvidia-cublas 13.1.0.3` (vendored at `.venv/lib/python3.11/site-packages/nvidia/cu13/lib`). Torch's wheels use `DT_RUNPATH`, which loses to `LD_LIBRARY_PATH`, so a global `LD_LIBRARY_PATH=/opt/cuda/lib64` makes the 13.6 library win.

Symptom is deceptive: the model downloads and loads fine, mmgp builds its offload plan, then the *first denoise step* dies with `CUDA error: CUBLAS_STATUS_NOT_INITIALIZED ... cublasLtMatmulAlgoGetHeuristic`. Plain `a @ b` still works — only the cublasLt path (`nn.Linear`) breaks, so it looks like a model bug rather than an environment one. It is not OOM.

`.envrc` fixes it with `unset LD_LIBRARY_PATH`. **Editing `.envrc` re-blocks it — run `direnv allow` or the fix silently isn't applied.** To confirm which library is live: `ldconfig -p | grep cublas`. One-off workaround without direnv: `env -u LD_LIBRARY_PATH python wgp.py`.

**2. torchaudio must be pinned.** `torchaudio` unpinned resolves to 2.11.0 against torch 2.10.0 and fails at import with `undefined symbol: torch_dtype_float4_e2m1fn_x2`, which kills startup at `wgp.py:84` (the `wgp_config_migration` → `postprocessing.seedvc` import chain). The `install` function in `.salias` pins all three (`torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0`). Installing `-r requirements.txt` afterwards does *not* bump them, despite `speechbrain`/`pyannote.audio`/`torch-audiomentations` all depending on torchaudio.

## Gotchas

- `.salias`'s `linkfolders` still points at `/mnt/llm/Wan2GP/*`, which **no longer exists**. Running it would `rmsymlinks` and then create dangling links, cutting off the local `ckpts/` and `loras/`. Don't run it without rewriting the paths first.
- `ckpts/` holds only auxiliary/preprocessing weights (depth, pose, flow, mask, wav2vec, pyannote, roformer, rife). Main generative transformers are **not** vendored — WanGP auto-downloads them from HuggingFace on first use of a model. A fresh checkout showing no `.safetensors` in `ckpts/` is normal, not broken.
- `.venv/bin/python*` are symlinks into uv's managed interpreter (`~/.local/share/uv/python/...`). A repo-wide dangling-symlink sweep can delete them and leave a venv whose libs are intact but which has no interpreter. Recreate with `ln -s <uv-python>/bin/python3.11 python3.11 && ln -s python3.11 python3 && ln -s python3.11 python`.
- `.gitignore`'s committed merge-conflict markers were resolved during the 2026-07-30 flatten: upstream's block won, widened to `loras*/` (covers `loras_flux/`, `loras_hunyuan/`, `loras_qwen/`, `loras_tts/`, …). It also now carries `plugins/wan2gp-*/` and a `!.salias` negation (line 1's `.*` would otherwise hide `.salias`).
- The plugin manager clones plugin repos into `plugins/wan2gp-*`, and eight of those clones had been committed as **stray gitlinks** (mode `160000`, with no `.gitmodules`). `diff.ignoreSubmodules=all` made them invisible to `git diff`, so they went unnoticed for a long time — use `git ls-files -s | awk '$1=="160000"'` to check. They were dropped in the flatten and are now gitignored.
- Local git config sets `diff.ignoreSubmodules=all` and `status.submoduleSummary=false`. Use `--ignore-submodules=none` when you actually need submodule state.
- `wgp_config.json`, `plugins_local.json`, `settings/`, `finetunes/`, `outputs/`, `ckpts/`, `loras*/` are gitignored — machine-local state.
- Much of `wgp.py`'s top level executes at import time, so importing it has side effects (config writes, model-file migration, deprecated-checkpoint deletion). Prefer `shared/api.py` for programmatic use.
- `requirements.txt` pins hard (`torch 2.10.0 + cu130`, `gradio==5.29.0`, `transformers==4.54.0`, `diffusers==0.36.0`). PyTorch 2.8/2.9 are known-bad here (RAM leak / conv3d VRAM regression).
