# Use NVIDIA CUDA base image (matching PyTorch CUDA 12.1)
FROM nvcr.io/nvidia/cuda:12.1.1-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
ENV TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"
ENV FORCE_CUDA=1

# Set working directory
WORKDIR /workspace

# Configure apt to use Tuna mirror
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list && \
    sed -i 's@//.*security.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    build-essential \
    cmake \
    ninja-build \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgcc-s1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh

# Add conda to PATH
ENV PATH="/opt/conda/bin:${PATH}"

# Configure conda to use Tuna mirror and accept ToS
RUN conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/pro && \
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2 && \
    conda config --set show_channel_urls yes && \
    conda config --set channel_priority flexible

# Accept Terms of Service for required channels
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Create conda environment with Python 3.9
RUN conda create -n streetcrafter python=3.9 -y

# Activate the environment and configure pip
RUN echo "conda activate streetcrafter" >> ~/.bashrc && \
    /opt/conda/bin/conda run -n streetcrafter pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    /opt/conda/bin/conda run -n streetcrafter pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

# Set the default environment
ENV CONDA_DEFAULT_ENV=streetcrafter
ENV CONDA_PREFIX=/opt/conda/envs/streetcrafter
ENV PATH="/opt/conda/envs/streetcrafter/bin:${PATH}"

# Install PyTorch with CUDA 12.1 support (as specified in README)
RUN conda run -n streetcrafter pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121

# Copy requirements and install Python dependencies
COPY requirements.txt /workspace/
RUN conda run -n streetcrafter pip install -r requirements.txt

# Install gsplat
RUN conda run -n streetcrafter pip install "git+https://github.com/dendenxu/gsplat.git"

# Copy the project files
COPY . /workspace/

# Install submodules
RUN conda run -n streetcrafter pip install ./submodules/sdata
RUN conda run -n streetcrafter pip install ./submodules/simple-knn

# ======================================================================================
# SSH Server Setup
# --------------------------------------------------------------------------------------
# Install and configure OpenSSH server for remote access.
# IMPORTANT: Change 'sparsedrive123' to a secure password in production.
# ======================================================================================

# Install OpenSSH server
RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*

# Create SSH directory and set permissions
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd

# Set root password (IMPORTANT: Change this in production!)
RUN echo 'root:password' | chpasswd

# Allow root login via SSH (for development purposes)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Configure SSH to use port 22 and allow external connections
RUN echo "Port 22" >> /etc/ssh/sshd_config && \
    echo "ListenAddress 0.0.0.0" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

# Set working directory
WORKDIR /workspace/street-crafter

# Create startup script inline
RUN echo '#!/bin/bash' > /start.sh && \
    echo 'echo "Starting SSH service on port 22..."' >> /start.sh && \
    echo 'mkdir -p /var/run/sshd' >> /start.sh && \
    echo 'chmod 0755 /var/run/sshd' >> /start.sh && \
    echo 'echo "Testing SSH configuration..."' >> /start.sh && \
    echo 'sshd -t' >> /start.sh && \
    echo 'service ssh start' >> /start.sh && \
    echo 'echo "SSH service started. Checking status..."' >> /start.sh && \
    echo 'service ssh status' >> /start.sh && \
    echo 'echo "Checking SSH port..."' >> /start.sh && \
    echo 'netstat -tlnp | grep 22 || echo "SSH port not listening yet"' >> /start.sh && \
    echo 'echo "Activating conda environment..."' >> /start.sh && \
    echo 'source /root/miniconda3/bin/activate sparsedrive' >> /start.sh && \
    echo 'cd /workspace/street-crafter' >> /start.sh && \
    echo 'echo "Container is ready. SSH service is running on port 22."' >> /start.sh && \
    echo 'echo "You can connect using: ssh root@localhost -p 22"' >> /start.sh && \
    echo 'echo "Password: password"' >> /start.sh && \
    echo 'echo "Default working directory: /workspace/street-crafter"' >> /start.sh && \
    echo 'exec "$@"' >> /start.sh && \
    chmod +x /start.sh

# Set the default command to keep container running
CMD ["/start.sh", "tail", "-f", "/dev/null"]
