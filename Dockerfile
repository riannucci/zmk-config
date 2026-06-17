FROM zmkfirmware/zmk-dev-arm:stable

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libglib2.0-dev-bin=2.80.0-6ubuntu3.8 \
    python3-venv=3.12.3-0ubuntu2.1 \
  && rm -rf /var/lib/apt/lists/* \
  # Adafruit serial-DFU packager, isolated in its own venv so its Python deps can't clash
  # with the Zephyr/west build environment. Only the CLI entry point is exposed on PATH (via a symlink);
  # the venv interpreter must NOT shadow the system python3 that `west build` uses,
  # so we deliberately do not put the venv on PATH.
  # Lives in /opt (outside the bind-mounted /workspace, /zmk-config, /firmware).
  && python3 -m venv /opt/nrfutil-venv \
  && /opt/nrfutil-venv/bin/pip install --no-cache-dir adafruit-nrfutil==0.5.3.post16 \
  && ln -s /opt/nrfutil-venv/bin/adafruit-nrfutil /usr/local/bin/adafruit-nrfutil \
  && mkdir -p /workspace \
  && chown -R ubuntu:ubuntu /workspace

USER ubuntu
WORKDIR /workspace

COPY --chown=ubuntu:ubuntu entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy the west manifest so the workspace is initialized with both ZMK
# and YADS (zmk-dongle-screen). Without this, YADS is only available at
# runtime and `west build` fails with "shield not found: dongle_screen".
COPY --chown=ubuntu:ubuntu config/west.yml config/west.yml

# Initialize the west workspace using the user's manifest.
# This fetches ZMK v0.3.0, Zephyr, all HALs, and YADS in one shot.
# Expensive step (~2 GB download) — cached by Docker layer.
RUN west init -l config \
  && west update \
  && west zephyr-export

# Route all `docker compose run` commands through the build script.
# Usage: docker compose run --rm make [dongle|left|right|reset|all]
# For a shell: docker compose run --rm --entrypoint bash make
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
