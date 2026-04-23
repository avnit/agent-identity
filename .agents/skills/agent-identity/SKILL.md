```markdown
# agent-identity Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill covers the core development patterns and conventions used in the `agent-identity` TypeScript codebase. You'll learn how to structure files, write imports and exports, and follow commit and testing practices specific to this repository. This guide is ideal for contributors or anyone looking to understand the project's style and workflows.

## Coding Conventions

### File Naming
- Use **snake_case** for all file names.
  - Example:  
    ```
    user_profile.ts
    agent_identity.test.ts
    ```

### Import Style
- Use **relative imports** for referencing other files or modules within the project.
  - Example:
    ```typescript
    import { getUser } from './user_profile';
    ```

### Export Style
- Use **named exports** instead of default exports.
  - Example:
    ```typescript
    // In user_profile.ts
    export function getUser(id: string) { ... }

    // In another file
    import { getUser } from './user_profile';
    ```

### Commit Patterns
- Commit messages are **freeform** and do not follow a strict prefix or format.
- Average commit message length is about 29 characters.

## Workflows

_No automated or CI workflows were detected in this repository._

## Testing Patterns

- **Test files** follow the pattern: `*.test.*`
  - Example:  
    ```
    agent_identity.test.ts
    ```
- **Testing framework** is not explicitly detected. Check individual test files for framework usage (e.g., Jest, Mocha, etc.).
- Place test files alongside or near the code they test, using the `.test.` infix.

## Commands
| Command | Purpose |
|---------|---------|
| /new-file | Create a new snake_case TypeScript file |
| /add-test | Add a new test file using the *.test.* pattern |
| /import-example | Show an example of relative import and named export |
```