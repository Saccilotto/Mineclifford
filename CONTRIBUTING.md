# Contributing to Mineclifford

Thank you for your interest in contributing to Mineclifford! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Environment Setup](#development-environment-setup)
- [Branching Strategy](#branching-strategy)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Coding Standards](#coding-standards)
- [Documentation](#documentation)
- [Issue Reporting](#issue-reporting)
- [Feature Requests](#feature-requests)

## Code of Conduct

We expect all contributors to follow our [Code of Conduct](CODE_OF_CONDUCT.md). Please make sure you read and understand it before contributing.

## Getting Started

1. Fork the repository.
2. Clone your fork to your local machine.
3. Add the original repository as a remote to keep your fork in sync:

   ```bash
   git remote add upstream https://github.com/original-owner/mineclifford.git
   ```

4. Create a new branch for your changes.
5. Make your changes and commit them to your branch.
6. Push your branch to your fork.
7. Create a pull request from your branch to the main repository.

## Development Environment Setup

### Prerequisites

- Terraform v1.0.0+
- Ansible v2.9+
- Docker and Docker Compose
- AWS CLI or Azure CLI (depending on which provider you're working with)
- kubectl (for Kubernetes development)
- Go 1.16+ (for running tests)
- BATS (Bash Automated Testing System) for shell script testing

### Setup Steps

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/mineclifford.git
   cd mineclifford
   ```

2. Install development dependencies:

   ```bash
   # For BATS (Bash Automated Testing System)
   npm install -g bats

   # For Go testing frameworks
   go get -u github.com/gruntwork-io/terratest
   go get -u github.com/stretchr/testify/assert
   ```

3. Create a `.env` file with your configuration:

   ```bash
   cp .env.example .env
   # Edit .env file with your settings
   ```

## Branching Strategy

We use a simplified GitFlow branching model:

- `main`: The main branch that contains the stable code. All releases are made from this branch.
- `develop`: Development branch where features are integrated.
- `feature/*`: Feature branches for new features.
- `bugfix/*`: Bugfix branches for fixing bugs.
- `hotfix/*`: Hotfix branches for critical fixes to production.

When starting a new feature or bugfix, branch off from `develop`:

```bash
git checkout develop
git pull
git checkout -b feature/your-feature-name
```

## Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for commit messages:

```plaintext
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Types:

- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, indentation)
- `refactor`: Code refactoring without functionality changes
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `build`: Build system or external dependency changes
- `ci`: CI configuration changes
- `chore`: Other changes that don't modify src or test files

Examples:

```plaintext
feat(kubernetes): add support for AKS
fix(aws): correct security group rule for Minecraft Bedrock
docs(readme): update deployment instructions
```

## Pull Request Process

1. Update your branch with the latest changes from the `develop` branch.
2. Ensure all tests pass.
3. Update documentation if necessary.
4. Create a pull request to the `develop` branch.
5. Fill out the pull request template with all relevant information.
6. Request review from at least one maintainer.
7. Address any feedback or requested changes.
8. Once approved, a maintainer will merge your PR.

## Testing

We use several testing frameworks:

- **BATS** for shell script testing
- **Terratest** for Terraform testing
- **pytest** for Python testing (if applicable)

### Running Tests

```bash
# Run all tests
cd tests
./run-tests.sh

# Run specific test types
./run-tests.sh --type script
./run-tests.sh --type terraform
./run-tests.sh --type kubernetes

# Run with verbose output
./run-tests.sh --verbose
```

### Adding Tests

When adding new features, please also add appropriate tests:

- For shell scripts: Add tests to `tests/script-tests/`
- For Terraform configurations: Add tests to `tests/terraform-tests/`
- For Kubernetes manifests: Add tests to `tests/kubernetes-tests/`

## Coding Standards

### Shell Scripts

- Use shellcheck to validate your scripts.
- Add error handling to all scripts.
- Use functions for reusable code.
- Add usage information and help flags.
- Follow Google's Shell Style Guide.

### Terraform

- Format your code with `terraform fmt`.
- Use modules for reusable infrastructure components.
- Use consistent naming conventions.
- Add meaningful descriptions to all resources.
- Add appropriate tags to all resources.

### Ansible

- Use YAML syntax consistently.
- Use roles for reusable configurations.
- Add meaningful comments to complex tasks.
- Use variables instead of hardcoded values.

### Go

- Follow the standard Go style guidelines.
- Use gofmt to format your code.
- Write meaningful comments and documentation.

## Documentation

Documentation is a crucial part of our project. Please update or add documentation when making changes:

- Update the main README.md if necessary.
- Update or add relevant documentation in the `docs/` directory.
- Add inline comments to your code to explain complex logic.
- Update configuration examples if you add or change configuration options.

## Issue Reporting

If you find a bug or have a suggestion, please create an issue in our issue tracker. When creating an issue, please:

1. Check if a similar issue already exists.
2. Use a clear, descriptive title.
3. Provide a detailed description of the issue or suggestion.
4. Include steps to reproduce the issue if applicable.
5. Include information about your environment (OS, tool versions, etc.).
6. Add appropriate labels.

## Feature Requests

We welcome feature requests! When requesting a feature, please:

1. Check if a similar request already exists.
2. Clearly describe the feature and its benefits.
3. Consider including examples of how the feature would be used.
4. Consider if the feature is general enough to be useful to multiple users.

Thank you for contributing to Mineclifford! Together, we can make this project better for everyone.
