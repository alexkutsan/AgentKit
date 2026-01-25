FROM crystallang/crystal:latest

RUN apt-get update && apt-get install -y \
    git \
    curl \
    sudo \
    just \
    python3 \
    python3-pip \
    python3-venv \
    # Dependencies for building kcov (code coverage)
    binutils-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    libdw-dev \
    libiberty-dev \
    cmake \
    build-essential \
    # Node.js (includes npm and npx)
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Build and install kcov for code coverage
RUN cd /tmp && \
    git clone --depth 1 https://github.com/SimonKagstrom/kcov.git && \
    cd kcov && mkdir build && cd build && \
    cmake .. && make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/kcov

# Простое создание пользователя без сложной логики
ARG USERNAME=vscode
RUN useradd -m -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install uv (Python package manager) globally
RUN curl -LsSf https://astral.sh/uv/install.sh | env sh

WORKDIR /workspace
USER $USERNAME