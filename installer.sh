#!/usr/bin/env bash
set -euo pipefail

BASE="https://shogo-portfolio-ebon.vercel.app/scripts"
INSTALL_DIR="$HOME/.shogo"
BIN_DIR="$HOME/.local/bin"

echo "Installing Shogo CLI..."
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
curl -fsSL "$BASE/shogo.tar.gz" -o /tmp/shogo.tar.gz
tar -xzf /tmp/shogo.tar.gz -C "$INSTALL_DIR" --overwrite
ln -sf "$INSTALL_DIR/bin/shogo" "$BIN_DIR/shogo"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
fi

echo "Installed. Now run: shogo dev-setup"
