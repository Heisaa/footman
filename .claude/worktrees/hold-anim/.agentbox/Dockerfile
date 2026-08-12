ARG AGENTBOX_BASE_IMAGE=agentbox/fullstack:latest
FROM ${AGENTBOX_BASE_IMAGE}

# >>> agentbox features (managed; use `agentbox features sync`)
USER root
# No Agentbox features selected.
# <<< agentbox features

# Add project-specific Dockerfile instructions below this line.
ARG GODOT_VERSION=4.7.1
ARG GODOT_SHA256_AMD64=c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba
ARG GODOT_SHA256_ARM64=8f527179cd4ae58b402fa265fe817dc505e5b6b14574f309efe57113be562ac1

RUN apt-get update \
    && apt-get install --no-install-recommends --yes ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && case "$(uname -m)" in \
        x86_64) godot_arch="x86_64"; godot_sha256="${GODOT_SHA256_AMD64}" ;; \
        aarch64|arm64) godot_arch="arm64"; godot_sha256="${GODOT_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac \
    && godot_archive="/tmp/godot.zip" \
    && curl --fail --location --silent --show-error \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}.zip" \
        --output "${godot_archive}" \
    && echo "${godot_sha256}  ${godot_archive}" | sha256sum --check --strict - \
    && unzip -q "${godot_archive}" -d /tmp/godot \
    && install -m 0755 \
        "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}" \
        /usr/local/bin/godot \
    && rm -rf "${godot_archive}" /tmp/godot \
    && godot --headless --version
