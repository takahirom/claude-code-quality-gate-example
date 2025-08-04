# Claude Code Quality Gate Example

A complete quality automation system using Claude Code Hooks and Subagents to enforce code quality standards automatically.

**In simple terms**: A system that uses Hooks to repeatedly launch quality-gate-keeper Subagent and perform fixes until it says `Final Result: ✅ APPROVED`.

> **⚠️ Note**: This system may cause infinite loops if quality standards are too strict. Adjust quality-gate-keeper.md or modify scripts if needed.

## How to Install (Global Settings)

1. Clone this repository:
   ```bash
   git clone https://github.com/takahirom/claude-code-quality-gate-example.git ~/claude-quality-gate
   chmod +x ~/claude-quality-gate/.claude/scripts/*.sh
   ```

2. Add to your global Claude Code settings (`~/.claude/settings.json`):
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "~/claude-quality-gate/.claude/scripts/quality-gate-pre-commit.sh",
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
               "command": "~/claude-quality-gate/.claude/scripts/quality-gate-stop.sh",
               "timeout": 30
             }
           ]
         }
       ]
     }
   }
   ```

3. Link the Subagent definition:
   ```bash
   mkdir -p ~/.claude/agents
   ln -s ~/claude-quality-gate/.claude/agents/quality-gate-keeper.md ~/.claude/agents/
   ```

4. Ensure dependencies are installed:
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

## Execution Flow

```mermaid
flowchart TD
    A[Claude Code<br/>ends work] --> B[Stop Hook] 
    B --> C[quality-gate-stop.sh]
    C --> D{Final Result<br/>in history?}
    D -->|APPROVED| E[✓ Session Complete]
    D -->|No/REJECTED| F{git changes?}
    F -->|No| E
    F -->|Yes| G[Show message:<br/>Use quality-gate-keeper]
    G --> H[Claude Code<br/>launches Subagent]
    H --> I[quality-gate-keeper checks quality and<br/>outputs Final Result: APPROVED/REJECTED]
    I --> J[Claude Code<br/>performs fixes]
    J --> B
    
    L[Claude Code<br/>runs git commit] --> M[PreToolUse Hook] 
    M --> N[quality-gate-pre-commit.sh]
    N --> O{Latest<br/>Final Result?}
    O -->|APPROVED| P[✓ Allow Commit]
    O -->|REJECTED/No Result| Q[❌ Commit Blocked<br/>Use quality-gate-keeper]
    Q --> R[Claude Code<br/>launches Subagent]
    R --> S[quality-gate-keeper checks quality and<br/>outputs Final Result: APPROVED/REJECTED]
    S --> T[Claude Code<br/>performs fixes]
    T --> U[Retry git commit]
    U --> M
```

## Components

### Hooks
- **Stop**: Launches `quality-gate-stop.sh` when work ends - checks transcript history for Final Result
- **PreToolUse**: Launches `quality-gate-pre-commit.sh` on git commit - blocks commit unless APPROVED

### Subagents
- **quality-gate-keeper**: Analyzes code quality and outputs clear verdicts
  - Must end with `Final Result: ✅ APPROVED` or `Final Result: ❌ REJECTED`
  - Focuses on session changes only
  - Applies "Less is More" principle
  - Detects testing cheats and shortcuts

## E2E Testing

Run the complete test suite:
```bash
./e2e-test.sh
```

This validates the entire workflow from test creation to quality intervention.

## Key Features

### Direct Verdict System
The system uses quality-gate-keeper's direct output for decision making:

1. **Direct Result Checking**: Parses transcript for `Final Result: ✅ APPROVED` or `Final Result: ❌ REJECTED`
2. **Stale Approval Detection**: Automatically invalidates old approvals after file edits


## Important Notes

- **REJECTED Handling**: Unlike the old passphrase system, you must actually fix issues - no shortcuts allowed
- **Infinite Loop Risk**: Quality standards that are too strict may cause loops. Adjust quality-gate-keeper.md or scripts as needed
- **Experimental System**: Test in a safe environment first  
- **Use at Your Own Risk**: No warranty or support provided

