# Contributing to Mac Storage Cleanup

Thank you for your interest in contributing to Mac Storage Cleanup! This document provides guidelines and instructions for contributing.

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help create a welcoming environment for all contributors

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates.

When filing a bug report, include:
- macOS version
- App version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots if applicable
- Console logs if relevant

### Suggesting Features

Feature requests are welcome! Please:
- Check if the feature has already been requested
- Clearly describe the feature and its benefits
- Explain your use case
- Consider implementation complexity

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow the coding style** used in the project
3. **Add tests** for new features
4. **Update documentation** as needed
5. **Ensure tests pass** before submitting
6. **Write clear commit messages**

#### Coding Standards

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions focused and small
- Use SwiftUI best practices
- Maintain MVVM architecture

#### Testing

- Write unit tests for new functionality
- Ensure existing tests pass
- Test on multiple macOS versions if possible
- Use Debug Mode for testing cleanup operations

#### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 72 characters
- Reference issues and pull requests when relevant

Example:
```
Add duplicate file finder feature

- Implement file hash comparison
- Add UI for duplicate results
- Include tests for hash algorithm

Fixes #123
```

### Development Setup

1. Clone the repository
2. Open `MacStorageCleanupApp.xcodeproj` in Xcode
3. Build and run the project
4. Enable Debug Mode in preferences for safe testing

### Project Structure

```
MacCleaner/
├── MacStorageCleanup/          # Core library
│   ├── Sources/                # Core functionality
│   └── Tests/                  # Unit tests
└── MacStorageCleanupApp/       # UI application
    ├── Views/                  # SwiftUI views
    ├── ViewModels/             # View models
    ├── Models/                 # Data models
    ├── Services/               # App services
    └── Tests/                  # UI tests
```

### Areas for Contribution

- **Bug fixes** - Always welcome
- **Performance improvements** - Especially for file scanning
- **UI/UX enhancements** - Better user experience
- **New cleanup categories** - Additional file types to clean
- **Localization** - Translations to other languages
- **Documentation** - Improvements to docs and comments
- **Tests** - Increase test coverage

### Questions?

Feel free to open an issue with the "question" label if you need help or clarification.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
