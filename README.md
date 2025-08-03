# Claude Code Quality Gate Automation System

A complete quality automation system using Claude Code Hooks and SubAgents to enforce code quality standards automatically.

> **⚠️ Disclaimer**: This system is provided as-is for educational and experimental purposes. Use at your own risk. The authors are not responsible for any issues, data loss, or unexpected behavior that may occur from using this automation system. Please test thoroughly in a safe environment before using in production.

## Features

- **Dual Quality Gates**: Work completion + pre-commit quality control  
- **SubAgent Integration**: quality-gate-keeper analyzes and recommends fixes
- **Session-scoped**: Only analyzes current changes, not entire codebase
- **Less is More**: Essential tests over exhaustive coverage

## System Architecture

```mermaid
flowchart TD
    A[Work] --> B[Stop Hook]
    A --> C[git commit] 
    B --> D{Quality OK?}
    C --> E[Pre-commit Hook]
    E --> F{Quality OK?}
    D -->|No| G[quality-gate-keeper]
    F -->|No| G
    G --> H[Fix Issues]
    H --> I[Say passphrase]
    I --> D
    I --> F
    D -->|Yes| J[✓ Complete]
    F -->|Yes| K[✓ Commit]
```

## Components

### Hooks
- **Stop**: Triggers quality gate on work completion
- **PreToolUse**: Blocks git commits until quality standards are met

### SubAgents
- **quality-gate-keeper**: Analyzes code quality and provides recommendations
  - Focuses on session changes only
  - Applies "Less is More" principle
  - Detects testing cheats and shortcuts

### Scripts  
- **quality-gate-stop.sh**: Main quality gate controller with passphrase detection
- **quality-gate-pre-commit.sh**: Pre-commit quality gate that blocks commits until standards are met

## Usage

1. **Setup**: Place the system in your project's `.claude/` directory
2. **Development**: Code normally - the system monitors automatically  
3. **Quality Gate Triggered**: When you complete work, the system will prompt:
   ```
   ✅ Work completion detected. Please launch quality-gate-keeper Agent to perform quality inspection.
   🔧 Then implement all recommended fixes immediately without asking.
   💡 When all fixes are complete, please say: 'I've addressed all the quality gatekeeper requests'
   ```
4. **Pre-commit Gate**: When attempting to commit, the system will block until quality is ensured:
   ```
   🔍 Quality check required. Launch quality-gate-keeper Agent, fix issues, then say: 'I've addressed all the quality gatekeeper requests' before commit
   ```
5. **Execute Quality Gate**: Run the SubAgent as prompted:
   ```
   Use quality-gate-keeper to analyze all files and receive actionable recommendations.
   ```
6. **Complete the Cycle**: After implementing fixes, say the magic passphrase to complete the quality gate and allow commits

## E2E Testing

Run the complete test suite:
```bash
./test-e2e-isolated.sh
```

This validates the entire workflow from test creation to quality intervention.

## Configuration

The system is configured in `test/.claude/settings.json` with relative paths for portability:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/scripts/quality-gate-pre-commit.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command", 
            "command": "./.claude/scripts/quality-gate-stop.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

## Key Features

### Magic Passphrase System
The system uses `"I've addressed all the quality gatekeeper requests"` as a completion signal to prevent infinite loops while ensuring all quality issues are resolved.

### Quality Gate Philosophy
- **Less is More**: Recommends 3-5 essential tests instead of exhaustive suites
- **Session-focused**: Only analyzes files modified in current work session
- **Anti-cheat**: Detects testing shortcuts and bypasses

This ensures the system works across different user environments without hardcoded paths.

## Important Notes

- **Experimental System**: Test in a safe environment first
- **Use at Your Own Risk**: No warranty or support provided

