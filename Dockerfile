ARG DOTFILES_SOURCE=remote

FROM ubuntu:26.04 AS base

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      7zip \
      bat \
      ca-certificates \
      chafa \
      command-not-found \
      curl \
      dnsutils \
      eza \
      fd-find \
      file \
      fontconfig \
      fastfetch \
      git \
      git-delta \
      grc \
      htop \
      mediainfo \
      micro \
      nano \
      openssh-client \
      poppler-utils \
      python3-pip \
      ripgrep \
      sudo \
      tmux \
      tree \
      unzip \
      vim \
      wget \
      zsh \
      default-jdk-headless nodejs python3 \
    && rm -rf /var/lib/apt/lists/*

# Install the standalone editor before copying the dotfiles so this download
# remains cached when only a repository file changes.
RUN architecture="$(dpkg --print-architecture)" \
    && download_url="$(curl -fsSL https://api.github.com/repos/sinelaw/fresh/releases/latest \
      | grep 'browser_download_url' \
      | grep "_${architecture}\\.deb" \
      | head -n 1 \
      | cut -d '"' -f 4)" \
    && test -n "$download_url" \
    && curl -fsSL "$download_url" -o /tmp/fresh-editor.deb \
    && apt-get update \
    && apt-get install -y /tmp/fresh-editor.deb \
    && rm -rf /tmp/fresh-editor.deb /var/lib/apt/lists/*

# Create a non-root user whose configured login shell is Zsh.
RUN useradd --create-home --shell /bin/zsh demo \
    && printf 'demo ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/demo \
    && chmod 0440 /etc/sudoers.d/demo

ENV HOME=/home/demo \
    SHELL=/bin/zsh \
    TERM=xterm-256color \
    USER=demo \
    PATH="/home/demo/.local/bin:${PATH}"

USER demo
WORKDIR /home/demo

# Install every tool exposed by the installer before copying the repository.
# The runtime wizard only changes configuration; it never changes the image's
# tool inventory.
RUN mkdir -p /home/demo/.local/bin \
    && ln -s /usr/bin/batcat /home/demo/.local/bin/bat \
    && ln -s /usr/bin/fdfind /home/demo/.local/bin/fd \
    && curl -fsSL https://mise.run | sh \
    && curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d /home/demo/.local/bin \
    && architecture="$(dpkg --print-architecture)" \
    && case "$architecture" in amd64) fzf_platform=linux_amd64 ;; arm64) fzf_platform=linux_arm64 ;; *) exit 1 ;; esac \
    && fzf_url="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest \
      | awk -F '"' -v suffix="-${fzf_platform}.tar.gz" '/"browser_download_url"/ && index($4, suffix) { print $4; exit }')" \
    && test -n "$fzf_url" \
    && curl -fsSL "$fzf_url" -o /tmp/fzf.tar.gz \
    && tar -xzf /tmp/fzf.tar.gz -C /home/demo/.local/bin fzf \
    && chmod 755 /home/demo/.local/bin/fzf \
    && rm -f /tmp/fzf.tar.gz \
    && curl -fsSL https://github.com/KevenGoncalves/lig/releases/latest/download/install.sh \
      | LIG_INSTALL_DIR=/home/demo/.local/bin sh

RUN mkdir -p /home/demo/Developer/personal@github \
      /home/demo/Developer/work@github \
    && cd /home/demo/Developer \
    && git clone https://github.com/jenkins-docs/simple-java-maven-app.git work@github/simple-java-maven-app \
    && git clone https://github.com/johnpapa/node-hello.git personal@github/simple-node-hello \
    && git clone https://github.com/dbarnett/python-helloworld.git personal@github/python-helloworld \
    && git clone https://github.com/imageio/test_images.git personal@github/test_images

# Download the demo runtimes in a cacheable layer. Their global and per-project
# selections are applied after the configuration has been copied.
RUN mise install java@17.0.2 python@3.13.6 node@22.14.0

# The default source is the Git repository. Override DOTFILES_REPO_URL or
# DOTFILES_REF to test another remote checkout without changing this file.
FROM base AS dotfiles-remote

ENV DOTFILES_SOURCE_MODE=remote

ARG DOTFILES_REPO_URL=https://github.com/michelemadonna/dotfiles-nomad.git
ARG DOTFILES_REF=main

RUN git clone --depth 1 --branch "$DOTFILES_REF" \
      "$DOTFILES_REPO_URL" /home/demo/.dotfiles

# Local development is opt-in with --build-arg DOTFILES_SOURCE=local.
FROM base AS dotfiles-local

ENV DOTFILES_SOURCE_MODE=local

COPY --chown=demo:demo . /home/demo/.dotfiles

# install.sh accepts an existing checkout only when it contains Git metadata.
RUN git -C /home/demo/.dotfiles init -q

# Select either dotfiles-remote (default) or dotfiles-local while sharing the
# complete configuration sequence below.
FROM dotfiles-${DOTFILES_SOURCE} AS final

# System packages are already installed in the cacheable base stage. Seed the
# installer's versioned marker, but leave every preference for the runtime menu.
RUN test -f /home/demo/.dotfiles/install.sh \
    && mkdir -p /home/demo/.local/state/dotfiles-nomad \
    && touch /home/demo/.local/state/dotfiles-nomad/base-packages-v4-linux-apt.done

RUN mkdir -p /home/demo/.fonts \
    && cp /home/demo/.dotfiles/fonts/* /home/demo/.fonts/ \
    && fc-cache -f

RUN cd /home/demo \
    && cd /home/demo/Developer/personal@github/simple-node-hello \
    && mise use node@22.14.0 \
    && cd /home/demo/Developer/work@github/simple-java-maven-app \
    && mise use java@17.0.2 \
    && cd /home/demo/Developer/personal@github/python-helloworld \
    && mise use python@3.13.6

COPY docker/demo-start.sh /usr/local/bin/dotfiles-demo

# Zsh needs a UTF-8 locale to measure the prompt's glyphs in terminal columns.
ENV LANG=C.UTF-8

CMD ["sh", "/usr/local/bin/dotfiles-demo"]
