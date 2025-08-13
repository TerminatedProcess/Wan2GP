#!/bin/bash
clear

# WanGP Installation Script using uv
# This script installs WanGP with all dependencies using uv instead of conda

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect GPU generation
detect_gpu() {
    echo "rtx40"  # RTX 4070 - hardcoded
}


# Function to create virtual environment
create_venv() {
    print_status "Creating Python 3.10.9 virtual environment with uv..."
    
    # Remove existing .venv if it exists
    if [ -d ".venv" ]; then
        print_warning "Removing existing .venv directory..."
        rm -rf .venv
        print_status "Previous environment removed. Please run the script again."
        exit 0
    fi
    
    # Create new virtual environment (use system Python or closest available)
    uv venv --python 3.10
    
    # Activate virtual environment
    source .venv/bin/activate
    
    print_success "Virtual environment created and activated"
}

# Function to install PyTorch based on GPU
install_pytorch() {
    local gpu_type=$1
    
    print_status "Installing PyTorch for GPU type: $gpu_type"
    
    case $gpu_type in
        "rtx50")
            print_status "Installing PyTorch 2.7.0 for RTX 50XX (beta support)..."
            uv pip install torch==2.7.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu128
            ;;
        "rtx40"|"rtx20"|"unknown")
            print_status "Installing PyTorch 2.6.0 for RTX 10XX-40XX (stable)..."
            uv pip install torch==2.6.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu124
            ;;
        "none")
            print_warning "No NVIDIA GPU detected. Installing CPU-only PyTorch..."
            uv pip install torch==2.6.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
            ;;
    esac
}

# Function to install core dependencies
install_dependencies() {
    print_status "Installing core dependencies..."
    uv pip install -r requirements.txt
}

# Function to install optional performance optimizations
install_optimizations() {
    local gpu_type=$1
    
    print_status "Installing optional performance optimizations..."
    
    # Only install optimizations for NVIDIA GPUs
    if [[ $gpu_type == "none" ]]; then
        print_warning "Skipping GPU optimizations (no NVIDIA GPU detected)"
        return
    fi
    
    # Install Sage Attention (30% speed boost)
    print_status "Installing Sage Attention (30% speed boost)..."
    uv pip install sageattention || print_warning "Failed to install sageattention"
    
    # Install Flash Attention (good performance)
    print_status "Installing Flash Attention (optional)..."
    uv pip install flash-attn --no-build-isolation || print_warning "Failed to install flash-attn (this is optional)"
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check if Python can import key modules
    python -c "import torch; print(f'PyTorch {torch.__version__} - CUDA available: {torch.cuda.is_available()}')" || {
        print_error "PyTorch verification failed"
        exit 1
    }
    
    python -c "import gradio; print(f'Gradio {gradio.__version__}')" || {
        print_error "Gradio verification failed"
        exit 1
    }
    
    python -c "import diffusers; print(f'Diffusers {diffusers.__version__}')" || {
        print_error "Diffusers verification failed"
        exit 1
    }
    
    print_success "Installation verification completed successfully!"
}

# Function to create activation script
create_activation_script() {
    print_status "Creating activation script..."
    
    cat > activate.sh << 'EOF'
#!/bin/bash
# WanGP Environment Activation Script
source .venv/bin/activate
echo "WanGP environment activated!"
echo "Run 'python wgp.py' to start the application"
EOF
    
    chmod +x activate.sh
    print_success "Created activate.sh script"
}

# Main installation process
main() {
    echo "========================================"
    echo "    WanGP Installation Script (uv)"
    echo "========================================"
    echo
    
    # Check if we're in the right directory
    if [ ! -f "wgp.py" ]; then
        print_error "wgp.py not found. Please run this script from the WanGP directory."
        exit 1
    fi
    
    # Detect GPU
    GPU_TYPE=$(detect_gpu)
    print_status "Detected GPU type: $GPU_TYPE"
    
    
    # Create virtual environment
    create_venv
    
    # Install PyTorch
    install_pytorch $GPU_TYPE
    
    # Install dependencies
    install_dependencies
    
    # Install performance optimizations
    install_optimizations $GPU_TYPE
    
    # Verify installation
    verify_installation
    
    # Create activation script
    create_activation_script
    
    echo
    echo "========================================"
    print_success "WanGP installation completed!"
    echo "========================================"
    echo
    echo "To use WanGP:"
    echo "1. Activate the environment: source activate.sh"
    echo "2. Run the application: python wgp.py"
    echo
    echo "Additional run options:"
    echo "  python wgp.py --i2v          # Image-to-video mode"
    echo "  python wgp.py --listen       # Network accessible"
    echo "  python wgp.py --share        # Create public link"
    echo
    echo "For more options: python wgp.py --help"
    echo
}

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "WanGP Installation Script using uv"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  --no-opt       Skip optional optimizations"
        echo ""
        echo "This script will:"
        echo "1. Install uv if not present"
        echo "2. Create Python 3.10.9 virtual environment"
        echo "3. Install PyTorch (version based on detected GPU)"
        echo "4. Install all dependencies from requirements.txt"
        echo "5. Optionally install performance optimizations"
        exit 0
        ;;
    "--no-opt")
        SKIP_OPTIMIZATIONS=1
        ;;
esac

# Run main installation
main "$@"
