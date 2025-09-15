# Normi's NixOS Configuration

A complete NixOS configuration featuring Hyprland, home-manager, and a modern desktop environment setup.

## 🖥️ What's Included

### Desktop Environment
- **Window Manager**: Hyprland (Wayland compositor)
- **Shell**: noctalia-shell (custom shell based on QuickShell)
- **Display Manager**: SDDM with custom theme
- **Terminal**: Alacritty (with Kitty as backup)
- **Audio**: PipeWire with ALSA/Pulse compatibility

### Hardware Support
- Intel CPU with microcode updates
- Intel graphics with VA-API acceleration
- IPU6 camera support (MateBook GT / Meteor Lake)
- Steam hardware support
- Fingerprint authentication

### Virtualization & Development
- Docker
- libvirtd/QEMU/KVM with nested virtualization
- Waydroid (Android emulation)
- Android development tools (ADB)

### Applications & Tools
- **Browsers**: Firefox, Chrome options
- **Office**: OnlyOffice, WPS Office
- **Development**: VS Code, various editors
- **Gaming**: Steam with hardware acceleration
- **Communication**: Discord, Thunderbird
- **Security**: Bitwarden
- **Media**: OBS Studio, media controls

## 🚀 Quick Installation

### Prerequisites
- Fresh NixOS installation
- Git available
- Internet connection

### One-Command Install
```bash
sudo nixos-rebuild switch --flake github:Norzolrat/nixos-config#veronica
```

### Step-by-Step Installation

1. **Generate hardware configuration** (for new systems):
   ```bash
   sudo nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
   ```

2. **Clone and install**:
   ```bash
   git clone https://github.com/Norzolrat/nixos-config.git
   cd nixos-config
   
   # Replace hardware config if needed
   sudo cp /tmp/hardware-configuration.nix common/hardware-configuration.nix
   
   # Install the configuration
   sudo nixos-rebuild switch --flake .#veronica
   ```

3. **Create user** (if doesn't exist):
   ```bash
   sudo useradd -m -G wheel,networkmanager,libvirtd,kvm,docker normi
   sudo passwd normi
   ```

4. **Reboot**:
   ```bash
   sudo reboot
   ```

## 🎨 Customization

### Changing the Hostname
Edit `hosts/veronica/configuration.nix` and change:
```nix
networking.hostName = "YourNewHostname";
```

### Adding Your User
1. Copy the user configuration:
   ```bash
   cp -r users/normi users/yourusername
   ```

2. Update `flake.nix` to include your user:
   ```nix
   home-manager.users.yourusername.imports = [
     ./users/yourusername/home.nix
   ];
   ```

3. Update personal information in `users/yourusername/home.nix`

### Modifying Hyprland Settings
- **Keybindings**: Edit `users/normi/dots/hypr/hyprland/keybinds.conf`
- **Appearance**: Edit `users/normi/dots/hypr/hyprland/colors.conf`
- **Window rules**: Edit `users/normi/dots/hypr/hyprland/rules.conf`

## 📁 Structure

```
├── flake.nix                 # Main flake configuration
├── common/
│   ├── android.nix          # Android development tools
│   └── hardware-configuration.nix
├── hosts/
│   └── veronica/
│       └── configuration.nix # System configuration
└── users/
    └── normi/
        ├── home.nix          # Home-manager configuration
        └── dots/             # Dotfiles (Hyprland, Alacritty, etc.)
```

## 🔧 Updating the System

```bash
# Update flake inputs
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .#veronica

# Or rebuild and update in one command
sudo nixos-rebuild switch --flake github:Norzolrat/nixos-config#veronica --refresh
```

## 🎯 Key Features

### Hyprland Configuration
- **Gestures**: 3-finger workspace switching
- **Animations**: Smooth transitions with bezier curves
- **Window Management**: Smart tiling with gaps and borders
- **Screenshot Tools**: Region and fullscreen capture
- **Screen Recording**: Built-in recording scripts
- **AI Integration**: Text selection AI queries (with Ollama)
- **Visual Effects**: Custom shaders (CRT, chromatic aberration, etc.)
- **Custom SDDM Theme**: "LockeD" theme with custom styling

### Security & Privacy
- **Fingerprint**: Login with fingerprint
- **Screen Lock**: GTKLock with custom styling
- **Firewall**: Basic security setup

### Development Environment
- **Containers**: Docker ready-to-use
- **Virtualization**: Full KVM/QEMU setup
- **Android**: Complete Android development stack
- **Git**: Pre-configured with user settings

## 🐛 Troubleshooting

### Common Issues

**Hardware not detected properly:**
```bash
sudo nixos-generate-config --show-hardware-config
# Compare with common/hardware-configuration.nix
```

**Hyprland not starting:**
- Check if you're logging into Hyprland session in SDDM
- Verify graphics drivers are working: `lspci | grep VGA`

**Audio not working:**
```bash
# Check PipeWire status
systemctl --user status pipewire pipewire-pulse
```

**Home-manager issues:**
```bash
# Rebuild just home configuration
home-manager switch --flake .#normi
```

## 📝 Notes

- This configuration is optimized for Intel hardware
- The user `normi` is configured by default - adapt for your needs
- Some applications may require additional configuration on first run
- The configuration uses unstable nixpkgs for latest packages

## 🤝 Contributing

Feel free to fork and adapt this configuration for your needs. If you find improvements or fixes, pull requests are welcome!

## 📄 License

This configuration is provided as-is for educational and personal use.