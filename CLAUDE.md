# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WanGP is a comprehensive open-source video generation platform that supports multiple AI models including Wan, Hunyuan Video, LTX Video, Flux, and Qwen. It provides a web-based interface for text-to-video, image-to-video, and advanced video manipulation features like VACE ControlNet, multitalk, and audio generation.

## Core Architecture

### Main Application Structure
- `wgp.py` - Main application entry point with Gradio web interface
- `models/` - Model implementations organized by type:
  - `wan/` - Wan model family (1.3B, 14B, and 2.2 variants)
  - `hyvideo/` - Hunyuan Video models and pipelines
  - `ltx_video/` - LTX Video models and configurations
  - `flux/` - Flux image generation models
  - `qwen/` - Qwen image generation models
- `shared/` - Shared utilities, attention mechanisms, and common functions
- `preprocessing/` - Input preprocessing tools (depth, pose, flow, masks)
- `postprocessing/` - Output enhancement (upsampling, audio generation, film grain)

### Configuration System
- `configs/` - Active model configurations (user-customizable)
- `defaults/` - Default model configurations (reference templates)
- `finetunes/` - Custom model definitions and LoRA combinations
- `loras*/` - LoRA storage directories organized by model type

### Key Components
- **VACE System**: Advanced video control using depth, pose, flow, and other conditions
- **Multitalk**: Multi-speaker audio generation and lip-sync
- **Sliding Windows**: Long video generation support
- **LoRA Support**: Extensive customization via Low-Rank Adaptations
- **Attention Modes**: Multiple attention implementations (SDPA, Sage, Sage2, Flash)

## Development Commands

### Running the Application
```bash
# Text-to-video mode (default)
python wgp.py

# Image-to-video mode
python wgp.py --i2v

# Specific model variants
python wgp.py --t2v-14B    # 14B text-to-video
python wgp.py --t2v-1-3B   # 1.3B text-to-video
python wgp.py --i2v-14B    # 14B image-to-video

# Network access
python wgp.py --listen --share

# Development/debugging options
python wgp.py --save-masks --save-speakers
```

### Installation Commands
```bash
# Environment setup
conda create -n wan2gp python=3.10.9
conda activate wan2gp

# For RTX 10XX-40XX (stable)
pip install torch==2.6.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu124
pip install -r requirements.txt

# For RTX 50XX (beta)
pip install torch==2.7.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu128
pip install -r requirements.txt

# Performance optimizations
pip install sageattention==1.0.6       # Sage attention
pip install flash-attn==2.7.2.post1    # Flash attention
```

### Update Commands
```bash
git pull
pip install -r requirements.txt
```

## Model System Architecture

### Model Loading Pattern
Models use a handler pattern where each model family has:
- `*_handler.py` - Model loading, configuration, and pipeline management
- `*_main.py` or core implementation files
- Configuration files in `defaults/` and `configs/`

### Memory Management
- Uses `mmgp` library for intelligent model offloading
- Profile-based VRAM management (Profile 3: high VRAM, Profile 4: low VRAM)
- Quantization support for reduced memory usage
- Dynamic model loading/unloading based on usage

### LoRA System
- Hierarchical LoRA storage by model type (`loras/`, `loras_flux/`, `loras_hunyuan/`, etc.)
- Multiplier support for LoRA strength adjustment
- Runtime LoRA combination and finetune creation
- Model-specific LoRA compatibility handling

## Key File Locations

### Configuration
- `wgp.py:1301-1600` - Command line argument parsing
- `shared/utils/utils.py` - Core utility functions
- `shared/attention.py` - Attention mode implementations

### Model Implementations
- `models/wan/wan_handler.py` - Main Wan model handler
- `models/hyvideo/hunyuan_handler.py` - Hunyuan model handler
- `models/ltx_video/ltxv_handler.py` - LTX Video handler
- `models/flux/flux_handler.py` - Flux model handler

### Processing Pipelines
- `preprocessing/` - Input conditioning (depth, pose, canny, flow)
- `postprocessing/mmaudio/` - Audio generation system
- `postprocessing/rife/` - Frame interpolation

## Important Notes

### GPU Compatibility
- RTX 10XX/20XX: Use SDPA attention mode
- RTX 30XX/40XX: Full feature support including Sage attention
- RTX 50XX: Beta support, requires PyTorch 2.7.0

### VRAM Requirements
- 1.3B models: ~6GB VRAM minimum
- 14B models: ~12GB VRAM minimum (with quantization)
- Full precision 14B: ~24GB VRAM
- Use Profile 4 for lower VRAM usage at cost of speed

### Performance Optimization
- Sage attention: 30% speed increase
- Sage2 attention: 40% speed increase  
- Flash attention: Good performance, complex Windows installation
- TeaCache/MagCache: Step skipping for faster generation
- Quantization: Reduces VRAM at small quality cost

## Development Guidelines

### Adding New Models
1. Create handler in appropriate `models/` subdirectory
2. Add default configuration in `defaults/`
3. Update model selection UI in `wgp.py`
4. Ensure LoRA compatibility if applicable

### Modifying Attention Systems
- Check `shared/attention.py` for supported modes
- Test across different GPU architectures
- Provide fallbacks for unsupported hardware

### Configuration Changes
- Maintain backward compatibility in config loading
- Update `settings_version` when breaking changes occur
- Provide migration paths for existing configurations