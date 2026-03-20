# CHANGELOG

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-03-20

### Added
- Initial release of SkyLite Debloat
- Multi-mode debloating system:
  - Performance Mode (balanced)
  - Potato PC Mode (ultra-aggressive)
  - Useless Apps Only (minimal)
  - Custom/Advanced Mode (user-selected)
  - Revert/Undo Mode
- Comprehensive app removal:
  - 20+ Microsoft bloatware apps targetted
  - Provisioned package removal (future users)
  - Safe error handling per app
- Service optimization:
  - Telemetry services disabled
  - Search/Superfetch optimization
  - Xbox/gaming services removal
  - Cortana disabling
  - OneDrive complete removal option
- Registry privacy tweaks:
  - Telemetry disabled
  - Web search in Start disabled
  - Ads disabled
  - Connection history cleared
- Visual effect tweaks:
  - Animation disabling (Potato mode)
  - Theme optimizations
- Detailed logging:
  - Change tracking to %TEMP% log file
  - Summary report with reboot prompt
  - Error reporting
- User experience:
  - Colorful ASCII art banner
  - Interactive menu system
  - Confirmation prompts for safety
  - Admin elevation auto-handling
  - Revert/undo functionality
  - No external dependencies
- Documentation:
  - Comprehensive README
  - Code comments throughout
  - Usage examples
  - Troubleshooting guide

### Technical Details
- Language: PowerShell 5.0+
- Targets: Windows 11 24H2/25H2
- Architecture: Modular functions
- Error Handling: Try-catch blocks with fallback
- Logging: Timestamped log to temp directory
- Safety: Confirmation prompts, rollback capability

### Known Limitations
- App reinstall may require Windows Store
- OneDrive uninstall is permanent
- Some system apps can't be removed (intentional)
- Registry tweaks persist (no undo)
- Service revert goes to "Auto" not original state

## Future Enhancements (v2.0)

- [ ] GUI version with WPF/XAML
- [ ] Whitelist/blacklist app configuration
- [ ] Profile system (save custom presets)
- [ ] Backup/restore system state
- [ ] Network optimization tweaks
- [ ] Driver optimization
- [ ] Gaming performance mode
- [ ] Cloud sync (GitHub) for updates
- [ ] Scheduled debloat option
- [ ] System restore integration
- [ ] PowerShell test framework
- [ ] Installer (.exe) version

## Notes

- All changes logged to temp directory
- No telemetry data sent from script
- Fully open-source and auditable
- Community contributions welcome
