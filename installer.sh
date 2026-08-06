#!/usr/bin/env bash
set -euo pipefail

BASE="https://shogo-portfolio-ebon.vercel.app/scripts"
INSTALL_DIR="$HOME/.ipile"
BIN_DIR="$HOME/.local/bin"

echo "Installing ipile..."
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
curl -fsSL "$BASE/ipile.tar.gz" -o /tmp/ipile.tar.gz
tar -xzf /tmp/ipile.tar.gz -C "$INSTALL_DIR" --overwrite
ln -sf "$INSTALL_DIR/bin/ipile" "$BIN_DIR/ipile"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
fi

echo "Installed. Now run: ipile dev-setup"
