#!/bin/bash

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
    if command_exists nvidia-smi; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [[ $GPU_INFO == *"RTX 50"* ]]; then
            echo "rtx50"
        elif [[ $GPU_INFO == *"RTX 40"* ]] || [[ $GPU_INFO == *"RTX 30"* ]]; then
            echo "rtx40"
        elif [[ $GPU_INFO == *"RTX 20"* ]] || [[ $GPU_INFO == *"RTX 10"* ]] || [[ $GPU_INFO == *"GTX"* ]]; then
            echo "rtx20"
        else
            echo "unknown"
        fi
    else
        echo "none"
    fi
}

# Function to install uv if not present
install_uv() {
    if ! command_exists uv; then
        print_status "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source $HOME/.cargo/env
        if ! command_exists uv; then
            print_error "Failed to install uv. Please install manually: https://docs.astral.sh/uv/getting-started/installation/"
            exit 1
        fi
    else
        print_success "uv is already installed"
    fi
}

# Function to create virtual environment
create_venv() {
    print_status "Creating Python 3.10.9 virtual environment with uv..."
    
    # Remove existing .venv if it exists
    if [ -d ".venv" ]; then
        print_warning "Removing existing .venv directory..."
        rm -rf .venv
    fi
    
    # Create new virtual environment with Python 3.10.9
    uv venv --python 3.10.9
    
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
    
    # Install Sage Attention
    print_status "Installing Sage Attention (30% speed boost)..."
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        uv pip install triton-windows || print_warning "Failed to install triton-windows"
    fi
    uv pip install sageattention==1.0.6 || print_warning "Failed to install sageattention"
    
    # Install Sage 2 Attention (more complex)
    if [[ $gpu_type != "rtx50" ]]; then
        print_status "Installing Sage 2 Attention (40% speed boost)..."
        if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
            uv pip install https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu126torch2.6.0-cp310-cp310-win_amd64.whl || print_warning "Failed to install Sage 2 for Windows"
        else
            print_status "Installing setuptools for Sage 2 compilation..."
            uv pip install "setuptools<=75.8.2" --force-reinstall
            
            # Clone and build Sage 2 (Linux)
            if [ ! -d "SageAttention" ]; then
                git clone https://github.com/thu-ml/SageAttention
            fi
            cd SageAttention
            uv pip install -e . || print_warning "Failed to compile Sage 2 Attention"
            cd ..
        fi
    fi
    
    # Flash Attention (optional, can be complex on Windows)
    print_status "Installing Flash Attention (optional)..."
    uv pip install flash-attn==2.7.2.post1 || print_warning "Failed to install flash-attn (this is optional)"
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
    
    # Install uv
    install_uv
    
    # Create virtual environment
    create_venv
    
    # Install PyTorch
    install_pytorch $GPU_TYPE
    
    # Install dependencies
    install_dependencies
    
    # Ask user about optimizations
    echo
    read -p "Install optional performance optimizations? (Sage Attention, Flash Attention) [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_optimizations $GPU_TYPE
    fi
    
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