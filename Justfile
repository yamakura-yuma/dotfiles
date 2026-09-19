# Re-link dotfiles-managed config files and sync mise-managed tool versions
reload:
    mkdir -p ~/.config/mise ~/.claude
    ln -sfn {{justfile_directory()}}/mise.toml ~/.config/mise/config.toml
    ln -sfn {{justfile_directory()}}/claude/statusline.sh ~/.claude/statusline.sh
    mise install
